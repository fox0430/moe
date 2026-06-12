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

import std/[options, json, os]

import pkg/results

import types/editor_types, lsp_integration
import command_handlers/[handler_manager, insert_handler]

proc applyDiagnosticsForUri*(e: Editor, uri: string, diagnostics: seq[Diagnostic]) =
  ## Route a server's publishDiagnostics to the buffer it targets, not just
  ## the active one. Diagnostics for a background buffer would otherwise be
  ## dropped, and the server does not resend them when that buffer is later
  ## focused.
  ## Diagnostics are server-push: there is no request to suppress, so the
  ## Lsp.Diagnostics.enable gate drops them here on receipt instead.
  if not e.config.lsp.diagnostics.enable:
    return

  let path = uriToPath(uri).absolutePath()
  for buf in e.buffers:
    if buf.filePath.isSome and buf.filePath.get.absolutePath() == path:
      applyDiagnosticsToBuffer(buf, diagnostics)
      e.state.windowDisplay.needsFullRedraw = true
      return
  # No matching open buffer: drop. The server only publishes for documents
  # we opened (didOpen), so this is the closed-in-the-meantime case.

proc clearAllDiagnostics*(e: Editor) =
  ## Drop stored diagnostics and their line markers from every buffer.
  ## Used when Lsp.Diagnostics is disabled on a config reload: the server
  ## keeps pushing (and applyDiagnosticsForUri keeps dropping), but what was
  ## already applied has to be removed explicitly.
  for buf in e.buffers:
    applyDiagnosticsToBuffer(buf, @[])
  e.state.windowDisplay.needsFullRedraw = true

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

      if not e.config.lsp.documentFormatting.enable:
        e.state.statusMessage = "LSP document formatting is disabled"
        return false

      let activeBuffer = e.activeBuffer()
      # Snapshot the buffer state before awaiting: the server's edits are
      # positioned against this state and must not be applied if the user
      # typed while the request was in flight
      let seqBeforeRequest = activeBuffer.changeSeq

      # Get formatting result from LSP
      let formatResult = await e.lsp.requestFormatting(activeBuffer)
      if formatResult.isErr:
        e.state.statusMessage = "LSP format failed: " & formatResult.error
        return false

      let edits = formatResult.get
      if edits.len == 0:
        e.state.statusMessage = "No formatting changes"
        return true

      if activeBuffer.changeSeq != seqBeforeRequest:
        e.state.statusMessage = "Buffer changed during format; edits discarded"
        return false

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
  ## Request LSP folding ranges and fold the buffer (LSP "fold all").
  ## Manual folds are preserved. When folding is disabled or unsupported the
  ## existing folds are left untouched. If the cursor ends up inside a freshly
  ## collapsed fold, `prepareFrame` pins it back onto a visible line on the next
  ## render, so this proc does not adjust the cursor itself.
  try:
    if not e.lsp.enabled:
      e.state.statusMessage = "LSP not enabled"
      return
    if not e.config.lsp.foldingRange.enable:
      e.state.statusMessage = "LSP folding range is disabled"
      return

    let activeBuffer = e.activeBuffer()

    # hasFoldingRangeSupport indexes the capability table; guard the lookup so
    # this raises-[] proc stays exception-free.
    let supported =
      try:
        e.lsp.hasFoldingRangeSupport(activeBuffer)
      except KeyError:
        false
    if not supported:
      e.state.statusMessage = "Folding range is not supported by the language server"
      return

    # Add the LSP ranges collapsed (fold-all); manual folds are kept.
    let foldResult =
      await lsp_integration.refreshLspFolds(e.lsp, activeBuffer, startCollapsed = true)
    if foldResult.isErr:
      e.state.statusMessage = "LSP fold failed: " & foldResult.error
      return

    # The cursor may now sit inside a collapsed fold; prepareFrame normalizes it
    # onto a visible line on the next render, so no cursor fix-up is needed here.
    let count = foldResult.get
    e.state.statusMessage =
      if count > 0:
        "Folded " & $count & " region(s)"
      else:
        "No foldable regions"
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

      if not e.config.lsp.rename.enable:
        e.state.statusMessage = "LSP rename is disabled"
        return

      let activeBuffer = e.activeBuffer()
      let line = e.state.renameState.cursorLine
      let col = e.state.renameState.cursorColumn

      # Snapshot every open buffer's changeSeq before awaiting: the
      # server's edits are positioned against this state. If any target
      # buffer changes while the request is in flight, applying the stale
      # coordinates would corrupt text, so the whole edit is discarded
      # (aborting beats partial application).
      # Key by buffer id, not path: two buffers can share a file path (one
      # opened relative, one absolute), and a path-keyed snapshot would let
      # one buffer's changeSeq shadow the other's, rejecting valid renames.
      var seqSnapshot: Table[BufferId, int]
      for buf in e.buffers:
        seqSnapshot[buf.id] = buf.changeSeq

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

      # Reject the edit if any targeted open buffer changed during the await.
      # Compare each buffer against its OWN pre-await changeSeq (keyed by id).
      for path in collectWorkspaceEditPaths(workspaceEdit):
        let absPath = normalizedPath(absolutePath(path))
        for buf in e.buffers:
          if buf.filePath.isSome and
              normalizedPath(absolutePath(buf.filePath.get)) == absPath and
              buf.changeSeq != seqSnapshot.getOrDefault(buf.id, buf.changeSeq):
            e.state.statusMessage = "Buffer changed during rename; edits discarded"
            return

      # Apply the workspace edits to all affected buffers
      let applyResult = applyWorkspaceEdit(e.buffers, workspaceEdit)
      if applyResult.isErr:
        e.state.statusMessage = "Failed to apply rename: " & applyResult.error
        return

      # Sync the server with every buffer we just rewrote. maybeUpdateLsp
      # only covers the active buffer, so non-active buffers would otherwise
      # stay stale on the server side.
      for bufferIdx in applyResult.get.modifiedBufferIndexes:
        let buf = e.buffers[bufferIdx]
        let syncResult = e.lsp.onBufferChange(buf)
        if syncResult.isOk:
          e.lastLspChangeSeqs[buf.id] = buf.changeSeq
        elif buf.filePath.isSome:
          logLspDegraded("rename: didChange " & buf.filePath.get, syncResult.error)

      let modifiedCount = applyResult.get.modifiedCount
      e.state.statusMessage =
        "Renamed '" & e.state.renameState.originalWord & "' to '" & newName & "' (" &
        $modifiedCount & " file" & (if modifiedCount > 1: "s" else: "") & " modified)"
      e.state.windowDisplay.needsFullRedraw = true
    except CancelledError:
      discard
    except Exception as err:
      e.state.statusMessage = "LSP rename error: " & err.msg

proc renotifyOpenBuffers(e: Editor, langId: string): int =
  ## (Re-)send didOpen for every open buffer whose language is `langId` and
  ## return how many failed. Used both by an explicit `:lspRestart` and by the
  ## automatic crash-recovery path: a freshly (re)started server has no open
  ## documents, so without this its diagnostics/completion stay dead.
  for buf in e.buffers:
    if buf.filePath.isSome:
      let bufLangIdOpt = e.lsp.service.getLanguageIdFromPath(buf.filePath.get)
      if bufLangIdOpt.isSome and bufLangIdOpt.get == langId:
        let openResult = e.lsp.onBufferOpen(buf)
        if openResult.isErr:
          inc result
          logLspDegraded("re-open " & buf.filePath.get, openResult.error)

proc onLspServerRestart*(e: Editor, langId: string) =
  ## Crash-recovery hook: a language server re-initialized after crashing, so
  ## the documents it knew about were lost. Re-open them automatically. Without
  ## this the user would have to run `:lspRestart` by hand to get LSP features
  ## back for the affected buffers.
  let failures = e.renotifyOpenBuffers(langId)
  if failures > 0:
    e.state.statusMessage =
      "LSP server for " & langId & " restarted (" & $failures &
      " buffer(s) failed to re-open; see LSP log)"
  else:
    e.state.statusMessage = "LSP server for " & langId & " restarted automatically"

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
  let renotifyFailures = e.renotifyOpenBuffers(langId)

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

      if not e.config.lsp.executeCommand.enable:
        e.state.statusMessage = "LSP execute command is disabled"
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
