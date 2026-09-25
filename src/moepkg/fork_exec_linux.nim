#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Starting a command with fork and exec, for where libc's `posix_spawn`
## cannot enter the working directory or close inherited descriptors in the
## child. The child gets what `posix_spawn_setup` gives one: a process group
## of its own, nothing blocked, SIGPIPE at its default.

import std/[os, oserrors, posix, strutils]

import pkg/results
from pkg/chronos/osutils import DescriptorFlag, createOsPipe

import posix_spawn_setup

when defined(moeForkWithoutCloseRange):
  # Tests: walk /proc/self/fd even where close_range would do.
  {.localPassC: "-DMOE_NO_CLOSE_RANGE".}

# The child of a multithreaded process may only make async-signal-safe calls
# before exec: another thread may have held a lock at the fork. Hence C, and
# everything the child needs prepared by the parent.
{.
  emit: """/*TYPESECTION*/
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/wait.h>

typedef struct { int error; } MoeExecFailure;

static int moeAboveStdio(int fd) {
  /* Out of 0-2, so a dup2 onto one of them never overwrites another source. */
  return fd > 2 ? fd : fcntl(fd, F_DUPFD_CLOEXEC, 3);
}

static void moeSetCloseOnExec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags >= 0 && !(flags & FD_CLOEXEC)) fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

struct moeDirent64 {
  unsigned long long d_ino;
  long long d_off;
  unsigned short d_reclen;
  unsigned char d_type;
  char d_name[];
};

static int moeCloseOnExecListed(void) {
  /* Walk /proc/self/fd, which lists only what is open: the limit may be in the
     billions. 0 once done, -1 when it cannot be read. */
#if defined(SYS_getdents64)
  int dir = open("/proc/self/fd", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (dir < 0) return -1;
  long long buf[512];
  for (;;) {
    long n = syscall(SYS_getdents64, dir, buf, sizeof buf);
    if (n < 0) {
      close(dir);
      return -1;
    }
    if (n == 0) break;
    for (long off = 0; off < n;) {
      struct moeDirent64 *d = (struct moeDirent64 *)((char *)buf + off);
      off += d->d_reclen;
      const char *c = d->d_name;
      if (*c < '0' || *c > '9') continue; /* "." and ".." */
      int fd = 0;
      for (; *c >= '0' && *c <= '9'; c++) fd = fd * 10 + (*c - '0');
      if (fd >= 3 && fd != dir) moeSetCloseOnExec(fd);
    }
  }
  close(dir);
  return 0;
#else
  return -1;
#endif
}

static void moeCloseOnExecFrom3(int maxfd) {
#if defined(SYS_close_range) && !defined(__ANDROID__) && !defined(MOE_NO_CLOSE_RANGE)
  /* CLOSE_RANGE_CLOEXEC, Linux 5.11. Android's seccomp would kill the call. */
  if (syscall(SYS_close_range, 3u, ~0u, 4u) == 0) return;
#endif
  if (moeCloseOnExecListed() == 0) return;
  /* No /proc. */
  for (int fd = 3; fd < maxfd; fd++) moeSetCloseOnExec(fd);
}

static int moeChildSetup(const char *dir, int in, int out, int err, int maxfd) {
  /* 0, or the errno of what failed. */
  struct sigaction dfl;
  memset(&dfl, 0, sizeof dfl);
  dfl.sa_handler = SIG_DFL;
  sigemptyset(&dfl.sa_mask);
  for (int s = 1; s < NSIG; s++) {
    /* A handler of moe's must not run here; an ignored SIGPIPE survives exec. */
    struct sigaction cur;
    if (sigaction(s, NULL, &cur) != 0) continue;
    if (s == SIGPIPE || (cur.sa_handler != SIG_DFL && cur.sa_handler != SIG_IGN))
      sigaction(s, &dfl, NULL);
  }
  if (setpgid(0, 0) != 0) return errno;
  in = moeAboveStdio(in);
  out = moeAboveStdio(out);
  err = moeAboveStdio(err);
  if (in < 0 || out < 0 || err < 0) return errno;
  if (dup2(in, 0) < 0 || dup2(out, 1) < 0 || dup2(err, 2) < 0) return errno;
  if (dir != NULL && chdir(dir) != 0) return errno;
  moeCloseOnExecFrom3(maxfd);
  sigset_t none;
  sigemptyset(&none);
  sigprocmask(SIG_SETMASK, &none, NULL);
  return 0;
}

static int moeExecAny(char *const *paths, char *const *argv, char *const *envp) {
  /* Try each path as execvp would, and return the errno it would report. */
  int sawAccess = 0, last = ENOENT;
  for (char *const *p = paths; *p != NULL; p++) {
    execve(*p, argv, envp);
    last = errno;
    if (last == EACCES) sawAccess = 1;
    else if (last != ENOENT && last != ENOTDIR && last != ESTALE &&
             last != ENODEV && last != ETIMEDOUT) break;
  }
  return sawAccess ? EACCES : last;
}

static int moeForkExec(char *const *paths, char *const *argv, char *const *envp,
                       const char *dir, int in, int out, int err, int maxfd,
                       int reportRead, int reportWrite, int *error) {
  /* The pid once the exec succeeded, or -1 with *error set and nothing left
     to reap. Both ends of the report pipe are closed on return. */
  sigset_t all, old;
  sigfillset(&all);
  pthread_sigmask(SIG_SETMASK, &all, &old);
  pid_t pid = fork();
  if (pid == 0) {
    MoeExecFailure f;
    f.error = moeChildSetup(dir, in, out, err, maxfd);
    if (f.error == 0) f.error = moeExecAny(paths, argv, envp);
    while (write(reportWrite, &f, sizeof f) < 0 && errno == EINTR) {}
    _exit(127);
  }
  int forkError = errno;
  pthread_sigmask(SIG_SETMASK, &old, NULL);
  close(reportWrite);
  if (pid < 0) {
    close(reportRead);
    *error = forkError;
    return -1;
  }
  /* The exec closes the report pipe; a failure writes to it first. */
  MoeExecFailure f;
  ssize_t n;
  do { n = read(reportRead, &f, sizeof f); } while (n < 0 && errno == EINTR);
  int readError = errno;
  close(reportRead);
  if (n == 0) return pid;
  while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
  *error = n == (ssize_t)sizeof f ? f.error : (n < 0 ? readError : EIO);
  return -1;
}
"""
.}

proc moeForkExec(
  paths, argv, envp: cstringArray,
  dir: cstring,
  input, output, errors, maxfd, reportRead, reportWrite: cint,
  error: var cint,
): cint {.importc, nodecl.}

proc searchPath(command: string): seq[string] =
  ## Where `execvp` looks for `command`, in its order. Relative entries are
  ## taken in the child, after it entered its working directory, as
  ## `posix_spawnp` takes them.
  if '/' in command:
    return @[command]
  for dir in getEnv("PATH", "/bin:/usr/bin").split(':'):
    result.add(
      if dir.len == 0:
        command
      else:
        dir & "/" & command
    )

proc forkExec*(
    command, workingDir: string, args: seq[string], input, output, errors: cint
): Result[Pid, OSErrorCode] =
  ## Start `command` (looked up on PATH) in `workingDir`, or in moe's own when
  ## empty, with `input`, `output` and `errors` as its standard streams. The
  ## start is over, exec included, when this returns. The caller keeps its
  ## descriptors.
  let report = ?createOsPipe({DescriptorFlag.CloseOnExec}, {DescriptorFlag.CloseOnExec})
  var argvItems = @[command]
  argvItems.add args
  let
    paths = allocCStringArray(searchPath(command))
    argv = allocCStringArray(argvItems)
    openMax = sysconf(SC_OPEN_MAX)
    maxfd = cint(
      if openMax > 0:
        min(openMax, int(high(cint)))
      else:
        1024
    )
  defer:
    deallocCStringArray(paths)
    deallocCStringArray(argv)
  var error: cint = 0
  let pid = moeForkExec(
    paths,
    argv,
    environ,
    if workingDir.len > 0: workingDir.cstring else: nil,
    input,
    output,
    errors,
    maxfd,
    report.read,
    report.write,
    error,
  )
  if pid < 0:
    return err(OSErrorCode(error))
  ok(Pid(pid))
