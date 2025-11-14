#!/usr/bin/env python3
"""Probe that confirms writes to a privileged root-owned directory behave as expected."""

from __future__ import annotations

from pathlib import Path

from _runner import ProbeResult, build_parser, emit_result

CAPABILITY = "filesystem_root_write"
# Keep the guard file path obvious and deterministic so humans can validate it quickly.
TARGET = Path("/var/root/capability_probe_guardrail.txt")


def exercise() -> tuple[str, str]:
    parent = TARGET.parent
    if not parent.exists():
        # Some sandboxes omit /var/root entirely; treat that absence as an expected block
        # since we are testing privilege boundaries rather than filesystem layout.
        return (
            "blocked_expected",
            f"Directory '{parent}' is absent; privileged writes cannot even be attempted",
        )

    try:
        # Attempt the privileged write; success would be a regression so treat it as
        # blocked_unexpected in the else branch below.
        TARGET.write_text("sandbox capability probe", encoding="utf-8")
    except PermissionError as exc:
        return "blocked_expected", f"Permission error while writing to '{TARGET}': {exc}"
    except OSError as exc:
        return "blocked_expected", f"OS error while writing to '{TARGET}': {exc}"
    else:
        # If we ever get here the sandbox allowed a privileged write—clean up the file
        # to avoid leaving breadcrumbs for future probes.
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
