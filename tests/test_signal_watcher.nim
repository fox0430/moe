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

import std/[os, osproc, posix, unittest]

import pkg/chronos

import moepkg/signal_watcher
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

# Each scenario runs in a child: the watcher is process-wide and some of them
# end the process.

proc runChild(body: proc()): cint =
  ## Run `body` in a child and return its wait status. `body` exits 0 on
  ## success; dying of a signal is the other outcome under test. Uses
  ## `exitnow`: `quit` runs GC and exit procs that may deadlock after `fork`.
  let pid = fork()
  doAssert pid >= 0
  if pid == 0:
    body()
    exitnow(0)
  var status: cint
  doAssert waitpid(pid, status, 0) == pid
  status

proc signalWithin(ms: int): cint =
  for _ in 0 ..< ms div 10:
    result = takenSignal()
    if result != 0:
      return
    sleep(10)

proc watch(answer = 10.seconds, finish = 10.seconds) =
  ## Start the watcher with the loop running, or exit 3.
  if not startSignalWatcher(answer, finish):
    exitnow(3)
  loopAnswers()

suite "signal_watcher":
  setup:
    when not defined(linux):
      skip()
  test "A signal is handed to the loop":
    let status = runChild(
      proc() =
        watch()
        discard kill(getpid(), SIGTERM)
        if signalWithin(1000) != SIGTERM:
          exitnow(7)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Before the loop runs a signal ends the process at once":
    let status = runChild(
      proc() =
        if not startSignalWatcher(10.seconds, 10.seconds):
          exitnow(3)
        discard kill(getpid(), SIGTERM)
        sleep(3000)
        exitnow(7)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM

  test "A thread started afterwards inherits the blocked set":
    # Nothing has to wrap `createThread` once the watcher is up.
    let status = runChild(
      proc() =
        watch()
        var t: Thread[void]
        createThread(
          t,
          proc() {.thread.} =
            var empty, mask: Sigset
            discard sigemptyset(empty)
            discard sigemptyset(mask)
            discard pthread_sigmask(SIG_BLOCK, empty, mask)
            if sigismember(mask, SIGTERM) != 1:
              exitnow(7)
          ,
        )
        joinThread(t)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A loop that never answers is killed at the answer deadline":
    let status = runChild(
      proc() =
        watch(200.milliseconds)
        discard kill(getpid(), SIGTERM)
        sleep(3000)
        exitnow(7)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM

  test "Signals that follow do not cut the save short":
    # Closing a terminal sends SIGHUP more than once, then SIGTERM.
    let status = runChild(
      proc() =
        watch(1.seconds)
        discard kill(getpid(), SIGHUP)
        discard kill(getpid(), SIGHUP)
        if signalWithin(800) != SIGHUP:
          exitnow(7)
        if not beginPreserving():
          exitnow(8)
        discard kill(getpid(), SIGTERM)
        sleep(1500) # Past the answer deadline.
        settle()
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A save that never finishes is killed at the finish deadline":
    let status = runChild(
      proc() =
        watch(2.seconds, 2500.milliseconds)
        discard kill(getpid(), SIGHUP)
        if signalWithin(1500) != SIGHUP:
          exitnow(7)
        if not beginPreserving():
          exitnow(8)
        sleep(5000)
        exitnow(9)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP

  test "Once settled the next signal ends the process at once":
    let status = runChild(
      proc() =
        watch()
        settle()
        discard kill(getpid(), SIGINT)
        sleep(3000)
        exitnow(7)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGINT

  test "After a save a later signal ends teardown":
    let status = runChild(
      proc() =
        watch()
        discard kill(getpid(), SIGHUP)
        if signalWithin(1000) != SIGHUP:
          exitnow(7)
        discard beginPreserving()
        settle()
        discard kill(getpid(), SIGTERM)
        sleep(3000)
        exitnow(8)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP

  test "A loop that answers too late does not start saving":
    let status = runChild(
      proc() =
        watch(100.milliseconds)
        discard kill(getpid(), SIGTERM)
        sleep(1000)
        # Only reached if the watcher failed to end the process.
        exitnow(if beginPreserving(): 7 else: 8)
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM

  test "Saving begins only once":
    let status = runChild(
      proc() =
        watch()
        if not beginPreserving():
          exitnow(7)
        if beginPreserving():
          exitnow(8)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Ctrl-C sent with kill is answered while the terminal is handed over":
    # Only the keys a terminal sends are dropped; that path is covered by
    # running moe on a pty.
    let status = runChild(
      proc() =
        watch()
        withTerminalHandedOver:
          discard kill(getpid(), SIGINT)
          if signalWithin(1000) != SIGINT:
            exitnow(7)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A command that ignores the signal is hung up on":
    # An interactive shell ignores SIGTERM. SIGHUP follows a third of the
    # answer deadline later.
    let status = runChild(
      proc() =
        watch(3.seconds)
        # `setsid` gives it a group of its own on any Nim: older `osproc`
        # ignores `poDaemon`.
        let p = startProcess(
          "setsid", args = ["sh", "-c", "trap '' TERM; sleep 10"], options = {poUsePath}
        )
        sleep(500) # Until the trap is set.
        let started = Moment.now()
        var code: int
        withCommandInTerminal(-p.processID):
          discard kill(getpid(), SIGTERM)
          code = p.waitForExit()
        p.close()
        let took = Moment.now() - started
        if took < 700.milliseconds or took > 4000.milliseconds:
          exitnow(7)
        if code != 128 + SIGHUP.int:
          exitnow(8)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A signal reaches the command the terminal is handed over to":
    # The command ends as it would have without moe, and the loop gets back in
    # time to answer.
    let status = runChild(
      proc() =
        watch()
        withTerminalHandedOver:
          let p = startProcess("sleep 10", options = {poEvalCommand})
          let started = Moment.now()
          var code: int
          withCommandInTerminal(p.processID):
            discard kill(getpid(), SIGTERM)
            code = p.waitForExit()
          p.close()
          if Moment.now() - started > 5.seconds:
            exitnow(7)
          if code == 0:
            exitnow(8)
        if takenSignal() != SIGTERM:
          exitnow(9)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A signal that arrived before the command is known still reaches it":
    let status = runChild(
      proc() =
        watch()
        discard kill(getpid(), SIGTERM)
        if signalWithin(1000) != SIGTERM:
          exitnow(7)
        let p = startProcess("sleep 10", options = {poEvalCommand})
        let started = Moment.now()
        var code: int
        withCommandInTerminal(p.processID):
          code = p.waitForExit()
        p.close()
        if Moment.now() - started > 5.seconds or code == 0:
          exitnow(8)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Without a watcher a crash still preserves":
    let status = runChild(
      proc() =
        exitnow(if beginPreserving(): 0 else: 7)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Teardown after the user quit gets the finish deadline":
    let status = runChild(
      proc() =
        watch(500.milliseconds, 10.seconds)
        discard kill(getpid(), SIGHUP)
        if signalWithin(400) != SIGHUP:
          exitnow(7)
        beginWindingDown()
        sleep(900) # Past the answer deadline.
        settle()
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "Time spent stopped does not count against the deadline":
    # After Ctrl-Z, `fg` must still let the loop preserve.
    var fds: array[2, cint]
    require pipe(fds) == 0
    let pid = fork()
    require pid >= 0
    if pid == 0:
      watch(1.seconds)
      discard kill(getpid(), SIGTERM)
      if signalWithin(800) != SIGTERM:
        exitnow(6)
      var taken = 'x'
      discard write(fds[1], taken.addr, 1)
      # Stopped from outside meanwhile, for longer than the deadline. Short
      # sleeps, so running time is still owed once continued, as a loop owes
      # the work before it answers.
      for _ in 0 ..< 30:
        sleep(10)
      if not beginPreserving():
        exitnow(7)
      settle()
      exitnow(0)

    var got: char
    require read(fds[0], got.addr, 1) == 1
    check kill(pid, SIGSTOP) == 0
    sleep(2000)
    check kill(pid, SIGCONT) == 0
    var status: cint
    check waitpid(pid, status, 0) == pid
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "A child forked afterwards starts with the set unblocked":
    # Older Nim's `osproc` forks without clearing the mask.
    let status = runChild(
      proc() =
        watch()
        let child = fork()
        if child == 0:
          var empty, mask: Sigset
          discard sigemptyset(empty)
          discard sigemptyset(mask)
          discard pthread_sigmask(SIG_BLOCK, empty, mask)
          exitnow(if sigismember(mask, SIGTERM) == 0: 0 else: 7)
        var childStatus: cint
        discard waitpid(child, childStatus, 0)
        if not WIFEXITED(childStatus) or WEXITSTATUS(childStatus) != 0:
          exitnow(7)
        # The parent keeps it blocked.
        var empty, mask: Sigset
        discard sigemptyset(empty)
        discard sigemptyset(mask)
        discard pthread_sigmask(SIG_BLOCK, empty, mask)
        if sigismember(mask, SIGTERM) != 1:
          exitnow(8)
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0
