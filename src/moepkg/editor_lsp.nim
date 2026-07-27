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

import std/[options, json, os, algorithm, strutils, tables]

import pkg/[chronos, results]

import types/editor_types, lsp_integration, motion, editor_codelens, lsp_request_context
import command_handlers/[handler_manager, insert_handler]

export lsp_request_context

proc launchAffectingFields(c: LanguageServerConfig): (string, seq[string], string) =
  (c.command, c.args, c.initializationOptions)

proc toWorkerTrace(t: LspTraceLevel): LspTrace =
  ## Translate the config-layer enum to the worker-layer enum. Two enums exist
  ## so config.nim can stay independent of the LSP thread/chronos deps; the
  ## variants are 1:1 by string value.
  case t
  of ltOff: traceOff
  of ltMessages: traceMessages
  of ltVerbose: traceVerbose

proc applyLspServerConfigs*(e: Editor) =
  ## Rebuild the LSP service config table from built-in defaults plus the
  ## per-language [Lsp.<lang>] entries in e.config. Called from newEditor and
  ## from applyConfigSettings so live reload picks up server-command /
  ## trace / rust-analyzer edits including deletions and toggle-offs.
  ## Already-running workers keep their old command until they restart; when
  ## the change affects a running worker, hint the user to `:lspRestart`.
  var runningSnapshot: Table[string, LanguageServerConfig]
  for langId in e.lsp.service.liveWorkerLangIds:
    let cfgOpt = e.lsp.service.getConfig(langId)
    if cfgOpt.isSome:
      runningSnapshot[langId] = cfgOpt.get

  e.lsp.service.resetConfigsToDefaults()
  for langId, serverCfg in e.config.lsp.servers:
    let existing = e.lsp.service.getConfig(langId)
    if existing.isSome:
      var c = existing.get
      if serverCfg.command.len > 0:
        c.command = serverCfg.command
        c.args = @[]
      if serverCfg.extensions.len > 0:
        c.extensions = serverCfg.extensions
      c.traceLevel = toWorkerTrace(serverCfg.trace)
      c.settings = serverCfg.settings
      if langId == "rust":
        c.initializationOptions =
          "{\"lens\":{\"run\":{\"enable\":" & $serverCfg.rustAnalyzerRunSingle &
          "},\"debug\":{\"enable\":" & $serverCfg.rustAnalyzerDebugSingle & "}}}"
      e.lsp.service.setConfig(langId, c)
    elif serverCfg.command.len > 0:
      e.lsp.service.setConfig(
        langId,
        LanguageServerConfig(
          command: serverCfg.command,
          args: @[],
          extensions: serverCfg.extensions,
          enabled: true,
          traceLevel: toWorkerTrace(serverCfg.trace),
          settings: serverCfg.settings,
        ),
      )

  var changed: seq[string]
  for langId, oldCfg in runningSnapshot:
    let newCfgOpt = e.lsp.service.getConfig(langId)
    if newCfgOpt.isNone or
        newCfgOpt.get.launchAffectingFields != oldCfg.launchAffectingFields:
      changed.add(langId)
  if changed.len > 0:
    changed.sort()
    e.state.statusMessage =
      "LSP server config changed for " & changed.join(", ") &
      "; run :lspRestart to apply"

proc applyDiagnosticsForUri*(
    e: Editor, uri: string, diagnostics: seq[Diagnostic], version: Option[int]
) =
  ## Route a server's publishDiagnostics to the buffer it targets, not just
  ## the active one. Diagnostics for a background buffer would otherwise be
  ## dropped, and the server does not resend them when that buffer is later
  ## focused.
  ## Diagnostics are server-push: there is no request to suppress, so the
  ## Lsp.Diagnostics.enable gate drops them here on receipt instead.
  ## When the server tagged the publish with a document version, drop frames
  ## older than the last didChange we sent - avoids applying stale coordinates
  ## across a reload/rapid-edit while an in-flight publish is on the wire.
  if not e.config.lsp.diagnostics.enable:
    return

  let path = normalizedPath(absolutePath(uriToPath(uri)))
  if version.isSome:
    let sent = e.lsp.sentDocumentVersion(path)
    if sent.isSome and version.get < sent.get:
      return
  for buf in e.buffers:
    if buf.filePath.isSome and normalizedPath(absolutePath(buf.filePath.get)) == path:
      applyDiagnosticsToBuffer(buf, diagnostics)
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

proc syncBufferAfterEdit*(e: Editor, buf: TextBuffer, context: string) =
  ## didChange a buffer we just rewrote so the server's copy doesn't go stale.
  ## maybeUpdateLsp only covers the active buffer, so non-active buffers would
  ## otherwise drift on the server side. `context` only tags the degrade log.
  let syncResult = e.lsp.onBufferChange(buf)
  if syncResult.isOk:
    e.lastLspContentVersions[buf.id] = buf.contentVersion
  elif buf.filePath.isSome:
    logLspDegraded(context & ": didChange " & buf.filePath.get, syncResult.error)

proc resyncBufferAfterReload*(e: Editor, buf: TextBuffer) =
  ## Re-publish diagnostics after a reload. A reload drops the buffer's
  ## diagnostics (their positions are stale against the new content), but a plain
  ## didChange is skipped when the reloaded text equals the server's shadow (`:e!`
  ## on a clean buffer, or an external touch that left the bytes unchanged), so
  ## diagnostics would stay gone until the next edit. Re-open the document
  ## (didClose + didOpen) to force a fresh publish regardless of whether the bytes
  ## changed — matching a reload's "re-read from disk" semantics.
  if not e.lsp.enabled or buf.filePath.isNone:
    return
  discard e.lsp.onBufferClose(buf) # best effort; re-opened next regardless
  let openResult = e.lsp.onBufferOpen(buf)
  if openResult.isOk:
    e.lastLspContentVersions[buf.id] = buf.contentVersion
  else:
    logLspDegraded("reload: didOpen " & buf.filePath.get, openResult.error)

proc openBufferWithLsp*(e: Editor, buf: TextBuffer) =
  ## didOpen a freshly registered buffer and record its synced contentVersion so
  ## the next didChange delta is computed against the right baseline. No-op when LSP
  ## is disabled or the buffer has no path (onBufferOpen guards both). Callers
  ## that register a buffer without going through `loadFile` (loadOrCreateBuffer)
  ## must call this, otherwise the server never learns about the document.
  if not e.lsp.enabled:
    return
  let openResult = e.lsp.onBufferOpen(buf)
  if openResult.isOk:
    e.lastLspContentVersions[buf.id] = buf.contentVersion
  elif buf.filePath.isSome:
    logLspDegraded("didOpen " & buf.filePath.get, openResult.error)

proc clampAllWindowCursors*(e: Editor) =
  ## Re-clamp every window's cursor to its buffer's bounds. A server-initiated
  ## workspace edit can rewrite — and shrink — a buffer shown in an inactive
  ## window, leaving its cursor past the new end. Clamping an in-bounds cursor
  ## is a no-op, so this is safe to call broadly.
  for window in e.windowManager.windows:
    let clamped = e.motionController.cursorManager.clampPosition(
      CursorPosition(x: window.cursor.column, y: window.cursor.line), window.buffer
    )
    window.cursor = BufferPosition(line: clamped.y, column: clamped.x)

proc applyWorkspaceEditFromServer*(
    e: Editor, edit: WorkspaceEdit
): ApplyWorkspaceEditResult {.gcsafe.} =
  ## Apply a server-initiated workspace/applyEdit (e.g. a rust-analyzer refactor
  ## delivered through executeCommand). Mirrors the rename flow: reject stale
  ## edits, apply to every affected buffer, then sync each modified buffer back
  ## to the server so it does not go stale. The server blocks on the response,
  ## so every path returns an `applied` verdict.
  ##
  ## After any buffer is rewritten, every window's cursor is re-clamped here (not
  ## by the caller), so a clamp failure can never flip the already-committed
  ## edit's verdict, and a shrinking edit cannot leave a cursor — including in an
  ## inactive split — dangling past the new buffer end.
  ##
  ## cast(gcsafe): applyWorkspaceEdit reaches the undo/redo transaction code,
  ## whose mutual recursion defeats the compiler's gcsafe inference. This runs
  ## only on the main thread (it is a poll()-time callback), so the cast is safe
  ## — the same reasoning the rename flow relies on.
  {.cast(gcsafe).}:
    if not e.lsp.enabled:
      return (applied: false, failureReason: some("LSP is disabled"))

    # Reject the edit if any targeted open buffer has local changes the server
    # has not seen: it positioned its edit against the text it knows, so
    # applying it onto newer text would corrupt the buffer.
    if hasStaleServerEditTarget(e.lsp, e.buffers, edit, e.lastLspContentVersions):
      e.state.statusMessage = "Buffer changed since last sync; server edit discarded"
      return
        (applied: false, failureReason: some("buffer changed since last didChange"))

    let applyResult = applyWorkspaceEdit(e.buffers, edit, "LSP Edit")
    if applyResult.isErr:
      # applyWorkspaceEdit commits each open buffer as it goes, so a failure
      # partway through can leave earlier buffers already modified. Re-sync every
      # target buffer (best effort) so those committed changes don't silently
      # diverge from the server's copy — an unmodified/rolled-back buffer's
      # didChange just resends identical text.
      for path in collectWorkspaceEditPaths(edit):
        let absPath = normalizedPath(absolutePath(path))
        for buf in e.buffers:
          if buf.filePath.isSome and
              normalizedPath(absolutePath(buf.filePath.get)) == absPath:
            e.syncBufferAfterEdit(buf, "applyEdit")
      # A partial apply may have shrunk already-committed buffers.
      e.clampAllWindowCursors()
      e.state.statusMessage = "Failed to apply server edit: " & applyResult.error
      return (applied: false, failureReason: some(applyResult.error))

    # Sync the server with every buffer we just rewrote.
    for bufferIdx in applyResult.get.modifiedBufferIndexes:
      e.syncBufferAfterEdit(e.buffers[bufferIdx], "applyEdit")

    e.clampAllWindowCursors()
    let modifiedCount = applyResult.get.modifiedCount
    e.state.statusMessage =
      "Applied server edit (" & $modifiedCount & " file" &
      (if modifiedCount == 1: "" else: "s") & " modified)"
    return (applied: true, failureReason: none(string))

proc maybeUpdateLsp*(e: Editor) =
  ## Update LSP if buffer was modified
  ## This notifies the LSP server of document changes for real-time diagnostics
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()

  # Only notify LSP if this buffer has changed since its last notification.
  # Key on contentVersion, not changeSeq: undo rewinds changeSeq, so a
  # follow-up edit could land on the exact value we last synced and be dropped
  # here, leaving the server permanently out of sync.
  if activeBuffer.contentVersion !=
      e.lastLspContentVersions.getOrDefault(activeBuffer.id, 0):
    let lspResult = e.lsp.onBufferChange(activeBuffer)
    if lspResult.isErr and activeBuffer.filePath.isSome:
      logLspDegraded("didChange " & activeBuffer.filePath.get, lspResult.error)
    # Advance even on failure: this proc fires every frame, and leaving the
    # tracked version behind would re-run (and re-log) the same failing
    # didChange every tick until the buffer is edited again.
    e.lastLspContentVersions[activeBuffer.id] = activeBuffer.contentVersion

proc pollLspCompletion*(e: Editor) =
  ## Poll for pending LSP completion responses
  ## This should be called from the main event loop
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  # Call the insert handler's poll function
  e.handlerManager.insertHandler.pollLspCompletion(e.state)
  e.handlerManager.insertHandler.pollLspResolve(e.state)

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
      if not e.lsp.hasFormattingSupport(activeBuffer):
        e.state.statusMessage = "LSP document formatting is not supported"
        return false

      # Snapshot the buffer state before awaiting: the server's edits are
      # positioned against this state and must not be applied if the user
      # typed while the request was in flight
      let versionBeforeRequest = activeBuffer.contentVersion

      # Get formatting result from LSP
      let formatResult = await e.lsp.requestFormatting(activeBuffer)
      if formatResult.isErr:
        e.state.statusMessage = "LSP format failed: " & formatResult.error
        return false

      let edits = formatResult.get
      if edits.len == 0:
        e.state.statusMessage = "No formatting changes"
        return true

      if activeBuffer.contentVersion != versionBeforeRequest:
        e.state.statusMessage = "Buffer changed during format; edits discarded"
        return false

      # Apply the text edits to the buffer
      let applyResult = applyTextEdits(activeBuffer, edits)
      if applyResult.isErr:
        e.state.statusMessage = "Failed to apply edits: " & applyResult.error
        return false

      e.state.statusMessage =
        "Formatted (" & $edits.len & " edit" & (if edits.len > 1: "s" else: "") & ")"
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
  ## collapsed fold, `updateForFrame` pins it back onto a visible line on the
  ## next render, so this proc does not adjust the cursor itself.
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

    # The cursor may now sit inside a collapsed fold; updateForFrame normalizes
    # it onto a visible line on the next render, so no cursor fix-up is needed.
    let count = foldResult.get
    e.state.statusMessage =
      if count > 0:
        "Folded " & $count & " region(s)"
      else:
        "No foldable regions"
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

      # Snapshot every open buffer's contentVersion before awaiting: the
      # server's edits are positioned against this state. If any target
      # buffer changes while the request is in flight, applying the stale
      # coordinates would corrupt text, so the whole edit is discarded
      # (aborting beats partial application).
      # Key by buffer id, not path: two buffers can share a file path (one
      # opened relative, one absolute), and a path-keyed snapshot would let
      # one buffer's contentVersion shadow the other's, rejecting valid renames.
      var versionSnapshot: Table[BufferId, int]
      for buf in e.buffers:
        versionSnapshot[buf.id] = buf.contentVersion

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

      # Reject the edit if any targeted open buffer changed during the await, or
      # was opened during it (no snapshot entry, so it is unverifiable).
      if hasStaleTargetBuffer(e.buffers, workspaceEdit, versionSnapshot):
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
        e.syncBufferAfterEdit(e.buffers[bufferIdx], "rename")

      let modifiedCount = applyResult.get.modifiedCount
      e.state.statusMessage =
        "Renamed '" & e.state.renameState.originalWord & "' to '" & newName & "' (" &
        $modifiedCount & " file" & (if modifiedCount > 1: "s" else: "") & " modified)"
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
        let openResult = e.lsp.onBufferOpen(buf, serverIsFresh = true)
        if openResult.isOk:
          # Record what the didOpen just sent. A leftover pre-restart baseline
          # would make the applyWorkspaceEdit staleness guard reject every
          # server-initiated edit — forever for non-active buffers, which
          # maybeUpdateLsp never repairs.
          e.lastLspContentVersions[buf.id] = buf.contentVersion
        else:
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

  # Wipe pending request state BEFORE `stopWorker`: it clears the service-side
  # tables but editor-side `pendingXxxRequestId` fields would keep dangling ids,
  # freezing the feature until an unrelated edit invalidates.
  e.invalidateAllLspCaches()

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

# LSP request-context helpers live in `lsp_request_context` (Phase A);
# re-exported above so existing callers keep working.
