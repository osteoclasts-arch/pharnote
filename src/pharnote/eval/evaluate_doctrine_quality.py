from __future__ import annotations

from pathlib import Path
from typing import Dict

from src.pharnote.doctrine.schemas import DoctrineCluster, ProblemDoctrinePayload
from src.pharnote.utils.json_utils import read_jsonl


def evaluate_doctrine_quality(approved_clusters_path: str | Path, payloads_path: str | Path) -> Dict:
    cluster_rows = [DoctrineCluster.model_validate(row) for row in read_jsonl(approved_clusters_path)]
    payload_rows = [ProblemDoctrinePayload.model_validate(row) for row in read_jsonl(payloads_path)]
    if not cluster_rows:
        return {"cluster_count": 0, "payload_count": len(payload_rows), "auto_approved_ratio": 0.0, "average_overall_score": 0.0}

    auto_ratio = sum(cluster.approval_status == "auto_approved" for cluster in cluster_rows) / len(cluster_rows)
    average_overall = sum(cluster.scores.overall_score for cluster in cluster_rows) / len(cluster_rows)
    return {
        "cluster_count": len(cluster_rows),
        "payload_count": len(payload_rows),
        "auto_approved_ratio": round(auto_ratio, 6),
        "average_overall_score": round(average_overall, 6),
    }
