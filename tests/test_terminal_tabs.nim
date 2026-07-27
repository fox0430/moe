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

import std/[unittest, options, posix, tables]

import ../src/moepkg/[editor, config, types, modes, terminal_mode]
import ../src/moepkg/terminal/[pty, ansi_parser]
import ../src/moepkg/buffer/core
import ../src/moepkg/command_handlers/[handler_result, result_processor]

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
    subMode: tsmInput,
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
    subMode: tsmInput,
    exitCode: none(int),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

proc registerFakeTerminal(
    e: Editor, command: string = "bash", state: TerminalState = nil
): TextBuffer =
  ## Mimic enterTerminalInActiveWindow without touching real PTY plumbing.
  ## `state` defaults to a pre-closed fake (cleanup() is a no-op); pass a
  ## `safeOpenFakeTerminalState()` to exercise teardown.
  result = newTextBuffer("")
  result.displayName = some("[Terminal: " & command & "]")
  e.addBuffer(result)
  e.addBufferToWindowList(result)
  e.terminalStates[result.id] =
    if state != nil:
      state
    else:
      fakeTerminalState()
  e.activeWindow.buffer = result
  e.activeWindow.modeState =
    ModeState(kind: mskTerminal, terminal: e.terminalStates[result.id])
  e.activeWindow.mode = EditorMode.Terminal
  e.setMode(EditorMode.Terminal)

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

    e.deleteCurrentBuffer()

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
