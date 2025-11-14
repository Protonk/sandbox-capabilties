#ifndef PROBES_RUNNER_C_H
#define PROBES_RUNNER_C_H

#include <limits.h>
#include <stddef.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

struct probe_cli {
    char output_path[PATH_MAX];
};

struct probe_result {
    const char *capability;
    const char *status;
    const char *detail;
};

int probe_cli_init(struct probe_cli *cli, const char *capability);
int probe_cli_parse(struct probe_cli *cli, int argc, char **argv);
const char *probe_cli_output_path(const struct probe_cli *cli);

int emit_result(const struct probe_result *result, const char *output_path);

#endif  // PROBES_RUNNER_C_H
