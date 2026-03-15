from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set

from src.pharnote.doctrine.approval_workflow import run_approval_workflow
from src.pharnote.doctrine.cluster_doctrines import run_cluster_doctrines
from src.pharnote.doctrine.export_pharnote_payloads import run_export_pharnote_payloads
from src.pharnote.doctrine.extract_candidates import run_extract_candidates
from src.pharnote.doctrine.normalize_candidates import run_normalize_candidates
from src.pharnote.doctrine.score_doctrines import run_score_doctrines
from src.pharnote.ingestion.load_problem_db import inspect_live_problem_db
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_jsonl, write_json


def _counter_from_values(values: Iterable[object]) -> Dict[str, int]:
    counter = collections.Counter(str(value) for value in values)
    return dict(sorted(counter.items()))


def _problem_ids_from_seed_bundles(config: Dict) -> List[str]:
    rows = read_jsonl(Path(config["paths"]["candidates"]) / "problem_seed_bundles.jsonl")
    return sorted({str(row["problem_id"]) for row in rows if row.get("problem_id")})


def _problem_ids_from_normalized_candidates(config: Dict) -> List[str]:
    rows = read_jsonl(Path(config["paths"]["normalized"]) / "normalized_doctrine_candidates.jsonl")
    return sorted({str(row["problem_id"]) for row in rows if row.get("problem_id")})


def _problem_ids_from_clusters(config: Dict) -> List[str]:
    rows = read_jsonl(Path(config["paths"]["approved"]) / "doctrine_clusters.jsonl")
    problem_ids: Set[str] = set()
    for row in rows:
        for problem_id in row.get("supported_problem_ids", []):
            problem_ids.add(str(problem_id))
    return sorted(problem_ids)


def _problem_ids_from_payloads(config: Dict) -> List[str]:
    rows = read_jsonl(Path(config["paths"]["outputs"]) / "problem_doctrine_payloads.jsonl")
    return sorted({str(row["problem_id"]) for row in rows if row.get("problem_id")})


def _build_stage_drop_map(
    scoped_problem_ids: List[str],
    seeded_problem_ids: List[str],
    normalized_problem_ids: List[str],
    clustered_problem_ids: List[str],
    payload_problem_ids: List[str],
) -> Dict[str, List[str]]:
    scoped = set(scoped_problem_ids)
    seeded = set(seeded_problem_ids)
    normalized = set(normalized_problem_ids)
    clustered = set(clustered_problem_ids)
    payloaded = set(payload_problem_ids)
    return {
        "scope_to_seed": sorted(scoped - seeded),
        "seed_to_normalized": sorted(seeded - normalized),
        "normalized_to_clustered": sorted(normalized - clustered),
        "clustered_to_payload": sorted(clustered - payloaded),
        "scope_to_payload": sorted(scoped - payloaded),
    }


def _coverage_alerts(
    config: Dict,
    report: Dict,
    scoped_problem_ids: List[str],
    seeded_problem_ids: List[str],
    normalized_problem_ids: List[str],
    clustered_problem_ids: List[str],
    payload_problem_ids: List[str],
    stage_drop_map: Dict[str, List[str]],
) -> List[str]:
    alerts: List[str] = []
    expected_years = {str(year) for year in config["scope"]["years"]}
    actual_years = set(report["actual_problem_count_by_year"].keys())
    missing_years = sorted(expected_years - actual_years)
    if missing_years:
        alerts.append(f"Missing scoped coverage for expected academic years: {', '.join(missing_years)}")

    expected_exam_types = set(config["scope"]["exam_types"])
    actual_exam_types = set(report["actual_problem_count_by_exam_type"].keys())
    missing_exam_types = sorted(expected_exam_types - actual_exam_types)
    if missing_exam_types:
        alerts.append(f"Missing scoped coverage for expected exam types: {', '.join(missing_exam_types)}")

    if stage_drop_map["scope_to_seed"]:
        alerts.append(
            "Some scoped problems did not produce seed bundles: "
            + ", ".join(stage_drop_map["scope_to_seed"])
        )
    if stage_drop_map["seed_to_normalized"]:
        alerts.append(
            "Some seeded problems produced no normalized candidates: "
            + ", ".join(stage_drop_map["seed_to_normalized"])
        )
    if stage_drop_map["normalized_to_clustered"]:
        alerts.append(
            "Some normalized-candidate problems were not linked to any doctrine cluster: "
            + ", ".join(stage_drop_map["normalized_to_clustered"])
        )
    if stage_drop_map["clustered_to_payload"]:
        alerts.append(
            "Some cluster-linked problems did not receive exported payloads: "
            + ", ".join(stage_drop_map["clustered_to_payload"])
        )

    common_rules = report["actual_problem_count_by_common_section_detection_rule"]
    if not common_rules:
        alerts.append("No common-section detection rules were recorded for scoped problems.")
    elif any(rule.endswith("unavailable") for rule in common_rules):
        alerts.append("Some scoped problems have unavailable common-section detection provenance.")

    point_rules = report["actual_problem_count_by_four_point_detection_rule"]
    if not point_rules:
        alerts.append("No 4-point detection rules were recorded for scoped problems.")
    elif any(rule.endswith("unavailable") for rule in point_rules):
        alerts.append("Some scoped problems have unavailable 4-point detection provenance.")

    if not scoped_problem_ids:
        alerts.append("Final scoped problem count is zero.")
    if scoped_problem_ids and not payload_problem_ids:
        alerts.append("Scoped problems were found, but no doctrine payloads were exported.")
    return alerts


def run_scope_coverage_audit(config: Dict, *, backend_override: Optional[str] = "supabase") -> Dict:
    inspection = inspect_live_problem_db(config, backend_override=backend_override)
    run_extract_candidates(config, backend_override=backend_override)
    run_normalize_candidates(config)
    run_cluster_doctrines(config)
    run_score_doctrines(config)
    run_approval_workflow(config)
    run_export_pharnote_payloads(config)

    scoped_rows = read_jsonl(Path(config["paths"]["candidates"]) / "scoped_problems.jsonl")
    scoped_problem_ids = sorted(str(row["problem_id"]) for row in scoped_rows if row.get("problem_id"))
    seeded_problem_ids = _problem_ids_from_seed_bundles(config)
    normalized_problem_ids = _problem_ids_from_normalized_candidates(config)
    clustered_problem_ids = _problem_ids_from_clusters(config)
    payload_problem_ids = _problem_ids_from_payloads(config)

    actual_problem_count_by_year = _counter_from_values(row["year"] for row in scoped_rows)
    actual_problem_count_by_exam_type = _counter_from_values(row["exam_type"] for row in scoped_rows)
    actual_problem_count_by_question_number = _counter_from_values(row["question_number"] for row in scoped_rows)
    actual_problem_count_by_common_rule = _counter_from_values(
        row.get("metadata", {}).get("common_section_detection_method", "unavailable")
        for row in scoped_rows
    )
    actual_problem_count_by_four_point_rule = _counter_from_values(
        row.get("metadata", {}).get("points_detection_method", "unavailable")
        for row in scoped_rows
    )

    skipped_rows = read_jsonl(Path(config["paths"]["logs"]) / "problem_scope_skips.jsonl")
    live_filter_drop_counts = _counter_from_values(row.get("skip_reason", "unknown") for row in skipped_rows)
    live_filter_drop_problem_ids = {
        key: sorted(str(row.get("record_id")) for row in skipped_rows if row.get("skip_reason") == key)
        for key in live_filter_drop_counts
    }

    stage_drop_map = _build_stage_drop_map(
        scoped_problem_ids,
        seeded_problem_ids,
        normalized_problem_ids,
        clustered_problem_ids,
        payload_problem_ids,
    )
    alerts = _coverage_alerts(
        config,
        {
            "actual_problem_count_by_year": actual_problem_count_by_year,
            "actual_problem_count_by_exam_type": actual_problem_count_by_exam_type,
            "actual_problem_count_by_common_section_detection_rule": actual_problem_count_by_common_rule,
            "actual_problem_count_by_four_point_detection_rule": actual_problem_count_by_four_point_rule,
        },
        scoped_problem_ids,
        seeded_problem_ids,
        normalized_problem_ids,
        clustered_problem_ids,
        payload_problem_ids,
        stage_drop_map,
    )

    expected_scope_text = (
        f"Academic years {', '.join(str(year) for year in config['scope']['years'])}; "
        f"exam types {', '.join(config['scope']['exam_types'])}; "
        f"subject {config['scope']['subject']}; "
        f"common_only={config['scope']['common_only']}; "
        f"points in {config['scope']['points']}."
    )

    report = {
        "expected_scope_definition": expected_scope_text,
        "inspection_summary": {
            "table_name": inspection["table_name"],
            "backend": inspection["backend"],
            "inspection_mode": inspection["inspection_mode"],
            "mapping_decisions": inspection["mapping_decisions"],
        },
        "actual_problem_count_by_year": actual_problem_count_by_year,
        "actual_problem_count_by_exam_type": actual_problem_count_by_exam_type,
        "actual_problem_count_by_question_number": actual_problem_count_by_question_number,
        "actual_problem_count_by_common_section_detection_rule": actual_problem_count_by_common_rule,
        "actual_problem_count_by_four_point_detection_rule": actual_problem_count_by_four_point_rule,
        "seeded_problem_ids": seeded_problem_ids,
        "payload_problem_ids": payload_problem_ids,
        "stage_counts": {
            "scoped_problems": len(scoped_problem_ids),
            "seeded_problems": len(seeded_problem_ids),
            "normalized_candidate_producing_problems": len(normalized_problem_ids),
            "clustered_doctrine_linked_problems": len(clustered_problem_ids),
            "exported_payload_problems": len(payload_problem_ids),
        },
        "problems_by_stage": {
            "scoped_problem_ids": scoped_problem_ids,
            "seeded_problem_ids": seeded_problem_ids,
            "normalized_candidate_problem_ids": normalized_problem_ids,
            "clustered_problem_ids": clustered_problem_ids,
            "payload_problem_ids": payload_problem_ids,
        },
        "problems_dropped_out_at_each_stage": {
            "live_filter_drop_counts": live_filter_drop_counts,
            "live_filter_drop_problem_ids": live_filter_drop_problem_ids,
            **stage_drop_map,
        },
        "coverage_alerts": alerts,
        "coverage_ok": not alerts,
    }
    return report


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit doctrine compiler scope coverage against the live DB.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    parser.add_argument("--problem-backend", choices=["supabase", "fixture"], default="supabase")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    report = run_scope_coverage_audit(config, backend_override=args.problem_backend)
    output_path = Path(config["paths"]["logs"]) / "scope_coverage_audit.json"
    write_json(output_path, report)
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
