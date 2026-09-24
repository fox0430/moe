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

import std/[unittest, posix, os, strutils, times, deques]

import pkg/results

import ../src/moepkg/deadly_signals
import ../src/moepkg/terminal/pty

proc childIsGone(pid: Pid): bool =
  ## After closePty reaps the child, signalling it must fail with ESRCH.
  kill(pid, cint(0)) == -1 and errno == ESRCH

proc spawnChild(ignoreSigterm: bool): PtyHandle =
  ## Fork a real child and wrap it in a PtyHandle so closePty can tear it down.
  ## The master fd is a throwaway /dev/null (close() is harmless); only the
  ## child pid matters here. The child loops forever, so it survives until
  ## closePty signals it — letting us observe the SIGTERM -> SIGKILL escalation.
  let devnull = posix.open("/dev/null".cstring, O_RDWR)
  let pid = fork()
  if pid == 0:
    discard setpgid(Pid(0), Pid(0))
    # Child: optionally make SIGTERM uncatchable-by-default into a no-op, then
    # block forever. Only SIGKILL (or, when cooperative, SIGTERM) can stop it.
    if ignoreSigterm:
      posix.signal(SIGTERM, SIG_IGN)
    while true:
      discard posix.sleep(cint(3600))
  PtyHandle(masterFd: devnull, childPid: pid, closed: false)

proc spawnChildWithDescendant(): tuple[pty: PtyHandle, descendantPid: Pid] =
  ## Create a process-group leader and a descendant in the same group.
  ## The leader ignores SIGTERM while the descendant keeps the default handler,
  ## so a group signal can be distinguished from a direct-child signal.
  var pidPipe: array[0 .. 1, cint]
  require posix.pipe(pidPipe) == 0
  let devnull = posix.open("/dev/null".cstring, O_RDWR)
  let pid = fork()
  if pid == 0:
    discard posix.close(pidPipe[0])
    discard setpgid(Pid(0), Pid(0))
    let descendantPid = fork()
    if descendantPid == 0:
      discard posix.close(pidPipe[1])
      while true:
        discard posix.sleep(cint(3600))

    posix.signal(SIGTERM, SIG_IGN)
    discard posix.write(pidPipe[1], addr descendantPid, sizeof(descendantPid))
    discard posix.close(pidPipe[1])
    while true:
      discard posix.sleep(cint(3600))

  require pid > 0
  discard posix.close(pidPipe[1])
  var descendantPid: Pid
  let bytesRead = posix.read(pidPipe[0], addr descendantPid, sizeof(descendantPid))
  discard posix.close(pidPipe[0])
  if bytesRead != sizeof(descendantPid):
    discard posix.kill(posix.Pid(-pid), SIGKILL)
    var status: cint
    discard waitpid(pid, status, 0)
    require false
  (PtyHandle(masterFd: devnull, childPid: pid, closed: false), descendantPid)

suite "closePty - bounded teardown":
  test "Escalates to SIGKILL when the child ignores SIGTERM":
    let pty = spawnChild(ignoreSigterm = true)
    require pty.childPid > 0
    # Let the child install its SIG_IGN handler before we signal it, so SIGTERM
    # is genuinely ignored and closePty is forced down the SIGKILL path.
    sleep(100)

    let start = epochTime()
    pty.closePty()
    let elapsed = epochTime() - start

    # It returned (no infinite blocking wait) and actually reaped the child.
    check pty.closed
    check childIsGone(pty.childPid)
    # SIGTERM was ignored, so teardown spent the poll window before SIGKILL —
    # proving the escalation ran rather than SIGTERM ending it immediately.
    check elapsed >= 0.15
    # ...but still bounded well under the per-file test timeout.
    check elapsed < 5.0

  test "Terminates descendants in the child's process group":
    let (pty, descendantPid) = spawnChildWithDescendant()
    defer:
      if not pty.closed:
        pty.closePty()
      if not childIsGone(descendantPid):
        discard kill(descendantPid, SIGKILL)

    let start = epochTime()
    pty.closePty()
    let elapsed = epochTime() - start

    check pty.closed
    check childIsGone(pty.childPid)
    # The leader ignores SIGTERM, so closePty must wait for the SIGKILL path.
    check elapsed >= 0.15
    # A direct-child signal would leave this same-group descendant alive.
    var descendantGone = false
    for _ in 0 ..< 100:
      if childIsGone(descendantPid):
        descendantGone = true
        break
      sleep(10)
    check descendantGone

  test "Returns promptly when the child honors SIGTERM":
    let pty = spawnChild(ignoreSigterm = false)
    require pty.childPid > 0
    sleep(50)

    let start = epochTime()
    pty.closePty()
    let elapsed = epochTime() - start

    check pty.closed
    check childIsGone(pty.childPid)
    # Default SIGTERM disposition kills it, so we should not burn the full poll
    # window.
    check elapsed < 1.0

  test "Is a no-op on an already-closed handle":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(999999), closed: true)
    pty.closePty() # must not raise or block
    check pty.closed

suite "queueWrite - non-blocking against a stopped child":
  test "Returns promptly when the child is SIGSTOP'd (EAGAIN never spins)":
    # Regression: the write path used to loop on poll(POLLOUT, 100ms) if
    # EAGAIN persisted, so a SIGSTOP'd or ^S-paused child froze the UI thread
    # until the child was killed. Now it must buffer and return.
    let ptyResult = openPtyAndSpawn("cat")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      discard kill(pty.childPid, SIGCONT)
      pty.closePty()

    require kill(pty.childPid, SIGSTOP) == 0
    sleep(50) # let the stop take effect so the kernel PTY buffer can fill

    let payload = "x".repeat(1024)
    let start = epochTime()
    var lastResult = pty.queueWrite(payload)
    # Keep writing until we overflow the userspace cap or run out of budget.
    # Every individual call MUST return without blocking.
    for _ in 0 ..< 200:
      if lastResult.isErr:
        break
      discard pty.flushWrites()
      lastResult = pty.queueWrite(payload)
    let elapsed = epochTime() - start

    # Must be dramatically faster than the old poll(100ms) * many iterations.
    check elapsed < 1.0
    # Queue never grew past its documented cap.
    check pty.pendingWriteBytes <= maxPtyWriteQueueBytes

  test "flushWrites pushes pending bytes once the child resumes":
    let ptyResult = openPtyAndSpawn("cat")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      discard kill(pty.childPid, SIGCONT)
      pty.closePty()

    require kill(pty.childPid, SIGSTOP) == 0
    sleep(50)

    # Fill until we buffer something in userspace.
    let payload = "y".repeat(4096)
    for _ in 0 ..< 32:
      if pty.queueWrite(payload).isErr:
        break
      discard pty.flushWrites()
    require pty.pendingWriteBytes > 0

    # Resume the child; cat starts consuming, so flushWrites should eventually
    # push everything through.
    require kill(pty.childPid, SIGCONT) == 0
    let deadline = epochTime() + 2.0
    while pty.pendingWriteBytes > 0 and epochTime() < deadline:
      discard pty.flushWrites()
      # Read the echoed bytes so the kernel keeps making room.
      discard pty.readFromPty(65536)
      sleep(10)

    check pty.pendingWriteBytes == 0

  test "queueWrite on empty data succeeds without touching the fd":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("").isOk

  test "queueWrite on a closed handle returns err":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: true)
    let r = pty.queueWrite("hello")
    check r.isErr

  test "A rejected write queues nothing, so the queue stays intact":
    let ptyResult = openPtyAndSpawn("cat")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      discard kill(pty.childPid, SIGCONT)
      pty.closePty()

    require kill(pty.childPid, SIGSTOP) == 0
    sleep(50)

    while pty.queueWrite("x".repeat(65536)).isOk:
      discard pty.flushWrites()
    let pending = pty.pendingWriteBytes
    check pty.queueWrite("y".repeat(maxPtyWriteQueueBytes)).isErr
    check pty.pendingWriteBytes == pending

  test "A failing write is reported by flushWrites, not by queueWrite":
    # fd -1 fails for real (EBADF) rather than with EAGAIN, like a master fd
    # whose slave side is gone.
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)

    # Accepting the bytes succeeds; the write behind it is not the queuer's
    # verdict to report.
    check pty.queueWrite("x").isOk
    check not pty.writeFailed
    check pty.flushWrites().isErr
    check pty.writeFailed
    check pty.pendingWriteBytes == 0

    # The handle now refuses bytes instead of taking them for a dead fd.
    let refused = pty.queueWrite("y")
    check refused.isErr
    check pty.pendingWriteBytes == 0

  test "A droppable write past its budget is refused whole, never cut":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let r = pty.queueWrite("z".repeat(maxPtyDroppableBytes + 1), wcDroppable)
    check r.isErr
    check pty.pendingWriteBytes == 0

  test "The droppable budget bounds the queue, not just one write":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let half = "z".repeat(maxPtyDroppableBytes div 2 + 1)
    check pty.queueWrite(half, wcDroppable).isOk
    check pty.queueWrite(half, wcDroppable).isErr
    check pty.pendingWriteBytes == half.len

  test "A queued droppable write never makes a keystroke refused":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("z".repeat(maxPtyWriteQueueBytes + 1024 * 1024), wcDroppable).isOk
    # The keystroke budget is measured over keystrokes alone.
    check pty.queueWrite("K").isOk

  test "cancelDroppable drops the pasted bytes and keeps the keystrokes":
    let ptyResult = openPtyAndSpawn("cat")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      discard kill(pty.childPid, SIGCONT)
      pty.closePty()

    require kill(pty.childPid, SIGSTOP) == 0
    sleep(50)

    discard pty.queueWrite("z".repeat(1024 * 1024), wcDroppable, tailBytes = 6)
    discard pty.flushWrites()
    # Part of the paste reached the child before the kernel buffer filled, so
    # the child is inside it.
    require pty.writeOffset > 0
    require pty.queueWrite("K").isOk

    check pty.cancelDroppable()
    # What is left is the tail in the dropped chunk's place, then the keystroke
    # that was typed behind it.
    check pty.pendingWriteBytes == 6 + 1

  test "A cancel inside the tail sends only the rest of it":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let data = "zzzz" & "\x1b[201~"
    check pty.queueWrite(data, wcDroppable, tailBytes = 6).isOk
    # The fd stopped two bytes into the closing marker.
    pty.writeOffset = data.len - 4

    check pty.cancelDroppable()
    check pty.writeQueue.len == 1
    check pty.writeQueue.peekFirst.data == "201~"
    check pty.pendingWriteBytes == 4

  test "A cancel inside the opening marker finishes it before the tail":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let data = "\x1b[200~" & "zzzz" & "\x1b[201~"
    check pty.queueWrite(data, wcDroppable, headBytes = 6, tailBytes = 6).isOk
    # The fd stopped three bytes into the opening marker, so the child holds a
    # truncated CSI that would swallow whatever is queued next.
    pty.writeOffset = 3

    check pty.cancelDroppable()
    check pty.writeQueue.len == 1
    check pty.writeQueue.peekFirst.data == "00~" & "\x1b[201~"
    check pty.writeQueue.peekFirst.kind == wcEssential
    check pty.pendingWriteBytes == 9

  test "A cancel inside an unbracketed paste kills the line it truncated":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    # No markers: the child never asked for bracketed paste.
    check pty.queueWrite("rm -rf /home/user/project", wcDroppable).isOk
    pty.writeOffset = 20

    check pty.cancelDroppable()
    check pty.writeQueue.len == 1
    # Nothing to close, so the truncated line is killed instead of left for the
    # next Enter to run.
    check pty.writeQueue.peekFirst.data == "\x15"
    check pty.writeQueue.peekFirst.kind == wcEssential
    check pty.pendingWriteBytes == 1

  test "A cancel before an unbracketed paste started owes the child nothing":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("rm -rf /home/user/project", wcDroppable).isOk

    check pty.cancelDroppable()
    check pty.writeQueue.len == 0
    check pty.pendingWriteBytes == 0

  test "One flushWrites never pushes more than a tick's worth":
    let ptyResult = openPtyAndSpawn("cat > /dev/null")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      pty.closePty()

    let total = 4 * maxPtyWriteBytesPerFlush
    require pty.queueWrite("z".repeat(total), wcDroppable).isOk

    # A child that drains as fast as we write must not take the whole queue in
    # one frame; the rest goes out on later ticks.
    require pty.flushWrites().isOk
    check pty.pendingWriteBytes >= total - maxPtyWriteBytesPerFlush

    var ticks = 0
    while pty.pendingWriteBytes > 0 and ticks < 1000:
      require pty.flushWrites().isOk
      inc ticks
      sleep(1)
    check pty.pendingWriteBytes == 0

  test "clearWriteQueue drops the backlog and leaves the queue usable":
    let ptyResult = openPtyAndSpawn("cat")
    require ptyResult.isOk
    let pty = ptyResult.get
    defer:
      discard kill(pty.childPid, SIGCONT)
      pty.closePty()

    require kill(pty.childPid, SIGSTOP) == 0
    sleep(50)

    while pty.queueWrite("x".repeat(65536)).isOk:
      discard pty.flushWrites()
    require pty.pendingWriteBytes > 0

    pty.clearWriteQueue()
    check pty.pendingWriteBytes == 0
    check pty.queueWrite("z").isOk

suite "queueResponse":
  test "An answer goes ahead of a queued paste":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("K").isOk
    check pty.queueWrite("paste", wcDroppable).isOk

    check pty.queueResponse("\x1b[0n").isOk
    check pty.writeQueue.len == 3
    check pty.writeQueue[0].data == "K"
    check pty.writeQueue[1].data == "\x1b[0n"
    check pty.writeQueue[2].data == "paste"

  test "An answer mid-paste closes the bracket and re-opens it after":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let paste = "\x1b[200~paste\x1b[201~"
    check pty.queueWrite(paste, wcDroppable, headBytes = 6, tailBytes = 6).isOk
    # The fd stopped inside the body.
    pty.writeOffset = 8
    pty.droppableBytes = paste.len - 8

    check pty.queueResponse("\x1b[0n").isOk
    check pty.writeOffset == 0
    check pty.writeQueue.len == 3
    check pty.writeQueue[0].data == "\x1b[201~"
    check pty.writeQueue[1].data == "\x1b[0n"
    check pty.writeQueue[2].data == "\x1b[200~ste\x1b[201~"
    check pty.writeQueue[2].kind == wcDroppable
    check pty.essentialBytes == 10
    check pty.droppableBytes == pty.writeQueue[2].data.len

  test "An answer inside the opening marker finishes it before closing it":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let paste = "\x1b[200~paste\x1b[201~"
    check pty.queueWrite(paste, wcDroppable, headBytes = 6, tailBytes = 6).isOk
    pty.writeOffset = 3
    pty.droppableBytes = paste.len - 3

    check pty.queueResponse("\x1b[0n").isOk
    check pty.writeQueue.len == 3
    check pty.writeQueue[0].data == "00~\x1b[201~"
    check pty.writeQueue[1].data == "\x1b[0n"
    # No body byte reached the child, so the paste starts over whole.
    check pty.writeQueue[2].data == paste

  test "An answer inside the closing marker needs no re-open":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    let paste = "\x1b[200~paste\x1b[201~"
    check pty.queueWrite(paste, wcDroppable, headBytes = 6, tailBytes = 6).isOk
    pty.writeOffset = 13
    pty.droppableBytes = paste.len - 13

    check pty.queueResponse("\x1b[0n").isOk
    check pty.writeQueue.len == 2
    check pty.writeQueue[0].data == "201~"
    check pty.writeQueue[1].data == "\x1b[0n"
    check pty.droppableBytes == 0

  test "An answer stays behind an unbracketed paste the fd is inside":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("paste", wcDroppable).isOk
    pty.writeOffset = 2
    pty.droppableBytes = 3

    check pty.queueResponse("\x1b[0n").isOk
    check pty.writeQueue.len == 2
    check pty.writeQueue[0].data == "paste"
    check pty.writeQueue[1].data == "\x1b[0n"
    check pty.writeOffset == 2

  test "An empty answer leaves the queue untouched":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueWrite("K").isOk
    check pty.queueWrite("paste", wcDroppable).isOk

    check pty.queueResponse("").isOk
    check pty.writeQueue.len == 2
    check pty.writeQueue[0].data == "K"
    check pty.writeQueue[1].data == "paste"

  test "An empty answer on an empty queue is a no-op":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.queueResponse("").isOk
    check pty.writeQueue.len == 0

suite "openPtyAndSpawn - signal mask":
  test "The child starts with nothing blocked":
    # `exec` keeps the mask, and the editor blocks the deadly set for
    # `signal_watcher` to take. Inherited, it would leave the shell — and
    # everything it runs — deaf to Ctrl-C and to `kill`.
    when not defined(linux):
      # The check reads the mask from /proc, which only Linux has.
      skip()
    else:
      check blockDeadlySignals()
      # Restore on every exit: a test binary that keeps the deadly set blocked
      # answers nothing but SIGKILL.
      defer:
        restoreDeadlySignalDefaults()

      let spawned = openPtyAndSpawn("grep SigBlk /proc/self/status", 80, 24)
      require spawned.isOk

      var
        buf = newString(4096)
        output = ""
        sigBlk = -1
      let deadline = getTime() + initDuration(seconds = 5)
      while getTime() < deadline and sigBlk < 0:
        let n = read(spawned.get.masterFd, buf[0].addr, 4096)
        if n > 0:
          output.add buf[0 ..< n]
        # Only complete lines: the tail chunk may cut the value short.
        var lines = output.splitLines()
        if not output.endsWith("\n") and lines.len > 0:
          lines.setLen(lines.len - 1)
        for line in lines:
          if line.startsWith("SigBlk"):
            let fields = line.splitWhitespace()
            if fields.len >= 2:
              try:
                sigBlk = parseHexInt(fields[^1])
              except ValueError:
                discard
            break
        if sigBlk < 0:
          sleep(10)

      # A complete SigBlk line arrived; the child must start with nothing
      # blocked. SigBlk is a hex bitmask whose width depends on the kernel.
      check sigBlk == 0

      spawned.get.closePty()
