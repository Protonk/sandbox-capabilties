#include "_runner_c.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char *CAPABILITY = "c_runner_cli_test";

int main(void) {
    struct probe_cli cli;
    if (probe_cli_init(&cli, CAPABILITY) != 0) {
        fprintf(stderr, "probe_cli_init failed\n");
        return 1;
    }

    char program_name[] = "test_runner_cli";
    char *argv[] = {program_name, NULL};
    if (probe_cli_parse(&cli, 1, argv) != 0) {
        fprintf(stderr, "probe_cli_parse rejected default arguments\n");
        return 1;
    }

    const char *expected = "artifacts/c_runner_cli_test.json";
    const char *resolved = probe_cli_output_path(&cli);
    if (resolved == NULL || strcmp(resolved, expected) != 0) {
        fprintf(stderr, "expected output path '%s' but saw '%s'\n", expected, resolved);
        return 1;
    }

    struct probe_result result = {
        .capability = CAPABILITY,
        .status = "supported",
        .detail = "c runtime emits JSON artifacts",
    };

    if (emit_result(&result, resolved) != 0) {
        fprintf(stderr, "emit_result returned failure\n");
        return 1;
    }

    if (access(resolved, F_OK) != 0) {
        fprintf(stderr, "Artifact '%s' does not exist\n", resolved);
        return 1;
    }

    return 0;
}
