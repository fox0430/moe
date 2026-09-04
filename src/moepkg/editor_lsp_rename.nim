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

## LSP rename: request the edit, give every file it touches a buffer and apply
## it there. Nothing is written to disk; the targets are left as modified
## buffers to save with `:w`/`:wa`.
##
## Split out of `editor_lsp` because `initLoadedBuffer` lives above it in the
## import graph.

import std/[options, sets, tables]

import pkg/[chronos, results]

import
  types/editor_types,
  editor_lsp,
  editor_navigation,
  editor_buffers,
  lsp_integration,
  lsp_service,
  buffer,
  logger,
  message_log

proc closeRenameTargets(e: Editor, ids: seq[BufferId]) =
  ## Drop the buffers `openRenameTargets` created. They were never shown nor
  ## written, so closing them discards a half-applied edit.
  for id in ids:
    let idx = e.bufferIndexById(id)
    if idx >= 0:
      e.deleteBufferAt(idx)

proc openRenameTargets(e: Editor, edit: WorkspaceEdit): Result[seq[BufferId], string] =
  ## Give every file the rename touches a buffer, and return the ids of the ones
  ## opened here. `applyWorkspaceEdit` only edits open buffers, so this is what
  ## lets a rename reach a file the user has not opened.
  ##
  ## Every target must be editable before the first one changes: a target that
  ## will not load closes what was opened so far and refuses the rename.
  let rejectReason = staticRejectionReason(edit)
  if rejectReason.isSome:
    return err(sanitizeForLog(rejectReason.get) & "; no edits applied")

  var preexisting = initHashSet[BufferId]()
  for buf in e.buffers:
    preexisting.incl(buf.id)

  var opened: seq[BufferId] = @[]
  for path in collectWorkspaceEditPaths(edit):
    let bufRes = e.openFileInBackground(path)
    if bufRes.isErr:
      e.closeRenameTargets(opened)
      return err(
        "Failed to open " & sanitizeForLog(path) & ": " & sanitizeForLog(bufRes.error) &
          "; no edits applied"
      )
    let id = bufRes.get.id
    if id notin preexisting and id notin opened:
      opened.add(id)

  ok(opened)

proc requestLspRename*(
    e: Editor, newName: string
): Future[void] {.async: (raises: []).} =
  ## Request LSP rename and apply workspace edits
  {.cast(gcsafe).}:
    try:
      if not e.lsp.enabled:
        e.state.statusMessage = "LSP not enabled"
        return

      if not e.config.lsp.rename.enable:
        e.state.statusMessage = "LSP rename is disabled"
        return

      let activeBuffer = e.activeBuffer()
      let line = e.state.renameState.cursorLine
      let col = e.state.renameState.cursorColumn

      # The server positions its edits against this state, so a target that
      # changes during the await makes the whole edit unusable.
      # Keyed by buffer id, not path: two buffers can share a path.
      var versionSnapshot: Table[BufferId, int]
      for buf in e.buffers:
        versionSnapshot[buf.id] = buf.contentVersion

      let renameResult = await e.lsp.requestRename(activeBuffer, line, col, newName)
      if renameResult.isErr:
        let msg = "LSP rename failed: " & sanitizeForLog(renameResult.error)
        e.state.statusMessage = msg
        logInfo("lsp", msg)
        addLspMessageLog(msg)
        return

      let workspaceEditOpt = renameResult.get
      if workspaceEditOpt.isNone:
        e.state.statusMessage = "No rename changes"
        return

      let workspaceEdit = workspaceEditOpt.get

      # Also rejects a target opened during the await: no snapshot entry.
      if hasStaleTargetBuffer(e.buffers, workspaceEdit, versionSnapshot):
        e.state.statusMessage = "Buffer changed during rename; edits discarded"
        return

      # Nothing on screen moves: the new buffers join no window.
      let openedRes = e.openRenameTargets(workspaceEdit)
      if openedRes.isErr:
        let msg = "Failed to apply rename: " & openedRes.error
        e.state.statusMessage = msg
        logInfo("lsp", msg)
        addLspMessageLog(msg)
        return
      let openedIds = openedRes.get

      let applyResult = applyWorkspaceEdit(e.buffers, workspaceEdit)
      if applyResult.isErr:
        e.closeRenameTargets(openedIds)
        # Pre-existing buffers keep what a half-applied edit did to them, so
        # re-sync them after the drop above (the dropped ones are not resent).
        e.recoverFromFailedWorkspaceEdit(workspaceEdit, applyResult.error, "rename")
        let msg = "Failed to apply rename: " & sanitizeForLog(applyResult.error)
        e.state.statusMessage = msg
        logInfo("lsp", msg)
        addLspMessageLog(msg)
        return

      # maybeUpdateLsp only covers the active buffer.
      for bufferIdx in applyResult.get.modifiedBufferIndexes:
        e.syncBufferAfterEdit(e.buffers[bufferIdx], "rename")

      # A rename can shrink a buffer shown in an inactive window.
      e.clampAllWindowCursors()

      let modifiedCount = applyResult.get.modifiedCount
      var renameMsg =
        "Renamed '" & sanitizeForLog(e.state.renameState.originalWord) & "' to '" &
        sanitizeForLog(newName) & "' (" & $modifiedCount & " file" &
        (if modifiedCount > 1: "s" else: "") & " modified)"
      renameMsg &= e.buildModifiedPathSuffix(applyResult.get)
      if modifiedCount > 0:
        renameMsg &= " (not written; :wa to save)"
      logInfo("lsp", renameMsg)
      addLspMessageLog(renameMsg)
      e.state.statusMessage = renameMsg
    except CancelledError:
      discard
    except TransactionRollbackError as err:
      # asyncSpawn only logs future failures, so report this state here.
      logError "lsp", "Rename aborted, buffer state untrustworthy: " & err.msg
      e.state.statusMessage = "LSP rename error: buffer state may be inconsistent"
    except Exception as err:
      e.state.statusMessage = "LSP rename error: " & sanitizeForLog(err.msg)
