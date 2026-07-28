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

## Tests for pollTerminalWindows: one terminal exiting must not skip the
## remaining terminal windows' pollOutput in the same frame.

import std/[unittest, options, posix, tables]

import ../src/moe {.all.}
import ../src/moepkg/[editor, config, types, modes]
import ../src/moepkg/terminal/[pty, ansi_parser]
import ../src/moepkg/buffer/core

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)
  result.syncActiveWindow()

proc exitedTerminalState(): TerminalState =
  ## Fake TerminalState whose PTY is pre-closed and whose shell already exited.
  ## `pollOutput` short-circuits on a closed PTY, so pollTerminalWindows
  ## observes the pre-set `exitCode` and triggers closeTerminalBuffer without
  ## going through a real PTY.
  TerminalState(
    pty: PtyHandle(masterFd: -1, childPid: Pid(0), closed: true),
    grid: newTerminalGrid(80, 24),
    subMode: tsmInput,
    exitCode: some(0),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

proc registerExitedTerminalInWindow(
    e: Editor, window: EditorWindow, command: string
): TextBuffer =
  ## Attach a pre-exited terminal buffer to `window` and register it in
  ## `e.terminalStates`, mirroring the state pollTerminalWindows sees when a
  ## shell has just quit.
  result = newTextBuffer("")
  result.displayName = some("[Terminal: " & command & "]")
  e.addBuffer(result)
  window.bufferIds.add(result.id)
  e.terminalStates[result.id] = exitedTerminalState()
  window.buffer = result
  window.modeState = ModeState(kind: mskTerminal, terminal: e.terminalStates[result.id])
  window.mode = EditorMode.Terminal

proc addSecondWindow(e: Editor): EditorWindow =
  ## Add a second window sharing the first window's viewport dimensions so
  ## `calculateTerminalAreaDimensions` returns positive values for both.
  let first = e.windowManager.windows[0]
  result = EditorWindow(
    buffer: first.buffer,
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

suite "pollTerminalWindows - multi-window regression":
  test "One terminal exit does not skip a second terminal's teardown":
    ## Regression for the `return`-inside-the-loop bug. When two windows are
    ## each showing a Terminal buffer and both shells have exited by the time
    ## pollTerminalWindows runs, both must be torn down in this frame — not
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

    e.pollTerminalWindows()

    # Both terminals must be torn down. With the previous `return`, only the
    # first would be, and t2's state would linger until the next frame.
    check not e.terminalStates.hasKey(t1Id)
    check not e.terminalStates.hasKey(t2Id)
    check w1.mode != EditorMode.Terminal
    check w2.mode != EditorMode.Terminal
