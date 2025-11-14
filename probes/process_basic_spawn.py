#!/usr/bin/env python3
"""Probe that verifies we can spawn child processes."""

from __future__ import annotations

import subprocess

from _runner import ProbeResult, build_parser, emit_result

CAPABILITY = "process_basic_spawn"
COMMAND = ["/bin/echo", "capability-probe"]


def exercise() -> tuple[str, str]:
    try:
        completed = subprocess.run(
            COMMAND,
            capture_output=True,
            check=True,
            text=True,
        )
    except FileNotFoundError as exc:
        return "blocked_unexpected", f"Spawn failed; '{COMMAND[0]}' missing: {exc}"
    except PermissionError as exc:
        return "blocked_unexpected", f"Spawn blocked by permissions: {exc}"
    except subprocess.CalledProcessError as exc:
        return "blocked_unexpected", f"Child process exited with {exc.returncode}: {exc.stderr.strip()}"

    detail = f"Spawned '{' '.join(COMMAND)}' and received: {completed.stdout.strip()}"
    return "supported", detail


def main() -> None:
    parser = build_parser(CAPABILITY)
    args = parser.parse_args()
    status, detail = exercise()
    result = ProbeResult(capability=CAPABILITY, status=status, detail=detail)
    emit_result(result, args.output)


if __name__ == "__main__":
    main()
