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

proc flushWrites(state: TerminalState, budget: var int) =
  ## Push the queue a little further, spending `budget` - what one poll may
  ## write in total, across all the flushes it makes.
  if budget <= 0:
    return
  let pending = state.pty.pendingWriteBytes
  let flushResult = state.pty.flushWrites(budget)
  budget -= pending - state.pty.pendingWriteBytes
  if flushResult.isErr:
    logError "terminal", flushResult.error

proc flushWrites*(state: TerminalState) =
  ## Push the queue a little further on a budget of its own, for the callers
  ## outside a poll.
  var budget = maxPtyWriteBytesPerFlush
  state.flushWrites(budget)

proc queueBytes(state: TerminalState, data: string): bool {.discardable.} =
  ## Queue bytes for the child. Returns whether they were queued.
  let writeResult = state.pty.queueWrite(data)
  if writeResult.isErr:
    logError "terminal", writeResult.error
    return false
  true

proc feedInput*(state: TerminalState, data: string) =
  ## Queue raw bytes for the child (keystrokes) and push what we can now.
  if state.pty.closed:
    return
  state.queueBytes(data)
  state.flushWrites()

proc flushPendingResponses(
    state: TerminalState, budget: var int
): bool {.discardable.} =
  ## Queue any pending terminal query responses back to the PTY, ahead of the
  ## droppable bytes already queued. Returns false if one was refused; it and
  ## the answers after it stay queued, since the child pairs answers with its
  ## queries by order.
  if state.pty.closed:
    return true
  if state.pty.writeFailed:
    # Nothing can reach the child any more, so stop retrying these forever.
    state.grid.clearPendingResponses()
    state.responseFlushBlocked = false
    return true

  var sent = 0
  result = true
  for response in state.grid.pendingResponses:
    # The queue takes an answer whole or not at all, so a refusal leaves the
    # child owed all of it and there is no prefix to account for.
    let queued = state.pty.queueResponse(response)
    if queued.isErr:
      if not state.responseFlushBlocked:
        logError "terminal", queued.error
        state.responseFlushBlocked = true
      result = false
      break
    sent.inc
  state.grid.dropSentResponses(sent)
  if sent > 0:
    state.flushWrites(budget)
  if result:
    state.responseFlushBlocked = false

proc pollOutput*(state: TerminalState): bool =
  ## Drain the PTY through the ANSI parser (up to maxPtyReadBytesPerPoll
  ## bytes; remainder drains next tick). Returns true if the grid changed.
  if state.pty.closed:
    return false

  var writeBudget = maxPtyWriteBytesPerFlush
  state.flushWrites(writeBudget)

  # Answers kept by a failed flush are only sent from here: a child waiting on
  # them produces no output to drive a flush.
  var flushBlocked = false
  if state.grid.pendingResponses.len > 0:
    flushBlocked = not state.flushPendingResponses(writeBudget)

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
      flushBlocked = not state.flushPendingResponses(writeBudget)

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

      state.flushPendingResponses(writeBudget)
      state.exitCode = code
      state.needsBufferRefresh = true
      return true

  false

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

proc interrupt*(state: TerminalState) =
  ## Ctrl-C: drop what the interrupt is allowed to drop, then send it.
  state.pty.cancelDroppable()
  state.sendInput("\x03")

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
