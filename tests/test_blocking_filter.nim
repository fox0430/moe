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

import std/[unittest, atomics, options, os, strutils]

import pkg/chronos

import ../src/moepkg/background_process
import ../src/moepkg/blocking_filter {.all.}

when not defined(windows):
  from std/posix import RLimit, getrlimit, setrlimit, RLIMIT_NOFILE, FD_SETSIZE, dup2

import ../src/moepkg/signal_watcher

when signalWatcherSupported:
  from std/posix import SIGTERM
  import ../src/moepkg/signal_watcher_linux {.all.}

const Unbounded = 64 * 1024 * 1024

proc runFilter(
    cmd: string,
    args: seq[string],
    input: string,
    timeout = InfiniteDuration,
    onWait: proc(): bool {.gcsafe, raises: [].} = nil,
    slice = BlockingWaitSlice,
): FilterProcessResult =
  runFilterBlocking(
    BackgroundProcessCommand(cmd: cmd, args: args, workingDir: getTempDir()),
    input,
    timeout,
    Unbounded,
    onWait,
    slice,
  )

proc countWaits(
    cmd: string, args: seq[string], slice = BlockingWaitSlice
): tuple[r: FilterProcessResult, calls: int] =
  var calls = 0
  let r = runFilter(
    cmd,
    args,
    "",
    onWait = proc(): bool =
      inc calls
      false,
    slice = slice,
  )
  (r, calls)

proc stopOnceExists(path: string): proc(): bool {.gcsafe, raises: [].} =
  ## An `onWait` that stops the command once `path` exists.
  proc(): bool =
    fileExists(path)

var loopRan = false

proc markLoopRan() {.async.} =
  await sleepAsync(1.milliseconds)
  loopRan = true

suite "runFilterBlocking":
  test "The output, the diagnostics and the exit code come back":
    let r =
      runFilter("sh", @["-c", "tr a-z A-Z; echo 'a warning' >&2; exit 3"], "hello\n")
    check r.isOk
    check r.get.output == "HELLO\n"
    check r.get.diagnostics == @["a warning"]
    check r.get.exitCode == some(3)

  test "An input larger than a pipe buffer does not deadlock":
    let input = "x".repeat(4 * 1024 * 1024) & "\n"
    let r = runFilter("cat", @[], input)
    check r.isOk
    check r.get.output == input

  test "A command that cannot start is a start failure":
    let r = runFilter("/nonexistent/command/that/does/not/exist", @[], "")
    check r.isErr
    check r.error.kind == ffStartFailed

  test "A command past its timeout is killed":
    let start = Moment.now()
    let r = runFilter("sleep", @["5"], "", timeout = 100.milliseconds)
    check r.isErr
    check r.error.kind == ffTimedOut
    check Moment.now() - start < 3.seconds

  test "onWait gets turns while the command runs":
    let (r, calls) = countWaits("sleep", @["0.2"])
    check r.isOk
    check calls >= 3

  test "The end of the command ends the wait, not the next turn":
    let start = Moment.now()
    let (r, calls) = countWaits("true", @[], slice = 5.seconds)
    check r.isOk
    check calls == 0
    check Moment.now() - start < 2500.milliseconds

  test "A slice too long for poll still gives a turn every second":
    let (r, calls) = countWaits("sleep", @["1.5"], slice = InfiniteDuration)
    check r.isOk
    check calls >= 1

  test "onWait returning true stops the command and what it started":
    let
      started = getTempDir() / "moe_blocking_filter_started_marker"
      finished = getTempDir() / "moe_blocking_filter_finished_marker"
    removeFile(started)
    removeFile(finished)
    defer:
      removeFile(started)
      removeFile(finished)

    # Stopping only once the command runs: a stop before the worker takes the
    # job never starts it, and would pass without killing anything.
    let r = runFilter(
      "sh",
      @["-c", ": > " & started & "; sleep 0.5; : > " & finished],
      "",
      onWait = stopOnceExists(started),
    )
    check r.isErr
    check r.error.kind == ffCancelled
    check fileExists(started)
    # Past the moment the command would have written it: no marker means it
    # was killed before then.
    sleep(1000)
    check not fileExists(finished)

  test "A stop asked before the start keeps the command from starting":
    # A turn can come before the worker gets to the job. Starting this command
    # would fail, so a start shows as a start failure.
    var job = FilterJob(
      command: BackgroundProcessCommand(
        cmd: "/nonexistent/command/that/does/not/exist", workingDir: getTempDir()
      ),
      timeout: InfiniteDuration,
      limit: Unbounded,
    )
    job.stopAsked.store(true)
    waitFor runJob(addr worker, addr job)
    check job.outcome.isErr
    check job.outcome.error.kind == ffCancelled

  test "A stopped run leaves the next one alone":
    let stopped = runFilter(
      "sleep",
      @["5"],
      "",
      onWait = proc(): bool =
        true,
    )
    check stopped.isErr
    check stopped.error.kind == ffCancelled
    let r = runFilter("cat", @[], "next\n")
    check r.isOk
    check r.get.output == "next\n"

  when signalWatcherSupported:
    test "A deadly signal taken meanwhile stops the command":
      # The loop cannot answer it before the caller is back.
      defer:
        taken.store(0)
      let r = runFilter(
        "sleep",
        @["5"],
        "",
        onWait = proc(): bool =
          taken.store(SIGTERM.int)
          false,
      )
      check r.isErr
      check r.error.kind == ffCancelled

    test "A deadly signal taken before the run keeps the command from starting":
      # Starting this command would fail, so a start shows as a start failure.
      taken.store(SIGTERM.int)
      defer:
        taken.store(0)
      let r = runFilter("/nonexistent/command/that/does/not/exist", @[], "")
      check r.isErr
      check r.error.kind == ffCancelled

  when defined(linux):
    test "A run leaves no descriptor open":
      proc openFds(): int =
        for _ in walkDir("/proc/self/fd"):
          inc result

      discard runFilter("true", @[], "")
      let before = openFds()
      for _ in 0 ..< 5:
        discard runFilter("cat", @[], "x\n")
      discard runFilter("sleep", @["5"], "", timeout = 50.milliseconds)
      check openFds() == before

  when not defined(windows):
    test "The done signal works on a descriptor past FD_SETSIZE":
      # `select` cannot take one, and a long session can hand one out.
      let high = FD_SETSIZE + 100
      var limit: RLimit
      check getrlimit(RLIMIT_NOFILE, limit) == 0
      if limit.rlim_max >= 0 and limit.rlim_max <= high:
        skip()
      else:
        let saved = limit
        if limit.rlim_cur >= 0 and limit.rlim_cur <= high:
          limit.rlim_cur = high + 1
          check setrlimit(RLIMIT_NOFILE, limit) == 0
        let s = newDoneSignal().get
        defer:
          s.close()
          discard posix.close(high)
          var saved = saved
          discard setrlimit(RLIMIT_NOFILE, saved)
        check dup2(s.readFd, high) == high
        let signal = DoneSignal(readFd: high, writeFd: s.writeFd)
        check not signal.waitFired(10.milliseconds)
        signal.fire()
        check signal.waitFired(10.milliseconds)
        check not signal.waitFired(10.milliseconds)

  test "The caller's event loop does not run meanwhile":
    loopRan = false
    let marking = markLoopRan()
    let r = runFilter("sleep", @["0.1"], "")
    check r.isOk
    check not loopRan
    waitFor marking
    check loopRan
