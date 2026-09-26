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

## Tests for Terminal-mode tab integration: applyBufferMode and
## closeTerminalBuffer keep `e.terminalStates`, `bufferIds`, and the
## active window's mode in sync as Terminal buffers come and go.

import std/[unittest, options, os, posix, tables]

import pkg/results

import
  ../src/moepkg/[
    editor, config, types, modes, terminal_mode, editor_window, editor_window_state,
    handler, key_bindings, viewer_mode, buffer_manager, window_manager,
  ]
import ../src/moepkg/terminal/[pty, ansi_parser]
import ../src/moepkg/buffer/core
import ../src/moepkg/command_handlers/[editor_ops, handler_result, result_processor]

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)
  result.syncActiveWindow()

proc fakeTerminalState(): TerminalState =
  ## Build a TerminalState whose PTY is pre-closed so cleanup() is a no-op.
  ## Lets tests drive the tab/state lifecycle without spawning a real shell.
  TerminalState(
    pty: PtyHandle(masterFd: -1, childPid: Pid(0), closed: true),
    grid: newTerminalGrid(80, 24),
    exitCode: none(int),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

proc safeOpenFakeTerminalState(): TerminalState =
  ## Build a TerminalState whose PTY looks "open" but is safe to tear down
  ## without a real shell, so a test can observe cleanup()/closePty() actually
  ## running (the `closed` flag flips false -> true):
  ## - masterFd is a throwaway /dev/null fd, so closePty()'s close() is harmless.
  ## - childPid is a positive pid the test never forked, so closePty()'s
  ##   waitpid() returns ECHILD (-1) and the SIGTERM branch is skipped.
  ## NEVER use Pid(0) here: waitpid(0)/kill(0) target the whole process group
  ## and could signal the test runner itself.
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

proc registerFakeTerminal(
    e: Editor, command: string = "bash", state: TerminalState = nil
): TextBuffer =
  ## Open a Terminal tab through the real `installTerminalSession` path,
  ## without touching real PTY plumbing. `state` defaults to a pre-closed fake
  ## (cleanup() is a no-op); pass a `safeOpenFakeTerminalState()` to exercise
  ## teardown.
  e.installTerminalSession(
    if state != nil:
      state
    else:
      fakeTerminalState(),
    command,
  )

proc enterNormal(e: Editor): TextBuffer =
  ## Ctrl-\ Ctrl-N through the real key path: the dispatcher sets the sub-mode,
  ## the result epilogue derives the view from it. Returns the scrollback
  ## snapshot the window ends up showing.
  discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "\\", modifiers: {kmCtrl}))
  discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl}))
  e.activeWindow.modeState.scrollbackSnapshot

proc charKey(c: string): KeyCombo =
  KeyCombo(isSpecial: false, char: c, modifiers: {})

proc runCommand(e: Editor, command: string) =
  discard e.handleKeyCombo(charKey(":"))
  for ch in command:
    discard e.handleKeyCombo(charKey($ch))
  discard e.handleKeyCombo(KeyCombo(isSpecial: true, special: skEnter))

template checkOnSession(e: Editor, win: EditorWindow, termBuf: TextBuffer) =
  ## `win` is parked on `termBuf`'s session and shows what its sub-mode says.
  check win.tabBufferId == termBuf.id
  check win.mode == EditorMode.Terminal
  check win.modeState.kind == mskTerminal
  if win.modeState.kind == mskTerminal:
    check win.modeState.terminal == e.terminalStates[termBuf.id]
    case win.modeState.terminalSubMode
    of tsmNormal:
      check win.buffer == win.modeState.scrollbackSnapshot
    of tsmInput:
      check win.buffer == termBuf

proc focusWindow(e: Editor, win: EditorWindow) =
  for i, w in e.windowManager.windows:
    if w == win:
      e.windowManager.activateWindow(i)
  e.syncActiveWindow()

proc twoWindowsOnSession(
    e: Editor, textBuf, termBuf: TextBuffer
): tuple[first, second: EditorWindow] =
  ## Split, then put both windows on `termBuf`'s session. `second` is active.
  require e.activateBuffer(textBuf.id)
  require e.vsplit().isOk
  result.second = e.activeWindow
  for w in e.windowManager.windows:
    if w != result.second:
      result.first = w
  require e.activateBuffer(termBuf.id)
  e.focusWindow(result.first)
  require e.activateBuffer(termBuf.id)
  e.focusWindow(result.second)

suite "Terminal tabs - applyBufferMode":
  test "Activating a Terminal buffer restores Terminal mode":
    let e = createTestEditor()
    let originalBuf = e.activeWindow.buffer
    let termBuf = registerFakeTerminal(e, "bash")

    # Force the window into Normal first so we can confirm applyBufferMode
    # promotes it back to Terminal on its own.
    e.activeWindow.mode = EditorMode.Normal
    e.activeWindow.modeState = ModeState(kind: mskNone)

    e.applyBufferMode(termBuf)

    check e.activeWindow.mode == EditorMode.Terminal
    check e.activeWindow.modeState.kind == mskTerminal
    # The original file buffer is untouched.
    check originalBuf != termBuf

  test "Activating a non-Terminal buffer from Terminal mode resets to Normal":
    let e = createTestEditor()
    let originalBuf = e.activeWindow.buffer
    discard registerFakeTerminal(e, "bash")

    e.applyBufferMode(originalBuf)

    check e.activeWindow.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone

suite "Terminal tabs - closeTerminalBuffer":
  test "Closing the terminal removes its state and falls back to a sibling tab":
    let e = createTestEditor()
    let originalBuf = e.activeWindow.buffer
    let termBuf = registerFakeTerminal(e, "bash")
    let termBufId = termBuf.id

    check e.terminalStates.hasKey(termBufId)
    check termBufId in e.activeWindow.bufferIds

    e.closeTerminalBuffer(termBufId)

    check not e.terminalStates.hasKey(termBufId)
    check termBufId notin e.activeWindow.bufferIds
    check e.bufferIndexById(termBufId) == -1
    # Fell back to the file tab that was already in this window.
    check e.activeWindow.buffer == originalBuf
    check e.activeWindow.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone

  test "Closing the last terminal in a fresh window spawns a No Name buffer":
    let e = createTestEditor()
    # Wipe the seed buffer so the only tab is the terminal we register next.
    let seed = e.activeWindow.buffer
    let seedIdx = e.bufferIndexById(seed.id)
    if seedIdx >= 0:
      e.deleteBufferAt(seedIdx)
    e.activeWindow.bufferIds = @[]

    let termBuf = registerFakeTerminal(e, "htop")
    check e.activeWindow.bufferIds == @[termBuf.id]

    e.closeTerminalBuffer(termBuf.id)

    check e.activeWindow.bufferIds.len == 1
    check e.activeWindow.buffer != nil
    check e.activeWindow.buffer.displayName.isNone
    check e.activeWindow.mode == EditorMode.Normal

  test "Closing one terminal leaves siblings intact":
    let e = createTestEditor()
    let t1 = registerFakeTerminal(e, "bash")
    let t2 = registerFakeTerminal(e, "htop")
    let t1Id = t1.id
    let t2Id = t2.id

    check e.terminalStates.hasKey(t1Id)
    check e.terminalStates.hasKey(t2Id)

    e.closeTerminalBuffer(t2Id)

    check e.terminalStates.hasKey(t1Id)
    check not e.terminalStates.hasKey(t2Id)
    check t1Id in e.activeWindow.bufferIds
    check t2Id notin e.activeWindow.bufferIds
    # The surviving terminal becomes active and Terminal mode is restored.
    check e.activeWindow.buffer.id == t1Id
    check e.activeWindow.mode == EditorMode.Terminal
    check e.activeWindow.modeState.kind == mskTerminal

suite "Terminal tabs - deleteCurrentBuffer":
  test ":bd on a Terminal buffer routes through closeTerminalBuffer":
    let e = createTestEditor()
    let originalBuf = e.activeWindow.buffer
    let termBuf = registerFakeTerminal(e, "bash")
    let termBufId = termBuf.id

    check e.deleteCurrentBuffer().isOk

    # PTY state and buffer registration were torn down.
    check not e.terminalStates.hasKey(termBufId)
    check termBufId notin e.activeWindow.bufferIds
    # Active buffer rolled back to the file tab in Normal mode.
    check e.activeWindow.buffer == originalBuf
    check e.activeWindow.mode == EditorMode.Normal

suite "Terminal tabs - cleanupAllTerminals":
  test "Tears down every live terminal PTY and clears the state map":
    let e = createTestEditor()
    # Two "open" terminals plus the seed file buffer in the active window.
    let t1 = registerFakeTerminal(e, "bash", safeOpenFakeTerminalState())
    let t2 = registerFakeTerminal(e, "htop", safeOpenFakeTerminalState())
    let s1 = e.terminalStates[t1.id]
    let s2 = e.terminalStates[t2.id]
    check not s1.pty.closed
    check not s2.pty.closed
    check e.terminalStates.len == 2

    e.cleanupAllTerminals()

    # cleanup() ran on each session (master fd closed) and the map is empty.
    check s1.pty.closed
    check s2.pty.closed
    check e.terminalStates.len == 0
    # Unlike closeTerminalBuffer, exit-time teardown only releases the PTYs —
    # the buffers themselves are left in place (the editor is exiting anyway).
    check e.bufferIndexById(t1.id) >= 0
    check e.bufferIndexById(t2.id) >= 0

  test "Is a no-op on an editor with no terminals":
    let e = createTestEditor()
    check e.terminalStates.len == 0
    e.cleanupAllTerminals() # must not raise
    check e.terminalStates.len == 0

  test "Is idempotent — a second call after teardown stays safe":
    let e = createTestEditor()
    discard registerFakeTerminal(e, "bash", safeOpenFakeTerminalState())
    e.cleanupAllTerminals()
    check e.terminalStates.len == 0
    e.cleanupAllTerminals() # second call: still safe, still empty
    check e.terminalStates.len == 0

  test "Skips cleanup branches safely for an already-closed PTY":
    # The default fake is pre-closed; cleanupAllTerminals must treat it as a
    # no-op teardown and still clear the map.
    let e = createTestEditor()
    let t = registerFakeTerminal(e, "bash") # pre-closed fake
    let s = e.terminalStates[t.id]
    check s.pty.closed

    e.cleanupAllTerminals()

    check s.pty.closed
    check e.terminalStates.len == 0

suite "Terminal tabs - hrCloseWindow via processResult":
  test "processResult(hrCloseWindow) cleans up terminal state":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    let termBufId = termBuf.id

    check e.terminalStates.hasKey(termBufId)
    check e.terminalStates.len == 1

    discard e.processResult(HandlerResult(kind: hrCloseWindow), e.activeBuffer())

    check e.terminalStates.len == 0
    check not e.terminalStates.hasKey(termBufId)
    check e.activeWindow.mode != EditorMode.Terminal

suite "Terminal tabs - Terminal-Normal browses an unregistered snapshot":
  test "bdelete closes the session instead of failing on the snapshot":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    let termBufId = termBuf.id
    let snapshot = e.enterNormal()

    check snapshot.id != termBufId

    # A terminal buffer is exempt from the modified check, so the snapshot the
    # window is showing must not make `:bd` refuse.
    check e.deleteCurrentBuffer().isOk

    check not e.terminalStates.hasKey(termBufId)
    check e.activeWindow.mode != EditorMode.Terminal

  test "enew from Terminal-Normal detaches the window from the session":
    # Regression: the window's tab identity used to be derived from
    # `modeState.kind`, which `enew` leaves on mskTerminal, so `:bd` killed
    # the shell instead of the buffer the window had moved to.
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    let termBufId = termBuf.id
    discard e.enterNormal()

    discard e.enew()
    let newBufId = e.activeBuffer().id
    check newBufId != termBufId
    check e.activeWindow.tabBufferId == newBufId

    check e.deleteCurrentBuffer().isOk

    check e.terminalStates.hasKey(termBufId)
    check e.bufferById(newBufId).isNone

  test "A second terminal detaches the window from the previous session":
    # Regression: the window's tab identity used to be guessed from
    # `originalBuffer`, which still pointed at the session the window was
    # browsing, so every teardown path (PTY close, `:bd`, `Ctrl-w c`) hit the
    # wrong session.
    let e = createTestEditor()
    let termA = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    # Browsing the scrollback is a view swap, so the tab does not move.
    check e.activeWindow.tabBufferId == termA.id

    let termB = registerFakeTerminal(e, "bash")

    check e.activeWindow.tabBufferId == termB.id

    # The shell in B exits: only B's tab and state go away.
    e.closeTerminalBuffer(e.activeWindow.tabBufferId)

    check not e.terminalStates.hasKey(termB.id)
    check e.terminalStates.hasKey(termA.id)

  test "The tab list still finds the session's tab":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()

    check e.windowBufferIndex() == e.activeWindow.bufferIds.find(termBuf.id)
    check e.windowBufferIndex() >= 0
    # What the tab line marks as the current tab.
    check e.tabBuffer(e.activeWindow) == termBuf

suite "Terminal tabs - a session takes the window over":
  test "The viewer bookkeeping the window was carrying is dropped":
    # A viewer entry would undo its placement on top of the live session, and a
    # suspended mode would resume into it.
    let e = createTestEditor()
    let originBuf = e.activeWindow.buffer
    e.activeWindow.viewerEntry = some(
      ViewerEntry(
        mode: EditorMode.BufferManager,
        placement: vpInPlace,
        returnMode: EditorMode.Normal,
        bufferId: originBuf.id,
      )
    )
    e.activeWindow.suspendMode()

    discard registerFakeTerminal(e, "bash")

    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.suspendedMode.isNone
    check e.activeWindow.mode == EditorMode.Terminal

suite "Terminal tabs - the view is derived from the sub-mode":
  proc plainKey(c: string): KeyCombo =
    KeyCombo(isSpecial: false, char: c, modifiers: {})

  test "the sub-mode round trip swaps the view, not the tab":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    check e.activeWindow.buffer == termBuf

    let snapshot = e.enterNormal()
    check e.activeWindow.modeState.terminalSubMode == tsmNormal
    check e.activeWindow.buffer == snapshot
    check e.activeWindow.tabBufferId == termBuf.id

    # `i` returns to Terminal-Input; the session's own tab buffer comes back
    # under the live grid.
    discard e.handleKeyCombo(plainKey("i"))
    check e.activeWindow.modeState.terminalSubMode == tsmInput
    check e.activeWindow.buffer == termBuf
    check e.activeWindow.tabBufferId == termBuf.id

  test "a backgrounded Terminal-Normal tab resumes live":
    # Regression: the sub-mode was per-session state that survived a tab
    # switch while the view was rebuilt from scratch, so the window came back
    # in TERMINAL mode showing neither the live grid nor the snapshot.
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    require e.activeWindow.modeState.terminalSubMode == tsmNormal

    let other = newTextBuffer("")
    e.addBuffer(other)
    e.addBufferToWindowList(other)
    check e.activateBuffer(other.id)

    # Leaving the tab ends the browsing session; nothing is carried across.
    check e.activeWindow.modeState.kind == mskNone

    check e.activateBuffer(termBuf.id)
    check e.activeWindow.mode == EditorMode.Terminal
    check e.activeWindow.modeState.kind == mskTerminal
    check e.activeWindow.modeState.terminalSubMode == tsmInput
    check e.activeWindow.buffer == termBuf
    check e.activeWindow.tabBufferId == termBuf.id

  test "enew from Terminal-Normal ends the browsing session too":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    require e.activeWindow.modeState.terminalSubMode == tsmNormal

    discard e.enew()

    check e.activeWindow.modeState.kind == mskNone
    # The session is still alive, just not on screen.
    check e.terminalStates.hasKey(termBuf.id)

    require e.activateBuffer(termBuf.id)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.activeWindow.buffer == termBuf

  test "closing the only Terminal tab drops viewerEntry and suspendedMode":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    let termId = termBuf.id
    # Only-tab case: after prune the window has no sibling to switch to.
    e.activeWindow.bufferIds = @[termId]
    e.activeWindow.setTab(termBuf)
    e.activeWindow.viewerEntry = some(
      ViewerEntry(
        mode: EditorMode.BufferManager,
        placement: vpInPlace,
        returnMode: EditorMode.Normal,
        bufferId: termId,
        originCursor: BufferPosition(line: 0, column: 0),
        originTopLine: 0,
        originTopWrapOffset: 0,
        originLeftColumn: 0,
      )
    )
    e.activeWindow.suspendedMode =
      some(SuspendedMode(mode: EditorMode.Filer, modeState: ModeState(kind: mskNone)))

    e.closeTerminalBuffer(termId)

    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.suspendedMode.isNone
    check e.state.mode == EditorMode.Normal
    check not e.terminalStates.hasKey(termId)

  test "BufferManager delete of a Terminal tears down the PTY session":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termState = safeOpenFakeTerminalState()
    let termBuf = registerFakeTerminal(e, "bash", termState)
    let termId = termBuf.id
    require e.terminalStates.hasKey(termId)
    require not termState.pty.closed
    require e.buffers.len >= 2

    var termIdx = -1
    for i, buf in e.buffers:
      if buf.id == termId:
        termIdx = i
        break
    require termIdx >= 0

    let r = HandlerResult(kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: termIdx)
    discard e.processResult(r, textBuf)

    check not e.terminalStates.hasKey(termId)
    check e.bufferById(termId).isNone
    check termState.pty.closed

  test "BufferManager overlay survives delete of its origin Terminal tab":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termState = safeOpenFakeTerminalState()
    let termBuf = registerFakeTerminal(e, "bash", termState)
    let termId = termBuf.id
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
    require e.activeWindow.tabBufferId == termId
    require e.activeWindow.modeState.kind == mskBufferManager
    var termIdx = -1
    for i, buf in e.buffers:
      if buf.id == termId:
        termIdx = i
        break
    require termIdx >= 0

    let r = HandlerResult(kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: termIdx)
    discard e.processResult(r, textBuf)

    check not e.terminalStates.hasKey(termId)
    check termState.pty.closed
    check e.activeWindow.modeState.kind == mskBufferManager
    check e.activeWindow.viewerEntry.isSome

  test "closing a per-window-only Terminal tab adopts a global survivor":
    let e = createTestEditor()
    let textId = e.buffers[0].id
    let termBuf = registerFakeTerminal(e, "bash")
    let termId = termBuf.id
    e.activeWindow.bufferIds = @[termId]
    e.activeWindow.setTab(termBuf)

    e.closeTerminalBuffer(termId)

    check not e.terminalStates.hasKey(termId)
    check e.bufferById(termId).isNone
    check e.bufferById(textId).isSome
    check e.activeWindow.tabBufferId == textId

  test "leaving the viewer after deleting its origin Terminal tab restores the retabbed survivor":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termState = safeOpenFakeTerminalState()
    let termBuf = registerFakeTerminal(e, "bash", termState)
    let termId = termBuf.id
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
    require e.activeWindow.tabBufferId == termId
    var termIdx = -1
    for i, buf in e.buffers:
      if buf.id == termId:
        termIdx = i
        break
    require termIdx >= 0

    let r = HandlerResult(kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: termIdx)
    discard e.processResult(r, textBuf)
    require e.bufferById(termId).isNone

    e.leaveViewerMode(EditorMode.BufferManager)

    check e.activeWindow.tabBufferId != termId
    check e.activeWindow.buffer.id != termId
    check e.bufferById(e.activeWindow.tabBufferId).isSome

  test "closing a per-window-only Terminal tab onto a live Terminal survivor re-enters Terminal mode":
    let e = createTestEditor()
    let termBuf1 = registerFakeTerminal(e, "bash")
    let termId1 = termBuf1.id
    let termBuf2 = registerFakeTerminal(e, "bash")
    let termId2 = termBuf2.id
    require termId1 != termId2
    e.activeWindow.bufferIds = @[termId1]
    e.activeWindow.setTab(termBuf1)
    e.applyBufferMode(termBuf1)
    require e.state.mode == EditorMode.Terminal

    e.closeTerminalBuffer(termId1)

    check not e.terminalStates.hasKey(termId1)
    check e.bufferById(termId1).isNone
    check e.terminalStates.hasKey(termId2)
    check e.activeWindow.tabBufferId == termId2
    check e.state.mode == EditorMode.Terminal
    check e.activeWindow.modeState.kind == mskTerminal

suite "Terminal tabs - the window's mode follows its tab":
  test ":bd onto a Terminal successor resumes the session":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    require e.activateBuffer(textBuf.id)
    require e.state.mode == EditorMode.Normal

    check e.deleteCurrentBuffer().isOk

    check e.bufferById(textBuf.id).isNone
    checkOnSession(e, e.activeWindow, termBuf)
    check e.state.mode == EditorMode.Terminal

  test "leaving a viewer whose tab was deleted underneath it lands on the Terminal successor":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    require e.activateBuffer(textBuf.id)
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
    let r = HandlerResult(
      kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: e.bufferIndexById(textBuf.id)
    )
    discard e.processResult(r, e.activeBuffer)
    require e.bufferById(textBuf.id).isNone
    require e.activeWindow.modeState.kind == mskBufferManager

    e.leaveViewerMode(EditorMode.BufferManager)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.state.mode == EditorMode.Terminal

  test "leaving a viewer whose Terminal tab was closed underneath it drops Terminal mode":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
    e.closeTerminalBuffer(termBuf.id)
    require e.activeWindow.tabBufferId == textBuf.id
    require e.activeWindow.modeState.kind == mskBufferManager

    e.leaveViewerMode(EditorMode.BufferManager)

    check e.state.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone

  test "closing a viewer opened from Terminal-Normal returns to Terminal-Normal":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    e.runCommand("ls")
    require e.state.mode == EditorMode.BufferManager

    discard e.handleKeyCombo(charKey("q"))

    checkOnSession(e, e.activeWindow, termBuf)
    check e.state.mode == EditorMode.Terminal
    check e.activeWindow.modeState.terminalSubMode == tsmNormal

    discard e.handleKeyCombo(charKey("i"))

    check e.activeWindow.modeState.terminalSubMode == tsmInput
    check e.activeWindow.buffer == termBuf

  test "picking another tab from a viewer over Terminal-Normal leaves the session live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    e.runCommand("ls")
    require e.state.mode == EditorMode.BufferManager

    let r = HandlerResult(
      kind: hrBufferManagerSelectBuffer,
      selectBufferIndex: e.bufferIndexById(textBuf.id),
    )
    discard e.processResult(r, e.activeBuffer)
    require e.activeWindow.tabBufferId == textBuf.id

    require e.activateBuffer(termBuf.id)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.activeWindow.buffer == termBuf

  test "switching tabs while a viewer holds a Terminal-Normal tab leaves the session live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    e.runCommand("ls")
    require e.state.mode == EditorMode.BufferManager

    require e.activateBuffer(textBuf.id)

    check e.state.mode == EditorMode.Normal

    require e.activateBuffer(termBuf.id)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.activeWindow.buffer == termBuf

  test "a split opened from a Filer over Terminal-Normal leaves the origin window on the session":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    let path = getTempDir() / "moe_test_terminal_tabs_split.txt"
    writeFile(path, "hello\n")
    try:
      discard e.enterNormal()
      e.runCommand("e .")
      require e.state.mode == EditorMode.Filer

      let r = HandlerResult(kind: hrFilerOpenFileVSplit, filerFilePath: path)
      discard e.processResult(r, e.activeBuffer)
      require e.windowManager.windows.len == 2

      var origin: EditorWindow
      for w in e.windowManager.windows:
        if w.tabBufferId == termBuf.id:
          origin = w
      require origin != nil
      checkOnSession(e, origin, termBuf)
    finally:
      removeFile(path)

  test "leaving a viewer over Terminal-Normal whose session was closed underneath it shows the text tab":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    var output = ""
    for i in 1 .. 30:
      output.add "line " & $i & "\r\n"
    e.terminalStates[termBuf.id].grid.processOutput(output)
    let snapshot = e.enterNormal()
    # Deep in the scrollback, past the end of the text tab.
    let deepLine = snapshot.len - 1
    require deepLine >= textBuf.len
    e.activeWindow.cursor = BufferPosition(line: deepLine, column: 0)
    e.activeWindow.viewport.resetViewportTop(deepLine)
    e.runCommand("ls")
    require e.state.mode == EditorMode.BufferManager

    let r = HandlerResult(
      kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: e.bufferIndexById(termBuf.id)
    )
    discard e.processResult(r, e.activeBuffer)
    require e.bufferById(termBuf.id).isNone
    require e.activeWindow.tabBufferId == textBuf.id
    require e.activeWindow.modeState.kind == mskBufferManager

    discard e.handleKeyCombo(charKey("q"))

    check e.state.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.buffer == textBuf
    check e.activeWindow.cursor.line < textBuf.len
    check e.activeWindow.viewport.topLine < textBuf.len

  test "a jump out of a viewer over Terminal-Normal whose session was closed lands on the text tab":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.enterNormal()
    e.runCommand("e .")
    require e.state.mode == EditorMode.Filer
    e.closeTerminalBuffer(termBuf.id)
    require e.activeWindow.tabBufferId == textBuf.id

    # What an Enter on a file that then fails to open leaves behind.
    discard e.leaveViewerModeForJump(EditorMode.Filer)

    check e.state.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.buffer == textBuf
    check e.activeWindow.cursor.line < textBuf.len

  test "closing a window in Terminal-Normal leaves the session live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    require e.activateBuffer(textBuf.id)
    require e.vsplit().isOk
    require e.activateBuffer(termBuf.id)
    discard e.enterNormal()
    require e.activeWindow.modeState.terminalSubMode == tsmNormal

    require not e.closeWindow()
    require e.activeWindow.tabBufferId == textBuf.id

    require e.activateBuffer(termBuf.id)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.activeWindow.buffer == termBuf

  test ":only closing a window in Terminal-Normal leaves the session live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    require e.activateBuffer(textBuf.id)
    require e.vsplit().isOk
    require e.activateBuffer(termBuf.id)
    discard e.enterNormal()
    require e.activeWindow.modeState.terminalSubMode == tsmNormal
    for i, w in e.windowManager.windows:
      if w.tabBufferId == textBuf.id:
        e.windowManager.activateWindow(i)
    e.syncActiveWindow()
    require e.activeWindow.tabBufferId == textBuf.id

    discard e.processResult(HandlerResult(kind: hrOnlyWindow), e.activeBuffer)
    require e.windowManager.windows.len == 1

    require e.activateBuffer(termBuf.id)

    checkOnSession(e, e.activeWindow, termBuf)
    check e.activeWindow.buffer == termBuf

  test ":bd in a split viewer onto a Terminal successor ends the viewer":
    let e = createTestEditor()
    let termBuf = registerFakeTerminal(e, "bash")
    discard e.processResult(HandlerResult(kind: hrEnterHelpViewer), e.activeBuffer)
    let helpWin = e.activeWindow
    require helpWin.viewerEntry.isSome

    check e.deleteCurrentBuffer().isOk

    check helpWin.viewerEntry.isNone
    checkOnSession(e, helpWin, termBuf)
    check not e.focusExistingViewerWindow(EditorMode.Help)

    # A leftover split entry would close this window instead.
    let windowCount = e.windowManager.windows.len
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )

    check e.windowManager.windows.len == windowCount
    check e.activeWindow == helpWin

suite "Terminal tabs - browsing belongs to the window":
  test "browsing in one window leaves another window on the session live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    let (live, browsing) = e.twoWindowsOnSession(textBuf, termBuf)
    discard e.enterNormal()
    require browsing.modeState.terminalSubMode == tsmNormal

    checkOnSession(e, live, termBuf)
    check live.modeState.terminalSubMode == tsmInput

    require e.activateBuffer(textBuf.id)
    e.focusWindow(live)

    checkOnSession(e, live, termBuf)
    check live.modeState.terminalSubMode == tsmInput

  test "leaving a session another window browses keeps that browsing":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    let (live, browsing) = e.twoWindowsOnSession(textBuf, termBuf)
    let snapshot = e.enterNormal()
    e.focusWindow(live)

    require e.activateBuffer(textBuf.id)

    checkOnSession(e, browsing, termBuf)
    check browsing.buffer == snapshot

  test "closing a viewer while another window browses the session resumes live":
    let e = createTestEditor()
    let textBuf = e.buffers[0]
    let termBuf = registerFakeTerminal(e, "bash")
    let (covered, browsing) = e.twoWindowsOnSession(textBuf, termBuf)
    e.focusWindow(covered)
    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer)
    require covered.mode == EditorMode.BufferManager
    e.focusWindow(browsing)
    discard e.enterNormal()
    e.focusWindow(covered)

    discard e.handleKeyCombo(charKey("q"))

    checkOnSession(e, covered, termBuf)
    check covered.modeState.terminalSubMode == tsmInput
