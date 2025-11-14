# Thin compatibility shim: the canonical base-R probe runtime lives in
# runtime/r/probe_runtime.R. Probes and tests should continue to source this file;
# external projects may vendor runtime/r/ directly.
source(file.path("runtime", "r", "probe_runtime.R"), chdir = TRUE)
