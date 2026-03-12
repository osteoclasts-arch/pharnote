from __future__ import annotations

import unittest

from src.pharnote.doctrine.schemas import (
    DoctrineCluster,
    DoctrineScoreBundle,
    NormalizedDoctrineCandidate,
    ProblemDbSchemaProfile,
    ProblemDoctrinePayload,
    ProblemDoctrineSeed,
    RawDoctrineCandidate,
)


class DoctrineSchemaTest(unittest.TestCase):
    def test_raw_candidate_schema(self) -> None:
        candidate = RawDoctrineCandidate(
            candidate_id="cand_0001",
            problem_id="2024_06_mock_common_q15",
            source_type="community",
            source_ref="orbi_post_331",
            author="orbi_user_x",
            raw_text="조건을 따로 보지 말고 묶어서 봐야 한다",
            source_reliability_tier=3,
        )
        self.assertEqual(candidate.problem_id, "2024_06_mock_common_q15")

    def test_normalized_candidate_schema(self) -> None:
        candidate = NormalizedDoctrineCandidate(
            candidate_id="cand_0001",
            problem_id="2024_06_mock_common_q15",
            source_type="community",
            condition="여러 조건이 동일한 변수 또는 객체에 결합된다",
            action="조건을 분리 전개하지 말고 공통 변수 기준으로 재정렬한다",
            normalization_confidence=0.81,
        )
        self.assertAlmostEqual(candidate.normalization_confidence, 0.81)

    def test_cluster_and_payload_schema(self) -> None:
        cluster = DoctrineCluster(
            doctrine_id="doc_0001",
            condition="여러 조건이 하나의 대상에 걸려 있다",
            action="조건을 공통 대상 기준으로 재정렬한다",
            supported_problem_ids=["2024_06_mock_common_q15", "2025_09_mock_common_q14"],
            scores=DoctrineScoreBundle(overall_score=0.83),
            approval_status="review_needed",
        )
        payload = ProblemDoctrinePayload(
            problem_id="2024_06_mock_common_q15",
            recommended_doctrine_ids=["doc_0001"],
            required_doctrines=[],
            common_missed_doctrines=[],
        )
        self.assertEqual(cluster.approval_status, "review_needed")
        self.assertEqual(payload.recommended_doctrine_ids[0], "doc_0001")

    def test_schema_profile_and_seed(self) -> None:
        profile = ProblemDbSchemaProfile(
            backend="fixture",
            table_name="past_questions",
            introspection_mode="fixture",
            available_columns=["id", "content", "metadata"],
            metadata_keys=["points", "section"],
            resolved_fields={"stem": "content"},
            resolved_metadata_fields={"points": "points"},
            sample_row_count=2,
        )
        seed = ProblemDoctrineSeed(
            seed_id="seed_a",
            problem_id="2024_06_mock_common_q15",
            bucket="required_doctrines",
            taxonomy_group="condition_binding",
            taxonomy_code="condition_binding",
            condition="여러 조건이 동일한 변수 또는 객체에 결합된다",
            action="조건을 분리 전개하지 말고 공통 변수 기준으로 재정렬한다",
            evidence_spans=["같은 함수 f(x)에 걸려"],
            seed_confidence=0.88,
        )
        self.assertEqual(profile.backend, "fixture")
        self.assertEqual(seed.taxonomy_code, "condition_binding")


if __name__ == "__main__":
    unittest.main()
