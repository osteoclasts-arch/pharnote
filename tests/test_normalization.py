from __future__ import annotations

import unittest
from pathlib import Path

from src.pharnote.doctrine.extract_candidates import run_extract_candidates
from src.pharnote.doctrine.normalize_candidates import run_normalize_candidates
from src.pharnote.utils.json_utils import read_jsonl
from tests._doctrine_helpers import build_temp_config


class NormalizationTest(unittest.TestCase):
    def test_normalization_outputs_condition_action(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            run_extract_candidates(config, backend_override="fixture")
            result = run_normalize_candidates(config)
            normalized_rows = read_jsonl(Path(config["paths"]["normalized"]) / "normalized_doctrine_candidates.jsonl")
            rejection_rows = read_jsonl(Path(config["paths"]["logs"]) / "normalization_rejections.jsonl")

            self.assertGreater(result["normalized_candidates"], 0)
            self.assertTrue(any("공통 변수 기준" in row["action"] for row in normalized_rows))
            self.assertTrue(any(row["rejection_reason"] == "too_item_specific" for row in rejection_rows))
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
