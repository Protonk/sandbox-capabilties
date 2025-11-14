#!/usr/bin/env python3
"""Common helpers for capability probes."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Literal

Status = Literal["supported", "blocked_expected", "blocked_unexpected"]


def _default_output(capability: str) -> Path:
    return Path("artifacts") / f"{capability}.json"


def build_parser(capability: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=f"Capability probe for '{capability}'",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=_default_output(capability),
        help="Where to write the machine-readable probe result",
    )
    return parser


@dataclass
class ProbeResult:
    capability: str
    status: Status
    detail: str


_SUCCESS_STATUSES: set[Status] = {"supported", "blocked_expected"}


def persist_result(result: ProbeResult, output_path: Path) -> int:
    """Write a JSON artifact and return an appropriate exit code."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(asdict(result), indent=2) + "\n", encoding="utf-8")
    return 0 if result.status in _SUCCESS_STATUSES else 1


def emit_result(result: ProbeResult, output_path: Path) -> None:
    """Persist the probe result and exit with the right status code."""

    exit_code = persist_result(result, output_path)
    raise SystemExit(exit_code)
