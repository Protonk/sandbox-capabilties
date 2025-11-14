# Agents Guide

This repo maps sandbox behaviors into named "capabilities" that are backed by self-contained probe scripts. Everything is orchestrated through `make` so agents can run the full suite with a single command and capture the results as JSON artifacts.

## Layout
- `Makefile` knows how to list, run, and fan out to every `probes/*.py`, `probes/*.c`, or `probes/*.R` probe. All artefacts are stored in `artifacts/` (ignored by git).
- `probes/_runner.py` is the tiny harness shared by Python probes. It handles CLI parsing, JSON emission, and exit codes.
- `probes/_runner_c.{c,h}` provide the same helper surface for native probes so C authors do not reimplement the CLI or JSON writer.
- `probes/_runner_r.R` mirrors the contract for probes written in base R so they can plug into the same suite.
- Individual probe sources live beside the runners (`filesystem_tmp_write.py`, `filesystem_root_write.py`, `process_basic_spawn.py`, `filesystem_tmp_write_c.c`, `filesystem_tmp_write_r.R`). Each focuses on a single behavior.
- `README.md` describes the philosophy behind capability probes in a manner designed to also be consumed by agents. Pay attention to it and maintain it as a living document.

## Running the suite
1. `make list` – discover every available probe name.
2. `make probes` – execute the entire suite. Artifacts land in `artifacts/<probe>.json` and the exit code aggregates failures.
3. `make run PROBE=<name>` – run one probe in isolation when iterating on a capability.

Every probe emits a JSON object with `capability`, `status`, and `detail`. Exit code `0` indicates the observed behavior matches the contract (`supported` or `blocked_expected`). Exit code `1` means we saw something new or broken (`blocked_unexpected`).

## Adding a capability
1. Observe or anticipate an environment rule worth tracking.
2. Choose a short slug (e.g., `process_basic_spawn`). Use it as the filename and capability identifier, then pick a language: `probes/<slug>.py` for Python (import `_runner`), `probes/<slug>.c` for native code (include `_runner_c.h`), or `probes/<slug>.R` for base R (source `_runner_r.R`).
3. Copy the skeleton from one of the existing probes and update the logic inside `exercise()` so it performs exactly one behavior and classifies the result.
4. Use the helpers from the corresponding runner to parse `--output` and emit the final JSON.
5. Run `make run PROBE=<slug>` to make sure it behaves as expected, then `make probes` to ensure the suite still passes.

## Consuming capability results
Artifacts are intentionally simple (one JSON per capability) so downstream tooling can:
- Parse the directory and index statuses.
- Assert preconditions before kicking off expensive tests.
- Surface regressions whenever a status flips from `supported` → `blocked_expected` (or vice versa).

Feel free to build higher-level scripts that read `artifacts/*.json`, join with the capability catalog, or push the results elsewhere. Keep the probes tiny and deterministic; put richer logic in the layers that **consume** these artifacts.

## Tests
- Run `make test` before and after meaningful changes to ensure the Python, C, and R helpers remain stable. The target runs `unittest`, compiles `tests/c/*.c`, and executes each `tests/r/*.R`.
- Python tests live under `tests/` as `test_*.py` files that subclass `unittest.TestCase`. Native smoke tests live under `tests/c/` and should link against `_runner_c.c`, while base-R smoke tests live under `tests/r/` and source `_runner_r.R`.
