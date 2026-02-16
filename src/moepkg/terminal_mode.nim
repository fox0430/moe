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

## Terminal mode state management.
## Integrates PTY handle with ANSI parser grid and manages sub-modes.

import std/options

import pkg/results

import terminal/[pty, ansi_parser]
import buffer

type
  TerminalSubMode* = enum
    tsmInput # All keystrokes forwarded to PTY (default)
    tsmNormal # Vim-like scrollback navigation

  TerminalState* = ref object
    pty*: PtyHandle
    grid*: TerminalGrid
    subMode*: TerminalSubMode
    originalBuffer*: TextBuffer
    scrollbackSnapshot*: TextBuffer # Snapshot for Terminal-Normal mode
    command*: string
    exitCode*: Option[int]
    waitingForCtrlN*: bool # Waiting for Ctrl-N after Ctrl-\
    needsBufferRefresh*: bool

proc newTerminalState*(
    command: string = "", cols: int = 80, rows: int = 24
): Result[TerminalState, string] =
  ## Create a new terminal state: open PTY, spawn shell, initialize grid.
  let ptyResult = openPtyAndSpawn(command, cols, rows)
  if ptyResult.isErr:
    return err(ptyResult.error)

  let state = TerminalState(
    pty: ptyResult.get,
    grid: newTerminalGrid(cols, rows),
    subMode: tsmInput,
    originalBuffer: nil,
    scrollbackSnapshot: nil,
    command: command,
    exitCode: none(int),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

  ok(state)

proc pollOutput*(state: TerminalState): bool =
  ## Non-blocking read from PTY and process through ANSI parser.
  ## Returns true if the grid was updated.
  if state.pty.closed:
    return false

  let data = state.pty.readFromPty()
  if data.len > 0:
    state.grid.processOutput(data)
    state.needsBufferRefresh = true
    return true

  # Check if process exited (use checkExitStatus which reaps and stores in one call)
  if state.exitCode.isNone:
    let code = state.pty.checkExitStatus()
    if code.isSome:
      # Drain remaining output
      var remaining = state.pty.readFromPty()
      while remaining.len > 0:
        state.grid.processOutput(remaining)
        remaining = state.pty.readFromPty()

      state.exitCode = code
      state.needsBufferRefresh = true
      return true

  false

proc feedInput*(state: TerminalState, data: string) =
  ## Forward raw bytes to the PTY (keystrokes).
  if not state.pty.closed:
    discard state.pty.writeToPty(data)

proc enterNormalSubMode*(state: TerminalState): TextBuffer =
  ## Switch to Terminal-Normal sub-mode.
  ## Creates a snapshot of the grid as a TextBuffer for scrollback browsing.
  state.subMode = tsmNormal
  let plainText = state.grid.toPlainText()
  state.scrollbackSnapshot = newTextBuffer(plainText)
  state.scrollbackSnapshot.readOnly = true
  state.scrollbackSnapshot

proc exitNormalSubMode*(state: TerminalState) =
  ## Return to Terminal-Input sub-mode.
  state.subMode = tsmInput
  state.scrollbackSnapshot = nil

proc resize*(state: TerminalState, cols, rows: int) =
  ## Resize the terminal grid and notify the PTY.
  state.grid.resize(cols, rows)
  state.pty.resizePty(cols, rows)

proc cleanup*(state: TerminalState) =
  ## Close PTY and release resources.
  if not state.pty.closed:
    state.pty.closePty()
