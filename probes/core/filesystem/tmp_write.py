#!/usr/bin/env python3
"""Probe that verifies we can write to the system temporary directory."""

from __future__ import annotations

import tempfile
import time
from pathlib import Path

from _runner import ProbeResult, build_parser, emit_result

CAPABILITY = "filesystem_tmp_write"


def exercise() -> tuple[str, str]:
    tmp_dir = Path(tempfile.gettempdir())
    # Use a timestamped filename so concurrent probe executions do not collide.
    probe_file = tmp_dir / f"capability_probe_{int(time.time() * 1000)}.txt"

    try:
        probe_file.write_text("sandbox capability probe", encoding="utf-8")
        probe_file.unlink()
        return "supported", f"Temporary directory '{tmp_dir}' is writable"
    except PermissionError as exc:
        return "blocked_unexpected", f"Permission error while writing to '{tmp_dir}': {exc}"
    except OSError as exc:
        return "blocked_unexpected", f"OS error while writing to '{tmp_dir}': {exc}"


def main() -> None:
    parser = build_parser(CAPABILITY)
    args = parser.parse_args()
    status, detail = exercise()
    # All specimens report the same capability slug even when they use different languages.
    result = ProbeResult(capability=CAPABILITY, status=status, detail=detail)
    emit_result(result, args.output)


if __name__ == "__main__":
    main()
