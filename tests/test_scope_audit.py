from __future__ import annotations

import unittest

from src.pharnote.eval.audit_scope_coverage import run_scope_coverage_audit
from tests._doctrine_helpers import build_temp_config


class ScopeCoverageAuditTest(unittest.TestCase):
    def test_scope_coverage_audit_report_shape(self) -> None:
        temp_dir, config = build_temp_config()
        try:
            report = run_scope_coverage_audit(config, backend_override="fixture")
            self.assertIn("expected_scope_definition", report)
            self.assertIn("stage_counts", report)
            self.assertIn("problems_dropped_out_at_each_stage", report)
            self.assertIn("actual_problem_count_by_year", report)
            self.assertEqual(report["stage_counts"]["scoped_problems"], 4)
            self.assertTrue(report["payload_problem_ids"])
        finally:
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
