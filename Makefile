SHELL := /bin/bash
PYTHON ?= python3
CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra
RSCRIPT ?= Rscript
ARTIFACT_DIR := artifacts
C_BUILD_DIR := $(ARTIFACT_DIR)/.c_probes
C_TEST_BIN_DIR := $(ARTIFACT_DIR)/.c_tests

PYTHON_PROBE_SCRIPTS := $(filter-out probes/_%.py,$(wildcard probes/*.py))
PYTHON_PROBES := $(basename $(notdir $(PYTHON_PROBE_SCRIPTS)))
PYTHON_ARTIFACTS := $(addprefix $(ARTIFACT_DIR)/,$(addsuffix .json,$(PYTHON_PROBES)))

C_PROBE_SOURCES := $(filter-out probes/_%.c,$(wildcard probes/*.c))
C_PROBES := $(basename $(notdir $(C_PROBE_SOURCES)))
C_ARTIFACTS := $(addprefix $(ARTIFACT_DIR)/,$(addsuffix .json,$(C_PROBES)))
C_PROBE_BINARIES := $(addprefix $(C_BUILD_DIR)/,$(C_PROBES))

R_PROBE_SCRIPTS := $(filter-out probes/_%.R,$(wildcard probes/*.R))
R_PROBES := $(basename $(notdir $(R_PROBE_SCRIPTS)))
R_ARTIFACTS := $(addprefix $(ARTIFACT_DIR)/,$(addsuffix .json,$(R_PROBES)))

PROBES := $(sort $(PYTHON_PROBES) $(C_PROBES) $(R_PROBES))

C_TEST_SOURCES := $(wildcard tests/c/*.c)
R_TEST_SCRIPTS := $(wildcard tests/r/*.R)

.PHONY: all probes clean list run test python-tests c-tests r-tests $(PROBES)

all: probes

probes: $(PYTHON_ARTIFACTS) $(C_ARTIFACTS) $(R_ARTIFACTS)

$(ARTIFACT_DIR):
	mkdir -p $@

$(C_BUILD_DIR):
	mkdir -p $@

$(C_TEST_BIN_DIR):
	mkdir -p $@

$(PYTHON_ARTIFACTS): $(ARTIFACT_DIR)/%.json: probes/%.py | $(ARTIFACT_DIR)
	@echo "[probe] $*"
	$(PYTHON) $< --output $@

$(C_PROBE_BINARIES): $(C_BUILD_DIR)/%: probes/%.c probes/_runner_c.c probes/_runner_c.h | $(C_BUILD_DIR)
	$(CC) $(CFLAGS) -Iprobes -o $@ $< probes/_runner_c.c

$(C_ARTIFACTS): $(ARTIFACT_DIR)/%.json: $(C_BUILD_DIR)/% | $(ARTIFACT_DIR)
	@echo "[probe] $*"
	$< --output $@

$(R_ARTIFACTS): $(ARTIFACT_DIR)/%.json: probes/%.R | $(ARTIFACT_DIR)
	@echo "[probe] $*"
	$(RSCRIPT) $< --output $@

$(PROBES): %: $(ARTIFACT_DIR)/%.json
	@echo "wrote $<"

list:
	@echo "Available probes:" && for name in $(PROBES); do \
		if [ -f "probes/$$name.py" ]; then \
			lang="python"; \
		elif [ -f "probes/$$name.c" ]; then \
			lang="c"; \
		elif [ -f "probes/$$name.R" ]; then \
			lang="r"; \
		else \
			lang="unknown"; \
		fi; \
		echo "  - $$name ($$lang)"; \
	done

run:
	@test -n "$(PROBE)" || (echo "Usage: make run PROBE=<name>" >&2 && exit 1)
	@if [ ! -f "probes/$(PROBE).py" ] && [ ! -f "probes/$(PROBE).c" ] && [ ! -f "probes/$(PROBE).R" ]; then \
		echo "Unknown probe '$(PROBE)'" >&2; \
		exit 1; \
	fi
	$(MAKE) $(ARTIFACT_DIR)/$(PROBE).json

clean:
	rm -rf $(ARTIFACT_DIR)

test: python-tests c-tests r-tests

python-tests:
	$(PYTHON) -m unittest discover -s tests -p "test_*.py"

c-tests: | $(C_TEST_BIN_DIR)
	@if [ -z "$(strip $(C_TEST_SOURCES))" ]; then \
		echo "No C tests discovered"; \
	else \
		for src in $(C_TEST_SOURCES); do \
			name=$$(basename $$src .c); \
			echo "[c-test] $$name"; \
			$(CC) $(CFLAGS) -Iprobes -o $(C_TEST_BIN_DIR)/$$name $$src probes/_runner_c.c || exit 1; \
			$(C_TEST_BIN_DIR)/$$name || exit $$?; \
		done; \
	fi

r-tests:
	@if [ -z "$(strip $(R_TEST_SCRIPTS))" ]; then \
		echo "No R tests discovered"; \
	else \
		for script in $(R_TEST_SCRIPTS); do \
			name=$$(basename $$script); \
			echo "[r-test] $$name"; \
			$(RSCRIPT) $$script || exit $$?; \
		done; \
	fi
