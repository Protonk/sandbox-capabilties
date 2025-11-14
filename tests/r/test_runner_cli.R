source(file.path("probes", "_runner_r.R"))

CAPABILITY <- "r_runner_cli_test"

args <- parse_args(CAPABILITY, character(0))
expected <- file.path("artifacts", paste0(CAPABILITY, ".json"))
if (!identical(args$output, expected)) {
  stop(sprintf("Expected default output '%s' but saw '%s'", expected, args$output), call. = FALSE)
}

exit_code <- persist_result(
  list(
    capability = CAPABILITY,
    status = "supported",
    detail = "R runtime emits JSON artifacts"
  ),
  args$output
)

if (exit_code != 0) {
  stop(sprintf("persist_result returned %d for supported status", exit_code), call. = FALSE)
}

if (!file.exists(args$output)) {
  stop(sprintf("Artifact '%s' was not created", args$output), call. = FALSE)
}

quit(status = 0, save = "no")
