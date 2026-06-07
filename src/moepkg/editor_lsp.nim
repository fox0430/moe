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

## LSP-related procedures for the editor

import std/[options, json]

import pkg/results

import editor_types, lsp_integration
import command_handlers/[handler_manager, insert_handler]

proc maybeUpdateLsp*(e: Editor) =
  ## Update LSP if buffer was modified
  ## This notifies the LSP server of document changes for real-time diagnostics
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()

  # Only notify LSP if this buffer has changed since its last notification
  if activeBuffer.changeSeq != e.lastLspChangeSeqs.getOrDefault(activeBuffer.id, 0):
    let lspResult = e.lsp.onBufferChange(activeBuffer)
    if lspResult.isOk:
      e.lastLspChangeSeqs[activeBuffer.id] = activeBuffer.changeSeq

proc pollLspCompletion*(e: Editor) =
  ## Poll for pending LSP completion responses
  ## This should be called from the main event loop
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  # Call the insert handler's poll function
  e.handlerManager.insertHandler.pollLspCompletion()
  e.handlerManager.insertHandler.pollLspResolve()

proc requestLspFormat*(e: Editor): Future[bool] {.async: (raises: [CancelledError]).} =
  ## Request LSP document formatting and apply edits
  ## Returns true if successful
  {.cast(gcsafe).}:
    try:
      if not e.lsp.enabled:
        e.state.statusMessage = "LSP not enabled"
        return false

      let activeBuffer = e.activeBuffer()

      # Get formatting result from LSP
      let formatResult = await e.lsp.requestFormatting(activeBuffer)
      if formatResult.isErr:
        e.state.statusMessage = "LSP format failed: " & formatResult.error
        return false

      let edits = formatResult.get
      if edits.len == 0:
        e.state.statusMessage = "No formatting changes"
        return true

      # Apply the text edits to the buffer
      let applyResult = applyTextEdits(activeBuffer, edits)
      if applyResult.isErr:
        e.state.statusMessage = "Failed to apply edits: " & applyResult.error
        return false

      e.state.statusMessage =
        "Formatted (" & $edits.len & " edit" & (if edits.len > 1: "s" else: "") & ")"
      e.state.windowDisplay.needsFullRedraw = true
      return true
    except CancelledError as err:
      raise err
    except Exception as err:
      e.state.statusMessage = "LSP format error: " & err.msg
      return false

proc refreshLspFolds*(e: Editor): Future[void] {.async: (raises: []).} =
  ## Request LSP folding ranges and update buffer fold markers
  try:
    if not e.lsp.enabled:
      e.state.statusMessage = "LSP not enabled"
      return

    let activeBuffer = e.activeBuffer()

    # Use lsp_integration's refreshLspFolds
    let foldResult = await lsp_integration.refreshLspFolds(e.lsp, activeBuffer)
    if foldResult.isErr:
      e.state.statusMessage = "LSP fold failed: " & foldResult.error
      return

    e.state.statusMessage = "Updated fold markers"
    e.state.windowDisplay.needsFullRedraw = true
  except CancelledError:
    discard

proc requestLspRename*(
    e: Editor, newName: string
): Future[void] {.async: (raises: []).} =
  ## Request LSP rename and apply workspace edits
  {.cast(gcsafe).}:
    try:
      if not e.lsp.enabled:
        e.state.statusMessage = "LSP not enabled"
        return

      let activeBuffer = e.activeBuffer()
      let line = e.state.renameState.cursorLine
      let col = e.state.renameState.cursorColumn

      # Get rename result from LSP
      let renameResult = await e.lsp.requestRename(activeBuffer, line, col, newName)
      if renameResult.isErr:
        e.state.statusMessage = "LSP rename failed: " & renameResult.error
        return

      let workspaceEditOpt = renameResult.get
      if workspaceEditOpt.isNone:
        e.state.statusMessage = "No rename changes"
        return

      let workspaceEdit = workspaceEditOpt.get

      # Apply the workspace edits to all affected buffers
      let applyResult = applyWorkspaceEdit(e.buffers, workspaceEdit)
      if applyResult.isErr:
        e.state.statusMessage = "Failed to apply rename: " & applyResult.error
        return

      let modifiedCount = applyResult.get
      e.state.statusMessage =
        "Renamed '" & e.state.renameState.originalWord & "' to '" & newName & "' (" &
        $modifiedCount & " file" & (if modifiedCount > 1: "s" else: "") & " modified)"
      e.state.windowDisplay.needsFullRedraw = true
    except CancelledError:
      discard
    except Exception as err:
      e.state.statusMessage = "LSP rename error: " & err.msg

proc restartLspServer*(e: Editor): bool =
  ## Restart LSP server for the current buffer's language
  ## This will start the server even if it was not running
  ## Returns true if successful
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.state.statusMessage = "No file path for current buffer"
    return false

  let langIdOpt = e.lsp.service.getLanguageIdFromPath(activeBuffer.filePath.get)
  if langIdOpt.isNone:
    e.state.statusMessage = "No LSP support for this file type"
    return false

  let langId = langIdOpt.get

  # Stop the worker if it exists. Stopping a not-yet-running server is benign,
  # so keep this quiet (LSP log only) rather than surfacing to the status line.
  let stopResult = e.lsp.service.stopWorker(langId)
  if stopResult.isErr:
    logLspDegraded("restart: stop " & langId, stopResult.error)

  # Start the worker
  let startResult = e.lsp.service.startWorker(langId)
  if startResult.isErr:
    e.state.statusMessage = "Failed to start LSP server: " & startResult.error
    return false

  # Re-notify about open buffers for this language. A re-open failure leaves that
  # buffer untracked by the server, so surface it: the user explicitly requested
  # the restart and otherwise has no way to know the feature silently degraded.
  var renotifyFailures = 0
  for buf in e.buffers:
    if buf.filePath.isSome:
      let bufLangIdOpt = e.lsp.service.getLanguageIdFromPath(buf.filePath.get)
      if bufLangIdOpt.isSome and bufLangIdOpt.get == langId:
        let openResult = e.lsp.onBufferOpen(buf)
        if openResult.isErr:
          inc renotifyFailures
          logLspDegraded("restart: re-open " & buf.filePath.get, openResult.error)

  if renotifyFailures > 0:
    e.state.statusMessage =
      "Restarted LSP server for " & langId & " (" & $renotifyFailures &
      " buffer(s) failed to re-open; see LSP log)"
  else:
    e.state.statusMessage = "Restarted LSP server for " & langId
  return true

proc requestLspExecuteCommand*(
    e: Editor, command: string, args: seq[string] = @[]
): Future[void] {.async: (raises: []).} =
  ## Execute an LSP workspace command
  {.cast(gcsafe).}:
    try:
      if not e.lsp.enabled:
        e.state.statusMessage = "LSP not enabled"
        return

      let activeBuffer = e.activeBuffer()

      # Check if execute command is supported
      if not e.lsp.hasExecuteCommandSupport(activeBuffer):
        e.state.statusMessage = "Execute command not supported by LSP server"
        return

      # Convert string arguments to JSON
      var jsonArgs: seq[JsonNode] = @[]
      for arg in args:
        jsonArgs.add(%arg)

      # Execute the command
      let execResult =
        await e.lsp.requestExecuteCommand(activeBuffer, command, jsonArgs)
      if execResult.isErr:
        e.state.statusMessage = "LSP executeCommand failed: " & execResult.error
        return

      let response = execResult.get
      if response.kind == JNull:
        e.state.statusMessage = "Executed: " & command
      else:
        e.state.statusMessage = "Executed: " & command & " -> " & $response
    except CancelledError:
      discard
    except Exception as err:
      e.state.statusMessage = "LSP executeCommand error: " & err.msg
