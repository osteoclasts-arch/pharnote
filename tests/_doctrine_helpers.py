from __future__ import annotations

import copy
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Dict, Iterator, Tuple

from src.pharnote.utils.config_utils import load_pipeline_config


def build_temp_config() -> Tuple[TemporaryDirectory, Dict]:
    temp_dir = TemporaryDirectory()
    root = Path(temp_dir.name)
    config = copy.deepcopy(load_pipeline_config())
    for key in ["raw_sources", "candidates", "normalized", "approved", "outputs", "logs"]:
        if key == "raw_sources":
            config["paths"][key] = str(Path("data/doctrine/raw_sources"))
        else:
            target = root / key
            target.mkdir(parents=True, exist_ok=True)
            config["paths"][key] = str(target)
    config["problem_db"]["fixture_path"] = "tests/fixtures/doctrine/past_questions_fixture.json"
    return temp_dir, config
