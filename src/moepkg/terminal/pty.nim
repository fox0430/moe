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

## POSIX pseudo-terminal (PTY) wrapper for terminal emulation.
## Provides PTY creation, non-blocking I/O, resize, and process lifecycle.

import std/[deques, os, posix, options]

import pkg/results

import ../deadly_signals

type
  WriteChunkKind* = enum
    wcEssential ## Bytes the child must receive: a keystroke or a query answer.
    wcDroppable ## Bytes an interrupt is allowed to drop, such as a paste.

  WriteChunk* = object
    data*: string
    kind*: WriteChunkKind
    headBytes*: int
      ## How many bytes at the start of `data` the child must have received in
      ## full before the tail below means anything to it.
    tailBytes*: int
      ## How many bytes at the end of `data` the child is owed even if the
      ## chunk is dropped after it already received part of it.

  PtyHandle* = ref object
    masterFd*: cint
    childPid*: Pid
    closed*: bool
    writeQueue*: Deque[WriteChunk]
      ## The one queue of bytes bound for the child. Everything goes through
      ## queueWrite, so the child sees bytes in the order they were queued.
      ## Chunked rather than flat, so an interrupt can drop what is droppable
      ## and leave the rest in place.
    writeOffset*: int ## How much of the front chunk the fd has already taken.
    essentialBytes*: int ## Queued wcEssential bytes the fd has not taken yet.
    droppableBytes*: int ## Queued wcDroppable bytes the fd has not taken yet.
    writeFailed*: bool
      ## A write to the master fd failed for real (not EAGAIN), so the fd is
      ## gone and nothing more can reach the child.

const
  maxPtyWriteQueueBytes* = 4 * 1024 * 1024
    ## Bound on what the unbounded producers - keystrokes and query responses -
    ## can make a wedged child's queue hold. Measured over wcEssential bytes
    ## alone, so a queued paste can never make us refuse a keystroke.

  maxPtyDroppableBytes* = 64 * 1024 * 1024
    ## Bound on the droppable bytes queued at once. These are user-sized amounts
    ## that already exist in memory and that an interrupt can drop, so they get a
    ## budget of their own; one past what is left of it is refused whole, never
    ## cut, because half a pasted command is worse than none of it.

  maxPtyReadBytesPerPoll* = 256 * 1024
    ## Byte cap for one pollOutput drain. Bounds tick cost so a runaway
    ## child (`yes`, `cat` big file) can't monopolize a render frame.

  maxPtyWriteBytesPerFlush* = 256 * 1024
    ## Byte cap for one poll's writes, the mirror of the read cap above. The
    ## queue holds up to maxPtyDroppableBytes, so a child that drains as fast as
    ## we write (`cat > /dev/null`) would otherwise take a whole paste in one
    ## frame; the rest goes out on the next tick.

# POSIX PTY bindings
when defined(macosx):
  proc forkpty(
    amaster: var cint, name: cstring, termp: pointer, winp: pointer
  ): Pid {.importc, header: "<util.h>".}

elif defined(freebsd):
  {.passL: "-lutil".}
  proc forkpty(
    amaster: var cint, name: cstring, termp: pointer, winp: pointer
  ): Pid {.importc, header: "<libutil.h>".}

else:
  proc forkpty(
    amaster: var cint, name: cstring, termp: pointer, winp: pointer
  ): Pid {.importc, header: "<pty.h>".}

type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
  ws_row: cushort
  ws_col: cushort
  ws_xpixel: cushort
  ws_ypixel: cushort

when defined(macosx):
  const TIOCSWINSZ = 0x80087467.culong
else:
  const TIOCSWINSZ = 0x5414.culong

proc ioctl(
  fd: cint, request: culong
): cint {.importc, header: "<sys/ioctl.h>", varargs.}

proc openPtyAndSpawn*(
    command: string = "", cols: int = 80, rows: int = 24
): Result[PtyHandle, string] =
  ## Create a PTY pair via forkpty() and spawn a shell (or command) in the child.
  ## Returns the master fd and child pid on success.

  var masterFd: cint
  var ws: Winsize
  ws.ws_col = cols.cushort
  ws.ws_row = rows.cushort

  let pid = forkpty(masterFd, nil, nil, addr ws)
  if pid < 0:
    return err("forkpty failed: " & $strerror(errno))

  if pid == 0:
    # `exec` keeps the editor's blocked deadly set.
    discard clearSignalMask()

    putEnv("TERM", "xterm-256color")

    let shell = getEnv("SHELL", "/bin/sh")
    if command.len > 0:
      discard execl(shell.cstring, shell.cstring, "-c".cstring, command.cstring, nil)
    else:
      discard execl(shell.cstring, shell.cstring, nil)

    # execl only returns on error
    quit(1)

  # Parent process: set master fd to non-blocking
  let flags = fcntl(masterFd, F_GETFL)
  if flags == -1:
    discard close(masterFd)
    return err("fcntl F_GETFL failed")
  if fcntl(masterFd, F_SETFL, flags or O_NONBLOCK) == -1:
    discard close(masterFd)
    return err("fcntl F_SETFL O_NONBLOCK failed")

  ok(PtyHandle(masterFd: masterFd, childPid: pid, closed: false))

proc tryWriteNonblock(
    fd: cint, data: string, offset: int, maxBytes: int
): tuple[written: int, err: string] =
  ## Write as much of data[offset ..< len], up to maxBytes of it, as the kernel
  ## will take without blocking. Returns bytes written and an empty err on
  ## EAGAIN, or a populated err on a real failure.
  var written = 0
  let stop = min(data.len, offset + maxBytes)
  while offset + written < stop:
    let n = write(fd, unsafeAddr data[offset + written], stop - offset - written)
    if n < 0:
      if errno == EINTR:
        continue
      if errno == EAGAIN or errno == EWOULDBLOCK:
        return (written, "")
      return (written, "write to PTY failed: " & $strerror(errno))
    if n == 0:
      # No error and no progress: leave rather than spin.
      return (written, "")
    written += n.int
  (written, "")

proc pendingWriteBytes*(pty: PtyHandle): int =
  ## Bytes queued for the child that the fd has not taken yet.
  pty.essentialBytes + pty.droppableBytes

proc clearWriteQueue*(pty: PtyHandle) =
  ## Drop everything still queued.
  pty.writeQueue.clear()
  pty.writeOffset = 0
  pty.essentialBytes = 0
  pty.droppableBytes = 0

proc cancelDroppable*(pty: PtyHandle): bool {.discardable.} =
  ## Drop every droppable chunk and keep the rest of the queue in order. A chunk
  ## the child is already inside still owes it the tail it was queued with, in
  ## the chunk's own place, so what was queued after it is not misread.
  ## Returns true if anything was dropped.
  var
    kept = initDeque[WriteChunk]()
    essential = 0
    isFront = true
  for chunk in pty.writeQueue.items:
    let started = isFront and pty.writeOffset > 0
    isFront = false
    if chunk.kind == wcDroppable:
      result = true
      if started:
        # What is owed depends on how far the fd got. Stopped inside the
        # opening marker, the child holds a truncated escape sequence that
        # would eat whatever we queue next, so finish the marker before
        # closing it; past the head, the tail alone (or the rest of it).
        # With no markers at all there is nothing to close, and the child is
        # left holding a truncated line it would run on the next Enter, so
        # kill the line instead.
        let owed =
          if chunk.tailBytes == 0:
            "\x15"
          elif pty.writeOffset < chunk.headBytes:
            chunk.data[pty.writeOffset ..< chunk.headBytes] &
              chunk.data[chunk.data.len - chunk.tailBytes ..^ 1]
          else:
            chunk.data[max(pty.writeOffset, chunk.data.len - chunk.tailBytes) ..^ 1]
        if owed.len > 0:
          kept.addLast WriteChunk(data: owed, kind: wcEssential)
          essential += owed.len
    else:
      var keep = chunk
      if started:
        keep.data = chunk.data[pty.writeOffset ..< chunk.data.len]
      kept.addLast keep
      essential += keep.data.len

  pty.writeQueue = kept
  pty.writeOffset = 0
  pty.essentialBytes = essential
  pty.droppableBytes = 0

proc flushWrites*(
    pty: PtyHandle, maxBytes: int = maxPtyWriteBytesPerFlush
): Result[void, string] =
  ## Try to push the queue to the PTY without blocking. Safe to call every UI
  ## tick - a stopped or flow-controlled child just leaves the queue in place.
  ## Written bytes are accounted for before an error is reported, so nothing is
  ## sent twice. This is the only place a write failure is reported: it means
  ## the fd is gone, not that the child is slow, so the queue is dropped and
  ## the handle stops accepting bytes rather than retrying a broken fd.
  if pty.closed or pty.pendingWriteBytes == 0:
    return ok()

  var budget = maxBytes
  while pty.writeQueue.len > 0 and budget > 0:
    let (written, err) = tryWriteNonblock(
      pty.masterFd, pty.writeQueue.peekFirst.data, pty.writeOffset, budget
    )
    budget -= written
    pty.writeOffset += written
    case pty.writeQueue.peekFirst.kind
    of wcEssential:
      pty.essentialBytes -= written
    of wcDroppable:
      pty.droppableBytes -= written

    let chunkDone = pty.writeOffset >= pty.writeQueue.peekFirst.data.len
    if chunkDone:
      pty.writeQueue.popFirst()
      pty.writeOffset = 0

    if err.len > 0:
      pty.writeFailed = true
      pty.clearWriteQueue()
      return err(err)
    if not chunkDone:
      # EAGAIN, or the tick's budget ran out mid-chunk.
      break
  ok()

proc queueWrite*(
    pty: PtyHandle,
    data: string,
    kind: WriteChunkKind = wcEssential,
    headBytes: int = 0,
    tailBytes: int = 0,
): Result[void, string] =
  ## Queue bytes for the child. About acceptance only: err means the budget for
  ## `kind` had no room for all of `data` (or the PTY is gone), and then nothing
  ## was queued. Queuing does not touch the fd; flushWrites pushes the queue out
  ## and owns whatever the write reports.
  ## The budgets are checked here only; the few bytes cancelDroppable and
  ## queueResponse add to close or re-open a bracket ride past them.
  if pty.closed:
    return err("PTY is closed")
  if pty.writeFailed:
    return err("Terminal is no longer reachable")
  if data.len == 0:
    return ok()

  case kind
  of wcEssential:
    if pty.essentialBytes + data.len > maxPtyWriteQueueBytes:
      return err(
        "PTY write queue full (" & $pty.essentialBytes &
          " bytes pending); child is not consuming input"
      )
  of wcDroppable:
    if pty.droppableBytes + data.len > maxPtyDroppableBytes:
      return err(
        "Write of " & $data.len & " bytes does not fit the " & $maxPtyDroppableBytes &
          " byte budget (" & $pty.droppableBytes & " bytes already queued)"
      )

  pty.writeQueue.addLast WriteChunk(
    data: data, kind: kind, headBytes: headBytes, tailBytes: tailBytes
  )
  case kind
  of wcEssential:
    pty.essentialBytes += data.len
  of wcDroppable:
    pty.droppableBytes += data.len
  ok()

proc queueResponse*(pty: PtyHandle, data: string): Result[void, string] =
  ## Queue an answer to a query the child made. Bounded and counted like any
  ## other essential write, but placed ahead of the queued pastes: the child
  ## may be blocked on the answer, and under bracketed paste an answer that
  ## landed after the closing marker would be read as typed input.
  if data.len == 0:
    # queueWrite takes an empty write without queuing anything, so there would
    # be no chunk of ours to move.
    return ok()

  if pty.droppableBytes == 0:
    # Nothing queued to be placed ahead of, so the tail is already the spot.
    return pty.queueWrite(data)

  let queued = pty.queueWrite(data)
  if queued.isErr:
    return queued

  let answer = pty.writeQueue.popLast
  var
    rebuilt = initDeque[WriteChunk]()
    placed = false
    isFront = true
  for chunk in pty.writeQueue.items:
    let started = isFront and pty.writeOffset > 0
    isFront = false
    if placed or chunk.kind != wcDroppable:
      rebuilt.addLast chunk
      continue

    if not started:
      rebuilt.addLast answer
      placed = true
      rebuilt.addLast chunk
    elif chunk.tailBytes > 0:
      # The fd is inside a bracketed paste, so there is no spot ahead of it to
      # move to. Close the bracket where the fd stands, answer outside it, and
      # re-open it for what is left, as the sequence the child reads is what
      # decides whether the answer is text.
      let
        off = pty.writeOffset
        bodyEnd = chunk.data.len - chunk.tailBytes
        closer =
          if off < chunk.headBytes:
            chunk.data[off ..< chunk.headBytes] & chunk.data[bodyEnd ..^ 1]
          else:
            chunk.data[max(off, bodyEnd) ..^ 1]
        restStart = max(off, chunk.headBytes)

      pty.droppableBytes -= chunk.data.len - off
      rebuilt.addLast WriteChunk(data: closer, kind: wcEssential)
      pty.essentialBytes += closer.len
      rebuilt.addLast answer
      placed = true
      if restStart < bodyEnd:
        let rest =
          chunk.data[0 ..< chunk.headBytes] & chunk.data[restStart ..< bodyEnd] &
          chunk.data[bodyEnd ..^ 1]
        rebuilt.addLast WriteChunk(
          data: rest,
          kind: wcDroppable,
          headBytes: chunk.headBytes,
          tailBytes: chunk.tailBytes,
        )
        pty.droppableBytes += rest.len
      pty.writeOffset = 0
    else:
      # Unbracketed: the child reads the paste as typed bytes either way, so
      # there is nothing to place the answer ahead of.
      rebuilt.addLast chunk
  if not placed:
    rebuilt.addLast answer
  pty.writeQueue = rebuilt
  ok()

proc readFromPty*(pty: PtyHandle, maxBytes: int = 4096): string =
  ## Non-blocking read from PTY master fd.
  ## Returns empty string if no data is available.
  if pty.closed:
    return ""

  var buf = newString(maxBytes)
  let n = read(pty.masterFd, addr buf[0], maxBytes)
  if n < 0:
    if errno == EINTR:
      let n2 = read(pty.masterFd, addr buf[0], maxBytes)
      if n2 <= 0:
        return ""
      buf.setLen(n2)
      return buf
    return ""
  if n == 0:
    return ""
  buf.setLen(n)
  buf

proc resizePty*(pty: PtyHandle, cols, rows: int) =
  ## Send TIOCSWINSZ ioctl to update the terminal size.
  ## The kernel sends SIGWINCH to the child process group.
  if pty.closed:
    return

  var ws: Winsize
  ws.ws_col = cols.cushort
  ws.ws_row = rows.cushort
  discard ioctl(pty.masterFd, TIOCSWINSZ, addr ws)

proc isAlive*(pty: PtyHandle): bool =
  ## Check if the child process is still running.
  if pty.closed:
    return false

  var status: cint
  let r = waitpid(pty.childPid, status, WNOHANG)
  # waitpid returns 0 if child is still running
  return r == 0

proc waitForExit*(pty: PtyHandle): int =
  ## Wait for the child process to exit and return the exit code.
  var status: cint
  discard waitpid(pty.childPid, status, 0)
  if WIFEXITED(status):
    WEXITSTATUS(status)
  else:
    -1

proc checkExitStatus*(pty: PtyHandle): Option[int] =
  ## Non-blocking check for process exit. Reaps the zombie and returns the exit
  ## code in a single waitpid call. Returns none if the process is still running.
  if pty.closed:
    return some(-1)

  var status: cint
  let r = waitpid(pty.childPid, status, WNOHANG)
  if r > 0:
    # Process exited and was reaped
    if WIFEXITED(status):
      return some(WEXITSTATUS(status).int)
    else:
      return some(-1)
  elif r == 0:
    # Still running
    return none(int)
  else:
    # waitpid error (e.g. already reaped) — treat as exited
    return some(-1)

proc reap(pty: PtyHandle, flags: cint): cint =
  ## waitpid that retries on EINTR, so a stray signal can't make us misread a
  ## live child as gone and skip the kill (WNOHANG: >0 reaped, 0 still running,
  ## -1 with ECHILD already collected elsewhere).
  var status: cint
  result = waitpid(pty.childPid, status, flags)
  while result == -1 and errno == EINTR:
    result = waitpid(pty.childPid, status, flags)

proc signalProcessGroup(pid: Pid, signal: cint) =
  ## forkpty makes the child a process-group leader, so its pid is also the
  ## process group id. Signal the group to include descendants of the shell.
  if pid <= 0:
    return
  discard posix.kill(posix.Pid(-pid), signal)

proc closePty*(pty: PtyHandle) =
  ## Close the master fd and reap the child shell and its process group.
  ##
  ## Escalates SIGTERM -> SIGKILL with a bounded, non-blocking poll so a child
  ## that ignores SIGTERM (or the SIGHUP raised by closing the master fd) can
  ## never wedge editor shutdown. SIGKILL cannot be caught or ignored, so the
  ## final reap is bounded by the kernel.
  if pty.closed:
    return

  pty.closed = true

  discard close(pty.masterFd)

  if pty.childPid <= 0:
    return

  if pty.reap(WNOHANG) != 0:
    # Exited (reaped here) or already gone — nothing left to signal.
    return

  # Still running: ask it to terminate, then poll for up to ~200ms without
  # blocking the shutdown path.
  signalProcessGroup(pty.childPid, SIGTERM)
  var ts = Timespec(tv_sec: Time(0), tv_nsec: 10_000_000) # 10ms
  for _ in 0 ..< 20:
    var remaining: Timespec
    discard nanosleep(ts, remaining)
    if pty.reap(WNOHANG) != 0:
      return

  # Refused SIGTERM: force-kill. SIGKILL is uncatchable, so this final reap is
  # bounded by the kernel tearing the process down.
  signalProcessGroup(pty.childPid, SIGKILL)
  discard pty.reap(0)
