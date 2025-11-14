# Agents Guide

This repo maps sandbox behaviors into named "capabilities" that are backed by self-contained probe specimens. Everything is orchestrated through `make` so agents can run the full suite with a single command and capture the results as JSON artifacts.

Use this document as the operational playbook—commands, directory maps, and workflows live here. The top-level `README.md` focuses on philosophy, context, and system architecture.

## Layout
- `Makefile` – recursively discovers every probe under `probes/`, derives a stable probe ID from the path (remove `probes/`, strip the extension, replace `/` with `__`), and emits `artifacts/<probe-id>.json`.
- `probes/_runner.py`, `_runner_c.{c,h}`, `_runner_r.R` – shared helpers that keep the CLI/JSON contract identical across Python, C, and base R.
- `probes/core/<domain>/` – hand-maintained specimens for each capability slug (e.g., `filesystem/tmp_write.py`, `process/basic_spawn.py`).
- `probes/fuzz/<domain>/<capability>/<NNNN>_<short_desc>.<ext>` – generated or fuzz-reduced specimens. The directory structure prevents collisions even when thousands of files accumulate.
- `README.md`, `AGENTS.md`, and `probes/AGENTS.md` – living documentation for repo users and probe authors.

## Running the suite
1. `make list` – discover every probe ID plus its source path.
2. `make probes` – execute the entire suite. Artifacts land in `artifacts/<probe-id>.json` and the exit code aggregates failures.
3. `make run PROBE=<probe-id>` – run one specimen in isolation. Example: `make run PROBE=core__filesystem__tmp_write`.

Every probe emits a JSON object with `capability`, `status`, and `detail`. Exit code `0` indicates the observed behavior matches the contract (`supported` or `blocked_expected`). Exit code `1` means we saw something new or broken (`blocked_unexpected`).

### Execution environment
The Makefile exports `PROBE_ID=<probe-id>` to every specimen. The shared runner helpers read this variable to select the correct default artifact path (`artifacts/<probe-id>.json`) even when `--output` is omitted. When invoking a probe outside of `make`, either set `PROBE_ID` or pass an explicit `--output` argument so artifacts remain unique.

## Capability slugs vs probe specimens
- A **capability slug** (e.g., `filesystem_tmp_write`) is declared inside every probe (`CAPABILITY = "<slug>"`) and stays stable over time.
- A **probe specimen** is a concrete implementation that reports on that slug. Multiple specimens can share the same slug (Python vs C vs R, or multiple fuzz variants) but live at different paths and therefore have unique probe IDs.
- Probe IDs are derived from paths, so adding a new specimen never requires editing a registry; just place the file under the right directory and `make` picks it up automatically.

## Adding a capability or specimen
1. Observe or anticipate an environment rule worth tracking.
2. Choose a capability slug (short, lowercase, underscore-separated). Every specimen for that behavior must declare the same slug.
3. Place the file according to its role:
   - Canonical probes go under `probes/core/<domain>/` with straightforward filenames (e.g., `filesystem/tmp_write.py`, `filesystem/tmp_write_native.c`, `filesystem/tmp_write_r.R`).
   - Generated/fuzzed probes go under `probes/fuzz/<domain>/<capability>/` following the `NNNN_short_desc` pattern (`0001_short_stacktrace.py`, `0002_open_twice.c`, ...).
4. Implement the probe using the appropriate runner helper, keeping the logic tiny and deterministic.
5. Run `make run PROBE=<probe-id>` to iterate, then `make probes` to exercise the full suite before landing changes.

### Workflow for fuzz/AI agents
1. Map the observed behavior to an existing capability slug and domain.
2. Create or reuse `probes/fuzz/<domain>/<capability>/`.
3. Enumerate existing specimens, pick the next `NNNN` (zero-padded integer), and choose a short descriptor for the filename.
4. Write `NNNN_short_desc.<ext>` with `CAPABILITY = "<slug>"` and the minimal reproduction logic.
5. `make run PROBE=fuzz__<domain>__<capability>__<NNNN_short_desc>` to validate locally; the harness writes `artifacts/<probe-id>.json`.

## Consuming capability results
Artifacts remain small (one JSON per probe ID) so downstream tools can:
- Parse the directory and index statuses.
- Assert preconditions before kicking off expensive tests.
- Surface regressions whenever a status flips from `supported` → `blocked_expected` (or vice versa).

Feel free to build higher-level scripts that read `artifacts/*.json`, join with the capability catalog, or push the results elsewhere. Keep the probes tiny and deterministic; put richer logic in the layers that **consume** these artifacts.

## Tests
- Run `make test` before and after meaningful changes to ensure the Python, C, and R helpers remain stable. The target runs `unittest`, compiles `tests/c/*.c`, and executes each `tests/r/*.R`.
- Python tests live under `tests/` as `test_*.py` files that subclass `unittest.TestCase`. Native smoke tests live under `tests/c/` and should link against `_runner_c.c`, while base-R smoke tests live under `tests/r/` and source `_runner_r.R`.

## Code comments are documentation

Write code comments as a senior engineer mentoring a first-year CS intern: concise, specific, and geared toward guiding and reminding rather than lecturing. Assume the reader may be fluent in one toolchain but unfamiliar with another (e.g., comfortable with `make` but new to R build tools, or vice versa), so comments should explain “why this matters here” and “what to watch out for,” not just restate the code.

* Use inline comments to explain non-obvious control flow, tricky invariants, unusual language features, and build/tooling quirks; focus on intent, hidden constraints, and gotchas rather than narrating straightforward operations.
* At the top of files and major sections, briefly document the purpose, inputs/outputs, and any cross-tool assumptions (e.g., how `Makefile` targets, R scripts, and shell helpers fit together) so an intern can safely extend or debug the code without guessing.
