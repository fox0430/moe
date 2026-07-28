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

import std/[unittest, options, os, times, deques]
import pkg/results
import ../src/moepkg/[terminal_mode, key_bindings]
import ../src/moepkg/buffer/core
import ../src/moepkg/command_handlers/terminal_handler
import ../src/moepkg/terminal/[pty, ansi_parser]

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: true, special: sk, modifiers: mods)

suite "keyComboToBytes - Regular characters":
  test "Simple character 'a'":
    check keyComboToBytes(charKey("a")) == "a"

  test "Character 'Z'":
    check keyComboToBytes(charKey("Z")) == "Z"

  test "Space character":
    check keyComboToBytes(charKey(" ")) == " "

suite "keyComboToBytes - Special keys":
  test "Enter key":
    check keyComboToBytes(specialKey(skEnter)) == "\r"

  test "Escape key":
    check keyComboToBytes(specialKey(skEscape)) == "\x1b"

  test "Backspace key":
    check keyComboToBytes(specialKey(skBackspace)) == "\x7f"

  test "Tab key":
    check keyComboToBytes(specialKey(skTab)) == "\t"

  test "Up arrow":
    check keyComboToBytes(specialKey(skUp)) == "\x1b[A"

  test "Down arrow":
    check keyComboToBytes(specialKey(skDown)) == "\x1b[B"

  test "Right arrow":
    check keyComboToBytes(specialKey(skRight)) == "\x1b[C"

  test "Left arrow":
    check keyComboToBytes(specialKey(skLeft)) == "\x1b[D"

  test "Home key":
    check keyComboToBytes(specialKey(skHome)) == "\x1b[H"

  test "End key":
    check keyComboToBytes(specialKey(skEnd)) == "\x1b[F"

  test "Delete key":
    check keyComboToBytes(specialKey(skDelete)) == "\x1b[3~"

  test "PageUp key":
    check keyComboToBytes(specialKey(skPageUp)) == "\x1b[5~"

  test "PageDown key":
    check keyComboToBytes(specialKey(skPageDown)) == "\x1b[6~"

suite "keyComboToBytes - Ctrl combinations":
  test "Ctrl+a":
    check keyComboToBytes(charKey("a", {kmCtrl})) == "\x01"

  test "Ctrl+c":
    check keyComboToBytes(charKey("c", {kmCtrl})) == "\x03"

  test "Ctrl+d":
    check keyComboToBytes(charKey("d", {kmCtrl})) == "\x04"

  test "Ctrl+z":
    check keyComboToBytes(charKey("z", {kmCtrl})) == "\x1a"

  test "Ctrl+l":
    check keyComboToBytes(charKey("l", {kmCtrl})) == "\x0c"

suite "handleTerminalModeKey - Terminal-Input sub-mode":
  test "Regular key in Input mode returns trHandled":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let result = handleTerminalModeKey(termState.get, charKey("a"))
      check result.kind == trHandled
      termState.get.cleanup()

  test "Ctrl-backslash sets waitingForCtrlN":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let result = handleTerminalModeKey(termState.get, charKey("\\", {kmCtrl}))
      check result.kind == trHandled
      check termState.get.waitingForCtrlN == true
      termState.get.cleanup()

suite "handleTerminalModeKey - Terminal-Normal sub-mode":
  test "'i' in Normal sub-mode returns trReturnToInput":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handleTerminalModeKey(termState.get, charKey("i"))
      check result.kind == trReturnToInput
      termState.get.cleanup()

  test "'a' in Normal sub-mode returns trReturnToInput":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handleTerminalModeKey(termState.get, charKey("a"))
      check result.kind == trReturnToInput
      termState.get.cleanup()

  test "':' in Normal sub-mode returns trEnterCommand":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handleTerminalModeKey(termState.get, charKey(":"))
      check result.kind == trEnterCommand
      termState.get.cleanup()

# Bug fix regression tests

suite "checkExitStatus - single waitpid call (regression)":
  ## Regression test for the bug where isAlive() reaped the zombie via waitpid,
  ## then getExitCode() called waitpid again on the already-reaped process and
  ## returned none(int), causing the terminal to never detect process exit.
  ## Fixed by replacing isAlive+getExitCode with a single checkExitStatus call.

  test "checkExitStatus returns none for running process":
    let pty = openPtyAndSpawn("sleep 10", 80, 24)
    if pty.isOk:
      let status = pty.get.checkExitStatus()
      check status.isNone
      pty.get.closePty()

  test "checkExitStatus returns some after process exits":
    let pty = openPtyAndSpawn("true", 80, 24)
    if pty.isOk:
      # Wait for the short-lived process to finish
      sleep(200)
      let status = pty.get.checkExitStatus()
      check status.isSome
      check status.get == 0
      pty.get.closePty()

  test "checkExitStatus returns some(-1) after already reaped":
    let pty = openPtyAndSpawn("true", 80, 24)
    if pty.isOk:
      sleep(200)
      # First call reaps the zombie
      let status1 = pty.get.checkExitStatus()
      check status1.isSome
      # Second call: zombie already reaped, waitpid returns -1
      let status2 = pty.get.checkExitStatus()
      check status2.isSome # Must NOT be none (that was the bug)
      check status2.get == -1
      pty.get.closePty()

  test "checkExitStatus captures non-zero exit code":
    let pty = openPtyAndSpawn("false", 80, 24)
    if pty.isOk:
      sleep(200)
      let status = pty.get.checkExitStatus()
      check status.isSome
      check status.get == 1
      pty.get.closePty()

suite "pollOutput sets exitCode on process exit (regression)":
  ## Regression test: pollOutput must set TerminalState.exitCode when the
  ## shell process exits, so pollTerminalWindows can detect it and close
  ## the terminal window. A `:terminal` session always runs a persistent
  ## interactive shell, so the exit happens when the user quits the shell.

  test "pollOutput sets exitCode after the shell is quit":
    let termState = newTerminalState("", 80, 24)
    if termState.isOk:
      let ts = termState.get
      check ts.exitCode.isNone

      ts.feedInput("exit\n")

      # Poll until process exit is detected (max ~2 seconds)
      var detected = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          detected = true
          break
        sleep(20)

      check detected
      check ts.exitCode.isSome
      ts.cleanup()

  test "pollOutput sets exitCode = 0 when the shell exits cleanly":
    let termState = newTerminalState("", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.feedInput("exit 0\n")
      var detected = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          detected = true
          break
        sleep(20)

      check detected
      check ts.exitCode.get == 0
      ts.cleanup()

  test "pollOutput captures non-zero exit code from the shell":
    let termState = newTerminalState("", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.feedInput("exit 1\n")
      var detected = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          detected = true
          break
        sleep(20)

      check detected
      check ts.exitCode.get == 1
      ts.cleanup()

suite "enterNormalSubMode snapshots live session (regression)":
  ## `enterNormalSubMode` (entered manually via Ctrl-\ Ctrl-N) snapshots the
  ## current grid into a read-only TextBuffer for scrollback browsing. The
  ## snapshot must contain the command output and not be full of empty lines.

  test "Snapshot buffer contains command output":
    let termState = newTerminalState("echo hello", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # Poll long enough for the command output to reach the grid. The session
      # itself stays alive (the command runs, then `exec $SHELL` takes over),
      # so we do not wait for an exit.
      for _ in 0 ..< 20:
        discard ts.pollOutput()
        sleep(20)

      let snapshot = ts.enterNormalSubMode()
      check ts.subMode == tsmNormal
      check snapshot.len > 0
      # Should not have 24 lines (grid height) of mostly empty content
      check snapshot.len < 24
      ts.cleanup()

  test "Snapshot buffer is read-only":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let ts = termState.get
      for _ in 0 ..< 20:
        discard ts.pollOutput()
        sleep(20)

      let snapshot = ts.enterNormalSubMode()
      check snapshot.readOnly == true
      ts.cleanup()

suite "Persistent shell behavior (regression)":
  ## The session always runs as a persistent interactive shell. `:terminal ls`
  ## runs the command and then keeps the shell alive instead of exiting and
  ## recording the output into a snapshot buffer.

  test "Command mode keeps the shell alive after the command finishes":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # The `echo` finishes quickly, but `exec $SHELL` keeps the session
      # running, so the process must not have exited on its own.
      for _ in 0 ..< 20:
        discard ts.pollOutput()
        sleep(20)

      check ts.exitCode.isNone
      ts.cleanup()

  test "Shell exits when the user quits it":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # Let the command run and the interactive shell take over.
      for _ in 0 ..< 20:
        discard ts.pollOutput()
        sleep(20)

      # Quitting the shell (sending `exit`) terminates the session.
      ts.feedInput("exit\n")
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          break
        sleep(20)

      check ts.exitCode.isSome
      ts.cleanup()

suite "pollOutput drains multi-chunk bursts in one tick (regression)":
  ## pollOutput used to issue a single 4 KiB readFromPty per tick, so any
  ## burst larger than the kernel PTY buffer visibly lagged at ~4 KiB * FPS.
  ## It now loops until EAGAIN (bounded by maxPtyReadBytesPerPoll) so one
  ## call empties everything currently queued.

  test "single pollOutput consumes well past the legacy 4 KiB ceiling":
    # Bash-agnostic burst: 10000 "x\n" lines (~20 KiB) then a live sleep,
    # so the exit-branch drain (unchanged) does not mask the live path.
    let ptyResult = openPtyAndSpawn("yes x | head -n 10000; sleep 5", 80, 24)
    require ptyResult.isOk
    let ts = TerminalState(
      pty: ptyResult.get,
      grid: newTerminalGrid(80, 24),
      subMode: tsmInput,
      scrollbackSnapshot: nil,
      exitCode: none(int),
      waitingForCtrlN: false,
      needsBufferRefresh: false,
    )
    defer:
      ts.cleanup()

    # Give the child enough time to write far more than one 4 KiB chunk.
    sleep(400)

    let started = epochTime()
    discard ts.pollOutput()
    let elapsed = epochTime() - started

    # Each "x\n" that scrolls past row 24 becomes one scrollback entry. The
    # legacy per-call ceiling was ~2024 entries (4096 / 2 - 24 visible rows).
    check ts.grid.scrollbackBuffer.len >= 4000
    # Draining thousands of "x\n" via the ANSI parser stays well under a
    # frame budget.
    check elapsed < 1.0
