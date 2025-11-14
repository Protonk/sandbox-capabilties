SHELL := /bin/bash
PYTHON ?= python3
CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra
RSCRIPT ?= Rscript
ARTIFACT_DIR := artifacts
C_BUILD_DIR := $(ARTIFACT_DIR)/.c_probes
C_TEST_BIN_DIR := $(ARTIFACT_DIR)/.c_tests

# Recursively discover every specimen so the harness auto-scales as files are added
# beneath probes/core/** or probes/fuzz/**. Helpers and runners keep their `_` prefix
# to stay hidden from find.
PYTHON_PROBE_SOURCES := $(shell find probes -type f -name '*.py' ! -name '_*.py' | sort)
C_PROBE_SOURCES := $(shell find probes -type f -name '*.c' ! -name '_*.c' | sort)
R_PROBE_SOURCES := $(shell find probes -type f -name '*.R' ! -name '_*.R' | sort)

# Convert an absolute probe path into a probes-relative fragment for display.
define probe_rel
$(patsubst probes/%,%,$1)
endef

# Flatten the path (swap / -> __) so every specimen produces a unique ID + artifact.
define probe_id
$(subst /,__,$(basename $(call probe_rel,$1)))
endef

# Map a specimen path to its JSON artifact path.
define artifact_path
$(ARTIFACT_DIR)/$(call probe_id,$1).json
endef

# Local build directory for compiled C probes so source directories stay clean.
define c_binary_path
$(C_BUILD_DIR)/$(call probe_id,$1)
endef

PYTHON_ARTIFACTS := $(foreach src,$(PYTHON_PROBE_SOURCES),$(call artifact_path,$(src)))
C_ARTIFACTS := $(foreach src,$(C_PROBE_SOURCES),$(call artifact_path,$(src)))
R_ARTIFACTS := $(foreach src,$(R_PROBE_SOURCES),$(call artifact_path,$(src)))
ALL_ARTIFACTS := $(sort $(PYTHON_ARTIFACTS) $(C_ARTIFACTS) $(R_ARTIFACTS))

PROBE_IDS := $(sort $(foreach src,$(PYTHON_PROBE_SOURCES) $(C_PROBE_SOURCES) $(R_PROBE_SOURCES),$(call probe_id,$(src))))

PROBE_INDEX := $(foreach src,$(PYTHON_PROBE_SOURCES),$(call probe_id,$(src))@@@python@@@$(call probe_rel,$(src))) \
	$(foreach src,$(C_PROBE_SOURCES),$(call probe_id,$(src))@@@c@@@$(call probe_rel,$(src))) \
	$(foreach src,$(R_PROBE_SOURCES),$(call probe_id,$(src))@@@r@@@$(call probe_rel,$(src)))

PROBES := $(PROBE_IDS)

C_TEST_SOURCES := $(wildcard tests/c/*.c)
R_TEST_SCRIPTS := $(wildcard tests/r/*.R)

.PHONY: all probes clean list run test python-tests c-tests r-tests $(PROBES)

all: probes

probes: $(ALL_ARTIFACTS)

$(ARTIFACT_DIR):
	mkdir -p $@

$(C_BUILD_DIR):
	mkdir -p $@

$(C_TEST_BIN_DIR):
	mkdir -p $@

define PYTHON_PROBE_RULE
$(call artifact_path,$1): $1 | $(ARTIFACT_DIR)
	@echo "[probe] $(call probe_id,$1)"
	# Export PROBE_ID so the shared runner emits artifacts to the ID-matched path even
	# when the script relies on its default `--output`.
	PROBE_ID=$(call probe_id,$1) PYTHONPATH=probes:$${PYTHONPATH} $(PYTHON) $1 --output $$@
endef

define C_PROBE_RULE
$(call c_binary_path,$1): $1 probes/_runner_c.c probes/_runner_c.h | $(C_BUILD_DIR)
	$(CC) $(CFLAGS) -Iprobes -o $$@ $1 probes/_runner_c.c
$(call artifact_path,$1): $(call c_binary_path,$1) | $(ARTIFACT_DIR)
	@echo "[probe] $(call probe_id,$1)"
	# Native probes read PROBE_ID through probe_cli_init so their default artifact path
	# matches the Make-derived ID instead of the capability slug.
	PROBE_ID=$(call probe_id,$1) $(call c_binary_path,$1) --output $$@
endef

define R_PROBE_RULE
$(call artifact_path,$1): $1 | $(ARTIFACT_DIR)
	@echo "[probe] $(call probe_id,$1)"
	# R helpers mirror the same PROBE_ID behavior; note that Rscript inherits env vars.
	PROBE_ID=$(call probe_id,$1) $(RSCRIPT) $1 --output $$@
endef

PYTHON_RULE_EVAL := $(foreach src,$(PYTHON_PROBE_SOURCES),$(eval $(call PYTHON_PROBE_RULE,$(src))))
C_RULE_EVAL := $(foreach src,$(C_PROBE_SOURCES),$(eval $(call C_PROBE_RULE,$(src))))
R_RULE_EVAL := $(foreach src,$(R_PROBE_SOURCES),$(eval $(call R_PROBE_RULE,$(src))))

$(PROBES): %: $(ARTIFACT_DIR)/%.json
	@echo "wrote $<"

list:
	@echo "Available probes:" && \
	for entry in $(PROBE_INDEX); do \
		id=$${entry%%@@@*}; \
		rest=$${entry#*@@@}; \
		lang=$${rest%%@@@*}; \
		path=$${rest#*@@@}; \
		echo "  - $$id ($$lang) <- probes/$$path"; \
	done

run:
	@test -n "$(PROBE)" || (echo "Usage: make run PROBE=<name>" >&2 && exit 1)
	@if ! echo " $(PROBE_IDS) " | grep -q " $(PROBE) "; then \
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
