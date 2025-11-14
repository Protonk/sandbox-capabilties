# Capability Probes: A Sandbox-Aware Test Harness

This repository turns sandbox quirks into **explicit, repeatable signals**. Every capability you care about is represented by focused probes under `probes/core/` or `probes/fuzz/`, and the shared `Makefile` orchestrates discovery, execution, and artifact collection. The outcome is a machine-readable catalog of "what this environment can and cannot do" that downstream tools can trust.

---

## Concept, grounded in this repo

1. **Detect** an environment behavior with a single-purpose script (a probe).
2. **Classify** the observation into one of three statuses:
   - `supported`
   - `blocked_expected`
   - `blocked_unexpected`
3. **Persist** the classification as a JSON artifact (one file per probe specimen) so other workflows can consume it deterministically.

The philosophy described above shows up concretely via `make` targets, helper utilities, and example probes. Everything is designed so that adding the next capability is trivial, even when AI or fuzzers generate dozens of variants.

---

## Quick start

```sh
# enumerate every probe discovered under probes/core/** and probes/fuzz/**
make list

# run every probe and populate artifacts/<probe-id>.json
make probes

# iterate on a single specimen (identified by probe ID)
make run PROBE=core__filesystem__tmp_write
```

`make probes` exits non-zero if any probe reports `blocked_unexpected`, making it ideal for CI jobs that need to fail fast when the sandbox changes.

Typical run (truncated):

```
$ make probes
mkdir -p artifacts
[probe] core__filesystem__root_write
PYTHONPATH=probes: python3 probes/core/filesystem/root_write.py --output artifacts/core__filesystem__root_write.json
[probe] core__filesystem__tmp_write
PYTHONPATH=probes: python3 probes/core/filesystem/tmp_write.py --output artifacts/core__filesystem__tmp_write.json
[probe] core__filesystem__tmp_write_native
cc -std=c11 -Wall -Wextra -Iprobes -o artifacts/.c_probes/core__filesystem__tmp_write_native probes/core/filesystem/tmp_write_native.c probes/_runner_c.c
artifacts/.c_probes/core__filesystem__tmp_write_native --output artifacts/core__filesystem__tmp_write_native.json
[probe] core__filesystem__tmp_write_r
Rscript probes/core/filesystem/tmp_write_r.R --output artifacts/core__filesystem__tmp_write_r.json
[probe] core__process__basic_spawn
PYTHONPATH=probes: python3 probes/core/process/basic_spawn.py --output artifacts/core__process__basic_spawn.json
[probe] fuzz__filesystem__tmp_write__0001_repeated_open
PYTHONPATH=probes: python3 probes/fuzz/filesystem/tmp_write/0001_repeated_open.py --output artifacts/fuzz__filesystem__tmp_write__0001_repeated_open.json
```

Every probe—no matter the implementation language—obeys the same CLI contract by accepting `--output <path>` and emitting identical JSON artifacts. Python probes use the shared helpers in `_runner.py`, native probes link against `_runner_c.{c,h}`, and R probes source `_runner_r.R` to share the same parser and JSON writer.
The harness also exports `PROBE_ID=<probe-id>` when launching a specimen so the helpers can derive the correct default artifact path. When running a probe manually, either keep that environment variable or pass `--output` explicitly.

---

## Repository map

- `Makefile` – recursively discovers every probe under `probes/`, derives a unique artifact ID from the file path, and dispatches to the right toolchain. Key fragment:

  ```make
  PYTHON_PROBE_SOURCES := $(shell find probes -type f -name '*.py' ! -name '_*.py' | sort)

  define probe_id
  $(subst /,__,$(basename $(patsubst probes/%,%,$1)))
  endef

  define artifact_path
  $(ARTIFACT_DIR)/$(call probe_id,$1).json
  endef

  $(foreach src,$(PYTHON_PROBE_SOURCES),$(eval $(call PYTHON_PROBE_RULE,$(src))))
  ```

- `probes/_runner.py` – shared glue that handles CLI parsing, JSON serialization, artifact directories, and exit codes. Individual probes just import `build_parser`, `ProbeResult`, and `emit_result`.
- `probes/_runner_c.{c,h}` – native runtime helpers that expose the same CLI contract and artifact writer to C probes (and their unit tests).
- `probes/_runner_r.R` – base-R helpers that mirror the CLI/JSON contract so R probes stay tiny while integrating with the rest of the harness.
- `probes/core/<domain>/` – hand-curated probes organized by capability domain (`filesystem`, `process`, etc.).
- `probes/fuzz/<domain>/<capability>/` – AI/fuzzer-generated specimens organized by domain, capability, and probe number.
- `artifacts/` – output directory (ignored via `.gitignore`) where every probe writes `<probe-id>.json`.
- `AGENTS.md` and `probes/AGENTS.md` – short guides tailored to repo users and probe authors respectively.

---

## Capability slugs, specimens, and IDs

- A **capability slug** (e.g., `filesystem_tmp_write`, `process_basic_spawn`) is the human-readable identifier for a behavior. It is declared inside every probe via `CAPABILITY = "<slug>"` (or the equivalent constant in C/R) and remains stable even if multiple specimens exist.
- A **probe specimen** is a concrete implementation of a capability probe (e.g., Python vs C vs R, or different fuzz-minimized variants). Multiple specimens may report the same capability slug.
- Each specimen lives at a unique path such as `probes/core/filesystem/tmp_write.py` or `probes/fuzz/filesystem/tmp_write/0001_short_stacktrace.py`.
- The Makefile deterministically converts that path into a **probe ID** by:
  1. Stripping the `probes/` prefix.
  2. Removing the file extension.
  3. Replacing `/` with `__`.

  Examples:

  | Probe path | Probe ID | Artifact |
  | --- | --- | --- |
  | `probes/core/filesystem/tmp_write.py` | `core__filesystem__tmp_write` | `artifacts/core__filesystem__tmp_write.json` |
  | `probes/fuzz/filesystem/tmp_write/0001_repeated_open.py` | `fuzz__filesystem__tmp_write__0001_repeated_open` | `artifacts/fuzz__filesystem__tmp_write__0001_repeated_open.json` |

The probe ID is what you pass to `make run PROBE=<id>` and what downstream tooling uses to join capability artifacts.

---

## Directory layout: core vs fuzz

The `probes/` tree separates hand-maintained probes from high-volume generated ones:

- `probes/core/<domain>/<file>` – canonical, human-reviewed probes. Domains are broad areas like `filesystem`, `process`, `network`, or `time`. Filenames should be short and descriptive (`tmp_write.py`, `root_write.py`, `basic_spawn.py`). If multiple languages exist for the same capability, encode the nuance in the filename (`tmp_write_native.c`, `tmp_write_r.R`) while keeping `CAPABILITY = "filesystem_tmp_write"` across all of them.
- `probes/fuzz/<domain>/<capability>/<NNNN>_<short_desc>.<ext>` – fuzz-discovered or AI-generated probes. The `<domain>` matches the same high-level buckets as core probes, `<capability>` mirrors the slug, `<NNNN>` is a zero-padded integer (`0001`, `0002`, ...), and `<short_desc>` is a brief kebab/underscore summary of what the specimen does or why it exists.

This shallow layout keeps the repository understandable for humans while providing enough structure for automation to add thousands of specimens without collisions.

---

## Probe anatomy

All probes follow the same structure: declare a capability slug, implement a tiny `exercise()` function that performs a single operation, classify the result, and emit it through the shared helper for that language.

- **Python probe** – `probes/core/filesystem/tmp_write.py` tests whether the system temporary directory is writable:

  ```python
  CAPABILITY = "filesystem_tmp_write"

  def exercise() -> tuple[str, str]:
      tmp_dir = Path(tempfile.gettempdir())
      probe_file = tmp_dir / f"capability_probe_{int(time.time() * 1000)}.txt"

      try:
          probe_file.write_text("sandbox capability probe", encoding="utf-8")
          probe_file.unlink()
          return "supported", f"Temporary directory '{tmp_dir}' is writable"
      except PermissionError as exc:
          return "blocked_unexpected", f"Permission error while writing to '{tmp_dir}': {exc}"
      except OSError as exc:
          return "blocked_unexpected", f"OS error while writing to '{tmp_dir}': {exc}"
  ```

- **C probe** – `probes/core/filesystem/tmp_write_native.c` performs the same capability via native syscalls and still reports `CAPABILITY = "filesystem_tmp_write"`.
- **R probe** – `probes/core/filesystem/tmp_write_r.R` exercises the same slug via base R.

Every specimen parses `--output`, writes JSON through the helper runtime, and returns `0` only when the status is `supported` or `blocked_expected`.

---

## Adding a fuzz specimen

Automated agents and fuzzers follow the same recipe when contributing new specimens:

1. **Identify the capability slug** (`filesystem_tmp_write`, `process_basic_spawn`, etc.). All specimens must declare the same `CAPABILITY` string so downstream tools can correlate results.
2. **Map the slug to a domain.** Use the existing `probes/core/` layout as inspiration (`filesystem`, `process`, `network`, `time`, `misc`, ...).
3. **Create or reuse the directory** `probes/fuzz/<domain>/<capability>/`.
4. **Allocate the next specimen number.** List existing files, find the highest `NNNN` prefix, and pick `NNNN+1` (zero padded to four digits).
5. **Pick a short description** for the filename (`0003_misaligned_fd.py`, `0004_drop_privs.c`, ...). Keep it kebab or underscore separated.
6. **Implement the probe** in your language of choice, sourcing the appropriate `_runner` helper and declaring `CAPABILITY = "<slug>"`.
7. **Run it.** `make run PROBE=fuzz__<domain>__<capability>__<NNNN_short_desc>` automatically compiles/interprets the specimen, exports `PROBE_ID=<probe-id>`, and places the artifact at `artifacts/<probe-id>.json`.
8. **Document interesting behaviors** inside the probe or accompanying commit message if the fuzz discovery needs additional context.

Because artifact names are derived from the path, there is no risk of overwriting an existing result and no registry to update manually.

---

## Consuming capability results

Artifacts are intentionally simple (one JSON per probe ID) so downstream tooling can:
- Parse the directory and index statuses.
- Assert preconditions before kicking off expensive tests.
- Surface regressions whenever a status flips from `supported` → `blocked_expected` (or vice versa).

Build higher-level scripts that read `artifacts/*.json`, join with the capability catalog, or push the results elsewhere. Keep the probes tiny and deterministic; put richer logic in the layers that **consume** these artifacts.

---

## Tests

- Run `make test` before and after meaningful changes to ensure the Python, C, and R helpers remain stable. The target runs `unittest`, compiles `tests/c/*.c`, and executes each `tests/r/*.R`.
- Python tests live under `tests/` as `test_*.py` files that subclass `unittest.TestCase`. Native smoke tests live under `tests/c/` and should link against `_runner_c.c`, while base-R smoke tests live under `tests/r/` and source `_runner_r.R`.

---

## What you gain

Treating sandbox constraints as first-class capabilities gives you:
- **Predictability** – failures now point to a named capability rather than a random stack trace.
- **Traceability** – artifacts from past runs show exactly when a capability flipped.
- **Composability** – higher-level tests can declare dependencies on capabilities instead of guessing what the environment supports.

Keep the probes tiny, deterministic, and well-documented, and this repository becomes a durable map of your runtime environment.
