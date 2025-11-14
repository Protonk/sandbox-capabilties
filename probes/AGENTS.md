# Probe Authoring Guide

Use this directory to store every individual capability probe. Probes may be written in Python (import `_runner`) or C (include `_runner_c.h`); both runtimes provide the same CLI/JSON glue so authors can focus on the behavior under test.

## Creating a probe
1. Pick a capability name (snake_case). Filename = `<capability>.py` for Python or `<capability>.c` for native code, and define `CAPABILITY = "<capability>"` in either case.
2. Implement a tiny `exercise` function that performs exactly one operation. Keep it deterministic and short-lived.
3. Map the observation to one of the three statuses:
   - `supported` – the capability works end-to-end.
   - `blocked_expected` – the capability is intentionally constrained but matches our documented contract.
   - `blocked_unexpected` – any new or unexplained behavior; treat these as failures.
4. Build the CLI with the appropriate helper so callers may override `--output`. Python probes call `build_parser(CAPABILITY)`; C probes call `probe_cli_init`/`probe_cli_parse`.
5. Emit the result with the helper (`emit_result` in Python or C). The helper ensures JSON files look identical and exit codes reflect the status.

## Contract tips
- Describe *why* a status was chosen in the `detail` string; downstream tools will surface this to humans.
- Prefer granular probes. If you need to check multiple behaviors, add multiple files.
- Any resources you create (files, processes, sockets) should be cleaned up before the script exits.
- Keep dependencies minimal (standard library whenever possible) so every probe can run in restricted sandboxes without extra setup.

## Running locally
Use `make run PROBE=<capability>` to iterate on a single probe and `make probes` before sending changes to ensure the full suite still passes. The shared Makefile automatically discovers any new `probes/*.py` or `probes/*.c` (excluding private helper modules that start with `_`) and selects the right interpreter/compiler automatically.
