from __future__ import annotations

import copy
import unittest
from pathlib import Path
from unittest import mock

from src.pharnote.doctrine.extract_candidates import run_extract_candidates
from src.pharnote.ingestion.load_problem_db import inspect_live_problem_db, load_scoped_problems
from src.pharnote.utils.json_utils import read_json, read_jsonl
from tests._doctrine_helpers import build_temp_config


class CandidateExtractionTest(unittest.TestCase):
    def test_extract_candidates_from_fixture(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            result = run_extract_candidates(config, backend_override="fixture")
            self.assertEqual(result["problems"], 4)

            seed_rows = read_jsonl(Path(config["paths"]["candidates"]) / "problem_seed_bundles.jsonl")
            raw_rows = read_jsonl(Path(config["paths"]["candidates"]) / "raw_doctrine_candidates.jsonl")
            rejection_rows = read_jsonl(Path(config["paths"]["logs"]) / "candidate_extraction_rejections.jsonl")

            self.assertTrue(any(row["problem_id"] == "2024_06_mock_common_q15" for row in seed_rows))
            self.assertTrue(any(row["source_type"] == "problem_seed" for row in raw_rows))
            self.assertTrue(any(row["source_type"] == "community" for row in raw_rows))
            self.assertTrue(any(row["reason"] == "motivational_only" for row in rejection_rows))
        finally:
            temp_dir.cleanup()

    def test_information_schema_introspection_path(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            sample_rows = [
                {
                    "record_id": "alt_1",
                    "curriculum_subject": "수학",
                    "exam_year": 2024,
                    "exam_month": 6,
                    "test_type": "6월 모의평가",
                    "item_number": 15,
                    "question_text": "함수 조건 문제 ① 1 ② 2 ③ 3 ④ 4 ⑤ 5",
                    "correct_answer": "3",
                    "explanation": "조건을 묶어 본다.",
                    "metadata": {"point_value": 4, "common_section": "공통", "concept_tags": ["함수"]},
                }
            ]
            with mock.patch("src.pharnote.ingestion.load_problem_db._determine_backend", return_value="database_url"), \
                 mock.patch("src.pharnote.ingestion.load_problem_db._fetch_rows_via_psql", return_value=sample_rows), \
                 mock.patch(
                     "src.pharnote.ingestion.load_problem_db._introspect_columns_via_psql",
                     return_value=["record_id", "curriculum_subject", "exam_year", "exam_month", "test_type", "item_number", "question_text", "correct_answer", "explanation", "metadata"],
                 ):
                profile, problems, _ = load_scoped_problems(config, backend_override="supabase")
            self.assertEqual(profile.introspection_mode, "information_schema")
            self.assertEqual(profile.resolved_fields["stem"], "question_text")
            self.assertEqual(profile.resolved_metadata_fields["points"], "point_value")
            self.assertEqual(len(problems), 1)
        finally:
            temp_dir.cleanup()

    def test_fail_closed_when_points_missing(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            broken_fixture = Path(temp_dir.name) / "broken_fixture.json"
            broken_fixture.write_text(
                '[{"id":"x1","subject":"수학","year":2024,"month":6,"exam_type":"6월 모의평가","question_number":15,"content":"문제 ① 1 ② 2 ③ 3 ④ 4 ⑤ 5","answer":"1","solution":"해설","metadata":{"section":"공통"}}]',
                encoding="utf-8",
            )
            config["problem_db"]["fixture_path"] = str(broken_fixture)
            profile, problems, skipped = load_scoped_problems(config, backend_override="fixture")
            self.assertEqual(profile.introspection_mode, "fixture")
            self.assertEqual(len(problems), 0)
            self.assertTrue(any(row["skip_reason"] == "points_unavailable_or_out_of_scope" for row in skipped))
        finally:
            temp_dir.cleanup()

    def test_live_inspection_report_shape(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            sample_rows = [
                {
                    "id": "pq1",
                    "subject": "수학",
                    "year": 2024,
                    "month": 6,
                    "exam_type": "6월 모의평가",
                    "question_number": 15,
                    "content": "함수 문제 ① 1 ② 2 ③ 3 ④ 4 ⑤ 5",
                    "answer": "3",
                    "solution": "조건을 묶는다.",
                    "metadata": {"points": 4, "section": "공통", "keywords": ["함수"]},
                },
                {
                    "id": "pq2",
                    "subject": "수학",
                    "year": 2025,
                    "month": 9,
                    "exam_type": "9월 모의평가",
                    "question_number": 27,
                    "content": "선택 문제",
                    "answer": "1",
                    "solution": "선택",
                    "metadata": {"points": 4, "section": "선택"},
                },
            ]
            with mock.patch("src.pharnote.ingestion.load_problem_db._determine_backend", return_value="supabase"), \
                 mock.patch("src.pharnote.ingestion.load_problem_db._fetch_rows_via_supabase", return_value=sample_rows):
                report = inspect_live_problem_db(config, backend_override="supabase")
            self.assertEqual(report["total_rows_sampled"], 2)
            self.assertIn("row_counts_dropped_by_filter", report)
            self.assertIn("common_section_detection", report)
            self.assertEqual(report["final_scoped_problem_count"], 1)
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
