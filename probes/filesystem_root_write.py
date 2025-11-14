#!/usr/bin/env python3
"""Probe that confirms writes to a privileged root-owned directory behave as expected."""

from __future__ import annotations

from pathlib import Path

from _runner import ProbeResult, build_parser, emit_result

CAPABILITY = "filesystem_root_write"
TARGET = Path("/var/root/capability_probe_guardrail.txt")


def exercise() -> tuple[str, str]:
    parent = TARGET.parent
    if not parent.exists():
        return (
            "blocked_expected",
            f"Directory '{parent}' is absent; privileged writes cannot even be attempted",
        )

    try:
        TARGET.write_text("sandbox capability probe", encoding="utf-8")
    except PermissionError as exc:
        return "blocked_expected", f"Permission error while writing to '{TARGET}': {exc}"
    except OSError as exc:
        return "blocked_expected", f"OS error while writing to '{TARGET}': {exc}"
    else:
        TARGET.unlink(missing_ok=True)
        return "blocked_unexpected", "Unexpectedly wrote to a privileged directory"


def main() -> None:
    parser = build_parser(CAPABILITY)
    args = parser.parse_args()
    status, detail = exercise()
    result = ProbeResult(capability=CAPABILITY, status=status, detail=detail)
    emit_result(result, args.output)


if __name__ == "__main__":
    main()
