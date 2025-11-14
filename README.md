# Capability Probes: A Sandbox-Aware Test Harness

This repository turns sandbox quirks into **explicit, repeatable signals**. Every capability you care about is represented by a focused probe under `probes/`, and the shared `Makefile` orchestrates discovery, execution, and artifact collection. The outcome is a machine-readable catalog of "what this environment can and cannot do" that downstream tools can trust.

---

## Concept, grounded in this repo

1. **Detect** an environment behavior with a single-purpose script (a probe).
2. **Classify** the observation into one of three statuses:
   - `supported`
   - `blocked_expected`
   - `blocked_unexpected`
3. **Persist** the classification as a JSON artifact (one file per capability) so other workflows can consume it deterministically.

The philosophy described above shows up concretely via `make` targets, helper utilities, and example probes. Everything is designed so that adding the next capability is trivial.

---

## Quick start

```sh
# enumerate every probe discovered under probes/*.py and probes/*.c
make list

# run every probe and populate artifacts/<capability>.json
make probes

# iterate on a single capability
make run PROBE=filesystem_tmp_write
```

`make probes` exits non-zero if any probe reports `blocked_unexpected`, making it ideal for CI jobs that need to fail fast when the sandbox changes.

Typical run (truncated):

```
$ make probes
mkdir -p artifacts
[probe] filesystem_root_write
python3 probes/filesystem_root_write.py --output artifacts/filesystem_root_write.json
[probe] filesystem_tmp_write
python3 probes/filesystem_tmp_write.py --output artifacts/filesystem_tmp_write.json
[probe] filesystem_tmp_write_c
cc -std=c11 -Wall -Wextra -Iprobes -o artifacts/.c_probes/filesystem_tmp_write_c probes/filesystem_tmp_write_c.c probes/_runner_c.c
artifacts/.c_probes/filesystem_tmp_write_c --output artifacts/filesystem_tmp_write_c.json
[probe] process_basic_spawn
python3 probes/process_basic_spawn.py --output artifacts/process_basic_spawn.json
```

Every probe—no matter the implementation language—obeys the same CLI contract by accepting `--output <path>` and emitting identical JSON artifacts. Python probes use the shared helpers in `_runner.py`, while native probes link against `_runner_c.{c,h}` to get a matching parser and JSON writer.

---

## Repository map

- `Makefile` – auto-discovers every `probes/*.py` and `probes/*.c` that don’t start with `_`, then dispatches to the right toolchain. Key fragment:

  ```make
  PYTHON_PROBE_SCRIPTS := $(filter-out probes/_%.py,$(wildcard probes/*.py))
  C_PROBE_SOURCES := $(filter-out probes/_%.c,$(wildcard probes/*.c))

  $(PYTHON_ARTIFACTS): $(ARTIFACT_DIR)/%.json: probes/%.py | $(ARTIFACT_DIR)
  	$(PYTHON) $< --output $@

  $(C_PROBE_BINARIES): $(C_BUILD_DIR)/%: probes/%.c probes/_runner_c.c probes/_runner_c.h | $(C_BUILD_DIR)
  	$(CC) $(CFLAGS) -Iprobes -o $@ $< probes/_runner_c.c
  ```

- `probes/_runner.py` – shared glue that handles CLI parsing, JSON serialization, artifact directories, and exit codes. Individual probes just import `build_parser`, `ProbeResult`, and `emit_result`.
- `probes/_runner_c.{c,h}` – native runtime helpers that expose the same CLI contract and artifact writer to C probes (and their unit tests).
- `probes/*.py` / `probes/*.c` – capability probes written in whichever language best exercises the behavior.
- `artifacts/` – output directory (ignored via `.gitignore`) where every probe writes `<capability>.json`.
- `AGENTS.md` and `probes/AGENTS.md` – short guides tailored to repo users and probe authors respectively.

---

## Probe anatomy

All probes follow the same structure: declare a capability slug, implement a tiny `exercise()`/`exercise` function that performs a single operation, classify the result, and emit it through the shared helper for that language.

- **Python probe** – import `_runner`, build the CLI parser, and emit a `ProbeResult`. `probes/filesystem_tmp_write.py` tests whether the system temporary directory is writable:

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

- **C probe** – include `_runner_c.h`, use `probe_cli_*` helpers to honor the CLI contract, and call `emit_result`. `probes/filesystem_tmp_write_c.c` exercises the same behavior from native code:

  ```c
  static const char *CAPABILITY = "filesystem_tmp_write_c";

  static struct probe_result exercise(void) {
      static char detail[512];
      const char *tmp_dir = getenv("TMPDIR");
      if (tmp_dir == NULL || tmp_dir[0] == '\0') {
          tmp_dir = "/tmp";
      }
      char file_path[PATH_MAX];
      snprintf(file_path, sizeof(file_path), "%s/%s.txt", tmp_dir, CAPABILITY);
      int fd = open(file_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
      if (fd == -1) {
          snprintf(detail, sizeof(detail), "Unable to write '%s': %s", file_path, strerror(errno));
          return (struct probe_result){CAPABILITY, "blocked_unexpected", detail};
      }
      /* ...write payload, unlink file... */
      snprintf(detail, sizeof(detail), "Temporary directory '%s' is writable via native code", tmp_dir);
      return (struct probe_result){CAPABILITY, "supported", detail};
  }
  ```

Built-in probes:
- `filesystem_root_write` – ensures privileged paths (such as `/var/root`) reject writes in sandboxes, which is treated as `blocked_expected`.
- `filesystem_tmp_write` – Python version of the temporary-directory write check.
- `filesystem_tmp_write_c` – the same capability executed via compiled C for environments that only authorize native binaries.
- `process_basic_spawn` – verifies `/bin/echo` can be spawned successfully, producing `supported` when child processes are allowed.

Use these examples as templates when authoring new capabilities—pick whichever language exposes the behavior most directly, but keep the probe itself tiny and deterministic.

---

## Tests

```sh
make test
```

This runs both the Python `unittest` suite (discovered under `tests/test_*.py`) and any native smoke tests stored under `tests/c/*.c`. Add Python tests whenever you touch `_runner.py` or the Makefile wiring, and add C tests whenever you extend `_runner_c` or other native helpers so regressions in those languages are caught early.

---

## Artifact format

Every probe writes `artifacts/<capability>.json` with a stable schema:

```json
{
  "capability": "filesystem_tmp_write",
  "status": "supported",
  "detail": "Temporary directory '/var/folders/.../T' is writable"
}
```

- `capability` matches the filename/slug.
- `status` governs the exit code (`supported`/`blocked_expected` ⇒ success, `blocked_unexpected` ⇒ failure).
- `detail` contains human-readable context for logs or dashboards.

Because artifacts are standalone files, downstream tooling can diff directories between runs, ingest them into dashboards, or gate higher-level tests by checking for required capabilities.

---

## Adding a capability

1. Observe an environment behavior worth tracking.
2. Choose a short slug (snake_case) and the language that best fits the behavior. Create `probes/<slug>.py` (importing `_runner`) or `probes/<slug>.c` (including `_runner_c.h`).
3. Keep the probe laser-focused on one operation and explain the rationale in the `detail` string so downstream tools surface a helpful message.
4. Run `make run PROBE=<slug>` until it behaves as expected. Then run `make probes` to ensure the whole suite still passes.
5. Commit the new probe along with any documentation updates referencing the capability and language.

If you plan to consume the new capability elsewhere, teach those scripts/tests to read the JSON artifacts rather than duplicating detection logic. This preserves the single source of truth for environment behavior.

---

## What you gain

Treating sandbox constraints as first-class capabilities gives you:
- **Predictability** – failures now point to a named capability rather than a random stack trace.
- **Traceability** – artifacts from past runs show exactly when a capability flipped.
- **Composability** – higher-level tests can declare dependencies on capabilities instead of guessing what the environment supports.

Keep the probes tiny, deterministic, and well-documented, and this repository becomes a durable map of your runtime environment.
