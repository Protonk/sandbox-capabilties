source(file.path("probes", "_runner_r.R"))

CAPABILITY <- "filesystem_tmp_write"

exercise <- function() {
  tmp_dir <- tempdir()
  # Mirror the Python/native specimens: timestamp suffix avoids clobbering parallel runs.
  file_path <- file.path(tmp_dir, sprintf("%s_%d.txt", CAPABILITY, as.integer(Sys.time())))
  payload <- "sandbox capability probe (r)"

  result <- tryCatch(
    {
      writeLines(payload, file_path, useBytes = TRUE)
      if (file.exists(file_path)) {
        # tempdir() may live on a shared volume—delete the file immediately to avoid
        # tripping future probes that run under stricter quotas.
        file.remove(file_path)
      }
      list(status = "supported", detail = sprintf("Temporary directory '%s' is writable via R", tmp_dir))
    },
    error = function(err) {
      list(
        status = "blocked_unexpected",
        detail = sprintf("Error while writing '%s': %s", file_path, conditionMessage(err))
      )
    }
  )
  result
}

main <- function() {
  args <- parse_args(CAPABILITY)
  outcome <- exercise()
  emit_result(
    list(capability = CAPABILITY, status = outcome$status, detail = outcome$detail),
    args$output
  )
}

if (sys.nframe() == 0L) {
  main()
}
