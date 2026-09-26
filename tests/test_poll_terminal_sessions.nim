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

## Tests for pollTerminalSessions: every live session is drained, whether or
## not it is on screen, and one terminal exiting must not skip the remaining
## sessions in the same frame.

import std/[unittest, options, posix, tables, strutils]

import pkg/results

import ../src/moe {.all.}
import ../src/moepkg/[editor, config, types, modes, handler, key_bindings]
import ../src/moepkg/terminal/[pty, ansi_parser]
import ../src/moepkg/buffer/core

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)
  result.syncActiveWindow()

proc exitedTerminalState(): TerminalState =
  ## Fake TerminalState whose PTY is pre-closed and whose shell already exited.
  ## `pollOutput` short-circuits on a closed PTY, so pollTerminalSessions
  ## observes the pre-set `exitCode` and triggers closeTerminalBuffer without
  ## going through a real PTY.
  TerminalState(
    pty: PtyHandle(masterFd: -1, childPid: Pid(0), closed: true),
    grid: newTerminalGrid(80, 24),
    exitCode: some(0),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

proc registerExitedTerminalInWindow(
    e: Editor, window: EditorWindow, command: string
): TextBuffer =
  ## Attach a pre-exited terminal buffer to `window` and register it in
  ## `e.terminalStates`, mirroring the state pollTerminalSessions sees when a
  ## shell has just quit.
  result = newTextBuffer("")
  result.displayName = some("[Terminal: " & command & "]")
  e.addBuffer(result)
  window.bufferIds.add(result.id)
  e.terminalStates[result.id] = exitedTerminalState()
  window.setTab(result)
  window.modeState = ModeState(kind: mskTerminal, terminal: e.terminalStates[result.id])
  window.mode = EditorMode.Terminal

proc addSecondWindow(e: Editor): EditorWindow =
  ## Add a second window sharing the first window's viewport dimensions so
  ## `calculateTerminalAreaDimensions` returns positive values for both.
  let first = e.windowManager.windows[0]
  result = EditorWindow(
    viewBuffer: first.buffer,
    tabBufferId: first.buffer.id,
    bufferIds: @[first.buffer.id],
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 12, x: 0, y: 12),
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
    active: false,
    wrapCountCache: WrapCountCache(),
  )
  e.windowManager.windows.add(result)

suite "pollTerminalSessions - multi-window regression":
  test "One terminal exit does not skip a second terminal's teardown":
    ## Regression for the `return`-inside-the-loop bug. When two windows are
    ## each showing a Terminal buffer and both shells have exited by the time
    ## pollTerminalSessions runs, both must be torn down in this frame — not
    ## just the first one the loop visits.
    let e = createTestEditor()

    let w1 = e.windowManager.windows[0]
    let w2 = e.addSecondWindow()

    let t1 = e.registerExitedTerminalInWindow(w1, "bash")
    let t2 = e.registerExitedTerminalInWindow(w2, "htop")
    let t1Id = t1.id
    let t2Id = t2.id

    check e.terminalStates.hasKey(t1Id)
    check e.terminalStates.hasKey(t2Id)
    check w1.mode == EditorMode.Terminal
    check w2.mode == EditorMode.Terminal

    e.pollTerminalSessions()

    # Both terminals must be torn down. With the previous `return`, only the
    # first would be, and t2's state would linger until the next frame.
    check not e.terminalStates.hasKey(t1Id)
    check not e.terminalStates.hasKey(t2Id)
    check w1.mode != EditorMode.Terminal
    check w2.mode != EditorMode.Terminal

suite "pollTerminalSessions - sub-mode round trip":
  proc singleTerminalEditor(): Editor =
    result = createTestEditor()
    discard
      result.registerExitedTerminalInWindow(result.windowManager.windows[0], "bash")
    result.state.mode = EditorMode.Terminal
    result.syncActiveWindow()

  test "Teardown still finds the session after a Normal-Input round trip":
    ## The sub-mode transitions swap `window.buffer`, so keying teardown off
    ## the window's current buffer left an exited shell's tab open for good.
    let e = singleTerminalEditor()
    let w = e.windowManager.windows[0]
    let termBufId = w.buffer.id

    discard
      e.handleKeyCombo(KeyCombo(isSpecial: false, char: "\\", modifiers: {kmCtrl}))
    discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl}))
    check w.modeState.terminalSubMode == tsmNormal

    discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "i", modifiers: {}))
    check w.modeState.terminalSubMode == tsmInput
    # The window is back on the registered buffer, not a fresh one.
    check w.buffer.id == termBufId

    e.pollTerminalSessions()

    check not e.terminalStates.hasKey(termBufId)
    check w.mode != EditorMode.Terminal

  test "q in Terminal-Normal closes the tab of an exited shell":
    let e = singleTerminalEditor()
    let w = e.windowManager.windows[0]
    let termBufId = w.buffer.id

    discard
      e.handleKeyCombo(KeyCombo(isSpecial: false, char: "\\", modifiers: {kmCtrl}))
    discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl}))
    check w.modeState.terminalSubMode == tsmNormal

    discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "q", modifiers: {}))

    check not e.terminalStates.hasKey(termBufId)
    check w.mode != EditorMode.Terminal

  test "An exited shell stays while any window on it browses the scrollback":
    let e = createTestEditor()
    let w1 = e.windowManager.windows[0]
    let termBuf = e.registerExitedTerminalInWindow(w1, "bash")
    let w2 = e.addSecondWindow()
    w2.modeState = ModeState(
      kind: mskTerminal,
      terminal: e.terminalStates[termBuf.id],
      scrollbackSnapshot: newTextBuffer(""),
    )
    w2.mode = EditorMode.Terminal

    e.pollTerminalSessions()

    check e.terminalStates.hasKey(termBuf.id)

    w2.modeState.scrollbackSnapshot = nil
    e.pollTerminalSessions()

    check not e.terminalStates.hasKey(termBuf.id)

suite "pollTerminalSessions - a backgrounded session keeps running":
  proc openTerminalState(): TerminalState =
    ## A session whose PTY looks open but is safe to poll: the fd is /dev/null,
    ## so `pollOutput` reads EOF rather than blocking on a real child.
    TerminalState(
      pty: PtyHandle(
        masterFd: posix.open("/dev/null".cstring, O_RDONLY),
        childPid: Pid(999999),
        closed: false,
      ),
      grid: newTerminalGrid(80, 24),
      exitCode: none(int),
      waitingForCtrlN: false,
      needsBufferRefresh: false,
    )

  test "a session on a background tab is still drained":
    ## Regression: the loop walked windows, so a backgrounded session got
    ## neither `pollOutput` nor the write flush it carries, stranding a queued
    ## paste and eventually blocking the child in write().
    let e = createTestEditor()
    let w = e.windowManager.windows[0]

    let termBuf = newTextBuffer("")
    termBuf.displayName = some("[Terminal: bash]")
    e.addBuffer(termBuf)
    w.bufferIds.add(termBuf.id)
    let session = openTerminalState()
    e.terminalStates[termBuf.id] = session
    w.setTab(termBuf)
    w.modeState = ModeState(kind: mskTerminal, terminal: session)
    w.mode = EditorMode.Terminal
    e.state.mode = EditorMode.Terminal
    e.syncActiveWindow()
    defer:
      session.pty.closePty()

    # Move the window to another tab; the session stays alive in the map.
    let other = newTextBuffer("")
    e.addBuffer(other)
    e.addBufferToWindowList(other)
    check e.activateBuffer(other.id)
    check e.terminalStates.hasKey(termBuf.id)
    check w.mode != EditorMode.Terminal

    # Queue more than one flush can push out, the way a large paste does.
    let payload = "x".repeat(maxPtyWriteBytesPerFlush * 2)
    require session.pty.queueWrite(payload, wcDroppable).isOk
    let pendingBefore = session.pty.pendingWriteBytes
    require pendingBefore > 0

    e.pollTerminalSessions()

    # The backgrounded session was drained: the queue moved.
    check session.pty.pendingWriteBytes < pendingBefore

  test "a backgrounded session that exited keeps its tab until it is visited":
    let e = createTestEditor()
    let w = e.windowManager.windows[0]
    let termBuf = e.registerExitedTerminalInWindow(w, "bash")
    let termBufId = termBuf.id

    let other = newTextBuffer("")
    e.addBuffer(other)
    e.addBufferToWindowList(other)
    check e.activateBuffer(other.id)

    e.pollTerminalSessions()
    # Not torn down behind the user's back.
    check e.terminalStates.hasKey(termBufId)

    check e.activateBuffer(termBufId)
    e.pollTerminalSessions()
    check not e.terminalStates.hasKey(termBufId)
