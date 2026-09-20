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

import std/[unittest, options, os, posix, times, deques, strutils, tables]
import pkg/results
import ../src/moepkg/[terminal_mode, key_bindings, editor, config, handler, types]
import ../src/moepkg/buffer/core
import ../src/moepkg/command_handlers/terminal_handler
import ../src/moepkg/terminal/[pty, ansi_parser]

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  KeyCombo(isSpecial: true, special: sk, modifiers: mods)

proc queuedBytes(pty: PtyHandle): string =
  ## What is still queued for the child, in order.
  var isFront = true
  for chunk in pty.writeQueue.items:
    if isFront:
      result.add chunk.data[pty.writeOffset ..< chunk.data.len]
      isFront = false
    else:
      result.add chunk.data

proc fillWriteQueue(ts: TerminalState) =
  ## `sleep` never reads stdin, so once the kernel PTY buffer is full the bytes
  ## a keystroke sends stay visible in the queue. Pad well past what a later
  ## write can drain back out, so the tail stays observable.
  for _ in 0 ..< 64:
    ts.feedInput("x".repeat(4096))
    if ts.pty.pendingWriteBytes >= 32768:
      break
  doAssert ts.pty.pendingWriteBytes >= 32768

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

    # Multi-byte characters and multi-character input carry no Ctrl mapping
    check keyComboToBytes(charKey("あ", {kmCtrl})) == ""
    check keyComboToBytes(charKey("ab", {kmCtrl})) == ""
    check keyComboToBytes(charKey("", {kmCtrl})) == ""

  test "Alt combinations with non-ASCII are rejected":
    # Alt is also single-ASCII-only (same rationale as Ctrl)
    check keyComboToBytes(charKey("a", {kmAlt})) == "\x1b" & "a"
    check keyComboToBytes(charKey("あ", {kmAlt})) == ""
    check keyComboToBytes(charKey("ab", {kmAlt})) == ""
    check keyComboToBytes(charKey("", {kmAlt})) == ""

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
  ## shell process exits, so pollTerminalSessions can detect it and close
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

suite "A doubled Ctrl-backslash sends one quit character":
  test "The second press releases the held one and arms nothing further":
    let termState = newTerminalState("sleep 3", 80, 24)
    require termState.isOk
    let ts = termState.get
    defer:
      ts.cleanup()
    fillWriteQueue(ts)

    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    require ts.waitingForCtrlN

    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    # One \x1c, and nothing left waiting to fire against a later key.
    check ts.pty.queuedBytes.endsWith("\x1c")
    check not ts.pty.queuedBytes.endsWith("\x1c\x1c")
    check not ts.waitingForCtrlN

    # A following Ctrl-N is an ordinary keystroke, not the idiom.
    check handleTerminalModeKey(ts, charKey("n", {kmCtrl})).kind == trHandled
    check ts.pty.queuedBytes.endsWith("\x1c\x0e")

suite "A held Ctrl-backslash and the keys that never reach the terminal handler":
  proc editorWithTerminal(ts: TerminalState): Editor =
    result = newEditor(newEditorConfig())
    result.syncActiveWindow()
    let buf = newTextBuffer("")
    buf.displayName = some("[Terminal: sleep]")
    result.addBuffer(buf)
    result.addBufferToWindowList(buf)
    result.terminalStates[buf.id] = ts
    result.activeWindow.setTab(buf)
    result.activeWindow.modeState = ModeState(kind: mskTerminal, terminal: ts)
    result.activeWindow.mode = EditorMode.Terminal
    result.setMode(EditorMode.Terminal)

  test "Ctrl-C through handleInterrupt releases the held one":
    let termState = newTerminalState("sleep 3", 80, 24)
    require termState.isOk
    let ts = termState.get
    defer:
      ts.cleanup()
    fillWriteQueue(ts)

    let e = editorWithTerminal(ts)
    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    require ts.waitingForCtrlN

    check e.handleInterrupt()
    check not ts.waitingForCtrlN
    check ts.pty.queuedBytes.endsWith("\x1c\x03")

  test "Ctrl-C drops a queued paste the child never read":
    let termState = newTerminalState("sleep 3", 80, 24)
    require termState.isOk
    let ts = termState.get
    defer:
      ts.cleanup()
    fillWriteQueue(ts)
    require ts.pty.queueWrite("pasted\n", wcDroppable).isOk

    let e = editorWithTerminal(ts)
    check e.handleInterrupt()
    check ts.pty.droppableBytes == 0
    check not ts.pty.queuedBytes.contains("pasted")
    check ts.pty.queuedBytes.endsWith("\x03")

  test "A Ctrl-W window command releases it instead of holding it":
    let termState = newTerminalState("sleep 3", 80, 24)
    require termState.isOk
    let ts = termState.get
    defer:
      ts.cleanup()
    fillWriteQueue(ts)

    let e = editorWithTerminal(ts)
    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    require ts.waitingForCtrlN

    check e.handleKeyCombo(charKey("w", {kmCtrl}))
    # The editor consumes the key, but the hold is still spent on it: the
    # quit character reaches the shell now rather than at some later keystroke.
    check not ts.waitingForCtrlN
    check ts.pty.queuedBytes.endsWith("\x1c")

  test "A consumed key does not leave the hold armed for a later Ctrl-N":
    let termState = newTerminalState("sleep 3", 80, 24)
    require termState.isOk
    let ts = termState.get
    defer:
      ts.cleanup()
    fillWriteQueue(ts)

    let e = editorWithTerminal(ts)
    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    check e.handleKeyCombo(charKey("w", {kmCtrl}))
    check e.handleKeyCombo(specialKey(skEscape))
    require not ts.waitingForCtrlN
    let afterCancel = ts.pty.pendingWriteBytes

    # The idiom now starts from scratch: Terminal-Normal, no second quit.
    discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
    require ts.waitingForCtrlN
    check handleTerminalModeKey(ts, charKey("n", {kmCtrl})).kind == trSwitchToNormal
    check ts.pty.pendingWriteBytes == afterCancel

suite "Query answers the write queue could not take":
  test "A query answer the queue refused is kept for the next tick":
    let termState = newTerminalState("cat", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # A full pipe stands in for a child that stopped reading: every write
      # EAGAINs, so the queue fills to the cap and nothing drains it again.
      var fds: array[2, cint]
      require pipe(fds) == 0
      require fcntl(fds[1], F_SETFL, fcntl(fds[1], F_GETFL) or O_NONBLOCK) == 0
      let realFd = ts.pty.masterFd
      ts.pty.masterFd = fds[1]

      for _ in 0 ..< 200:
        let room = maxPtyWriteQueueBytes - ts.pty.pendingWriteBytes
        if room == 0:
          break
        ts.feedInput("x".repeat(min(room, 64 * 1024)))
      require ts.pty.pendingWriteBytes == maxPtyWriteQueueBytes
      require ts.pty.queueWrite("z").isErr

      ts.grid.pendingResponses = @["\x1b[?1;2c"]
      discard ts.pollOutput()

      # The child may be blocking on that answer, so it is not thrown away.
      check ts.grid.pendingResponses == @["\x1b[?1;2c"]

      ts.pty.masterFd = realFd
      discard close(fds[0])
      discard close(fds[1])
      ts.cleanup()

  test "A query answer is retried on a tick that brings no new output":
    let termState = newTerminalState("cat", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # `cat` echoes only what it is fed, so nothing arrives on its own.
      ts.grid.pendingResponses = @["\x1b[?1;2c"]
      discard ts.pollOutput()
      check ts.grid.pendingResponses.len == 0
      ts.cleanup()

  test "A query answer is dropped once the fd is gone for good":
    let termState = newTerminalState("cat", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.pty.writeFailed = true
      ts.grid.pendingResponses = @["\x1b[?1;2c"]
      discard ts.pollOutput()
      # Retrying it forever would only relog the same failure every tick.
      check ts.grid.pendingResponses.len == 0
      ts.cleanup()

suite "pasteInput forwards pasted text to the PTY":
  ## A paste in Terminal-Input sub-mode belongs to the child process: the text
  ## goes to the PTY with newlines normalized to CR, wrapped in the bracketed
  ## paste markers when the child asked for them (DECSET 2004).

  test "Pasted command reaches the shell and runs":
    let termState = newTerminalState("", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.pasteInput("echo PASTEOK\n")

      var found = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if "PASTEOK" in ts.grid.toPlainText():
          found = true
          break
        sleep(20)

      check found
      ts.cleanup()
  test "Bracketed paste wraps the text in the paste markers":
    let termState = newTerminalState("cat -v", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # `cat -v` renders the markers as printable text, so what the child
      # actually received is observable in the grid.
      ts.grid.bracketedPaste = true
      ts.pasteInput("hi\n")

      var found = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if "^[[200~hi" in ts.grid.toPlainText():
          found = true
          break
        sleep(20)

      check found
      ts.cleanup()
  test "Escape sequences in the pasted text are dropped":
    let termState = newTerminalState("cat -v", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.pasteInput("a\x1b[31mb\n")

      var found = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if "a[31mb" in ts.grid.toPlainText():
          found = true
          break
        sleep(20)

      check found
      ts.cleanup()
  test "A paste larger than the kernel PTY buffer is delivered in full":
    let termState = newTerminalState("cat -v", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      # Well past the kernel PTY buffer, so the paste cannot go out in one
      # write and has to be flushed across poll ticks.
      let payload = "z\n".repeat(35000)
      ts.pasteInput(payload)
      # Typed after the paste, so the tty echoes it only once every byte of the
      # paste has gone out ahead of it. Unlike the paste's own closing marker,
      # it is the last thing on screen and cannot scroll off the grid.
      ts.feedInput("PASTE-END\r")

      var found = false
      for _ in 0 ..< 400:
        discard ts.pollOutput()
        if "PASTE-END" in ts.grid.toPlainText():
          found = true
          break
        sleep(20)

      check found
      check ts.pty.pendingWriteBytes == 0
      ts.cleanup()
  test "A paste is queued, not dropped, while the child is not reading":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # `sleep` never reads stdin, so the PTY buffer fills and the rest of the
      # paste has to wait instead of being thrown away.
      ts.pasteInput("z\n".repeat(200000))
      check ts.pty.pendingWriteBytes > 0
      ts.cleanup()
  test "A paste past the keystroke queue cap is queued whole, not cut":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      # The cap bounds what keystrokes can pile up, not one paste: cutting it
      # would split a UTF-8 sequence and leave a half-typed command behind.
      # A megabyte past the cap, so the kernel taking a bufferful up front
      # cannot be mistaken for the queue having cut the paste.
      let payload = "z".repeat(maxPtyWriteQueueBytes + 1024 * 1024)
      check ts.pasteInput(payload).isOk
      check ts.pty.pendingWriteBytes > maxPtyWriteQueueBytes
      ts.cleanup()
  test "A keystroke after a paste stays behind it instead of overtaking it":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.pasteInput("z".repeat(200000))
      let queuedAfterPaste = ts.pty.pendingWriteBytes
      require queuedAfterPaste > 0

      ts.feedInput("K")
      # The keystroke went on the same queue, behind the paste, rather than
      # straight to the fd.
      check ts.pty.pendingWriteBytes == queuedAfterPaste + 1
      ts.cleanup()
  test "Ctrl-C cancels the rest of a queued paste":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(200000))
      require ts.pty.pendingWriteBytes > 0

      ts.interrupt()
      # Only the paste terminator and \x03 are left; the rest is gone.
      check ts.pty.pendingWriteBytes <= 7
      ts.cleanup()
  test "A paste can be cancelled from the Normal sub-mode without an interrupt":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(1024 * 1024))
      discard ts.enterNormalSubMode()
      require ts.pty.writeOffset > 0

      ts.cancelQueuedPastes()
      # The child is closed out of the paste, but no \x03 is typed at it: the
      # keys belong to the editor while the scrollback is being browsed.
      check ts.pty.queuedBytes == "\x1b[201~"
      ts.cleanup()
  test "Ctrl-C closes the paste the child is still inside after a second paste":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      # Far past any kernel PTY buffer and the child never reads, so the first
      # paste is still open when the second one is queued behind it.
      ts.pasteInput("z".repeat(1024 * 1024))
      ts.pasteInput("y".repeat(1024))
      require ts.pty.writeOffset > 0

      ts.interrupt()
      # The second paste did not make the editor forget that the child is
      # still inside the first one.
      check ts.pty.queuedBytes == "\x1b[201~\x03"
      ts.cleanup()
  test "Ctrl-C drops the paste and keeps what the user typed after it":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(1024 * 1024))
      ts.feedInput("K")
      require ts.pty.writeOffset > 0

      ts.interrupt()
      # The closing marker takes the dropped paste's place, so the keystroke
      # behind it cannot be read as pasted text.
      check ts.pty.queuedBytes == "\x1b[201~K\x03"
      ts.cleanup()
  test "A paste keeps moving while the user browses the scrollback":
    let termState = newTerminalState("cat", 80, 24)
    if termState.isOk:
      let ts = termState.get
      discard ts.enterNormalSubMode()
      # `cat` echoes every byte back, so the paste only drains as long as the
      # output is drained too - which pollOutput does in either sub-mode.
      ts.pasteInput("z\n".repeat(35000))

      for _ in 0 ..< 400:
        discard ts.pollOutput()
        if ts.pty.pendingWriteBytes == 0:
          break
        sleep(20)

      check ts.pty.pendingWriteBytes == 0
      ts.cleanup()
  test "A query answer goes out ahead of the pastes still queued":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(1024 * 1024))
      require ts.pty.writeOffset > 0
      ts.pasteInput("y".repeat(1024))

      # A query the child made mid-paste: it may be blocked on the answer, and
      # under bracketed paste an answer behind a closer is read as input.
      ts.grid.processOutput("\x1b[c")
      require ts.grid.pendingResponses.len == 1
      # Queued without flushing, so the order is still the queue's to show.
      check ts.pty.queueResponse(ts.grid.pendingResponses[0]).isOk

      let queued = ts.pty.queuedBytes
      let answer = queued.find("\x1b[?6c")
      check answer > -1
      # After the closer of the paste the child is inside, so it is not read as
      # pasted text, and before the paste it re-opens for the rest.
      check answer > queued.find("\x1b[201~")
      check answer < queued.find("\x1b[200~")
      ts.cleanup()
  test "Ctrl-C sends the Ctrl-backslash held for Ctrl-N ahead of the interrupt":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(1024 * 1024))
      require ts.pty.writeOffset > 0

      discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
      require ts.waitingForCtrlN

      ts.interrupt()
      check not ts.waitingForCtrlN
      # The held byte was typed before Ctrl-C, so it goes out before it.
      check ts.pty.queuedBytes == "\x1b[201~\x1c\x03"
      ts.cleanup()
  test "A paste reports a dead fd instead of reporting success":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      let realFd = ts.pty.masterFd
      # Writes to fd -1 fail for real, like a master whose slave side is gone.
      ts.pty.masterFd = -1

      let r = ts.pasteInput("hi\n")
      check r.isErr
      check "no longer reachable" in r.error

      ts.pty.masterFd = realFd
      ts.cleanup()
  test "A paste flushes the Ctrl-backslash held back for Ctrl-N":
    let termState = newTerminalState("cat -v", 80, 24)
    if termState.isOk:
      let ts = termState.get
      discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
      check ts.waitingForCtrlN

      ts.pasteInput("hi\n")
      check not ts.waitingForCtrlN

      var found = false
      for _ in 0 ..< 100:
        discard ts.pollOutput()
        if "^\\hi" in ts.grid.toPlainText():
          found = true
          break
        sleep(20)

      check found
      ts.cleanup()
  test "A keystroke is still accepted while a paste past that cap is queued":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      require ts.pasteInput("z".repeat(maxPtyWriteQueueBytes + 1024 * 1024)).isOk

      ts.feedInput("K")
      # A paste has a budget of its own, so it cannot make a keystroke refused.
      check ts.pty.queuedBytes.endsWith("K")
      ts.cleanup()
  test "Ctrl-C keeps the held Ctrl-backslash when the paste is past that cap":
    let termState = newTerminalState("sleep 3", 80, 24)
    if termState.isOk:
      let ts = termState.get
      ts.grid.bracketedPaste = true
      ts.pasteInput("z".repeat(maxPtyWriteQueueBytes + 1024 * 1024))
      require ts.pty.writeOffset > 0

      discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
      require ts.waitingForCtrlN

      ts.interrupt()
      check ts.pty.queuedBytes == "\x1b[201~\x1c\x03"
      ts.cleanup()
  test "A paste that sanitizes to nothing still flushes the held Ctrl-backslash":
    let termState = newTerminalState("cat -v", 80, 24)
    if termState.isOk:
      let ts = termState.get
      discard handleTerminalModeKey(ts, charKey("\\", {kmCtrl}))
      require ts.waitingForCtrlN

      # A clipboard of control bytes alone: nothing is queued, but the wait is
      # over all the same, or the next key drags a stray \x1c in front of it.
      check ts.pasteInput("\x01\x02").isOk
      check not ts.waitingForCtrlN
      ts.cleanup()
  test "The Ctrl-backslash wait ends even after the terminal is gone":
    let termState = newTerminalState("cat", 80, 24)
    if termState.isOk:
      let ts = termState.get
      discard ts.handleTerminalModeKey(charKey("\\", {kmCtrl}))
      require ts.waitingForCtrlN
      ts.cleanup()
      discard ts.handleTerminalModeKey(charKey("a"))
      check not ts.waitingForCtrlN

suite "sanitizePastedText":
  test "CRLF collapses to a single CR":
    check sanitizePastedText("a\r\nb") == "a\rb"

  test "a lone CR is kept":
    check sanitizePastedText("a\rb") == "a\rb"

  test "LF becomes CR":
    check sanitizePastedText("a\nb") == "a\rb"

  test "tabs are kept":
    check sanitizePastedText("a\tb") == "a\tb"

  test "printable non-ASCII is kept":
    check sanitizePastedText("café — 日本語") == "café — 日本語"

  test "control bytes and DEL are dropped":
    # ESC is dropped; the CSI payload stays as plain text.
    check sanitizePastedText("a\x01b\x1b[31mc\x7fd") == "ab[31mcd"

  test "an empty string stays empty":
    check sanitizePastedText("") == ""

  test "control-only input sanitizes to nothing":
    check sanitizePastedText("\x01\x02\x1b") == ""

  test "NUL is dropped":
    check sanitizePastedText("a\x00b") == "ab"
