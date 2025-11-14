#!/usr/bin/env python3
"""Fuzz specimen that writes to the temp directory twice in rapid succession."""

from __future__ import annotations

import tempfile
import time
from pathlib import Path

from _runner import ProbeResult, build_parser, emit_result

CAPABILITY = "filesystem_tmp_write"


def exercise() -> tuple[str, str]:
    tmp_dir = Path(tempfile.gettempdir())
    # Simulate a fuzz discovery where multiple back-to-back writes trigger a sandbox bug.
    stem = tmp_dir / f"probe_repeat_{int(time.time() * 1000)}"
    attempts = []
    try:
        for idx in range(2):
            path = stem.with_suffix(f".{idx}")
            payload = f"repeated write #{idx}"
            path.write_text(payload, encoding="utf-8")
            attempts.append(f"{path.name}=ok")
            path.unlink()
    except PermissionError as exc:
        return "blocked_unexpected", f"Permission error while writing repeats: {exc}"
    except OSError as exc:
        return "blocked_unexpected", f"OS error while writing repeats: {exc}"
    finally:
        for candidate in stem.parent.glob(f"{stem.name}.*"):
            candidate.unlink(missing_ok=True)

    joined = ", ".join(attempts)
    return "supported", f"Repeated temp writes succeeded ({joined})"


def main() -> None:
    parser = build_parser(CAPABILITY)
    args = parser.parse_args()
    status, detail = exercise()
    emit_result(ProbeResult(capability=CAPABILITY, status=status, detail=detail), args.output)


if __name__ == "__main__":
    main()
