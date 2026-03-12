from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict

from src.pharnote.doctrine.build_problem_doctrine_map import build_problem_doctrine_payloads
from src.pharnote.utils.config_utils import load_pipeline_config
from src.pharnote.utils.json_utils import write_json, write_jsonl


def run_export_pharnote_payloads(config: Dict) -> Dict[str, int]:
    payloads, clusters = build_problem_doctrine_payloads(config)
    output_dir = Path(config["paths"]["outputs"])
    write_jsonl(output_dir / "problem_doctrine_payloads.jsonl", (payload.model_dump() for payload in payloads))
    write_jsonl(output_dir / "doctrine_catalog.jsonl", (cluster.model_dump() for cluster in clusters))
    write_json(
        output_dir / "sample_outputs.json",
        {
            "payload_examples": [payload.model_dump() for payload in payloads[:2]],
            "doctrine_examples": [cluster.model_dump() for cluster in clusters[:2]],
        },
    )
    return {"payloads": len(payloads), "clusters": len(clusters)}


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export problem-level doctrine payloads for PharNote review flows.")
    parser.add_argument("--config", default="configs/doctrine_pipeline.yaml")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    config = load_pipeline_config(args.config)
    run_export_pharnote_payloads(config)


if __name__ == "__main__":
    main()
