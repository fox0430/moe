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

import std/[options, os]

import pkg/results

import terminal/[pty, ansi_parser]
import buffer/core
import logger

import types/terminal_mode_types
export terminal_mode_types

proc newTerminalState*(
    command: string = "", cols: int = 80, rows: int = 24
): Result[TerminalState, string] =
  ## Create a new terminal state: open PTY, spawn shell, initialize grid.
  ##
  ## When a command is given (e.g. `:terminal ls`) it is run first and then the
  ## session hands control to an interactive shell via `exec`, so the terminal
  ## keeps running instead of exiting once the command finishes.
  let spawnCommand =
    if command.len > 0:
      command & "; exec " & getEnv("SHELL", "/bin/sh")
    else:
      ""
  let ptyResult = openPtyAndSpawn(spawnCommand, cols, rows)
  if ptyResult.isErr:
    return err(ptyResult.error)

  let state = TerminalState(
    pty: ptyResult.get,
    grid: newTerminalGrid(cols, rows),
    subMode: tsmInput,
    scrollbackSnapshot: nil,
    exitCode: none(int),
    waitingForCtrlN: false,
    needsBufferRefresh: false,
  )

  ok(state)

proc flushPendingResponses(state: TerminalState): bool {.discardable.} =
  ## Write any pending terminal query responses back to the PTY. Returns false
  ## if one could not be written; what the PTY did not take of it and the
  ## answers after it stay queued.
  if state.pty.closed:
    return true
  var sent = 0
  var consumedOfFailed = 0
  result = true
  for response in state.grid.pendingResponses:
    let (consumed, writeErr) = state.pty.writeToPtyCounted(response)
    if writeErr.len > 0:
      # Stop rather than skip this answer: writeToPty drains the buffer on
      # every call, so a later one could get through and be read as this
      # one's. A failed write can still have handed the child a prefix.
      if not state.responseFlushBlocked:
        logError "terminal", writeErr
        state.responseFlushBlocked = true
      consumedOfFailed = consumed
      result = false
      break
    sent.inc
  state.grid.dropSentResponses(sent)
  state.grid.trimHeadResponse(consumedOfFailed)
  if result:
    state.responseFlushBlocked = false

proc pollOutput*(state: TerminalState): bool =
  ## Drain the PTY through the ANSI parser (up to maxPtyReadBytesPerPoll
  ## bytes; remainder drains next tick). Returns true if the grid changed.
  if state.pty.closed:
    return false

  let drainResult = state.pty.drainWriteBuffer()
  if drainResult.isErr:
    logError "terminal", drainResult.error

  # Answers kept by a failed flush are only sent from here: a child waiting on
  # them produces no output to drive a flush.
  var flushBlocked = false
  if state.grid.pendingResponses.len > 0:
    flushBlocked = not state.flushPendingResponses()

  var updated = false
  var bytesRead = 0
  while bytesRead < maxPtyReadBytesPerPoll:
    let data = state.pty.readFromPty()
    if data.len == 0:
      break
    state.grid.processOutput(data)
    bytesRead += data.len
    updated = true
    # Flush inside the loop: a query flood answered only after the drain would
    # hit MaxPendingResponseBytes and drop answers the child waits on. Once a
    # flush fails nothing frees up within this poll, so stop retrying.
    if not flushBlocked and state.grid.pendingResponses.len > 0:
      flushBlocked = not state.flushPendingResponses()

  if updated:
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

      state.flushPendingResponses()
      state.exitCode = code
      state.needsBufferRefresh = true
      return true

  false

proc feedInput*(state: TerminalState, data: string) =
  ## Forward raw bytes to the PTY (keystrokes).
  if not state.pty.closed:
    let writeResult = state.pty.writeToPty(data)
    if writeResult.isErr:
      logError "terminal", writeResult.error

proc releaseHeldQuit*(state: TerminalState) =
  ## Send the Ctrl-\ that a pending Terminal-Normal switch is holding back.
  if state.waitingForCtrlN:
    state.waitingForCtrlN = false
    state.feedInput(TtyQuitChar)

proc sendInput*(state: TerminalState, data: string) =
  ## Forward keystroke bytes, releasing a held Ctrl-\ ahead of them. Keys the
  ## editor consumes release it too, before dispatch, so the hold never
  ## outlives the keystroke it was pressed for.
  state.releaseHeldQuit()
  if data.len > 0:
    state.feedInput(data)

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
