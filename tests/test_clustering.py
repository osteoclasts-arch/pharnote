from __future__ import annotations

import unittest
from pathlib import Path

from src.pharnote.doctrine.cluster_doctrines import run_cluster_doctrines
from src.pharnote.utils.json_utils import write_jsonl, read_jsonl
from tests._doctrine_helpers import build_temp_config


class ClusteringTest(unittest.TestCase):
    def test_heuristic_clustering_merges_near_duplicates(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            normalized_path = Path(config["paths"]["normalized"]) / "normalized_doctrine_candidates.jsonl"
            candidate_path = Path(config["paths"]["candidates"]) / "raw_doctrine_candidates.jsonl"
            write_jsonl(
                normalized_path,
                [
                    {
                        "candidate_id": "cand_0001",
                        "problem_id": "2024_06_mock_common_q15",
                        "source_type": "problem_seed",
                        "condition": "여러 조건이 동일한 변수 또는 객체에 결합된다",
                        "action": "조건을 분리 전개하지 말고 공통 변수 기준으로 재정렬한다",
                        "normalization_confidence": 0.95,
                        "normalized_fingerprint": "a",
                        "taxonomy_code": "condition_binding",
                    },
                    {
                        "candidate_id": "cand_0002",
                        "problem_id": "2025_09_mock_common_q14",
                        "source_type": "community",
                        "condition": "여러 조건이 같은 대상에 동시에 걸린다",
                        "action": "조건을 따로 풀지 말고 공통 대상 기준으로 묶는다",
                        "normalization_confidence": 0.82,
                        "normalized_fingerprint": "b",
                        "taxonomy_code": "condition_binding",
                    },
                    {
                        "candidate_id": "cand_0003",
                        "problem_id": "2026_csat_common_q18",
                        "source_type": "instructor",
                        "condition": "절댓값과 부호 때문에 경우가 갈린다",
                        "action": "분기 기준을 먼저 적고 경우를 나눈다",
                        "normalization_confidence": 0.9,
                        "normalized_fingerprint": "c",
                        "taxonomy_code": "case_triggering",
                    },
                ],
            )
            write_jsonl(
                candidate_path,
                [
                    {"candidate_id": "cand_0001", "problem_id": "2024_06_mock_common_q15", "source_type": "problem_seed", "source_ref": "seed1", "author": "sys", "raw_text": "조건: a / 행동: b", "source_reliability_tier": 5},
                    {"candidate_id": "cand_0002", "problem_id": "2025_09_mock_common_q14", "source_type": "community", "source_ref": "src1", "author": "orbi", "raw_text": "조건을 묶어라", "source_reliability_tier": 3},
                    {"candidate_id": "cand_0003", "problem_id": "2026_csat_common_q18", "source_type": "instructor", "source_ref": "src2", "author": "inst", "raw_text": "경우를 나눠라", "source_reliability_tier": 4},
                ],
            )
            result = run_cluster_doctrines(config)
            cluster_rows = read_jsonl(Path(config["paths"]["normalized"]) / "doctrine_clusters.jsonl")
            self.assertEqual(result["clusters"], 2)
            self.assertEqual(len(cluster_rows), 2)
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
