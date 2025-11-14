# Probe Authoring Guide

Use this directory to store every individual capability probe. Probes may be written in Python (import `_runner`), C (include `_runner_c.h`), or base R (source `_runner_r.R`); all runtimes provide the same CLI/JSON glue so authors can focus on the behavior under test.

## Capability slugs vs specimens
- **Capability slug** – the stable identifier for a behavior (`filesystem_tmp_write`, `process_basic_spawn`, ...). Every specimen that covers the same behavior must declare `CAPABILITY = "<slug>"` (or the equivalent constant in C/R).
- **Probe specimen** – the concrete implementation of a probe. Specimens live at unique paths and therefore have unique probe IDs (derived from the path), even when they share the same slug.

## Directory layout
- `core/<domain>/<file>` – hand-curated probes, organized by domain. Examples:
  - `core/filesystem/tmp_write.py`
  - `core/filesystem/tmp_write_native.c`
  - `core/filesystem/tmp_write_r.R`
  - `core/process/basic_spawn.py`
- `fuzz/<domain>/<capability>/<NNNN>_<short_desc>.<ext>` – generated or fuzz-reduced specimens. Examples:
  - `fuzz/filesystem/tmp_write/0001_short_stacktrace.py`
  - `fuzz/process/basic_spawn/0003_reexec_twice.c`

Keep the tree shallow—domain folders under `core/`, capability folders under `fuzz/`, and files underneath them. The `NNNN` component is a zero-padded integer and the short description should explain the distinguishing trait in a few words.

## Creating a probe
1. Pick a capability slug (snake_case) and declare it via `CAPABILITY`.
2. Place the file in the appropriate directory (`core/<domain>/` for canonical probes, `fuzz/<domain>/<capability>/` for generated ones).
3. Implement a tiny `exercise` function that performs exactly one operation. Keep it deterministic and short-lived.
4. Map the observation to one of the three statuses:
   - `supported` – the capability works end-to-end.
   - `blocked_expected` – the capability is intentionally constrained but matches our documented contract.
   - `blocked_unexpected` – any new or unexplained behavior; treat these as failures.
5. Build the CLI with the appropriate helper so callers may override `--output`. Python probes call `build_parser(CAPABILITY)`; C probes call `probe_cli_init`/`probe_cli_parse`; R probes call `parse_args(CAPABILITY)`.
6. Emit the result with the helper (`emit_result` in Python, C, or R). The helper ensures JSON files look identical and exit codes reflect the status.

## AI/fuzzer workflow
1. Map the reproduction to an existing capability slug and domain.
2. Create/reuse `fuzz/<domain>/<capability>/`.
3. Determine the next `NNNN` by listing existing specimens and incrementing the highest number (four digits, zero padded).
4. Name the file `<NNNN>_<short_desc>.<ext>` with a short descriptor (kebab/underscore style).
5. Implement the minimal reproduction in Python, C, or R with the shared runners.
6. `make run PROBE=fuzz__<domain>__<capability>__<NNNN_short_desc>` to validate locally. The harness exports `PROBE_ID=<probe-id>` and artifacts land in `artifacts/<probe-id>.json`.

## Contract tips
- Describe *why* a status was chosen in the `detail` string; downstream tools will surface this to humans.
- Prefer granular probes. If you need to check multiple behaviors, add multiple files.
- Any resources you create (files, processes, sockets) should be cleaned up before the script exits.
- Keep dependencies minimal (standard library whenever possible) so every probe can run in restricted sandboxes without extra setup.

## Running locally
Use `make run PROBE=<probe-id>` to iterate on a specimen and `make probes` before sending changes to ensure the full suite still passes. The shared Makefile automatically discovers new files anywhere under `probes/` (excluding private helper modules that start with `_`) and selects the right interpreter/compiler automatically. Running a probe manually? Either set `PROBE_ID` to the path-derived ID or pass `--output` so results do not collide.
