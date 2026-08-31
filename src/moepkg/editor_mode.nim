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

## Configuration-driven editor mode policy.

import std/[monotimes, options, times]

import pkg/results

import types/editor_types, buffer
import command_handlers/mode_dispatchers

func forceInsertMode(e: Editor): bool =
  not e.isNil and not e.config.isNil and e.config.standard.forceInsertMode

func canForceInsertMode(e: Editor): bool =
  e.forceInsertMode and e.state.overlay.isNone and not e.activeBuffer.readOnly

func effectiveMode*(e: Editor, requestedMode: EditorMode): EditorMode =
  ## Resolve a requested mode through the configured editing policy.
  if e.canForceInsertMode and requestedMode == EditorMode.Normal:
    EditorMode.Insert
  else:
    requestedMode

proc clearInsertSessionTracking(e: Editor) =
  e.state.editState.insertModeStartPos = none(BufferPosition)
  e.state.editState.insertReplayCount = 0
  e.state.editState.insertReplayLineEntry = false
  e.state.editState.visualBlockInsertContext = none(types.VisualBlockInsertContext)
  e.state.editState.substituteContext = none(types.SubstituteContext)

proc enforceModePolicy*(e: Editor) =
  ## Keep an editable window in a valid Insert session when Normal mode is disabled.
  if not e.forceInsertMode or e.state.overlay.isSome:
    return

  if e.activeBuffer.readOnly:
    if e.currentMode == EditorMode.Insert:
      if e.activeBuffer.inTransaction:
        let commitResult = e.activeBuffer.commitTransaction()
        if commitResult.isErr:
          e.state.statusMessage = "Failed to commit transaction: " & commitResult.error
      e.clearInsertSessionTracking()
      e.setMode(EditorMode.Normal)
    return

  if e.currentMode notin {EditorMode.Normal, EditorMode.Insert}:
    return

  let transactionResult = beginInsertModeSession(e.activeBuffer, e.state)
  if transactionResult.isErr:
    e.state.statusMessage = "Failed to begin transaction: " & transactionResult.error
    return

  if e.currentMode == EditorMode.Normal:
    e.setMode(EditorMode.Insert)

proc commitForcedInsertBoundary*(
    e: Editor, restart: bool = true
): Result[void, string] =
  ## Commit the active forced-Insert transaction for undo/save boundaries.
  if not e.forceInsertMode or e.currentMode != EditorMode.Insert or
      e.activeBuffer.readOnly:
    return ok()

  let commitResult =
    if e.state.editState.visualBlockInsertContext.isSome:
      let finalizeResult = finalizeInsertExit(e.activeBuffer, e.state)
      if finalizeResult.isErr:
        err(finalizeResult.error)
      else:
        ok()
    else:
      commitInsertModeBoundary(e.activeBuffer, e.state)
  if commitResult.isErr:
    return err(commitResult.error)

  if restart:
    let beginResult = beginInsertModeSession(e.activeBuffer, e.state)
    if beginResult.isErr:
      return err("Failed to begin transaction: " & beginResult.error)

  ok()

proc tickForcedInsertBoundary*(e: Editor) =
  ## End a typing undo group after a short idle period, then keep Insert active.
  const UndoIdleMilliseconds = 500

  if not e.canForceInsertMode or e.currentMode != EditorMode.Insert or
      not e.activeBuffer.inTransaction or e.activeBuffer.currentTransaction.isNone or
      e.activeBuffer.currentTransaction.get.changes.len == 0 or
      e.state.editState.visualBlockInsertContext.isSome:
    return

  let idle = getMonoTime() - e.state.timing.lastInputTime
  if idle.inMilliseconds < UndoIdleMilliseconds:
    return

  let boundaryResult = e.commitForcedInsertBoundary()
  if boundaryResult.isErr:
    e.state.statusMessage = boundaryResult.error
