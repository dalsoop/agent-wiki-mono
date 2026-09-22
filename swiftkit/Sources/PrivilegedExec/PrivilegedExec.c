#include "PrivilegedExec.h"

#include <TargetConditionals.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if TARGET_OS_OSX
#include <Security/Authorization.h>

static char *dup_msg(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s);
    char *p = malloc(n + 1);
    if (!p) return NULL;
    memcpy(p, s, n + 1);
    return p;
}
#endif

int PrivilegedExecRun(const char *command, char **out_stdout, char **out_stderr) {
    if (out_stdout) *out_stdout = NULL;
    if (out_stderr) *out_stderr = NULL;
    if (!command) {
        if (out_stderr) *out_stderr = strdup("empty command");
        return 1;
    }

#if !TARGET_OS_OSX
    (void)command;
    if (out_stderr) *out_stderr = strdup("privileged exec is macOS-only");
    return 1;
#else
    AuthorizationRef auth = NULL;
    OSStatus status = AuthorizationCreate(
        NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (status != errAuthorizationSuccess) {
        if (out_stderr) *out_stderr = dup_msg("AuthorizationCreate failed");
        return (int)status;
    }

    AuthorizationItem item = { "system.privilege.admin", 0, NULL, 0 };
    AuthorizationRights rights = { 1, &item };
    AuthorizationFlags flags = (AuthorizationFlags)(
        kAuthorizationFlagDefaults
        | kAuthorizationFlagInteractionAllowed
        | kAuthorizationFlagPreAuthorize
        | kAuthorizationFlagExtendRights);
    status = AuthorizationCopyRights(
        auth, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (status != errAuthorizationSuccess) {
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
        if (out_stderr) {
            *out_stderr = dup_msg(
                status == errAuthorizationCanceled
                    ? "User canceled"
                    : "AuthorizationCopyRights failed");
        }
        return (int)status;
    }

    char *args[] = { "-c", (char *)command, NULL };
    FILE *pipe = NULL;
    status = AuthorizationExecuteWithPrivileges(
        auth, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);
    if (status != errAuthorizationSuccess) {
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
        if (out_stderr) *out_stderr = dup_msg("AuthorizationExecuteWithPrivileges failed");
        return (int)status;
    }

    size_t cap = 4096;
    size_t len = 0;
    char *buf = malloc(cap);
    if (buf) buf[0] = '\0';
    if (buf && pipe) {
        char line[1024];
        while (fgets(line, (int)sizeof(line), pipe)) {
            size_t n = strlen(line);
            if (len + n + 1 > cap) {
                cap *= 2;
                char *nb = realloc(buf, cap);
                if (!nb) break;
                buf = nb;
            }
            memcpy(buf + len, line, n);
            len += n;
            buf[len] = '\0';
        }
        fclose(pipe);
    } else if (pipe) {
        fclose(pipe);
    }
    AuthorizationFree(auth, kAuthorizationFlagDefaults);
    if (out_stdout) *out_stdout = buf;
    else free(buf);
    return 0;
#endif
}
