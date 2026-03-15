from __future__ import annotations

from pathlib import Path
from typing import Optional, TypedDict

from src.pharnote.doctrine.schemas import PayloadDoctrineEntry, ProblemDoctrinePayload
from src.pharnote.utils.json_utils import read_jsonl


DEFAULT_PAYLOAD_PATH = Path("data/doctrine/outputs/problem_doctrine_payloads.jsonl")


class DoctrinePayloadContract(TypedDict):
    recommended_doctrine_ids: list[str]
    required_doctrines: list[dict]
    likely_missed_doctrines: list[dict]


def _entry_to_dict(entry: PayloadDoctrineEntry) -> dict:
    return {
        "doctrine_id": entry.doctrine_id,
        "taxonomy_code": entry.taxonomy_code,
        "condition": entry.condition,
        "action": entry.action,
        "evidence_summary": entry.evidence_summary,
    }


def get_doctrine_payload_for_problem(
    problem_id: str,
    payload_path: str | Path = DEFAULT_PAYLOAD_PATH,
) -> Optional[DoctrinePayloadContract]:
    rows = read_jsonl(payload_path)
    payload = next(
        (
            ProblemDoctrinePayload.model_validate(row)
            for row in rows
            if row.get("problem_id") == problem_id
        ),
        None,
    )
    if payload is None:
        return None
    return {
        "recommended_doctrine_ids": list(payload.recommended_doctrine_ids),
        "required_doctrines": [_entry_to_dict(entry) for entry in payload.required_doctrines],
        "likely_missed_doctrines": [_entry_to_dict(entry) for entry in payload.common_missed_doctrines],
    }
