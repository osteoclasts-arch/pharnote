from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List

from src.pharnote.doctrine.schemas import ApprovalDecision, DoctrineCluster
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_jsonl, write_jsonl
from src.pharnote.utils.text_cleaning import is_item_specific


def _load_overrides(path: Path) -> Dict[str, Dict]:
    if not path.exists():
        return {}
    return {row["doctrine_id"]: row for row in read_jsonl(path) if "doctrine_id" in row}


def _threshold_trace(cluster: DoctrineCluster, thresholds: Dict) -> Dict:
    trace = {}
    for key, minimum in thresholds.items():
        if key == "supported_problem_count_min":
            actual = len(cluster.supported_problem_ids)
        else:
            score_key = key.replace("_min", "")
            actual = cluster.scores.model_dump().get(score_key, 0.0)
        trace[key] = {
            "actual": round(actual, 6) if isinstance(actual, float) else actual,
            "minimum": minimum,
            "passed": actual >= minimum,
        }
    return trace


def run_approval_workflow(config: Dict) -> Dict[str, int]:
    cluster_rows = read_jsonl(Path(config["paths"]["normalized"]) / "scored_doctrine_clusters.jsonl")
    clusters = [DoctrineCluster.model_validate(row) for row in cluster_rows]
    approval_rules = config["heuristics"]["approval"]
    overrides = _load_overrides(Path(config["paths"]["approved"]) / "reviewer_overrides.jsonl")

    approved_clusters: List[DoctrineCluster] = []
    decisions: List[ApprovalDecision] = []

    for cluster in clusters:
        override = overrides.get(cluster.doctrine_id)
        rejection_reasons: List[str] = []
        triggered_rules: List[str] = []
        threshold_trace = _threshold_trace(cluster, approval_rules["auto_approved"])

        if is_item_specific(f"{cluster.condition} {cluster.action}"):
            rejection_reasons.append("too_item_specific")
        if cluster.scores.specificity_score < 0.35:
            rejection_reasons.append("too_vague")
        if cluster.scores.evidence_score < 0.35:
            rejection_reasons.append("low_evidence")
        if cluster.scores.problem_alignment_score < 0.30 or not cluster.supported_problem_ids:
            rejection_reasons.append("unsupported_by_problem")

        if override:
            cluster.approval_status = override["approval_status"]
            triggered_rules.append("reviewer_override")
            decision = ApprovalDecision(
                doctrine_id=cluster.doctrine_id,
                approval_status=cluster.approval_status,
                rejection_reasons=rejection_reasons,
                triggered_rules=triggered_rules,
                threshold_trace=threshold_trace,
                override_note=override.get("note"),
            )
            decisions.append(decision)
            approved_clusters.append(cluster)
            continue

        auto_checks = threshold_trace
        review_min = approval_rules["review_needed"]["overall_score_min"]
        if rejection_reasons or cluster.scores.overall_score < review_min:
            cluster.approval_status = "rejected"
            triggered_rules.append("heuristic_reject")
        elif all(item["passed"] for item in auto_checks.values()):
            cluster.approval_status = "auto_approved"
            triggered_rules.append("auto_thresholds_met")
        else:
            cluster.approval_status = "review_needed"
            triggered_rules.append("review_default")

        decisions.append(
            ApprovalDecision(
                doctrine_id=cluster.doctrine_id,
                approval_status=cluster.approval_status,
                rejection_reasons=rejection_reasons,
                triggered_rules=triggered_rules,
                threshold_trace={**threshold_trace, "review_needed_overall_score_min": review_min},
            )
        )
        approved_clusters.append(cluster)

    write_jsonl(
        Path(config["paths"]["approved"]) / "doctrine_clusters.jsonl",
        (cluster.model_dump() for cluster in approved_clusters),
    )
    write_jsonl(
        Path(config["paths"]["approved"]) / "review_queue.jsonl",
        (cluster.model_dump() for cluster in approved_clusters if cluster.approval_status == "review_needed"),
    )
    write_jsonl(
        Path(config["paths"]["logs"]) / "approval_decisions.jsonl",
        (decision.model_dump() for decision in decisions),
    )
    return {
        "clusters": len(approved_clusters),
        "auto_approved": sum(cluster.approval_status == "auto_approved" for cluster in approved_clusters),
        "review_needed": sum(cluster.approval_status == "review_needed" for cluster in approved_clusters),
        "rejected": sum(cluster.approval_status == "rejected" for cluster in approved_clusters),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Apply heuristic baseline approval rules to scored doctrine clusters.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_approval_workflow(config)


if __name__ == "__main__":
    main()
