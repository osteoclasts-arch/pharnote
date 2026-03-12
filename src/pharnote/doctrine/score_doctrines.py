from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List

from src.pharnote.doctrine.schemas import DoctrineCluster, ProblemDoctrineSeedBundle, RawDoctrineCandidate
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_jsonl, write_jsonl
from src.pharnote.utils.similarity import weighted_similarity
from src.pharnote.utils.text_cleaning import has_operational_signal, is_item_specific, is_vague_commentary, tokenize


def _parse_problem_year(problem_id: str) -> int:
    return int(problem_id.split("_", 1)[0])


def _parse_problem_session(problem_id: str) -> str:
    if "_csat_" in problem_id:
        return "csat"
    if "_06_mock_" in problem_id:
        return "06_mock"
    if "_09_mock_" in problem_id:
        return "09_mock"
    return "unknown"


def _specificity_score(condition: str, action: str) -> float:
    score = 1.0
    combined = f"{condition} {action}"
    token_count = len(tokenize(combined))
    if is_vague_commentary(combined):
        score -= 0.35
    if token_count < 6 or token_count > 40:
        score -= 0.2
    if not has_operational_signal(action):
        score -= 0.25
    if condition == action:
        score -= 0.1
    return round(max(0.0, min(score, 1.0)), 6)


def _problem_alignment_score(cluster: DoctrineCluster, seed_map: Dict[str, ProblemDoctrineSeedBundle], heuristics: Dict) -> float:
    scores: List[float] = []
    for problem_id in cluster.supported_problem_ids:
        bundle = seed_map.get(problem_id)
        if not bundle:
            scores.append(0.0)
            continue
        seed_texts = [
            f"{seed.condition} {seed.action}"
            for seed in (bundle.required_doctrines + bundle.anti_patterns + bundle.verification_doctrines)
        ]
        cluster_text = f"{cluster.condition} {cluster.action}"
        similarities = [
            weighted_similarity(
                cluster_text,
                seed_text,
                sequence_weight=heuristics["sequence_weight"],
                token_weight=heuristics["token_overlap_weight"],
                verb_weight=heuristics["verb_overlap_weight"],
            )["overall_score"]
            for seed_text in seed_texts
        ]
        scores.append(max(similarities) if similarities else 0.0)
    if not scores:
        return 0.0
    return round(sum(scores) / len(scores), 6)


def run_score_doctrines(config: Dict) -> Dict[str, int]:
    cluster_rows = read_jsonl(Path(config["paths"]["normalized"]) / "doctrine_clusters.jsonl")
    raw_rows = read_jsonl(Path(config["paths"]["candidates"]) / "raw_doctrine_candidates.jsonl")
    seed_rows = read_jsonl(Path(config["paths"]["candidates"]) / "problem_seed_bundles.jsonl")
    clusters = [DoctrineCluster.model_validate(row) for row in cluster_rows]
    raw_candidates = {row["candidate_id"]: RawDoctrineCandidate.model_validate(row) for row in raw_rows}
    seed_map = {
        row["problem_id"]: ProblemDoctrineSeedBundle.model_validate(row)
        for row in seed_rows
    }

    heuristics = config["heuristics"]["clustering"]
    weights = config["heuristics"]["scoring"]["overall_weights"]
    score_breakdown: List[Dict] = []

    for cluster in clusters:
        member_rows = [raw_candidates[candidate_id] for candidate_id in cluster.supporting_candidate_ids if candidate_id in raw_candidates]
        distinct_problem_count = len(cluster.supported_problem_ids)
        distinct_year_count = len({_parse_problem_year(problem_id) for problem_id in cluster.supported_problem_ids})
        distinct_session_count = len({_parse_problem_session(problem_id) for problem_id in cluster.supported_problem_ids})
        problem_seed_support_count = sum(1 for row in member_rows if row.source_type == "problem_seed")
        external_support_count = sum(1 for row in member_rows if row.source_type != "problem_seed")
        distinct_author_count = len({row.author for row in member_rows if row.author})
        source_diversity_count = len({row.source_type for row in member_rows})
        item_specific_penalty = 1.0 if is_item_specific(f"{cluster.condition} {cluster.action}") else 0.0

        reusability = (
            0.35 * min(distinct_problem_count / 4, 1.0)
            + 0.25 * min(distinct_year_count / 3, 1.0)
            + 0.20 * min(distinct_session_count / 3, 1.0)
            + 0.20 * (1.0 - item_specific_penalty)
        )
        specificity = _specificity_score(cluster.condition, cluster.action)
        evidence = (
            0.50 * min(problem_seed_support_count / 3, 1.0)
            + 0.30 * min(external_support_count / 4, 1.0)
            + 0.20 * min(distinct_author_count / 3, 1.0)
        )
        source_diversity = min(source_diversity_count / 4, 1.0)
        problem_alignment = _problem_alignment_score(cluster, seed_map, heuristics)
        overall = (
            weights["reusability_score"] * reusability
            + weights["specificity_score"] * specificity
            + weights["evidence_score"] * evidence
            + weights["source_diversity_score"] * source_diversity
            + weights["problem_alignment_score"] * problem_alignment
        )

        cluster.scores.reusability_score = round(reusability, 6)
        cluster.scores.specificity_score = round(specificity, 6)
        cluster.scores.evidence_score = round(evidence, 6)
        cluster.scores.source_diversity_score = round(source_diversity, 6)
        cluster.scores.problem_alignment_score = round(problem_alignment, 6)
        cluster.scores.overall_score = round(overall, 6)

        score_breakdown.append(
            {
                "doctrine_id": cluster.doctrine_id,
                "features": {
                    "distinct_problem_count": distinct_problem_count,
                    "distinct_year_count": distinct_year_count,
                    "distinct_session_count": distinct_session_count,
                    "problem_seed_support_count": problem_seed_support_count,
                    "external_support_count": external_support_count,
                    "distinct_author_count": distinct_author_count,
                    "source_diversity_count": source_diversity_count,
                    "item_specific_penalty": item_specific_penalty,
                },
                "scores": cluster.scores.model_dump(),
            }
        )

    write_jsonl(
        Path(config["paths"]["normalized"]) / "scored_doctrine_clusters.jsonl",
        (cluster.model_dump() for cluster in clusters),
    )
    write_jsonl(
        Path(config["paths"]["logs"]) / "score_breakdown.jsonl",
        score_breakdown,
    )
    return {"clusters": len(clusters)}


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Score doctrine clusters with heuristic baseline metrics.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_score_doctrines(config)


if __name__ == "__main__":
    main()
