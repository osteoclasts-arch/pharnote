from __future__ import annotations

from pathlib import Path
from typing import Dict

from src.pharnote.review.doctrine_payload_adapter import get_doctrine_payload_for_problem


def attach_doctrines_to_review(problem_id: str, review_record: Dict, payload_path: str | Path) -> Dict:
    payload = get_doctrine_payload_for_problem(problem_id, payload_path=payload_path)
    return {
        **review_record,
        "problem_id": problem_id,
        "doctrine_payload": payload,
    }
