from __future__ import annotations

import unittest
from pathlib import Path

from src.pharnote.doctrine.approval_workflow import run_approval_workflow
from src.pharnote.doctrine.cluster_doctrines import run_cluster_doctrines
from src.pharnote.doctrine.export_pharnote_payloads import run_export_pharnote_payloads
from src.pharnote.doctrine.extract_candidates import run_extract_candidates
from src.pharnote.doctrine.normalize_candidates import run_normalize_candidates
from src.pharnote.doctrine.score_doctrines import run_score_doctrines
from src.pharnote.utils.json_utils import read_json, read_jsonl
from tests._doctrine_helpers import build_temp_config


class ExportPayloadsTest(unittest.TestCase):
    def test_export_payloads_shape(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            run_extract_candidates(config, backend_override="fixture")
            run_normalize_candidates(config)
            run_cluster_doctrines(config)
            run_score_doctrines(config)
            run_approval_workflow(config)
            result = run_export_pharnote_payloads(config)

            payload_rows = read_jsonl(Path(config["paths"]["outputs"]) / "problem_doctrine_payloads.jsonl")
            sample_payload = read_json(Path(config["paths"]["outputs"]) / "sample_outputs.json")
            self.assertEqual(result["payloads"], 4)
            self.assertTrue(all("recommended_doctrine_ids" in row for row in payload_rows))
            self.assertIn("payload_examples", sample_payload)
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
