from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Tuple

from src.pharnote.doctrine.schemas import DoctrineCluster, PayloadDoctrineEntry, ProblemDoctrinePayload, ProblemDoctrineSeedBundle
from src.pharnote.utils.json_utils import read_jsonl


def _load_payload_inputs(config: Dict) -> Tuple[List[ProblemDoctrineSeedBundle], List[DoctrineCluster]]:
    seed_rows = read_jsonl(Path(config["paths"]["candidates"]) / "problem_seed_bundles.jsonl")
    cluster_rows = read_jsonl(Path(config["paths"]["approved"]) / "doctrine_clusters.jsonl")
    seeds = [ProblemDoctrineSeedBundle.model_validate(row) for row in seed_rows]
    clusters = [DoctrineCluster.model_validate(row) for row in cluster_rows]
    return seeds, clusters


def build_problem_doctrine_payloads(config: Dict) -> Tuple[List[ProblemDoctrinePayload], List[DoctrineCluster]]:
    seed_bundles, clusters = _load_payload_inputs(config)
    clusters_by_problem: Dict[str, List[DoctrineCluster]] = {}
    for cluster in clusters:
        for problem_id in cluster.supported_problem_ids:
            clusters_by_problem.setdefault(problem_id, []).append(cluster)

    payloads: List[ProblemDoctrinePayload] = []
    for bundle in seed_bundles:
        problem_clusters = sorted(
            clusters_by_problem.get(bundle.problem_id, []),
            key=lambda cluster: cluster.scores.overall_score,
            reverse=True,
        )
        auto_clusters = [cluster for cluster in problem_clusters if cluster.approval_status == "auto_approved"]
        review_clusters = [cluster for cluster in problem_clusters if cluster.approval_status == "review_needed"]
        recommended = [cluster.doctrine_id for cluster in auto_clusters] or [cluster.doctrine_id for cluster in review_clusters[:2]]

        def seed_to_entry(seed, matched_cluster):
            evidence_summary = "; ".join(seed.evidence_spans[:2]) or seed.condition
            return PayloadDoctrineEntry(
                doctrine_id=matched_cluster.doctrine_id if matched_cluster else None,
                taxonomy_code=seed.taxonomy_code,
                condition=seed.condition,
                action=seed.action,
                evidence_summary=evidence_summary,
            )

        required_entries = []
        for seed in bundle.required_doctrines:
            matched = next((cluster for cluster in problem_clusters if seed.taxonomy_code in cluster.taxonomy_codes and cluster.approval_status != "rejected"), None)
            required_entries.append(seed_to_entry(seed, matched))

        missed_entries = []
        for seed in bundle.anti_patterns:
            matched = next((cluster for cluster in problem_clusters if seed.taxonomy_code in cluster.taxonomy_codes and cluster.approval_status != "rejected"), None)
            missed_entries.append(seed_to_entry(seed, matched))

        for seed in bundle.verification_doctrines:
            matched = next((cluster for cluster in auto_clusters if seed.taxonomy_code in cluster.taxonomy_codes), None)
            if matched is None:
                missed_entries.append(seed_to_entry(seed, matched))

        payloads.append(
            ProblemDoctrinePayload(
                problem_id=bundle.problem_id,
                recommended_doctrine_ids=recommended,
                required_doctrines=required_entries,
                common_missed_doctrines=missed_entries,
            )
        )
    return payloads, clusters
