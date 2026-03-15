from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable

from .json_utils import ensure_parent, write_json, write_jsonl


def write_log_json(path: str | Path, payload: Any) -> None:
    write_json(path, payload)


def write_log_jsonl(path: str | Path, rows: Iterable[Any]) -> None:
    write_jsonl(path, rows)


def touch_placeholder(path: str | Path) -> None:
    resolved = ensure_parent(path)
    if not resolved.exists():
        resolved.write_text("", encoding="utf-8")
