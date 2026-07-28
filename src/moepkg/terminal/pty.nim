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

import std/[os, posix, options]

import pkg/results

type PtyHandle* = ref object
  masterFd*: cint
  childPid*: Pid
  closed*: bool
  writeBuffer*: string
    ## Bytes accepted by writeToPty that the kernel PTY buffer could not take
    ## yet (EAGAIN). Drained non-blockingly by drainWriteBuffer from the outer
    ## poll loop, so a stopped or flow-controlled child cannot wedge the UI.

const maxPtyWriteBufferBytes* = 64 * 1024
  ## Bound on writeBuffer so a wedged child can't grow it without limit.

const maxPtyReadBytesPerPoll* = 256 * 1024
  ## Byte cap for one pollOutput drain. Bounds tick cost so a runaway
  ## child (`yes`, `cat` big file) can't monopolize a render frame.

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
    # Child process
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
    fd: cint, data: string, offset: int
): tuple[written: int, err: string] =
  ## Write as much of data[offset ..< len] as the kernel will take without
  ## blocking. Returns bytes written and an empty err on EAGAIN, or a
  ## populated err on a real failure.
  var written = 0
  while offset + written < data.len:
    let n = write(fd, unsafeAddr data[offset + written], data.len - offset - written)
    if n < 0:
      if errno == EINTR:
        continue
      if errno == EAGAIN or errno == EWOULDBLOCK:
        return (written, "")
      return (written, "write to PTY failed: " & $strerror(errno))
    written += n.int
  (written, "")

proc drainWriteBuffer*(pty: PtyHandle): Result[void, string] =
  ## Try to push any buffered bytes to the PTY without blocking. Safe to call
  ## every UI tick — a stopped or flow-controlled child just leaves the buffer
  ## in place.
  if pty.closed or pty.writeBuffer.len == 0:
    return ok()

  let (written, err) = tryWriteNonblock(pty.masterFd, pty.writeBuffer, 0)
  if written > 0:
    if written >= pty.writeBuffer.len:
      pty.writeBuffer.setLen(0)
    else:
      pty.writeBuffer = pty.writeBuffer[written ..< pty.writeBuffer.len]
  if err.len > 0:
    return err(err)
  ok()

proc writeToPty*(pty: PtyHandle, data: string): Result[void, string] =
  ## Non-blocking write to the PTY master fd. Any bytes the kernel cannot
  ## accept immediately are appended to pty.writeBuffer and flushed later by
  ## drainWriteBuffer, so a SIGSTOP'd or ^S-paused child can never freeze the
  ## caller.
  if pty.closed:
    return err("PTY is closed")
  if data.len == 0:
    return ok()

  ?pty.drainWriteBuffer()

  var startOffset = 0
  var writeErr = ""
  if pty.writeBuffer.len == 0:
    let (written, err) = tryWriteNonblock(pty.masterFd, data, 0)
    startOffset = written
    writeErr = err

  if startOffset < data.len:
    let remaining = data.len - startOffset
    if pty.writeBuffer.len + remaining > maxPtyWriteBufferBytes:
      return err(
        "PTY write buffer full (" & $pty.writeBuffer.len &
          " bytes pending); child is not consuming input"
      )
    pty.writeBuffer.add data[startOffset ..< data.len]

  if writeErr.len > 0:
    return err(writeErr)
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

proc closePty*(pty: PtyHandle) =
  ## Close the master fd and reap the child shell.
  ##
  ## Escalates SIGTERM -> SIGKILL with a bounded, non-blocking poll so a child
  ## that ignores SIGTERM (or the SIGHUP raised by closing the master fd) can
  ## never wedge editor shutdown. SIGKILL cannot be caught or ignored, so the
  ## final reap is bounded by the kernel.
  if pty.closed:
    return

  pty.closed = true

  discard close(pty.masterFd)

  if pty.reap(WNOHANG) != 0:
    # Exited (reaped here) or already gone — nothing left to signal.
    return

  # Still running: ask it to terminate, then poll for up to ~200ms without
  # blocking the shutdown path.
  discard kill(pty.childPid, SIGTERM)
  var ts = Timespec(tv_sec: Time(0), tv_nsec: 10_000_000) # 10ms
  for _ in 0 ..< 20:
    var remaining: Timespec
    discard nanosleep(ts, remaining)
    if pty.reap(WNOHANG) != 0:
      return

  # Refused SIGTERM: force-kill. SIGKILL is uncatchable, so this final reap is
  # bounded by the kernel tearing the process down.
  discard kill(pty.childPid, SIGKILL)
  discard pty.reap(0)
