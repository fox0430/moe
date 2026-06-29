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

## Regression test for the LSP shutdown pipe-deadlock.
##
## A server that stops reading its stdin while moe is mid-write wedges the
## worker thread in a blocking write, so it never sees the queued shutdown and
## worker.stop()'s joinThread used to hang forever (the editor hung after the
## UI exited). worker.stop() now SIGKILLs the server's process group from the
## main thread first, which unblocks the write. This test forces that exact
## wedge and asserts stop() still returns promptly.
##
## A watchdog thread bounds the wait: if stop() ever hangs again it quit(1)s so
## the suite fails fast instead of hanging CI.

import std/[unittest, os, monotimes, times, strutils, atomics]

import pkg/results

import ../src/moepkg/lsp/worker

# A fake LSP server: answer `initialize` so the worker reaches lwsRunning, then
# stop reading stdin (but stay alive, so stdout never EOFs and it looks stuck
# rather than crashed). A later large didChange then blocks moe's write.
const StuckServerSrc = """
import std/[os, strutils]

proc readN(n: int): string =
  result = newString(n)
  var got = 0
  while got < n:
    let r = stdin.readBuffer(addr result[got], n - got)
    if r <= 0: break
    got += r

var header = ""
while not header.endsWith("\r\n\r\n"):
  header.add(stdin.readChar())

var contentLen = 0
for line in header.split("\r\n"):
  if line.toLowerAscii.startsWith("content-length:"):
    contentLen = parseInt(line.split(':')[1].strip())
discard readN(contentLen)

let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{}}}"
stdout.write("Content-Length: " & $body.len & "\r\n\r\n")
stdout.write(body)
stdout.flushFile()

while true:
  sleep(3_600_000)
"""

var stopFinished: Atomic[bool]

proc watchdog(deadlineMs: int) {.thread.} =
  ## Escape a regressed (infinite) joinThread so the suite fails instead of
  ## hanging: poll until stop() reports done, else force-exit past the deadline.
  let deadline = getMonoTime() + initDuration(milliseconds = deadlineMs)
  while getMonoTime() < deadline:
    if stopFinished.load(moAcquire):
      return
    sleep(20)
  if not stopFinished.load(moAcquire):
    stderr.writeLine(
      "REGRESSION: worker.stop() did not return within " & $deadlineMs &
        "ms -- the LSP shutdown deadlock is back"
    )
    quit(1)

proc buildStuckServer(baseDir: string) =
  ## Compile the fixture (at baseDir) with the same nim that built this test.
  let src = baseDir & ".nim"
  writeFile(src, StuckServerSrc)
  var nimExe = getCurrentCompilerExe()
  if nimExe.len == 0 or not fileExists(nimExe):
    nimExe = findExe("nim")
  doAssert nimExe.len > 0, "could not locate the nim compiler"
  let rc = execShellCmd(
    nimExe & " c --hints:off --warnings:off -o:" & baseDir.quoteShell & " " &
      src.quoteShell
  )
  doAssert rc == 0, "failed to build the stuck-server fixture"

suite "LspWorker - shutdown deadlock":
  let serverBin = getTempDir() / "moe_stuck_lsp_server"

  teardown:
    # Runs even if the build assert, a check, or stop() raises mid-test.
    removeFile(serverBin & ".nim")
    removeFile(serverBin)

  test "stop() returns promptly when the worker is wedged in a blocking write":
    buildStuckServer(serverBin)

    let w = newLspWorker("stucktest").get
    w.start()
    w.startServer(serverBin, @[], getTempDir())

    # Wait for the handshake to complete.
    let initDeadline = getMonoTime() + initDuration(seconds = 15)
    while getMonoTime() < initDeadline and w.state != lwsRunning:
      sleep(20)
    check w.state == lwsRunning

    # 8 MiB didChange far exceeds the OS pipe buffer; the server never reads it,
    # so the worker blocks in the write and can't observe the queued shutdown.
    w.didChangeFull("file:///wedge.nim", 2, "x".repeat(8 * 1024 * 1024))

    # Wait until the worker dequeues the didChange (so it has entered the
    # blocking-write path) instead of a fixed sleep that races on slow CI.
    let dequeueDeadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < dequeueDeadline and w.hasPendingCommands:
      sleep(20)
    check not w.hasPendingCommands
    # The path from dequeue to the suspending write has no yield points, so a
    # short sleep guarantees the worker has armed the write and suspended.
    sleep(200)

    stopFinished.store(false, moRelease)
    var wd: Thread[int]
    createThread(wd, watchdog, 15000)

    let t0 = getMonoTime()
    w.stop()
    let elapsedMs = (getMonoTime() - t0).inMilliseconds
    stopFinished.store(true, moRelease)
    joinThread(wd)

    check w.isStopped
    check elapsedMs < 15000
