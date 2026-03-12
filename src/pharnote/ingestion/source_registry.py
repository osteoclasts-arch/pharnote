from __future__ import annotations

from pathlib import Path
from typing import Dict


SUPPORTED_SOURCE_FILES: Dict[str, str] = {
    "community": "community_sources.jsonl",
    "instructor": "instructor_sources.jsonl",
    "founder": "founder_sources.jsonl",
}

SOURCE_RELIABILITY_TIERS: Dict[str, int] = {
    "problem_seed": 5,
    "instructor": 4,
    "founder": 4,
    "community": 3,
}


def build_source_paths(raw_sources_dir: str | Path) -> Dict[str, Path]:
    base = Path(raw_sources_dir)
    return {
        source_type: base / filename
        for source_type, filename in SUPPORTED_SOURCE_FILES.items()
    }
