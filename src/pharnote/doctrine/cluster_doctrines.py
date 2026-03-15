from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

from src.pharnote.doctrine.schemas import DoctrineCluster, DoctrineScoreBundle, NormalizedDoctrineCandidate, RawDoctrineCandidate
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import read_jsonl, write_jsonl
from src.pharnote.utils.similarity import weighted_similarity


SOURCE_PRIORITY = {
    "problem_seed": 4,
    "instructor": 3,
    "founder": 2,
    "community": 1,
}


class UnionFind:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))

    def find(self, index: int) -> int:
        while self.parent[index] != index:
            self.parent[index] = self.parent[self.parent[index]]
            index = self.parent[index]
        return index

    def union(self, left: int, right: int) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root != right_root:
            self.parent[right_root] = left_root


def _representative(group: List[NormalizedDoctrineCandidate]) -> NormalizedDoctrineCandidate:
    return max(
        group,
        key=lambda candidate: (
            candidate.normalization_confidence,
            SOURCE_PRIORITY[candidate.source_type],
            candidate.candidate_id,
        ),
    )


def run_cluster_doctrines(config: Dict) -> Dict[str, int]:
    normalized_rows = read_jsonl(Path(config["paths"]["normalized"]) / "normalized_doctrine_candidates.jsonl")
    raw_rows = read_jsonl(Path(config["paths"]["candidates"]) / "raw_doctrine_candidates.jsonl")
    normalized_candidates = [NormalizedDoctrineCandidate.model_validate(row) for row in normalized_rows]
    raw_candidates = {row["candidate_id"]: RawDoctrineCandidate.model_validate(row) for row in raw_rows}

    exact_groups: Dict[str, List[NormalizedDoctrineCandidate]] = defaultdict(list)
    for candidate in normalized_candidates:
        exact_groups[candidate.normalized_fingerprint or candidate.candidate_id].append(candidate)

    grouped_candidates = list(exact_groups.values())
    representatives = [_representative(group) for group in grouped_candidates]
    union_find = UnionFind(len(grouped_candidates))
    heuristics = config["heuristics"]["clustering"]
    pairwise_evidence: List[Dict] = []

    for left_index in range(len(grouped_candidates)):
        left_rep = representatives[left_index]
        left_text = f"{left_rep.condition} {left_rep.action}"
        for right_index in range(left_index + 1, len(grouped_candidates)):
            right_rep = representatives[right_index]
            right_text = f"{right_rep.condition} {right_rep.action}"
            scores = weighted_similarity(
                left_text,
                right_text,
                sequence_weight=heuristics["sequence_weight"],
                token_weight=heuristics["token_overlap_weight"],
                verb_weight=heuristics["verb_overlap_weight"],
            )
            taxonomy_bonus = 0.35 if (
                left_rep.taxonomy_code
                and left_rep.taxonomy_code == right_rep.taxonomy_code
            ) else 0.0
            adjusted_score = round(min(scores["overall_score"] + taxonomy_bonus, 1.0), 6)
            should_merge = adjusted_score >= heuristics["pairwise_merge_threshold"]
            pairwise_evidence.append(
                {
                    "left_candidate_id": left_rep.candidate_id,
                    "right_candidate_id": right_rep.candidate_id,
                    "left_fingerprint": left_rep.normalized_fingerprint,
                    "right_fingerprint": right_rep.normalized_fingerprint,
                    "merged": should_merge,
                    "scores": {
                        **scores,
                        "taxonomy_bonus": taxonomy_bonus,
                        "adjusted_overall_score": adjusted_score,
                    },
                }
            )
            if should_merge:
                union_find.union(left_index, right_index)

    clusters_by_root: Dict[int, List[NormalizedDoctrineCandidate]] = defaultdict(list)
    merge_evidence_by_root: Dict[int, List[Dict]] = defaultdict(list)
    for index, group in enumerate(grouped_candidates):
        root = union_find.find(index)
        clusters_by_root[root].extend(group)
    for evidence in pairwise_evidence:
        left_idx = next(
            idx for idx, rep in enumerate(representatives)
            if rep.candidate_id == evidence["left_candidate_id"]
        )
        right_idx = next(
            idx for idx, rep in enumerate(representatives)
            if rep.candidate_id == evidence["right_candidate_id"]
        )
        if union_find.find(left_idx) == union_find.find(right_idx):
            merge_evidence_by_root[union_find.find(left_idx)].append(evidence)

    doctrine_clusters: List[DoctrineCluster] = []
    for cluster_index, root in enumerate(sorted(clusters_by_root), start=1):
        cluster_candidates = clusters_by_root[root]
        representative = _representative(cluster_candidates)
        supported_problem_ids = sorted({candidate.problem_id for candidate in cluster_candidates})
        taxonomy_codes = sorted({candidate.taxonomy_code for candidate in cluster_candidates if candidate.taxonomy_code})
        source_types = sorted({candidate.source_type for candidate in cluster_candidates})
        evidence_summary = []
        for candidate in cluster_candidates[:4]:
            raw = raw_candidates.get(candidate.candidate_id)
            if raw:
                summary = f"{raw.source_type}:{raw.raw_text[:120]}"
                if summary not in evidence_summary:
                    evidence_summary.append(summary)

        doctrine_clusters.append(
            DoctrineCluster(
                doctrine_id=f"doc_{cluster_index:04d}",
                condition=representative.condition,
                action=representative.action,
                supported_problem_ids=supported_problem_ids,
                scores=DoctrineScoreBundle(),
                approval_status="review_needed",
                supporting_candidate_ids=sorted(candidate.candidate_id for candidate in cluster_candidates),
                taxonomy_codes=taxonomy_codes,
                source_types=source_types,
                merge_evidence=merge_evidence_by_root[root],
                evidence_summary=evidence_summary,
            )
        )

    write_jsonl(
        Path(config["paths"]["normalized"]) / "doctrine_clusters.jsonl",
        (cluster.model_dump() for cluster in doctrine_clusters),
    )
    write_jsonl(
        Path(config["paths"]["logs"]) / "cluster_merge_evidence.jsonl",
        pairwise_evidence,
    )
    return {
        "normalized_candidates": len(normalized_candidates),
        "clusters": len(doctrine_clusters),
        "pairwise_checks": len(pairwise_evidence),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cluster normalized doctrine candidates with heuristic similarity.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_cluster_doctrines(config)


if __name__ == "__main__":
    main()
