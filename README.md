# SACC: Sandbox-Aware Capability Catalog

This repository turns sandbox behavior into **explicit, repeatable capabilities**.  
Each capability you care about is implemented as one or more tiny probes under `probes/`, and a shared `Makefile` handles discovery, execution, and artifact collection. The result is a small JSON catalog of “what this environment can and cannot do” that other tools can read.

The philosophy is:
- treat sandbox quirks as named capabilities instead of ad‑hoc bugs,
- keep each probe minimal and deterministic,
- separate observation (“what happened”) from policy (“what to do about it”).

---

## Documentation map

- `README.md` (you are here) – conceptual overview, architecture, and the motivation for treating sandbox quirks as capabilities.
- `AGENTS.md` – the **authoritative workflow guide** for running probes, adding specimens, and following repo conventions. Treat it as the source of truth for commands, directory maps, and contribution steps. Subdirectories can contain their own `AGENTS.md`.
- Code level comments - low level expectations, tool use, and intent. Use this to help verify a probe records sandbox quirks and not a bug in this repo. 
The sections below summarize the system, while `AGENTS.md` carries the detailed checklists that agents (human or otherwise) should execute.

---

## Quick start

```sh
# list every probe and its source path
make list

# run all probes, writing artifacts/<probe-id>.json
make probes

# run a single specimen by probe ID
make run PROBE=core__filesystem__tmp_write
```

`make probes` exits non‑zero if any probe reports `blocked_unexpected`, which makes it useful in CI to detect changes in sandbox behavior.

---

## Capability model

At a high level, every probe follows the same flow:

1. **Detect** – perform one focused operation in the target environment (e.g., open a file, start a subprocess).
2. **Classify** – map the outcome onto a small status set:
   - `supported`
   - `blocked_expected`
   - `blocked_unexpected`
3. **Persist** – emit a single JSON object to disk so other workflows can consume it deterministically.

Every artifact has the same shape:

```json
{
  "capability": "filesystem_tmp_write",
  "status": "supported",
  "detail": "Temporary directory '/tmp' is writable"
}
```

Exit code `0` means the observed behavior matches the expected contract (`supported` or `blocked_expected`). Exit code `1` means something changed (`blocked_unexpected`).

---

## Probes, capabilities, and IDs

To keep the system composable, we distinguish between three concepts:

- **Capability slug** – the stable, human‑readable identifier for a behavior (e.g., `filesystem_tmp_write`, `process_basic_spawn`). Every specimen that reports on the same behavior declares the same `CAPABILITY` string (or equivalent constant in C/R).
- **Probe specimen** – a concrete implementation of a probe (Python vs C vs R, or different fuzz‑minimized variants). Multiple specimens may share a slug.
- **Probe ID** – a stable identifier derived from the specimen’s path. The `Makefile` builds this ID by:
  1. stripping the `probes/` prefix,
  2. removing the file extension,
  3. replacing `/` with `__`.

Examples:

| Probe path                                          | Probe ID                                         | Artifact path                                             |
| --------------------------------------------------- | ------------------------------------------------ | --------------------------------------------------------- |
| `probes/core/filesystem/tmp_write.py`              | `core__filesystem__tmp_write`                   | `artifacts/core__filesystem__tmp_write.json`             |
| `probes/fuzz/filesystem/tmp_write/0001_repeated_open.py` | `fuzz__filesystem__tmp_write__0001_repeated_open` | `artifacts/fuzz__filesystem__tmp_write__0001_repeated_open.json` |

The probe ID is what you pass to `make run PROBE=<id>` and what downstream tooling uses when indexing artifacts.

Every specimen, regardless of language:
- accepts `--output <path>` to choose an artifact file (falling back to `PROBE_ID` when available),
- writes a single JSON object with `capability`, `status`, and `detail`,
- uses the shared helpers in `probes/_runner.py`, `_runner_c.{c,h}`, or `_runner_r.R` to keep the CLI and JSON format aligned.

---

## Repository layout

- `Makefile` – discovers probe files under `probes/`, derives probe IDs, and orchestrates execution and artifact creation.
- `probes/_runner.py` – shared Python helper for CLI parsing, JSON serialization, and exit codes.
- `probes/_runner_c.{c,h}` – C helpers that mirror the same CLI/JSON contract.
- `probes/_runner_r.R` – thin compatibility shim that sources `runtime/r/probe_runtime.R` so existing probes/tests stay untouched.
- `runtime/r/` – canonical base‑R probe runtime; copy this directory (including the machine‑parsable `VERSION`) to vendor the same CLI/JSON contract elsewhere.
- `probes/core/<domain>/` – hand‑maintained, canonical probes grouped by domain (`filesystem`, `process`, etc.).
- `probes/fuzz/<domain>/<capability>/` – higher‑volume fuzz/AI‑generated specimens, organized to avoid path collisions.
- `artifacts/` – JSON outputs, one file per probe ID (ignored by Git).
- Documentation – see the “Documentation map” above for how README, `AGENTS.md`, and `probes/AGENTS.md` split responsibilities.

### Vendoring the base-R runtime

External projects (e.g., `RtoCodex`) can reuse the exact CLI/JSON contract by copying `runtime/r/` plus its `VERSION` file verbatim, then sourcing `probe_runtime.R`:

```r
source("runtime/r/probe_runtime.R")

CAPABILITY <- "filesystem_tmp_write"
args <- parse_args(CAPABILITY)
result <- list(
  capability = CAPABILITY,
  status = "supported",
  detail = sprintf("tmp dir writable (runtime %s)", RUNTIME_VERSION)
)
emit_result(result, args$output)
```

`runtime/r/VERSION` exposes a machine‑parsable semantic version (`0.1.0+<hash> (YYYY-MM-DD)`), while the in‑process `RUNTIME_VERSION` constant lets probes stamp the runtime build that produced a JSON artifact.

---

## Probe shape

All probes share the same logical structure:

1. Declare a capability slug (e.g., `CAPABILITY = "filesystem_tmp_write"`).
2. Implement a tiny function that performs a single operation and returns `(status, detail)`.
3. Use the language‑specific runner helper to parse CLI arguments and write the JSON artifact.

For example, the Python probe `probes/core/filesystem/tmp_write.py` tests whether the system temporary directory is writable:

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

Companion probes in C (`probes/core/filesystem/tmp_write_native.c`) and R (`probes/core/filesystem/tmp_write_r.R`) implement the same capability slug using their respective runtimes but still emit the same JSON schema and use the shared runners.

---

## Core vs fuzz specimens

The `probes/` tree separates long‑lived, human‑maintained probes from higher‑volume generated ones:

- `probes/core/<domain>/<file>` – canonical probes that define and document each capability. Domains are broad areas such as `filesystem`, `process`, `network`, or `time`. Filenames are short and descriptive (`tmp_write.py`, `root_write.py`, `basic_spawn.py`); if multiple languages exist for the same capability, that nuance lives in the filename (`tmp_write_native.c`, `tmp_write_r.R`) while the `CAPABILITY` string stays the same.
- `probes/fuzz/<domain>/<capability>/<NNNN>_<short_desc>.<ext>` – fuzz‑discovered or AI‑generated specimens. `<NNNN>` is a zero‑padded integer (`0001`, `0002`, …), and `<short_desc>` briefly summarizes what the specimen exercises.

This layout keeps the catalog navigable for humans while allowing automation to add many specimens without manual registry updates.

---

## Consuming capability results

Artifacts are intentionally small and uniform (one JSON object per probe ID), which makes them easy to:

- parse and index by capability, probe ID, or status,
- check as preconditions before running expensive tests,
- track over time to see when a capability flips from `supported` to `blocked_expected` or `blocked_unexpected`.

Most consumers simply read `artifacts/*.json`, join the results with their own capability catalog, and then enforce whatever policy they care about. Probes stay tiny and deterministic; richer logic belongs in the layers that consume these artifacts.

---

## Development and tests

- `make test` runs the Python unit tests, compiles C smoke tests under `tests/c/`, and executes R smoke tests under `tests/r/`.
- Python tests live under `tests/test_*.py` and exercise the shared runners.
- C and R tests link/source the same `_runner` helpers used by probes to keep the contract consistent.

---

## Why capabilities?

Treating sandbox constraints as first‑class capabilities gives you:

- **Predictability** – failures point at a named capability instead of a one‑off stack trace.
- **Traceability** – artifacts from past runs show exactly when a capability’s status changed.
- **Composability** – higher‑level tests can depend on capabilities instead of guessing what the environment supports.

Keeping probes small, deterministic, and well‑documented turns this repository into a durable map of your runtime environment.
