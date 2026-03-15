from __future__ import annotations

import unittest
from pathlib import Path

from src.pharnote.doctrine.approval_workflow import run_approval_workflow
from src.pharnote.doctrine.cluster_doctrines import run_cluster_doctrines
from src.pharnote.doctrine.extract_candidates import run_extract_candidates
from src.pharnote.doctrine.normalize_candidates import run_normalize_candidates
from src.pharnote.doctrine.score_doctrines import run_score_doctrines
from src.pharnote.utils.json_utils import read_jsonl
from tests._doctrine_helpers import build_temp_config


class ScoringTest(unittest.TestCase):
    def test_scoring_and_approval_emit_traces(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            run_extract_candidates(config, backend_override="fixture")
            run_normalize_candidates(config)
            run_cluster_doctrines(config)
            run_score_doctrines(config)
            approval_result = run_approval_workflow(config)

            score_rows = read_jsonl(Path(config["paths"]["logs"]) / "score_breakdown.jsonl")
            approval_rows = read_jsonl(Path(config["paths"]["logs"]) / "approval_decisions.jsonl")

            self.assertGreater(len(score_rows), 0)
            self.assertGreater(len(approval_rows), 0)
            self.assertIn("auto_approved", approval_result)
            self.assertTrue(all("threshold_trace" in row for row in approval_rows))
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
