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

import std/[unittest, options, os]
import pkg/results
import ../src/moepkg/[terminal_mode, key_bindings, buffer]
import ../src/moepkg/command_handlers/terminal_handler
import ../src/moepkg/terminal/pty

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: true, special: sk, modifiers: mods)

suite "SubStateHandler - Creation":
  test "newSubStateHandler creates handler":
    let handler = newSubStateHandler()
    check handler != nil

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
    let handler = newSubStateHandler()
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let result = handler.handleTerminalModeKey(termState.get, charKey("a"))
      check result.kind == trHandled
      termState.get.cleanup()

  test "Ctrl-backslash sets waitingForCtrlN":
    let handler = newSubStateHandler()
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let result = handler.handleTerminalModeKey(termState.get, charKey("\\", {kmCtrl}))
      check result.kind == trHandled
      check termState.get.waitingForCtrlN == true
      termState.get.cleanup()

suite "handleTerminalModeKey - Terminal-Normal sub-mode":
  test "'i' in Normal sub-mode returns trReturnToInput":
    let handler = newSubStateHandler()
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handler.handleTerminalModeKey(termState.get, charKey("i"))
      check result.kind == trReturnToInput
      termState.get.cleanup()

  test "'a' in Normal sub-mode returns trReturnToInput":
    let handler = newSubStateHandler()
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handler.handleTerminalModeKey(termState.get, charKey("a"))
      check result.kind == trReturnToInput
      termState.get.cleanup()

  test "':' in Normal sub-mode returns trEnterCommand":
    let handler = newSubStateHandler()
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      discard termState.get.enterNormalSubMode()
      let result = handler.handleTerminalModeKey(termState.get, charKey(":"))
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
  ## the terminal window.

  test "pollOutput sets exitCode after short command exits":
    let termState = newTerminalState("true", 80, 24)
    if termState.isOk:
      let ts = termState.get
      check ts.exitCode.isNone

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

  test "pollOutput sets exitCode = 0 for 'true' command":
    let termState = newTerminalState("true", 80, 24)
    if termState.isOk:
      let ts = termState.get
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

  test "pollOutput sets exitCode = 1 for 'false' command":
    let termState = newTerminalState("false", 80, 24)
    if termState.isOk:
      let ts = termState.get
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

suite "enterNormalSubMode after process exit (regression)":
  ## Regression test: when a short-lived command (e.g. `ls`) exits,
  ## pollTerminalWindows switches to Terminal-Normal sub-mode so the user
  ## can review output. The snapshot buffer must contain the command output
  ## and not be full of empty lines.

  test "Snapshot buffer contains command output after exit":
    let termState = newTerminalState("echo hello", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # Poll until process exits
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          break
        sleep(20)

      check ts.exitCode.isSome
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
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          break
        sleep(20)

      let snapshot = ts.enterNormalSubMode()
      check snapshot.readOnly == true
      ts.cleanup()

suite "Process exit behavior depends on command (regression)":
  ## `:terminal` (interactive shell, command="") should auto-close on exit.
  ## `:terminal ls` (command specified) should switch to Terminal-Normal
  ## so the user can review output.

  test "Interactive shell (empty command) stays in tsmInput after exit":
    # With empty command, pollTerminalWindows would auto-close.
    # At the TerminalState level, subMode remains tsmInput (caller closes).
    let termState = newTerminalState("true", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # Simulate as if this were an interactive shell
      ts.command = ""
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          break
        sleep(20)

      check ts.exitCode.isSome
      # subMode should still be tsmInput (not switched by pollOutput itself)
      check ts.subMode == tsmInput
      ts.cleanup()

  test "Command mode keeps command field non-empty":
    let termState = newTerminalState("echo test", 80, 24)
    if termState.isOk:
      let ts = termState.get
      check ts.command == "echo test"
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if ts.exitCode.isSome:
          break
        sleep(20)

      check ts.exitCode.isSome
      # command field preserved after exit
      check ts.command == "echo test"
      ts.cleanup()

  test "Default shell has empty command field":
    # newTerminalState with empty command spawns default shell
    let termState = newTerminalState("", 80, 24)
    if termState.isOk:
      let ts = termState.get
      check ts.command == ""
      ts.cleanup()
