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

import std/[os, posix, strutils, unittest]
from std/times import epochTime

import pkg/chronos

import moepkg/[signal_watcher, terminal_command]
import moepkg/deadly_signals

when defined(linux):
  proc posix_openpt(flags: cint): cint {.importc, header: "<stdlib.h>".}
  proc grantpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
  proc unlockpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
  proc ptsname(fd: cint): cstring {.importc, header: "<stdlib.h>".}

proc defaultActions() =
  ## Run as if started from an interactive shell: a background job or `nohup`
  ## inherits some of the set as ignored, which the editor leaves alone.
  for sig in DeadlySignals:
    var
      act = Sigaction(sa_handler: SIG_DFL)
      previous: Sigaction
    doAssert sigemptyset(act.sa_mask) == 0
    doAssert sigaction(sig, act, previous) == 0

defaultActions()

# Forked children below use `exitnow`: `quit` runs GC and exit procs that may
# deadlock after `fork`.

suite "terminal_command - runInTerminal":
  test "Reports the exit code as a shell does":
    check runInTerminal("exit 3") == 3
    check runInTerminal("kill -TERM $$") == 128 + SIGTERM.int

  test "A command that cannot start reports 127":
    check runInTerminal("exec /nonexistent/moe-test-command") == 127

  test "A signal to moe ends the command":
    # Sent once the command runs, not before: a signal taken first would keep
    # it from starting at all. Waits long enough for `sleep 10` to spawn.
    let pid = fork()
    require pid >= 0
    if pid == 0:
      if not startSignalWatcher(10.seconds, 10.seconds):
        exitnow(3)
      loopAnswers()
      var sender: Thread[void]
      createThread(
        sender,
        proc() {.thread.} =
          sleep(1000)
          discard kill(getpid(), SIGTERM),
      )
      let started = epochTime()
      let code = runInTerminal("sleep 10")
      joinThread(sender)
      let took = epochTime() - started
      exitnow(if took > 0.5 and took < 8 and code == 128 + SIGTERM.int: 0 else: 7)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "The command starts with nothing blocked":
    when defined(linux):
      let report = getTempDir() / "moe_test_command_mask.txt"
      removeFile(report)
      defer:
        removeFile(report)
      let pid = fork()
      require pid >= 0
      if pid == 0:
        if not startSignalWatcher(10.seconds, 10.seconds):
          exitnow(3)
        loopAnswers()
        exitnow(cint(runInTerminal("grep ^SigBlk /proc/self/status > " & report)))

      var status: cint
      check waitpid(pid, status, 0) == pid
      check WIFEXITED(status)
      check WEXITSTATUS(status) == 0
      let blocked = parseHexInt(readFile(report).strip.split()[1])
      for sig in DeadlySignals:
        check (blocked and (1 shl (sig.int - 1))) == 0

  test "A command is not started once moe is being ended":
    let marker = getTempDir() / "moe_test_not_run.txt"
    removeFile(marker)
    defer:
      removeFile(marker)
    let pid = fork()
    require pid >= 0
    if pid == 0:
      if not startSignalWatcher(10.seconds, 10.seconds):
        exitnow(3)
      loopAnswers()
      discard kill(getpid(), SIGTERM)
      var waited = 0
      while takenSignal() == 0 and waited < 5000:
        sleep(10)
        waited += 10
      if takenSignal() == 0:
        exitnow(7)
      exitnow(if runInTerminal("touch " & marker) == -1: 0 else: 7)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0
    check not fileExists(marker)

  test "With stdin redirected the command still runs instead of being killed":
    # `terminalJob` may see foreground through stdout or `/dev/tty` while
    # stdin is redirected; job control on stdin would then fail in
    # `giveTerminal` and kill the command. Guards the `stdinHoldsTerminal`
    # part of the `jobControl` condition in `runInTerminal`.
    when defined(linux):
      let pid = fork()
      require pid >= 0
      if pid == 0:
        let master = posix_openpt(O_RDWR or O_NOCTTY)
        if master < 0:
          exitnow(3)
        if grantpt(master) != 0 or unlockpt(master) != 0:
          exitnow(3)
        if ptsname(master) == nil:
          exitnow(3)
        let slaveName = $ptsname(master)
        if setsid() < 0:
          exitnow(3)
        let slave = open(slaveName.cstring, O_RDWR)
        if slave < 0:
          exitnow(3)
        if dup2(slave, STDOUT_FILENO) < 0 or dup2(slave, STDERR_FILENO) < 0:
          exitnow(3)
        let devnull = open("/dev/null".cstring, O_RDONLY)
        if devnull < 0:
          exitnow(3)
        if dup2(devnull, STDIN_FILENO) < 0:
          exitnow(3)
        if tcsetpgrp(slave, getpgrp()) != 0:
          exitnow(3)
        if slave > STDERR_FILENO:
          discard close(slave)
        if devnull > STDERR_FILENO:
          discard close(devnull)
        # The divergent state the guard is for: foreground through the pty
        # while stdin cannot move the foreground job.
        if terminalJob() != tjForeground or stdinHoldsTerminal():
          exitnow(3)
        exitnow(if runInTerminal("exit 42") == 42: 0 else: 7)

      var status: cint
      check waitpid(pid, status, 0) == pid
      check WIFEXITED(status)
      check WEXITSTATUS(status) == 0

suite "terminal_command - waitForEnter":
  test "A lone carriage return ends it":
    # A command may leave the terminal in raw mode, where Enter sends `\r`.
    var fds: array[2, cint]
    require pipe(fds) == 0
    let pid = fork()
    require pid >= 0
    if pid == 0:
      discard dup2(fds[0], STDIN_FILENO)
      waitForEnter()
      exitnow(0)
    discard close(fds[0])
    let input = "x\r"
    check write(fds[1], input.cstring, input.len) == input.len
    let started = epochTime()
    var status: cint
    while waitpid(pid, status, WNOHANG) == 0 and epochTime() - started < 3:
      sleep(10)
    if epochTime() - started >= 3:
      discard kill(pid, SIGKILL)
      discard waitpid(pid, status, 0)
    discard close(fds[1])
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0
