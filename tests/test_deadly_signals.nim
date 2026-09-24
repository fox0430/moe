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

import std/[os, osproc, posix, strutils, unittest]

import moepkg/deadly_signals

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

proc currentMask(): Sigset =
  ## The calling thread's signal mask. Blocking an empty set reports the mask
  ## without changing it.
  var empty: Sigset
  doAssert sigemptyset(empty) == 0
  doAssert sigemptyset(result) == 0
  doAssert pthread_sigmask(SIG_BLOCK, empty, result) == 0

suite "deadly_signals - blockDeadlySignals":
  test "Every deadly signal ends up blocked":
    var original = currentMask()

    require blockDeadlySignals()
    var blocked = currentMask()
    for sig in DeadlySignals:
      check sigismember(blocked, sig) == 1

    # Restore through the API: a raw mask reset would leave the
    # `blockDeadlySignals` baseline behind for later suites.
    restoreDeadlySignalDefaults()
    var restored = currentMask()
    for sig in DeadlySignals:
      check sigismember(restored, sig) == sigismember(original, sig)

suite "deadly_signals - absorbKeyboardSignals":
  test "Ctrl-C and Ctrl-\\ do nothing inside when nothing takes them":
    # The watcher did not start, so they are not blocked: `:!` must still not
    # let a Ctrl-C end the editor.
    let pid = fork()
    require pid >= 0
    if pid == 0:
      let absorbed = absorbKeyboardSignals()
      discard kill(getpid(), SIGINT)
      discard kill(getpid(), SIGQUIT)
      restoreKeyboardSignals(absorbed)
      discard kill(getpid(), SIGINT) # Default again: ends the process.
      sleep(1000)
      exitnow(7)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGINT

  test "A child started inside still answers Ctrl-C":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      var code = 0
      let absorbed = absorbKeyboardSignals()
      let p = startProcess("kill -INT $$; exit 0", options = {poEvalCommand})
      code = p.waitForExit()
      p.close()
      restoreKeyboardSignals(absorbed)
      exitnow(if code == 0: 7 else: 0)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "One inherited as ignored stays ignored, children included":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      var
        act = Sigaction(sa_handler: SIG_IGN)
        previous: Sigaction
      discard sigemptyset(act.sa_mask)
      discard sigaction(SIGINT, act, previous)
      var code = 1
      let absorbed = absorbKeyboardSignals()
      let p = startProcess("kill -INT $$; exit 0", options = {poEvalCommand})
      code = p.waitForExit()
      p.close()
      restoreKeyboardSignals(absorbed)
      exitnow(if code == 0: 0 else: 7)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

suite "deadly_signals - ignored signals":
  test "A signal inherited as ignored is left out":
    # `nohup moe`: blocked, SIGHUP would be taken as deadly.
    let pid = fork()
    require pid >= 0
    if pid == 0:
      var
        act = Sigaction(sa_handler: SIG_IGN)
        previous: Sigaction
      discard sigemptyset(act.sa_mask)
      discard sigaction(SIGHUP, act, previous)
      var mask: Sigset
      if not deadlySet(mask):
        exitnow(3)
      if sigismember(mask, SIGHUP) != 0 or sigismember(mask, SIGTERM) != 1:
        exitnow(7)
      restoreDeadlySignalDefaults()
      discard kill(getpid(), SIGHUP)
      exitnow(0) # Still ignored.

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

suite "deadly_signals - children":
  test "A process started with the set blocked starts with nothing blocked":
    # `osproc` clears the mask when it spawns, and on older Nim forks instead,
    # where only the fork handler clears it. Git, clipboard tools and the like
    # all go through it.
    when defined(linux):
      let report = getTempDir() / "moe_test_child_mask.txt"
      removeFile(report)
      defer:
        removeFile(report)

      check unblockInForkedChildren()
      check blockDeadlySignals()
      try:
        let p = startProcess(
          "grep ^SigBlk /proc/self/status > " & report,
          options = {poEvalCommand, poParentStreams},
        )
        check p.waitForExit() == 0
        p.close()
      finally:
        restoreDeadlySignalDefaults()

      # SigBlk is a hex bitmask, bit (signo - 1) per signal.
      let blocked = parseHexInt(readFile(report).strip.split()[1])
      for sig in DeadlySignals:
        check (blocked and (1 shl (sig.int - 1))) == 0

suite "deadly_signals - reraiseAsDeath":
  test "The process dies of the signal rather than exiting":
    let pid = fork()
    # `require`: on a fork failure `waitpid` would return -1 with ECHILD and
    # the checks below would read an uninitialized status and pass.
    require pid >= 0
    if pid == 0:
      # Blocked first, as the editor does, so the re-raise has to unblock it.
      discard blockDeadlySignals()
      reraiseAsDeath(SIGTERM)
      exitnow(7) # Only reached if the re-raise failed.

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM

suite "deadly_signals - restoreDeadlySignalDefaults":
  test "A signal arriving afterwards ends the process":
    # The preserve sequence hands the signals back before teardown that can
    # block without bound, so a second one is still a way out.
    let pid = fork()
    require pid >= 0
    if pid == 0:
      discard blockDeadlySignals()
      restoreDeadlySignalDefaults()
      discard kill(getpid(), SIGTERM)
      discard sleep(5.cint)
      exitnow(7) # Only reached if the signal was still held.

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM

  test "Signals blocked before keep staying blocked":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      var
        pre: Sigset
        previous: Sigset
      if sigemptyset(pre) != 0 or sigaddset(pre, SIGUSR1) != 0:
        exitnow(3)
      if pthread_sigmask(SIG_BLOCK, pre, previous) != 0:
        exitnow(3)
      if not blockDeadlySignals():
        exitnow(3)
      restoreDeadlySignalDefaults()
      var mask = currentMask()
      if sigismember(mask, SIGUSR1) != 1:
        exitnow(7)
      for sig in DeadlySignals:
        if sigismember(mask, sig) != 0:
          exitnow(8)
      exitnow(0)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Nested blocks need matching restores":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      var original = currentMask()
      if not blockDeadlySignals() or not blockDeadlySignals():
        exitnow(3)
      restoreDeadlySignalDefaults()
      var mid = currentMask()
      for sig in DeadlySignals:
        if sigismember(mid, sig) != 1:
          exitnow(7)
      restoreDeadlySignalDefaults()
      var restored = currentMask()
      for sig in DeadlySignals:
        if sigismember(restored, sig) != sigismember(original, sig):
          exitnow(8)
      exitnow(0)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

suite "deadly_signals - terminalJob":
  test "Without stdio terminals or a controlling terminal it is tjNone":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      if setsid() < 0:
        exitnow(3)
      let devnull = posix.open("/dev/null".cstring, O_RDONLY)
      if devnull < 0:
        exitnow(3)
      if dup2(devnull, STDIN_FILENO) < 0 or dup2(devnull, STDOUT_FILENO) < 0 or
          dup2(devnull, STDERR_FILENO) < 0:
        exitnow(3)
      if devnull > STDERR_FILENO:
        discard posix.close(devnull)
      if stdinHoldsTerminal():
        exitnow(7)
      exitnow(if terminalJob() == tjNone: 0 else: 8)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A stdin redirected to /dev/null never holds the terminal":
    let pid = fork()
    require pid >= 0
    if pid == 0:
      let devnull = posix.open("/dev/null".cstring, O_RDONLY)
      if devnull < 0:
        exitnow(3)
      if dup2(devnull, STDIN_FILENO) < 0:
        exitnow(3)
      if devnull > STDERR_FILENO:
        discard posix.close(devnull)
      exitnow(if stdinHoldsTerminal(): 7 else: 0)

    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

suite "deadly_signals - signalName":
  test "Known signals use their kill -l name":
    check signalName(SIGHUP) == "HUP"
    check signalName(SIGTERM) == "TERM"

  test "An unknown signal falls back to its number":
    check signalName(SIGUSR1) == $SIGUSR1
