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

## Running a shell command on the terminal as its own job: its process group
## holds the terminal, so Ctrl-C reaches the whole command and not moe, and
## signals to moe are passed on to the group.

import std/posix

import pkg/chronos/timer

import deadly_signals, logger, posix_wait, signal_watcher_linux

proc inBackground*(): bool =
  ## Whether another job holds moe's terminal, as after Ctrl-Z and `kill %1`.
  terminalJob() == tjBackground

proc orphaned(): bool =
  ## Whether no shell is left to continue moe; the kernel then drops its
  ## SIGTSTP.
  getsid(getppid()) != getsid(0)

proc giveTerminal(pgid: Pid): bool =
  ## Make `pgid` the foreground job. SIGTTOU is blocked: moe is in the
  ## background when it takes the terminal back.
  withSignalBlocked(SIGTTOU):
    result = tcsetpgrp(STDIN_FILENO, pgid) == 0

proc waitForCommand(pid: Pid, target: int, holdsTerminal: bool, lost: var cint): int =
  ## Wait for `pid` to exit without reaping it, so its pid is not reused, and
  ## return its shell-style exit code, or -1. A stopped command is continued
  ## only while it holds the terminal; otherwise it would just stop again.
  let stops = if holdsTerminal: WSTOPPED else: 0
  while true:
    var info: SigInfo
    if waitid(idPid, Id(pid), info, WEXITED or stops or WNOWAIT) != 0:
      if errno == EINTR:
        continue
      lost = errno
      return -1
    if info.si_code == cldStopped:
      # Never blocking: someone else may have continued it meanwhile.
      var consumed: SigInfo
      discard waitid(idPid, Id(pid), consumed, WSTOPPED or WNOHANG)
      discard kill(Pid(target), SIGCONT)
      continue
    return decodeSiginfo(info)

var environ {.importc, header: "<unistd.h>".}: cstringArray

proc spawnShell(command: string, ownGroup: bool, pid: var Pid): cint =
  ## Start `sh -c command` with nothing blocked, in its own process group when
  ## `ownGroup`. 0, or the error. Not `osproc`: older Nim forks without
  ## clearing the mask.
  var
    attrs: Tposix_spawnattr
    actions: Tposix_spawn_file_actions
    mask: Sigset
  result = posix_spawnattr_init(attrs)
  if result != 0:
    return
  defer:
    discard posix_spawnattr_destroy(attrs)
  result = posix_spawn_file_actions_init(actions)
  if result != 0:
    return
  defer:
    discard posix_spawn_file_actions_destroy(actions)

  var flags = POSIX_SPAWN_SETSIGMASK
  if sigemptyset(mask) != 0:
    return errno
  result = posix_spawnattr_setsigmask(attrs, mask)
  if result == 0 and ownGroup:
    flags = flags or POSIX_SPAWN_SETPGROUP
    result = posix_spawnattr_setpgroup(attrs, 0)
  if result == 0:
    result = posix_spawnattr_setflags(attrs, flags)
  if result != 0:
    return

  let argv = allocCStringArray(["sh", "-c", command])
  defer:
    deallocCStringArray(argv)
  result = posix_spawn(pid, "/bin/sh", actions, attrs, argv, environ)

proc runInTerminal*(command: string): int =
  ## Run `command` through the shell on the terminal and return its exit code.
  ## Not `execShellCmd`: `system()` passes on the blocked deadly set.
  if takenSignal() != 0:
    stdout.write("moe: the command was not run: moe is being ended\n")
    return -1
  # Job control only while stdin can move the foreground job: `terminalJob`
  # may see foreground through stdout or `/dev/tty` while stdin is redirected,
  # and `giveTerminal` on stdin would fail and kill the command below.
  let jobControl = terminalJob() == tjForeground and stdinHoldsTerminal()
  var pid: Pid
  let failed = spawnShell(command, jobControl, pid)
  if failed != 0:
    stdout.write("moe: cannot run the command: " & $strerror(failed) & "\n")
    return -1
  let target =
    if jobControl:
      -pid.int
    else:
      pid.int
  var
    ended = false
    lost: cint
  try:
    if jobControl:
      if giveTerminal(pid):
        # Continue any part that stopped reading the terminal before it had it.
        discard kill(Pid(target), SIGCONT)
      else:
        # In the background it would stop on its first read of the terminal.
        stdout.write("moe: cannot give the terminal to the command\n")
        discard kill(Pid(target), SIGKILL)
    withCommandInTerminal(target):
      result = waitForCommand(pid, target, jobControl, lost)
    ended = result >= 0
  finally:
    if not ended and lost != ECHILD:
      # It may still run. Once reaped (ECHILD), its pid may be another's.
      discard kill(Pid(target), SIGKILL)
    if jobControl and not giveTerminal(getpgrp()):
      # moe is left a background job; the frontend waits stopped for `fg`.
      logError("terminal_command", "Cannot take the terminal back: " & $errno)
    var status: cint
    while waitpid(pid, status, 0) < 0 and errno == EINTR:
      discard
  if not ended:
    # Only now: earlier, a write could stop moe under `stty tostop`.
    stdout.write("moe: cannot tell how the command ended\n")

proc waitForEnter*() =
  ## Wait for Enter, or return once a deadly signal arrives. A byte at a time:
  ## a command may leave the terminal raw, where Enter sends a lone `\r`.
  var fds = [TPollfd(fd: STDIN_FILENO, events: POLLIN)]
  while takenSignal() == 0:
    let ready = poll(fds[0].addr, 1, 100)
    if ready > 0:
      var c: char
      let n = read(STDIN_FILENO, c.addr, 1)
      if n <= 0 and not (n < 0 and errno == EINTR):
        return # End of file, or the terminal is gone.
      if n == 1 and c in {'\n', '\r'}:
        return
    elif ready < 0 and errno != EINTR:
      return

proc stayStoppedInBackground*() =
  ## Once continued after Ctrl-Z, stop again while another job holds the
  ## terminal. Returns when a signal is taken. A signal sent to the stopped
  ## process stays pending until it is continued, so this only observes it
  ## after `fg` or equivalent. With no shell left, hang up on self so the
  ## loop preserves.
  while inBackground():
    if waitForTakenSignal(500.milliseconds) != 0:
      return
    if orphaned():
      # Under `nohup` SIGHUP is ignored.
      discard kill(getpid(), SIGHUP)
      if waitForTakenSignal(500.milliseconds) == 0:
        discard kill(getpid(), SIGTERM)
      return
    discard kill(getpid(), SIGTSTP)
