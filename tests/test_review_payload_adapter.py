from __future__ import annotations

import unittest

from src.pharnote.review.doctrine_payload_adapter import get_doctrine_payload_for_problem


class ReviewPayloadAdapterSmokeTest(unittest.TestCase):
    def test_loads_fixture_doctrine_payload_for_known_problem(self) -> None:
        payload = get_doctrine_payload_for_problem("2024_06_mock_common_q15")
        self.assertIsNotNone(payload)
        assert payload is not None
        self.assertEqual(
            sorted(payload.keys()),
            ["likely_missed_doctrines", "recommended_doctrine_ids", "required_doctrines"],
        )
        self.assertIsInstance(payload["recommended_doctrine_ids"], list)
        self.assertIsInstance(payload["required_doctrines"], list)
        self.assertIsInstance(payload["likely_missed_doctrines"], list)
        attached_count = (
            len(payload["recommended_doctrine_ids"])
            + len(payload["required_doctrines"])
            + len(payload["likely_missed_doctrines"])
        )
        self.assertGreater(attached_count, 0)
        self.assertGreaterEqual(len(payload["recommended_doctrine_ids"]), 1)


if __name__ == "__main__":
    unittest.main()
