#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// `/bin/sh -c <command>` via Security.framework authorization prompt.
/// Caller frees `out_stdout` and `out_stderr` when non-NULL.
int PrivilegedExecRun(const char *command, char **out_stdout, char **out_stderr);

#ifdef __cplusplus
}
#endif
