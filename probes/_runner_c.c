#include "_runner_c.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static bool status_is_success(const char *status) {
    if (status == NULL) {
        return false;
    }
    return strcmp(status, "supported") == 0 || strcmp(status, "blocked_expected") == 0;
}

static int ensure_parent_dirs(const char *path) {
    char buffer[PATH_MAX];
    size_t length = strnlen(path, sizeof(buffer) - 1);
    if (length == 0) {
        return 0;
    }
    if (length >= sizeof(buffer)) {
        fprintf(stderr, "Path is too long: %s\n", path);
        return -1;
    }
    memcpy(buffer, path, length);
    buffer[length] = '\0';

    for (size_t i = 1; i < length; ++i) {
        if (buffer[i] != '/') {
            continue;
        }
        buffer[i] = '\0';
        if (buffer[0] != '\0') {
            if (mkdir(buffer, 0777) != 0 && errno != EEXIST) {
                fprintf(stderr, "Unable to create directory '%s': %s\n", buffer, strerror(errno));
                return -1;
            }
        }
        buffer[i] = '/';
    }
    return 0;
}

static void json_escape(FILE *fp, const char *text) {
    if (text == NULL) {
        return;
    }
    const unsigned char *cursor = (const unsigned char *)text;
    for (; *cursor != '\0'; ++cursor) {
        unsigned char ch = *cursor;
        switch (ch) {
            case '"':
                fputs("\\\"", fp);
                break;
            case '\\':
                fputs("\\\\", fp);
                break;
            case '\n':
                fputs("\\n", fp);
                break;
            case '\r':
                fputs("\\r", fp);
                break;
            case '\t':
                fputs("\\t", fp);
                break;
            default:
                if (ch < 0x20) {
                    fprintf(fp, "\\u%04x", ch);
                } else {
                    fputc(ch, fp);
                }
                break;
        }
    }
}

int probe_cli_init(struct probe_cli *cli, const char *capability) {
    if (cli == NULL || capability == NULL) {
        return -1;
    }
    int written = snprintf(cli->output_path, sizeof(cli->output_path), "artifacts/%s.json", capability);
    if (written < 0 || (size_t)written >= sizeof(cli->output_path)) {
        fprintf(stderr, "Capability name '%s' is too long for an artifact path\n", capability);
        return -1;
    }
    return 0;
}

int probe_cli_parse(struct probe_cli *cli, int argc, char **argv) {
    if (cli == NULL || argv == NULL) {
        return -1;
    }
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--output") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "--output flag requires a value\n");
                return -1;
            }
            ++i;
            size_t length = strnlen(argv[i], sizeof(cli->output_path) - 1);
            if (length >= sizeof(cli->output_path)) {
                fprintf(stderr, "Output path is too long: %s\n", argv[i]);
                return -1;
            }
            memcpy(cli->output_path, argv[i], length);
            cli->output_path[length] = '\0';
        } else {
            fprintf(stderr, "Unknown argument '%s'\n", argv[i]);
            return -1;
        }
    }
    return 0;
}

const char *probe_cli_output_path(const struct probe_cli *cli) {
    if (cli == NULL) {
        return NULL;
    }
    return cli->output_path;
}

int emit_result(const struct probe_result *result, const char *output_path) {
    if (result == NULL || output_path == NULL) {
        return 1;
    }

    if (ensure_parent_dirs(output_path) != 0) {
        return 1;
    }

    FILE *fp = fopen(output_path, "w");
    if (fp == NULL) {
        fprintf(stderr, "Unable to open '%s' for writing: %s\n", output_path, strerror(errno));
        return 1;
    }

    fputs("{\n  \"capability\": \"", fp);
    json_escape(fp, result->capability);
    fputs("\",\n  \"status\": \"", fp);
    json_escape(fp, result->status);
    fputs("\",\n  \"detail\": \"", fp);
    json_escape(fp, result->detail);
    fputs("\"\n}\n", fp);

    if (fclose(fp) != 0) {
        fprintf(stderr, "Failed to close '%s': %s\n", output_path, strerror(errno));
        return 1;
    }

    return status_is_success(result->status) ? 0 : 1;
}
