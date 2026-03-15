from __future__ import annotations

import argparse
from itertools import count
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Set

from src.pharnote.doctrine.schemas import (
    ProblemDoctrineSeed,
    ProblemDoctrineSeedBundle,
    RawDoctrineCandidate,
)
from src.pharnote.doctrine.taxonomy import TAXONOMY_BY_CODE, TAXONOMY_REGISTRY
from src.pharnote.ingestion.load_external_sources import load_external_sources
from src.pharnote.ingestion.load_problem_db import load_scoped_problems
from src.pharnote.ingestion.source_registry import SOURCE_RELIABILITY_TIERS
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import write_jsonl
from src.pharnote.utils.logging_utils import write_log_json, write_log_jsonl
from src.pharnote.utils.text_cleaning import (
    compact_whitespace,
    extract_evidence_spans,
    has_operational_signal,
    is_motivational_only,
    is_vague_commentary,
    split_text_fragments,
)


ANTI_PATTERN_MAP = {
    "condition_binding": ["condition_fragmentation"],
    "target_quantity_fixing": ["target_drift"],
    "structure_recognition": ["premature_expansion", "local_success_false_finish"],
    "representation_translation": ["premature_expansion"],
    "visual_relation_extraction": ["visual_ignoring"],
    "function_role_preservation": ["function_role_collapse"],
    "strategy_selection": ["premature_expansion"],
    "case_triggering": ["late_case_split"],
    "restriction_propagation": ["restriction_drop"],
    "option_usage": ["option_anchoring"],
}

VERIFICATION_MAP = {
    "condition_binding": ["original_condition_recheck"],
    "target_quantity_fixing": ["original_condition_recheck", "special_value_sanity_check"],
    "structure_recognition": ["original_condition_recheck"],
    "representation_translation": ["original_condition_recheck"],
    "visual_relation_extraction": ["special_value_sanity_check"],
    "function_role_preservation": ["domain_range_check"],
    "strategy_selection": ["choice_crosscheck"],
    "case_triggering": ["case_exhaustiveness_check"],
    "restriction_propagation": ["domain_range_check"],
    "option_usage": ["choice_crosscheck"],
}


def _taxonomy_entries(bucket: str) -> List[Dict[str, Any]]:
    return [entry for entry in TAXONOMY_REGISTRY if entry["bucket"] == bucket]


def _problem_corpus(problem: Dict[str, Any]) -> str:
    chunks = [
        problem["stem"],
        " ".join(problem.get("choices", [])),
        problem.get("solution_outline") or "",
        " ".join(problem.get("concept_tags", [])),
    ]
    return compact_whitespace(" ".join(chunk for chunk in chunks if chunk))


def _match_keywords(entry: Dict[str, Any], corpus: str) -> List[str]:
    normalized_corpus = corpus.lower()
    matches = []
    for keyword in entry["keywords"]:
        if keyword.lower() in normalized_corpus and keyword not in matches:
            matches.append(keyword)
    return matches


def _required_seed_codes(problem: Dict[str, Any]) -> Set[str]:
    corpus = _problem_corpus(problem)
    matches: Set[str] = set()
    for entry in _taxonomy_entries("required_doctrines"):
        keywords = _match_keywords(entry, corpus)
        code = str(entry["taxonomy_code"])
        threshold = 2
        if code in {"visual_relation_extraction", "function_role_preservation", "case_triggering", "restriction_propagation"}:
            threshold = 1
        if code == "option_usage" and problem.get("choices"):
            threshold = 1
            if problem.get("answer"):
                keywords = keywords + ["answer_present"]
        if len(keywords) >= threshold:
            matches.add(code)

    if any(token in corpus for token in ["조건", "서로 다른", "모든 실수"]):
        matches.add("condition_binding")
    if any(token in corpus for token in ["최댓값", "최솟값", "값", "구하시오"]):
        matches.add("target_quantity_fixing")
    if any(token in corpus for token in ["그래프", "도형", "표"]):
        matches.add("visual_relation_extraction")
    if any(token in corpus for token in ["함수", "f(", "g("]):
        matches.add("function_role_preservation")
    if any(token in corpus for token in ["절댓값", "경우", "구간", "부호"]):
        matches.add("case_triggering")
    if any(token in corpus for token in ["정의역", "범위", "자연수", "정수"]):
        matches.add("restriction_propagation")

    return matches


def _evidence_keywords(seed_code: str, corpus: str) -> List[str]:
    entry = TAXONOMY_BY_CODE[seed_code]
    return _match_keywords(entry, corpus) or list(entry["keywords"][:2])


def _seed_confidence(problem: Dict[str, Any], hit_count: int) -> float:
    confidence = 0.55 + min(hit_count, 4) * 0.08
    if problem.get("solution_outline"):
        confidence += 0.08
    if problem.get("concept_tags"):
        confidence += 0.06
    return round(min(confidence, 0.95), 4)


def _build_seed(problem: Dict[str, Any], seed_code: str) -> ProblemDoctrineSeed:
    entry = TAXONOMY_BY_CODE[seed_code]
    corpus = _problem_corpus(problem)
    evidence_keywords = _evidence_keywords(seed_code, corpus)
    return ProblemDoctrineSeed(
        seed_id=f"seed_{problem['problem_id']}_{entry['bucket']}_{seed_code}",
        problem_id=problem["problem_id"],
        bucket=entry["bucket"],
        taxonomy_group=entry["taxonomy_group"],
        taxonomy_code=seed_code,
        condition=entry["condition"],
        action=entry["action"],
        evidence_spans=extract_evidence_spans(corpus, evidence_keywords),
        seed_confidence=_seed_confidence(problem, len(evidence_keywords)),
    )


def _generate_seed_bundle(problem: Dict[str, Any]) -> ProblemDoctrineSeedBundle:
    required_codes = sorted(_required_seed_codes(problem))
    anti_codes = sorted({code for required in required_codes for code in ANTI_PATTERN_MAP.get(required, [])})
    verification_codes = sorted({code for required in required_codes for code in VERIFICATION_MAP.get(required, [])})
    if required_codes and "original_condition_recheck" not in verification_codes:
        verification_codes.append("original_condition_recheck")
    corpus = _problem_corpus(problem)
    if any(token in corpus for token in ["증가", "감소", "부호"]):
        verification_codes.append("sign_monotonicity_check")

    unique_verification = []
    for code in verification_codes:
        if code not in unique_verification:
            unique_verification.append(code)

    return ProblemDoctrineSeedBundle(
        problem_id=problem["problem_id"],
        required_doctrines=[_build_seed(problem, code) for code in required_codes],
        anti_patterns=[_build_seed(problem, code) for code in anti_codes],
        verification_doctrines=[_build_seed(problem, code) for code in unique_verification],
    )


def _seed_to_raw_candidate(seed: ProblemDoctrineSeed, candidate_id: str) -> RawDoctrineCandidate:
    return RawDoctrineCandidate(
        candidate_id=candidate_id,
        problem_id=seed.problem_id,
        source_type="problem_seed",
        source_ref=seed.seed_id,
        author="system_problem_seed",
        raw_text=f"조건: {seed.condition} / 행동: {seed.action}",
        source_reliability_tier=SOURCE_RELIABILITY_TIERS["problem_seed"],
        taxonomy_group=seed.taxonomy_group,
        taxonomy_code=seed.taxonomy_code,
        evidence_spans=seed.evidence_spans,
    )


def _extract_external_candidates(
    documents: Sequence[Any],
    candidate_counter: Iterable[int],
) -> tuple[List[RawDoctrineCandidate], List[Dict[str, Any]]]:
    candidates: List[RawDoctrineCandidate] = []
    rejected_fragments: List[Dict[str, Any]] = []

    for document in documents:
        for fragment in split_text_fragments(document.body):
            reason = None
            if is_motivational_only(fragment):
                reason = "motivational_only"
            elif is_vague_commentary(fragment):
                reason = "too_vague"
            elif not has_operational_signal(fragment):
                reason = "non_operational"

            if reason:
                rejected_fragments.append(
                    {
                        "source_id": document.source_id,
                        "source_type": document.source_type,
                        "fragment": fragment,
                        "reason": reason,
                    }
                )
                continue

            for problem_id in document.problem_ids:
                candidates.append(
                    RawDoctrineCandidate(
                        candidate_id=f"cand_{next(candidate_counter):04d}",
                        problem_id=problem_id,
                        source_type=document.source_type,
                        source_ref=document.source_id,
                        author=document.author,
                        raw_text=fragment,
                        source_reliability_tier=SOURCE_RELIABILITY_TIERS[document.source_type],
                    )
                )

    return candidates, rejected_fragments


def run_extract_candidates(config: Dict[str, Any], backend_override: str | None = None) -> Dict[str, Any]:
    profile, problems, skipped_rows = load_scoped_problems(config, backend_override=backend_override)
    external_documents, source_warnings = load_external_sources(config)

    candidate_counter = count(1)
    seed_bundles = [_generate_seed_bundle(problem.model_dump()) for problem in problems]
    raw_candidates: List[RawDoctrineCandidate] = []
    for bundle in seed_bundles:
        for seed in bundle.required_doctrines + bundle.anti_patterns + bundle.verification_doctrines:
            raw_candidates.append(_seed_to_raw_candidate(seed, f"cand_{next(candidate_counter):04d}"))

    external_candidates, rejected_fragments = _extract_external_candidates(external_documents, candidate_counter)
    raw_candidates.extend(external_candidates)

    paths = config["paths"]
    write_log_json(Path(paths["logs"]) / "problem_db_schema_profile.json", profile.model_dump())
    write_log_jsonl(Path(paths["logs"]) / "problem_scope_skips.jsonl", skipped_rows)
    write_log_jsonl(Path(paths["logs"]) / "candidate_extraction_rejections.jsonl", rejected_fragments)
    write_log_json(Path(paths["logs"]) / "external_source_warnings.json", {"warnings": source_warnings})
    write_jsonl(Path(paths["candidates"]) / "scoped_problems.jsonl", (problem.model_dump() for problem in problems))
    write_jsonl(Path(paths["candidates"]) / "problem_seed_bundles.jsonl", (bundle.model_dump() for bundle in seed_bundles))
    write_jsonl(Path(paths["candidates"]) / "raw_doctrine_candidates.jsonl", (candidate.model_dump() for candidate in raw_candidates))

    return {
        "profile": profile.model_dump(),
        "problems": len(problems),
        "seed_bundles": len(seed_bundles),
        "raw_candidates": len(raw_candidates),
        "source_warnings": source_warnings,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Extract doctrine candidates from scoped problems and raw text sources.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    parser.add_argument("--problem-backend", choices=["supabase", "fixture"], default=None)
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_extract_candidates(config, backend_override=args.problem_backend)


if __name__ == "__main__":
    main()
