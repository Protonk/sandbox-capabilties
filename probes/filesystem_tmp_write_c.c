#include "_runner_c.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static const char *CAPABILITY = "filesystem_tmp_write_c";

static struct probe_result exercise(void) {
    static char detail[512];

    const char *tmp_dir = getenv("TMPDIR");
    if (tmp_dir == NULL || tmp_dir[0] == '\0') {
        tmp_dir = "/tmp";
    }

    char file_path[PATH_MAX];
    snprintf(file_path, sizeof(file_path), "%s/%s_%ld.txt", tmp_dir, CAPABILITY, (long)time(NULL));

    int fd = open(file_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd == -1) {
        snprintf(detail, sizeof(detail), "Unable to open '%s' for writing: %s", file_path, strerror(errno));
        return (struct probe_result){CAPABILITY, "blocked_unexpected", detail};
    }

    const char payload[] = "sandbox capability probe (c)\n";
    ssize_t written = write(fd, payload, sizeof(payload) - 1);
    int saved_errno = errno;
    close(fd);

    if (written < 0) {
        snprintf(detail, sizeof(detail), "Write failed for '%s': %s", file_path, strerror(saved_errno));
        unlink(file_path);
        return (struct probe_result){CAPABILITY, "blocked_unexpected", detail};
    }

    unlink(file_path);
    snprintf(detail, sizeof(detail), "Temporary directory '%s' is writable via native code", tmp_dir);
    return (struct probe_result){CAPABILITY, "supported", detail};
}

int main(int argc, char **argv) {
    struct probe_cli cli;
    if (probe_cli_init(&cli, CAPABILITY) != 0) {
        fprintf(stderr, "Failed to initialize CLI defaults for %s\n", CAPABILITY);
        return 1;
    }
    if (probe_cli_parse(&cli, argc, argv) != 0) {
        return 2;
    }

    struct probe_result result = exercise();
    return emit_result(&result, probe_cli_output_path(&cli));
}
