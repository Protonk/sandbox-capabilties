default_output <- function(capability) {
  file.path("artifacts", paste0(capability, ".json"))
}

parse_args <- function(capability, argv = commandArgs(trailingOnly = TRUE)) {
  output <- default_output(capability)
  i <- 1
  while (i <= length(argv)) {
    arg <- argv[[i]]
    if (identical(arg, "--output")) {
      if (i == length(argv)) {
        stop("--output flag requires a value", call. = FALSE)
      }
      i <- i + 1
      output <- argv[[i]]
    } else {
      stop(sprintf("Unknown argument '%s'", arg), call. = FALSE)
    }
    i <- i + 1
  }
  list(output = output)
}

json_escape <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", value, fixed = TRUE)
  value <- gsub("\"", "\\\\\"", value, fixed = TRUE)
  value <- gsub("\n", "\\\\n", value, fixed = TRUE)
  value <- gsub("\r", "\\\\r", value, fixed = TRUE)
  value <- gsub("\t", "\\\\t", value, fixed = TRUE)
  value
}

persist_result <- function(result, output_path) {
  required <- c("capability", "status", "detail")
  missing_fields <- setdiff(required, names(result))
  if (length(missing_fields) > 0) {
    stop(
      sprintf("Result is missing required field(s): %s", paste(missing_fields, collapse = ", ")),
      call. = FALSE
    )
  }

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  json_blob <- sprintf(
    "{\n  \"capability\": \"%s\",\n  \"status\": \"%s\",\n  \"detail\": \"%s\"\n}\n",
    json_escape(result$capability),
    json_escape(result$status),
    json_escape(result$detail)
  )
  writeLines(json_blob, con = output_path, useBytes = TRUE)
  if (result$status %in% c("supported", "blocked_expected")) 0 else 1
}

emit_result <- function(result, output_path) {
  status <- persist_result(result, output_path)
  quit(status = status, save = "no")
}
