"""Config loading helpers.

The pipeline config file uses JSON syntax stored in a `.yaml` file so it remains valid
YAML while keeping the loader dependency-free.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict


DEFAULT_CONFIG_PATH = Path("configs/doctrine_pipeline.yaml")


def load_pipeline_config(config_path: str | Path | None = None) -> Dict[str, Any]:
    path = Path(config_path or DEFAULT_CONFIG_PATH)
    raw = path.read_text(encoding="utf-8")
    return json.loads(raw)
