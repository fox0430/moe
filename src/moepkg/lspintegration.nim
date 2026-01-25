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

## LSP Integration with Editor
## Connects LspService to Editor, TextBuffer, and UI components

import std/[options, json, strutils, algorithm, tables, times, unicode]

import pkg/[results, chronos]

import buffer, cursor, types, lspservice, messagelog, unicode_utils
import lsp/protocol/types as lspTypes

export lspservice
export lspTypes.WorkDoneProgress, lspTypes.WorkDoneProgressKind
export lspTypes.WorkDoneProgressBegin, lspTypes.WorkDoneProgressReport
export lspTypes.WorkDoneProgressEnd
export worker.ServerHealth, worker.LspEventKind

const MaxProgressTextLen* = 50 ## Maximum display width for progress text

type
  LspProgressState* = object ## State of an active LSP progress operation
    token*: string ## Progress token (unique identifier)
    langId*: string ## Language ID of the server
    title*: string ## Title of the operation (from begin)
    message*: Option[string] ## Current status message
    percentage*: Option[int] ## Progress percentage (0-100)
    cancellable*: bool ## Whether the operation can be cancelled
    startTime*: float ## Start time (epochTime) for ordering

  LspStatusState* = object ## Server status from experimental/serverStatus
    health*: ServerHealth ## Server health: ok, warning, or error
    quiescent*: bool ## True when no background work pending
    message*: Option[string] ## Explanatory message

  LspIntegration* = ref object ## Integration layer between LSP and Editor
    service*: LspService
    enabled*: bool
    # Buffer tracking (path -> version)
    openBuffers: seq[string]
    # Pending status messages to display in the editor
    pendingMessages*: seq[string]
    # Active progress operations (token -> state)
    activeProgress*: Table[string, LspProgressState]
    # Last time stale progress cleanup was performed
    lastProgressCleanupTime: float
    # Server status per language (langId -> status)
    serverStatus*: Table[string, LspStatusState]

const ProgressCleanupIntervalSeconds* = 1.0 ## Interval between stale progress checks

proc newLspIntegration*(workspaceRoot: string = ""): LspIntegration =
  ## Create a new LSP integration
  let svc = newLspService(workspaceRoot)

  result = LspIntegration(
    service: svc,
    enabled: true,
    openBuffers: @[],
    pendingMessages: @[],
    activeProgress: initTable[string, LspProgressState](),
    lastProgressCleanupTime: 0.0,
    serverStatus: initTable[string, LspStatusState](),
  )

  # Set up internal callback to collect LSP log messages for display
  let lsp = result
  svc.onLogMessage = proc(
      langId: string, msgType: MessageType, message: string
  ) {.gcsafe.} =
    if msgType == mtLog:
      # Raw JSON logs go directly to LSP log (not shown in status line)
      addLspMessageLog(message)
    else:
      let prefix =
        case msgType
        of mtError: "[LSP Error] "
        of mtWarning: "[LSP Warning] "
        of mtInfo: "[LSP Info] "
        of mtLog: "[LSP] "
      lsp.pendingMessages.add(prefix & langId & ": " & message)

  # Set up progress callback to track active progress operations
  svc.onProgress = proc(
      langId: string, token: string, progress: WorkDoneProgress
  ) {.gcsafe.} =
    case progress.kind
    of wdpkBegin:
      let state = LspProgressState(
        token: token,
        langId: langId,
        title: progress.begin.title,
        message: progress.begin.message,
        percentage: progress.begin.percentage,
        cancellable: progress.begin.cancellable.get(false),
        startTime: epochTime(),
      )
      lsp.activeProgress[token] = state
    of wdpkReport:
      if token in lsp.activeProgress:
        var state = lsp.activeProgress[token]
        if progress.report.message.isSome:
          state.message = progress.report.message
        if progress.report.percentage.isSome:
          state.percentage = progress.report.percentage
        if progress.report.cancellable.isSome:
          state.cancellable = progress.report.cancellable.get
        lsp.activeProgress[token] = state
      else:
        # Handle report without prior begin (create new state)
        let state = LspProgressState(
          token: token,
          langId: langId,
          title: "Progress",
          message: progress.report.message,
          percentage: progress.report.percentage,
          cancellable: progress.report.cancellable.get(false),
          startTime: epochTime(),
        )
        lsp.activeProgress[token] = state
    of wdpkEnd:
      lsp.activeProgress.del(token)

  # Set up status update callback to track server status
  svc.onStatusUpdate = proc(
      langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
  ) {.gcsafe.} =
    lsp.serverStatus[langId] =
      LspStatusState(health: health, quiescent: quiescent, message: message)

proc getAndClearMessages*(lsp: LspIntegration): seq[string] =
  ## Get all pending status messages and clear them
  result = lsp.pendingMessages
  lsp.pendingMessages = @[]

proc hasActiveProgress*(lsp: LspIntegration): bool =
  ## Check if there are any active progress operations
  lsp.activeProgress.len > 0

proc getServerStatus*(lsp: LspIntegration, langId: string): Option[LspStatusState] =
  ## Get the current status for a language server
  if langId in lsp.serverStatus:
    some(lsp.serverStatus[langId])
  else:
    none(LspStatusState)

proc hasServerStatus*(lsp: LspIntegration, langId: string): bool =
  ## Check if we have status information for a language server
  langId in lsp.serverStatus

proc isServerQuiescent*(lsp: LspIntegration, langId: string): bool =
  ## Check if the server is quiescent (no pending background work)
  if langId in lsp.serverStatus:
    lsp.serverStatus[langId].quiescent
  else:
    true # Default to true if no status

proc getServerHealth*(lsp: LspIntegration, langId: string): ServerHealth =
  ## Get the health status for a language server
  if langId in lsp.serverStatus:
    lsp.serverStatus[langId].health
  else:
    shOk # Default to ok if no status

proc clearStatusForLanguage*(lsp: LspIntegration, langId: string) =
  ## Clear status for a specific language server
  ## Called when a server is stopped
  lsp.serverStatus.del(langId)

proc getStatusText*(state: LspStatusState): string =
  ## Format status state as a display string
  ## Returns empty string if status is ok and quiescent
  if state.health == shOk and state.quiescent:
    return ""

  result =
    case state.health
    of shOk:
      if not state.quiescent: "Loading" else: ""
    of shWarning:
      "Warning"
    of shError:
      "Error"

  if state.message.isSome and state.message.get.len > 0:
    if result.len > 0:
      result &= ": " & state.message.get
    else:
      result = state.message.get

proc clearProgressForLanguage*(lsp: LspIntegration, langId: string) =
  ## Clear all progress operations for a specific language server
  ## Called when a server is stopped or crashes
  var tokensToRemove: seq[string] = @[]
  for token, state in lsp.activeProgress:
    if state.langId == langId:
      tokensToRemove.add(token)
  for token in tokensToRemove:
    lsp.activeProgress.del(token)

const ProgressTimeoutSeconds* = 300.0 ## 5 minutes timeout for stale progress

proc cleanupStaleProgress*(lsp: LspIntegration) =
  ## Remove progress entries that have been active for too long
  ## This handles cases where 'end' notification was never received
  ## Only runs cleanup at most once per ProgressCleanupIntervalSeconds
  let now = epochTime()

  # Rate limit cleanup checks
  if now - lsp.lastProgressCleanupTime < ProgressCleanupIntervalSeconds:
    return
  lsp.lastProgressCleanupTime = now

  var tokensToRemove: seq[string] = @[]
  for token, state in lsp.activeProgress:
    if now - state.startTime > ProgressTimeoutSeconds:
      tokensToRemove.add(token)
  for token in tokensToRemove:
    lsp.activeProgress.del(token)

proc getActiveProgressList*(lsp: LspIntegration): seq[LspProgressState] =
  ## Get all active progress operations
  result = @[]
  for state in lsp.activeProgress.values:
    result.add(state)

proc getLatestActiveProgress*(lsp: LspIntegration): Option[LspProgressState] =
  ## Get the most recently started active progress operation
  ## Returns the progress with the latest startTime for consistent display
  if lsp.activeProgress.len == 0:
    return none(LspProgressState)

  var latest: LspProgressState
  var found = false
  for state in lsp.activeProgress.values:
    if not found or state.startTime > latest.startTime:
      latest = state
      found = true
  if found:
    return some(latest)
  return none(LspProgressState)

proc truncateToWidth(s: string, maxWidth: int): string =
  ## Truncate string to fit within maxWidth display columns
  ## Adds "..." if truncated (single pass through runes)
  var currentWidth = 0
  for r in s.runes:
    let runeWidth = displayWidth($r)
    if currentWidth + runeWidth + 3 > maxWidth: # +3 for "..."
      result.add("...")
      return
    currentWidth += runeWidth
    result.add($r)
  # If we get here, no truncation needed

proc getProgressText*(state: LspProgressState): string =
  ## Format progress state as a display string with length limit
  result = state.title
  if state.message.isSome:
    result &= ": " & state.message.get
  if state.percentage.isSome:
    result &= " (" & $state.percentage.get & "%)"

  # Truncate if too long
  result = truncateToWidth(result, MaxProgressTextLen)

proc setDiagnosticsCallback*(
    lsp: LspIntegration,
    callback: proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.},
) =
  ## Set callback for diagnostics updates
  lsp.service.onDiagnosticsUpdate = callback

proc setLogCallback*(
    lsp: LspIntegration,
    callback: proc(langId: string, msgType: MessageType, message: string) {.gcsafe.},
) =
  ## Set callback for log messages
  lsp.service.onLogMessage = callback

# Buffer lifecycle operations
proc onBufferOpen*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer is opened/loaded
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = buffer.filePath.get
  let text = buffer.getTextString()

  # Track open buffer
  if path notin lsp.openBuffers:
    lsp.openBuffers.add(path)

  return lsp.service.notifyDocumentOpened(path, text)

proc onBufferClose*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer is closed
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = buffer.filePath.get

  # Remove from tracking
  let idx = lsp.openBuffers.find(path)
  if idx >= 0:
    lsp.openBuffers.delete(idx)

  return lsp.service.notifyDocumentClosed(path)

proc onBufferChange*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer content changes
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = buffer.filePath.get

  # Ensure buffer is tracked as open
  if path notin lsp.openBuffers:
    lsp.openBuffers.add(path)
    # Send didOpen first
    let text = buffer.getTextString()
    let openResult = lsp.service.notifyDocumentOpened(path, text)
    if openResult.isErr:
      return openResult
    return ok()

  let text = buffer.getTextString()
  return lsp.service.notifyDocumentChanged(path, buffer.changeSeq, text)

proc onBufferSave*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer is saved
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = buffer.filePath.get
  let text = some(buffer.getTextString())
  return lsp.service.notifyDocumentSaved(path, text)

# Polling for server messages
proc poll*(lsp: LspIntegration, timeoutMs: int = 0) =
  ## Poll for LSP server messages
  if lsp.enabled:
    lsp.service.poll(timeoutMs)

# Async (non-blocking) feature requests
# These return immediately with a request ID. Use poll() and checkResponse() to get results.

proc startCompletionRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a completion request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startCompletionRequest(path, line, column)

proc startHoverRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a hover request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startHoverRequest(path, line, column)

proc startDefinitionRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a definition request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startDefinitionRequest(path, line, column)

proc startDeclarationRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a declaration request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startDeclarationRequest(path, line, column)

proc startReferencesRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a references request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startReferencesRequest(path, line, column)

proc startTypeDefinitionRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a type definition request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startTypeDefinitionRequest(path, line, column)

proc startImplementationRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start an implementation request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startImplementationRequest(path, line, column)

proc startSignatureHelpRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a signature help request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startSignatureHelpRequest(path, line, column)

proc startDocumentHighlightRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a document highlight request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startDocumentHighlightRequest(path, line, column)

proc startCodeLensRequest*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[int, string] =
  ## Start a code lens request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startCodeLensRequest(path)

proc startCallHierarchyPrepareRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a call hierarchy prepare request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startCallHierarchyPrepareRequest(path, line, column)

proc startCallHierarchyIncomingCallsRequest*(
    lsp: LspIntegration, buffer: TextBuffer, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy incoming calls request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startCallHierarchyIncomingCallsRequest(path, item)

proc startCallHierarchyOutgoingCallsRequest*(
    lsp: LspIntegration, buffer: TextBuffer, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy outgoing calls request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startCallHierarchyOutgoingCallsRequest(path, item)

proc startDocumentSymbolsRequest*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[int, string] =
  ## Start a document symbols request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startDocumentSymbolsRequest(path)

proc startSelectionRangeRequest*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[int, string] =
  ## Start a selection range request (non-blocking). Returns request ID.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.startSelectionRangeRequest(path, line, column)

proc checkResponse*(
    lsp: LspIntegration, requestId: int
): tuple[status: LspResponseStatus, result: Option[JsonNode], error: Option[string]] =
  ## Non-blocking check if a response has arrived
  return lsp.service.checkResponse(requestId)

proc hasPendingRequests*(lsp: LspIntegration): bool =
  ## Check if there are any pending requests
  lsp.service.hasPendingRequests()

proc cleanupTimedOutRequests*(lsp: LspIntegration) =
  ## Clean up any timed out requests
  lsp.service.cleanupTimedOutRequests()

proc getSemanticTokensLegend*(
    lsp: LspIntegration, buffer: TextBuffer
): Option[SemanticTokensLegend] =
  ## Get the semantic tokens legend for a buffer's language
  if not lsp.enabled:
    return none(SemanticTokensLegend)

  if buffer.filePath.isNone:
    return none(SemanticTokensLegend)

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return none(SemanticTokensLegend)

  return lsp.service.getSemanticTokensLegend(langIdOpt.get)

proc startSemanticTokensRequest*(
    lsp: LspIntegration, buffer: TextBuffer, firstLine, lastLine: int
): Result[int, string] =
  ## Start a semantic tokens request (non-blocking). Returns request ID.
  ## Uses range request if supported, otherwise falls back to full document.
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  if buffer.len == 0:
    return err("Buffer is empty")

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return err("No LSP support for file: " & path)

  # Check if range request is supported, fall back to full if not
  if lsp.service.hasSemanticTokensRangeSupport(langIdOpt.get):
    # Clamp line numbers to valid range
    let actualLastLine = min(lastLine, buffer.len - 1)
    let actualFirstLine = min(firstLine, actualLastLine)
    let endChar = buffer.getLine(actualLastLine).charLen
    return lsp.service.startSemanticTokensRangeRequest(
      path, actualFirstLine, 0, actualLastLine, endChar
    )
  elif lsp.service.hasSemanticTokensFullSupport(langIdOpt.get):
    # Fall back to full document request
    return lsp.service.startSemanticTokensFullRequest(path)
  else:
    return err("Semantic tokens not supported")

proc hasInlineValueSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if inline value is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasInlineValueSupport(langIdOpt.get)

proc hasDocumentLinkSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if document link is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasDocumentLinkSupport(langIdOpt.get)

proc hasDocumentLinkResolveSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if document link resolve is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasDocumentLinkResolveSupport(langIdOpt.get)

# TextEdit application helpers
proc compareTextEditReverse(a, b: TextEdit): int =
  ## Compare TextEdits for reverse sorting (back to front)
  ## Returns positive if a should come before b (a is after b in document)
  if a.range.start.line != b.range.start.line:
    return b.range.start.line - a.range.start.line
  return b.range.start.character - a.range.start.character

proc applyTextEdits*(buffer: TextBuffer, edits: seq[TextEdit]): Result[void, string] =
  ## Apply a sequence of TextEdits to the buffer
  ## Edits are applied in reverse order (back to front) to preserve positions
  ## Note: LSP TextEdit.range.end is exclusive, buffer.deleteRange is inclusive
  if edits.len == 0:
    return ok()

  # Sort edits in reverse order (back to front)
  var sortedEdits = edits
  sortedEdits.sort(compareTextEditReverse)

  # Apply each edit
  for edit in sortedEdits:
    let startPos =
      BufferPosition(line: edit.range.start.line, column: edit.range.start.character)
    let lspEndPos = edit.range.`end`

    # Check if range is empty (LSP exclusive end == start means empty range)
    let isEmptyRange =
      edit.range.start.line == lspEndPos.line and
      edit.range.start.character == lspEndPos.character

    # Delete the range if it's not empty
    if not isEmptyRange:
      # Convert LSP exclusive end to buffer inclusive end
      var adjustedEndPos: BufferPosition
      if lspEndPos.character > 0:
        # Simply decrement character position
        adjustedEndPos =
          BufferPosition(line: lspEndPos.line, column: lspEndPos.character - 1)
      else:
        # End is at start of a line (character == 0)
        # Need to point to end of previous line to include the newline
        if lspEndPos.line > 0:
          let prevLineLen = buffer.getLine(lspEndPos.line - 1).charLen
          adjustedEndPos = BufferPosition(line: lspEndPos.line - 1, column: prevLineLen)
        else:
          # Edge case: end is at (0, 0), skip deletion
          adjustedEndPos = startPos

      # Only delete if we have a valid range
      if startPos.line < adjustedEndPos.line or (
        startPos.line == adjustedEndPos.line and startPos.column <= adjustedEndPos.column
      ):
        let deleteResult = buffer.deleteRange(startPos, adjustedEndPos)
        if deleteResult.isErr:
          return err("Failed to delete range: " & deleteResult.error)

    # Insert the new text if not empty
    if edit.newText.len > 0:
      let insertResult = buffer.insertText(startPos, edit.newText)
      if insertResult.isErr:
        return err("Failed to insert text: " & insertResult.error)

  return ok()

# Diagnostic helpers
proc applyDiagnosticsToBuffer*(buffer: TextBuffer, diagnostics: seq[Diagnostic]) =
  ## Apply LSP diagnostics to buffer's line markers
  ## Clears existing syntax markers and sets new ones

  # Clear existing syntax-related markers
  for i in 0 ..< buffer.lineMarkers.len:
    let marker = buffer.lineMarkers[i]
    if marker.isSome:
      let kind = marker.get
      if kind in {SidebarItemKind.SyntaxError, SidebarItemKind.SyntaxWarning}:
        buffer.lineMarkers[i] = none(SidebarItemKind)

  # Apply new diagnostics
  for diag in diagnostics:
    let line = diag.range.start.line
    if line >= 0 and line < buffer.len:
      let kind =
        if diag.severity.isSome:
          case diag.severity.get
          of dsError: SidebarItemKind.SyntaxError
          of dsWarning: SidebarItemKind.SyntaxWarning
          of dsInformation: SidebarItemKind.SyntaxWarning
          of dsHint: SidebarItemKind.SyntaxWarning
        else:
          SidebarItemKind.SyntaxError

      # Only set if no marker or lower priority marker exists
      let existing = buffer.getLineMarker(line)
      if existing.isNone or (
        existing.get != SidebarItemKind.SyntaxError and
        kind == SidebarItemKind.SyntaxError
      ):
        buffer.setLineMarker(line, kind)

# Signature help content helpers
proc getSignatureHelpText*(sigHelp: SignatureHelp): string =
  ## Extract formatted text from signature help response
  if sigHelp.signatures.len == 0:
    return ""

  # Get the active signature (default to first)
  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx < 0 or activeIdx >= sigHelp.signatures.len:
    return ""

  let sig = sigHelp.signatures[activeIdx]
  result = sig.label

  # Add documentation if available
  if sig.documentation.isSome:
    let doc = sig.documentation.get
    var docText = ""
    case doc.kind
    of JString:
      docText = doc.getStr
    of JObject:
      if doc.hasKey("value"):
        docText = doc["value"].getStr
    else:
      discard
    if docText.len > 0:
      result.add("\n\n" & docText)

proc getActiveParameterIndex*(sigHelp: SignatureHelp): int =
  ## Get the active parameter index from signature help
  # First check the top-level activeParameter
  if sigHelp.activeParameter.isSome:
    return sigHelp.activeParameter.get

  # Fall back to the active signature's activeParameter
  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx >= 0 and activeIdx < sigHelp.signatures.len:
    let sig = sigHelp.signatures[activeIdx]
    if sig.activeParameter.isSome:
      return sig.activeParameter.get

  return 0

proc getParameterInfo*(sigHelp: SignatureHelp): tuple[label: string, start, stop: int] =
  ## Get the active parameter's highlighting range within the signature label
  ## Returns (full label, start position, end position) for highlighting
  result = ("", -1, -1)

  if sigHelp.signatures.len == 0:
    return

  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx < 0 or activeIdx >= sigHelp.signatures.len:
    return

  let sig = sigHelp.signatures[activeIdx]
  result.label = sig.label

  if sig.parameters.isNone or sig.parameters.get.len == 0:
    return

  let paramIdx = getActiveParameterIndex(sigHelp)
  let params = sig.parameters.get

  if paramIdx < 0 or paramIdx >= params.len:
    return

  let param = params[paramIdx]
  if param.label.len > 0:
    # Find the parameter label in the signature label
    let pos = sig.label.find(param.label)
    if pos >= 0:
      result.start = pos
      result.stop = pos + param.label.len

# Hover content helpers
proc getHoverText*(hover: Hover): string =
  ## Extract plain text from hover content
  let contents = hover.contents

  case contents.kind
  of JString:
    return contents.getStr
  of JObject:
    # MarkupContent
    if contents.hasKey("value"):
      return contents["value"].getStr
    elif contents.hasKey("contents"):
      return getHoverText(Hover(contents: contents["contents"]))
  of JArray:
    # Multiple MarkedString entries
    var lines: seq[string] = @[]
    for item in contents:
      case item.kind
      of JString:
        lines.add(item.getStr)
      of JObject:
        if item.hasKey("value"):
          lines.add(item["value"].getStr)
      else:
        discard
    return lines.join("\n")
  else:
    return ""

# Status helpers
proc isEnabled*(lsp: LspIntegration): bool =
  lsp.enabled

proc setEnabled*(lsp: LspIntegration, enabled: bool) =
  lsp.enabled = enabled
  lsp.service.enabled = enabled

proc getRunningServers*(lsp: LspIntegration): seq[string] =
  ## Get list of running language server IDs
  lsp.service.getRunningLanguages()

proc hasServerForPath*(lsp: LspIntegration, path: string): bool =
  ## Check if there's LSP support for a file path
  lsp.service.getLanguageIdFromPath(path).isSome

proc isServerRunningForPath*(lsp: LspIntegration, path: string): bool =
  ## Check if server is running for a file path
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false
  lsp.service.getWorker(langIdOpt.get).isSome

# CodeLens support
proc hasCodeLensSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if code lens is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasCodeLensSupport(langIdOpt.get)

proc hasCodeLensResolveSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if code lens resolve is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasCodeLensResolveSupport(langIdOpt.get)

proc hasDocumentSymbolSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if document symbol is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasDocumentSymbolSupport(langIdOpt.get)

proc hasCallHierarchySupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if call hierarchy is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasCallHierarchySupport(langIdOpt.get)

proc requestCodeLensResolve*(
    lsp: LspIntegration, buffer: TextBuffer, lens: CodeLens
): Future[Result[CodeLens, string]] {.async: (raises: [CancelledError]).} =
  ## Resolve a code lens to get its command
  ## Used when the initial codeLens response doesn't include the command
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestCodeLensResolve(path, lens)

proc requestExecuteCommand*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    command: string,
    arguments: seq[JsonNode] = @[],
): Future[Result[JsonNode, string]] {.async: (raises: [CancelledError]).} =
  ## Execute a command on the LSP server (used for code lens commands)
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestExecuteCommand(path, command, arguments)

# Folding Range support
proc hasFoldingRangeSupport*(lsp: LspIntegration, buffer: TextBuffer): bool =
  ## Check if folding range is supported for a buffer's language
  if not lsp.enabled:
    return false

  if buffer.filePath.isNone:
    return false

  let path = buffer.filePath.get
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false

  return lsp.service.hasFoldingRangeSupport(langIdOpt.get)

proc applyLspFoldingRanges*(
    buffer: TextBuffer,
    ranges: seq[FoldingRange],
    clearExisting: bool = true,
    startCollapsed: bool = false,
): int =
  ## Apply LSP folding ranges to buffer's FoldState
  ## Returns the number of folds successfully added
  ## If clearExisting is true, removes all existing folds first
  ## If startCollapsed is false (default), folds are added in expanded state
  ## LSP FoldingRange uses 0-based line numbers which matches our FoldState
  ##
  ## Note: Due to the current FoldState design, overlapping/nested folds are not supported.
  ## This function sorts ranges by size (smallest first) to maximize the number of
  ## non-overlapping folds that can be added. Larger outer folds that overlap with
  ## already-added smaller folds will be skipped.
  if clearExisting:
    buffer.foldState = initFoldState()

  # Filter valid ranges and sort by size (smallest first) to prioritize inner folds
  var validRanges: seq[FoldingRange] = @[]
  for range in ranges:
    # Skip invalid ranges
    if range.endLine < range.startLine:
      continue
    # Skip ranges outside buffer bounds
    if range.startLine < 0 or range.endLine >= buffer.len:
      continue
    validRanges.add(range)

  # Sort by range size (endLine - startLine), smallest first
  validRanges.sort(
    proc(a, b: FoldingRange): int =
      let sizeA = a.endLine - a.startLine
      let sizeB = b.endLine - b.startLine
      result = sizeA - sizeB
  )

  var added = 0
  for range in validRanges:
    # Add fold with LSP-provided collapsedText
    # addFold checks for overlaps and maintains sorted order
    if buffer.foldState.addFold(
      range.startLine,
      range.endLine,
      collapsed = startCollapsed,
      collapsedText = range.collapsedText,
    ):
      inc added

  return added

# Cleanup
proc shutdown*(lsp: LspIntegration) =
  ## Shutdown all LSP servers
  lsp.service.stopAll()
  lsp.openBuffers = @[]
  lsp.activeProgress.clear()
  lsp.serverStatus.clear()

# ============================================================================
# Async request APIs
# ============================================================================

proc requestFormatting*(
    lsp: LspIntegration, buffer: TextBuffer, tabSize: int = 2, insertSpaces: bool = true
): Future[Result[seq[TextEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Request formatting for a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestFormatting(path, tabSize, insertSpaces)

proc requestRename*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int, newName: string
): Future[Result[Option[WorkspaceEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Request rename at a position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestRename(path, line, column, newName)

proc requestDefinition*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Request go to definition at a position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestDefinition(path, line, column)

proc requestReferences*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Request find references at a position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestReferences(path, line, column)

proc requestDocumentSymbols*(
    lsp: LspIntegration, buffer: TextBuffer
): Future[Result[DocumentSymbolResult, string]] {.async: (raises: [CancelledError]).} =
  ## Request document symbols
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestDocumentSymbols(path)

proc requestFoldingRanges*(
    lsp: LspIntegration, buffer: TextBuffer
): Future[Result[seq[FoldingRange], string]] {.async: (raises: [CancelledError]).} =
  ## Request folding ranges for a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return await lsp.service.requestFoldingRange(path)

proc refreshLspFolds*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    clearExisting: bool = true,
    startCollapsed: bool = false,
): Future[Result[int, string]] {.async: (raises: [CancelledError]).} =
  ## Request folding ranges from LSP and apply them to buffer
  {.cast(raises: [CancelledError]).}:
    let rangesResult = await lsp.requestFoldingRanges(buffer)
    if rangesResult.isErr:
      return err(rangesResult.error)

    let count =
      buffer.applyLspFoldingRanges(rangesResult.get, clearExisting, startCollapsed)
    return ok(count)
