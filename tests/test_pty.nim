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

import std/[unittest, posix, os, times]

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
    # Child: optionally make SIGTERM uncatchable-by-default into a no-op, then
    # block forever. Only SIGKILL (or, when cooperative, SIGTERM) can stop it.
    if ignoreSigterm:
      posix.signal(SIGTERM, SIG_IGN)
    while true:
      discard posix.sleep(cint(3600))
  PtyHandle(masterFd: devnull, childPid: pid, closed: false)

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
