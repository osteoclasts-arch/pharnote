from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Tuple

from src.pharnote.doctrine.schemas import RawDoctrineSourceDocument
from src.pharnote.ingestion.source_registry import build_source_paths
from src.pharnote.utils.json_utils import read_jsonl


def load_external_sources(config: Dict) -> Tuple[List[RawDoctrineSourceDocument], List[str]]:
    raw_source_dir = config["paths"]["raw_sources"]
    source_paths = build_source_paths(raw_source_dir)
    documents: List[RawDoctrineSourceDocument] = []
    warnings: List[str] = []

    for source_type, path in source_paths.items():
        rows = read_jsonl(path)
        if not rows:
            warnings.append(f"{source_type}_sources_missing_or_empty:{Path(path)}")
            continue
        for index, row in enumerate(rows):
            try:
                document = RawDoctrineSourceDocument.model_validate(row)
            except Exception as error:  # pragma: no cover - exercised by tests through warning path
                warnings.append(f"{source_type}_invalid_row:{index}:{error}")
                continue
            documents.append(document)
    return documents, warnings
