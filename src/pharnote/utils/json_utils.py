from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable, List


def ensure_parent(path: str | Path) -> Path:
    resolved = Path(path)
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def read_json(path: str | Path, default: Any = None) -> Any:
    resolved = Path(path)
    if not resolved.exists():
        return default
    return json.loads(resolved.read_text(encoding="utf-8"))


def write_json(path: str | Path, payload: Any) -> None:
    resolved = ensure_parent(path)
    resolved.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def read_jsonl(path: str | Path) -> List[Any]:
    resolved = Path(path)
    if not resolved.exists():
        return []
    rows: List[Any] = []
    for line in resolved.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text:
            continue
        rows.append(json.loads(text))
    return rows


def write_jsonl(path: str | Path, rows: Iterable[Any]) -> None:
    resolved = ensure_parent(path)
    with resolved.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True))
            handle.write("\n")
