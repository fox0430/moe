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

import std/[unittest, posix, os, strutils, times]

import pkg/results

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

suite "writeToPty - non-blocking against a stopped child":
  test "Returns promptly when the child is SIGSTOP'd (EAGAIN never spins)":
    # Regression: writeToPty used to loop on poll(POLLOUT, 100ms) forever if
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
    var lastResult = pty.writeToPty(payload)
    # Keep writing until we overflow the userspace cap or run out of budget.
    # Every individual call MUST return without blocking.
    for _ in 0 ..< 200:
      if lastResult.isErr:
        break
      lastResult = pty.writeToPty(payload)
    let elapsed = epochTime() - start

    # 200 * 1KiB well exceeds the 64 KiB userspace cap on top of any kernel
    # PTY buffer, so we should have hit the overflow err.
    check lastResult.isErr
    # Must be dramatically faster than the old poll(100ms) * many iterations.
    check elapsed < 1.0
    # Buffer never grew past its documented cap.
    check pty.writeBuffer.len <= maxPtyWriteBufferBytes

  test "drainWriteBuffer flushes pending bytes once the child resumes":
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
      if pty.writeToPty(payload).isErr:
        break
    require pty.writeBuffer.len > 0

    # Resume the child; cat starts consuming, so drainWriteBuffer should
    # eventually push everything through.
    require kill(pty.childPid, SIGCONT) == 0
    let deadline = epochTime() + 2.0
    while pty.writeBuffer.len > 0 and epochTime() < deadline:
      discard pty.drainWriteBuffer()
      # Read the echoed bytes so the kernel keeps making room.
      discard pty.readFromPty(65536)
      sleep(10)

    check pty.writeBuffer.len == 0

  test "writeToPty on an empty buffer succeeds without touching the fd":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check pty.writeToPty("").isOk

  test "writeToPty on a closed handle returns err":
    let pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: true)
    let r = pty.writeToPty("hello")
    check r.isErr
