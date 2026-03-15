from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from src.pharnote.doctrine.schemas import NormalizedDoctrineCandidate, RawDoctrineCandidate
from src.pharnote.doctrine.taxonomy import TAXONOMY_REGISTRY
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_jsonl, write_jsonl
from src.pharnote.utils.text_cleaning import (
    compact_whitespace,
    has_operational_signal,
    is_item_specific,
    is_motivational_only,
    is_vague_commentary,
    normalize_for_match,
)


def _taxonomy_match_from_text(text: str) -> Optional[Dict[str, Any]]:
    lowered = compact_whitespace(text).lower()
    scored: List[Tuple[int, Dict[str, Any]]] = []
    for entry in TAXONOMY_REGISTRY:
        hits = sum(1 for keyword in entry["keywords"] if keyword.lower() in lowered)
        if hits > 0:
            scored.append((hits, entry))
    if not scored:
        return None
    scored.sort(key=lambda item: (-item[0], item[1]["taxonomy_code"]))
    return scored[0][1]


def _parse_seed_markup(text: str) -> Optional[Tuple[str, str]]:
    if "조건:" not in text or "행동:" not in text:
        return None
    try:
        condition_part = text.split("조건:", 1)[1].split("/ 행동:", 1)[0]
        action_part = text.split("/ 행동:", 1)[1]
    except IndexError:
        return None
    condition = compact_whitespace(condition_part)
    action = compact_whitespace(action_part)
    if condition and action:
        return condition, action
    return None


def _generic_condition_action(text: str) -> Optional[Tuple[str, str]]:
    normalized = compact_whitespace(text)
    for marker in ["이면", "라면", "일 때", "경우"]:
        if marker in normalized:
            left, right = normalized.split(marker, 1)
            condition = compact_whitespace(left)
            action = compact_whitespace(right)
            if condition and action:
                return condition, action
    if "말고" in normalized or "먼저" in normalized:
        return "직접 전개보다 먼저 판단해야 할 구조가 있다", normalized
    return None


def _normalize_candidate(candidate: RawDoctrineCandidate) -> Tuple[Optional[NormalizedDoctrineCandidate], Optional[Dict[str, Any]]]:
    text = compact_whitespace(candidate.raw_text)
    if is_motivational_only(text):
        return None, {"candidate_id": candidate.candidate_id, "problem_id": candidate.problem_id, "raw_text": text, "rejection_reason": "motivational_only"}
    if is_vague_commentary(text):
        return None, {"candidate_id": candidate.candidate_id, "problem_id": candidate.problem_id, "raw_text": text, "rejection_reason": "too_vague"}
    if not has_operational_signal(text):
        return None, {"candidate_id": candidate.candidate_id, "problem_id": candidate.problem_id, "raw_text": text, "rejection_reason": "non_operational"}
    if candidate.source_type != "problem_seed" and is_item_specific(text):
        return None, {"candidate_id": candidate.candidate_id, "problem_id": candidate.problem_id, "raw_text": text, "rejection_reason": "too_item_specific"}

    parsed_seed = _parse_seed_markup(text)
    taxonomy_entry = None
    condition_action: Optional[Tuple[str, str]] = None
    confidence = 0.0

    if candidate.taxonomy_code:
        taxonomy_entry = next((entry for entry in TAXONOMY_REGISTRY if entry["taxonomy_code"] == candidate.taxonomy_code), None)
    if parsed_seed:
        condition_action = parsed_seed
        confidence = 0.95 if candidate.source_type == "problem_seed" else 0.82
    elif taxonomy_entry:
        condition_action = (taxonomy_entry["condition"], taxonomy_entry["action"])
        confidence = 0.88
    else:
        taxonomy_entry = _taxonomy_match_from_text(text)
        if taxonomy_entry:
            condition_action = (taxonomy_entry["condition"], taxonomy_entry["action"])
            confidence = 0.81 if candidate.source_type == "community" else 0.86
        else:
            parsed_generic = _generic_condition_action(text)
            if parsed_generic is None:
                return None, {"candidate_id": candidate.candidate_id, "problem_id": candidate.problem_id, "raw_text": text, "rejection_reason": "too_vague"}
            condition_action = parsed_generic
            confidence = 0.63

    condition, action = condition_action
    fingerprint = normalize_for_match(f"{condition}|{action}")
    return (
        NormalizedDoctrineCandidate(
            candidate_id=candidate.candidate_id,
            problem_id=candidate.problem_id,
            source_type=candidate.source_type,
            condition=condition,
            action=action,
            normalization_confidence=round(confidence, 4),
            source_ref=candidate.source_ref,
            taxonomy_group=taxonomy_entry["taxonomy_group"] if taxonomy_entry else candidate.taxonomy_group,
            taxonomy_code=taxonomy_entry["taxonomy_code"] if taxonomy_entry else candidate.taxonomy_code,
            normalized_fingerprint=fingerprint,
        ),
        None,
    )


def run_normalize_candidates(config: Dict[str, Any]) -> Dict[str, Any]:
    raw_rows = read_jsonl(Path(config["paths"]["candidates"]) / "raw_doctrine_candidates.jsonl")
    raw_candidates = [RawDoctrineCandidate.model_validate(row) for row in raw_rows]

    normalized_candidates: List[NormalizedDoctrineCandidate] = []
    rejections: List[Dict[str, Any]] = []
    for candidate in raw_candidates:
        normalized, rejection = _normalize_candidate(candidate)
        if normalized:
            normalized_candidates.append(normalized)
        if rejection:
            rejections.append(rejection)

    write_jsonl(
        Path(config["paths"]["normalized"]) / "normalized_doctrine_candidates.jsonl",
        (candidate.model_dump() for candidate in normalized_candidates),
    )
    write_jsonl(
        Path(config["paths"]["logs"]) / "normalization_rejections.jsonl",
        rejections,
    )
    return {
        "raw_candidates": len(raw_candidates),
        "normalized_candidates": len(normalized_candidates),
        "rejections": len(rejections),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Normalize raw doctrine candidates into condition-action doctrines.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_normalize_candidates(config)


if __name__ == "__main__":
    main()
