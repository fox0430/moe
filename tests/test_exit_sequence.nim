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

## Tests for the exit sequence in moe.nim: preserving on a crash or a signal,
## the user's quit suppressing it, and teardown dying of a late signal.

import std/[importutils, os, options, posix, strutils, unittest]

import pkg/chronos

import ../src/moe {.all.}
import
  ../src/moepkg/[
    editor, config, config_loader, cmdline, logger, signal_watcher, deadly_signals,
    recovery_format,
  ]
import ../src/moepkg/types/editor_types

privateAccess(Death)

proc defaultActions() =
  ## Run as if started from an interactive shell, whatever the runner ignores.
  for sig in DeadlySignals:
    var
      act = Sigaction(sa_handler: SIG_DFL)
      previous: Sigaction
    doAssert sigemptyset(act.sa_mask) == 0
    doAssert sigaction(sig, act, previous) == 0

defaultActions()

let TestRoot = getTempDir() / "moe_test_exit_sequence"

# Each scenario runs in a child: the watcher is process-wide and the sequence
# ends the process. The child's HOME points at `home`, so the recovery copy
# lands there through the real save path.

proc waitChild(pid: Pid, limit: Duration): cint =
  ## Wait up to `limit` for the child, then kill it rather than hang the run.
  let deadline = Moment.now() + limit
  while true:
    var status: cint
    let got = waitpid(pid, status, WNOHANG)
    if got == pid:
      return status
    doAssert got >= 0
    if Moment.now() >= deadline:
      discard kill(pid, SIGKILL)
      doAssert waitpid(pid, status, 0) == pid
      doAssert false
    sleep(10)

proc runChild(home: string, body: proc()): cint =
  ## Run `body` in a child with HOME and stderr redirected under `home`, and
  ## return its wait status.
  createDir(home)
  let pid = fork()
  doAssert pid >= 0
  if pid == 0:
    putEnv("HOME", home)
    let errFd = posix.open(cstring(home / "stderr"), O_WRONLY or O_CREAT, 0o600)
    discard dup2(errFd, STDERR_FILENO)
    # Uncaught here it reaches the test runner, and the child goes on to run
    # the remaining tests and report them as this scenario's result.
    try:
      body()
    except Exception as ex:
      stderr.writeLine "child failed: " & ex.msg
      stderr.writeLine ex.getStackTrace()
      exitnow(1)
    exitnow(0)
  waitChild(pid, 30.seconds)

proc recoverySessions(home: string): seq[string] =
  let base = home / ".cache/moe/crash_recovery"
  if dirExists(base):
    for kind, path in walkDir(base):
      if kind == pcDir:
        result.add path

proc savedCopies(home: string): seq[string] =
  ## The contents of every copy in every session under `home`.
  for session in recoverySessions(home):
    for kind, path in walkDir(session / PayloadDirName):
      if kind == pcFile:
        result.add readFile(path)

proc editedEditor(home: string): Editor =
  ## An editor holding a file with an unsaved edit.
  let path = home / "edited.txt"
  writeFile(path, "unsaved edit")
  result = newEditor(newEditorConfig(), newValidationResult())
  discard result.loadFile(path)
  let buf = result.activeBuffer()
  buf.changeSeq = buf.savedSeq + 1
  buf.lastLoadedContent = none(ContentFingerprint)

proc watch(answer = 10.seconds, finish = 10.seconds) =
  ## Start the watcher with the loop running, or exit 3.
  if not startSignalWatcher(answer, finish):
    exitnow(3)
  loopAnswers()

let quietLog = initLogger(enabled = false)

suite "exit sequence - preserveAndExit":
  setup:
    removeDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "A signal saves the unsaved buffer and dies of that signal":
    let home = TestRoot / "signal"
    let status = runChild(
      home,
      proc() =
        let e = editedEditor(home)
        e.preserveAndExit(
          nil, Death(kind: ckSignal, signal: SIGTERM), CmdLineConfig(), quietLog
        ),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM
    check savedCopies(home) == @["unsaved edit"]
    let report = readFile(home / "stderr")
    check "caught deadly signal TERM" in report
    check "Recovery files saved to" in report

  test "A crash saves the unsaved buffer and exits 1":
    let home = TestRoot / "crash"
    let status = runChild(
      home,
      proc() =
        let e = editedEditor(home)
        e.preserveAndExit(
          nil,
          Death(kind: ckCrash, exception: newException(ValueError, "boom")),
          CmdLineConfig(),
          quietLog,
        ),
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 1
    check savedCopies(home) == @["unsaved edit"]
    check "fatal error: boom" in readFile(home / "stderr")

  test "Nothing is saved once the user quit":
    let home = TestRoot / "quit"
    let status = runChild(
      home,
      proc() =
        let e = editedEditor(home)
        e.state.quitDecided = true
        e.preserveAndExit(
          nil, Death(kind: ckSignal, signal: SIGHUP), CmdLineConfig(), quietLog
        ),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP
    check recoverySessions(home).len == 0

  test "A nested death keeps the first death's signal and saves nothing more":
    let home = TestRoot / "nested"
    let status = runChild(
      home,
      proc() =
        let e = editedEditor(home)
        preserving = some(Death(kind: ckSignal, signal: SIGHUP))
        e.preserveAndExit(
          nil,
          Death(kind: ckCrash, exception: newException(ValueError, "nested")),
          CmdLineConfig(),
          quietLog,
        ),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP
    check recoverySessions(home).len == 0

suite "exit sequence - answerDeadlySignals":
  setup:
    removeDir(TestRoot)
    when not signalWatcherSupported:
      skip()

  teardown:
    removeDir(TestRoot)

  test "A signal before the user quit preserves":
    let home = TestRoot / "answer"
    let status = runChild(
      home,
      proc() =
        watch()
        let e = editedEditor(home)
        let answered = e.answerDeadlySignals(nil, CmdLineConfig(), quietLog)
        discard kill(getpid(), SIGTERM)
        discard waitFor answered.withTimeout(5.seconds)
        exitnow(7),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGTERM
    check savedCopies(home) == @["unsaved edit"]

  test "A signal after the user quit winds down and teardown dies of it":
    let home = TestRoot / "windDown"
    let reachedTeardown = home / "teardown"
    let status = runChild(
      home,
      proc() =
        watch(500.milliseconds, 10.seconds)
        let e = editedEditor(home)
        e.state.quitDecided = true
        let answered = e.answerDeadlySignals(nil, CmdLineConfig(), quietLog)
        discard kill(getpid(), SIGHUP)
        discard waitFor answered.withTimeout(5.seconds)
        # Past the answer deadline: without winding down the watcher kills.
        sleep(900)
        writeFile(reachedTeardown, "")
        e.windDown(CmdLineConfig(), quietLog)
        exitnow(7),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP
    check fileExists(reachedTeardown)
    check recoverySessions(home).len == 0

suite "exit sequence - windDown":
  setup:
    removeDir(TestRoot)

  teardown:
    removeDir(TestRoot)

  test "Without a signal teardown returns":
    let home = TestRoot / "clean"
    let status = runChild(
      home,
      proc() =
        let e = editedEditor(home)
        e.windDown(CmdLineConfig(), quietLog),
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

suite "exit sequence - settle":
  setup:
    removeDir(TestRoot)
    when not signalWatcherSupported:
      skip()

  teardown:
    removeDir(TestRoot)

  test "A signal after settle ends the process at once":
    let home = TestRoot / "settled"
    let status = runChild(
      home,
      proc() =
        # Both deadlines long, so only the settled stage can end this child.
        watch(10.seconds, 10.seconds)
        beginWindingDown()
        settle()
        discard kill(getpid(), SIGHUP)
        # Without settle() the watcher only hands the signal on, and the
        # finish deadline is ten seconds out.
        sleep(2000)
        exitnow(7),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP

  test "Teardown settles the watcher, so a later signal ends the process":
    let home = TestRoot / "settledByTeardown"
    let status = runChild(
      home,
      proc() =
        watch(10.seconds, 10.seconds)
        let e = editedEditor(home)
        e.windDown(CmdLineConfig(), quietLog)
        # Nothing was taken yet, so the teardown above returned.
        discard kill(getpid(), SIGHUP)
        # Only the stage teardown left can end this child: without the settle()
        # inside windDown the watcher hands the signal on until the finish
        # deadline ten seconds out.
        sleep(2000)
        exitnow(7),
    )
    check WIFSIGNALED(status)
    check WTERMSIG(status) == SIGHUP
    check recoverySessions(home).len == 0

  test "A child that raises is contained":
    let home = TestRoot / "raiseChild"
    let status = runChild(
      home,
      proc() =
        raise newException(ValueError, "child blew up"),
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 1
    check "child blew up" in readFile(home / "stderr")

suite "exit sequence - crashDeath":
  setup:
    removeDir(TestRoot)
    when not signalWatcherSupported:
      skip()

  teardown:
    removeDir(TestRoot)

  test "A crash that is not I/O does not wait for a signal":
    let status = runChild(
      TestRoot / "logic",
      proc() =
        watch()
        let started = Moment.now()
        let death = crashDeath(newException(ValueError, "logic"))
        if death.kind != ckCrash:
          exitnow(7)
        if Moment.now() - started > 100.milliseconds:
          exitnow(8)
      ,
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "An I/O crash takes a signal that follows shortly as the cause":
    let status = runChild(
      TestRoot / "hangup",
      proc() =
        watch()
        var t: Thread[void]
        createThread(
          t,
          proc() {.thread.} =
            sleep(50)
            discard kill(getpid(), SIGHUP),
        )
        let death = crashDeath(newException(IOError, "tty gone"))
        joinThread(t)
        if death.kind != ckSignal or death.signal != SIGHUP:
          exitnow(7)
        if death.detail != "HUP: tty gone":
          exitnow(8)
      ,
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0

  test "An I/O crash without a signal is a crash after the wait":
    let status = runChild(
      TestRoot / "ioOnly",
      proc() =
        watch()
        let started = Moment.now()
        let death = crashDeath(newException(OSError, "write failed"))
        if death.kind != ckCrash:
          exitnow(7)
        if Moment.now() - started < 150.milliseconds:
          exitnow(8)
      ,
    )
    check WIFEXITED(status)
    check WEXITSTATUS(status) == 0
