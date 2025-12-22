#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[options, json, strutils, algorithm]

import pkg/results

import buffer, cursor, types, lspservice
import lsp/protocol/types as lspTypes

export lspservice

type LspIntegration* = ref object ## Integration layer between LSP and Editor
  service*: LspService
  enabled*: bool
  # Buffer tracking (path -> version)
  openBuffers: seq[string]
  # Pending status messages to display in the editor
  pendingMessages*: seq[string]

proc newLspIntegration*(workspaceRoot: string = ""): LspIntegration =
  ## Create a new LSP integration
  let svc = newLspService(workspaceRoot)

  result =
    LspIntegration(service: svc, enabled: true, openBuffers: @[], pendingMessages: @[])

  # Set up internal callback to collect LSP log messages for display
  let lsp = result
  svc.onLogMessage = proc(
      langId: string, msgType: MessageType, message: string
  ) {.gcsafe.} =
    let prefix =
      case msgType
      of mtError: "[LSP Error] "
      of mtWarning: "[LSP Warning] "
      of mtInfo: "[LSP Info] "
      of mtLog: "[LSP] "
    lsp.pendingMessages.add(prefix & langId & ": " & message)

proc getAndClearMessages*(lsp: LspIntegration): seq[string] =
  ## Get all pending status messages and clear them
  result = lsp.pendingMessages
  lsp.pendingMessages = @[]

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

# Blocking feature requests (WARNING: These block the main thread!)
proc requestCompletion*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[CompletionItem], string] =
  ## Request completion at cursor position (BLOCKING)
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCompletion(path, line, column)

proc requestHover*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[Option[Hover], string] =
  ## Request hover information at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestHover(path, line, column)

proc requestDefinition*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[Location], string] =
  ## Request go to definition at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDefinition(path, line, column)

proc requestDeclaration*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[Location], string] =
  ## Request go to declaration at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDeclaration(path, line, column)

proc requestTypeDefinition*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[Location], string] =
  ## Request go to type definition at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestTypeDefinition(path, line, column)

proc requestImplementation*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[Location], string] =
  ## Request go to implementation at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestImplementation(path, line, column)

proc requestReferences*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[Location], string] =
  ## Request find references at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestReferences(path, line, column)

proc requestDocumentHighlight*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[DocumentHighlight], string] =
  ## Request document highlights at cursor position
  ## Returns all occurrences of the symbol at the given position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDocumentHighlight(path, line, column)

proc requestDocumentLinks*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[seq[DocumentLink], string] =
  ## Request document links for a buffer
  ## Returns links to internal or external resources (e.g., imports, URLs)
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDocumentLinks(path)

proc requestDocumentLinkResolve*(
    lsp: LspIntegration, buffer: TextBuffer, link: DocumentLink
): Result[DocumentLink, string] =
  ## Resolve a document link to get its target URI
  ## Used when the initial documentLink response doesn't include target
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDocumentLinkResolve(path, link)

proc requestSignatureHelp*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[Option[SignatureHelp], string] =
  ## Request signature help at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestSignatureHelp(path, line, column)

proc requestRename*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int, newName: string
): Result[Option[WorkspaceEdit], string] =
  ## Request rename of a symbol at cursor position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestRename(path, line, column, newName)

proc requestFormatting*(
    lsp: LspIntegration, buffer: TextBuffer, tabSize: int = 2, insertSpaces: bool = true
): Result[seq[TextEdit], string] =
  ## Request document formatting
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestFormatting(path, tabSize, insertSpaces)

proc requestRangeFormatting*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    startLine, startChar, endLine, endChar: int,
    tabSize: int = 2,
    insertSpaces: bool = true,
): Result[seq[TextEdit], string] =
  ## Request range formatting
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestRangeFormatting(
    path, startLine, startChar, endLine, endChar, tabSize, insertSpaces
  )

proc requestDocumentSymbols*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[DocumentSymbolResult, string] =
  ## Request document symbols for a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestDocumentSymbols(path)

proc requestInlayHints*(
    lsp: LspIntegration, buffer: TextBuffer, startLine, startChar, endLine, endChar: int
): Result[seq[InlayHint], string] =
  ## Request inlay hints for a range in a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestInlayHints(path, startLine, startChar, endLine, endChar)

proc requestInlayHintsForVisibleRange*(
    lsp: LspIntegration, buffer: TextBuffer, firstLine, lastLine: int
): Result[seq[InlayHint], string] =
  ## Request inlay hints for the visible range of a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  if buffer.len == 0:
    return ok(newSeq[InlayHint]())

  let path = buffer.filePath.get
  # Clamp line numbers to valid range
  let actualLastLine = min(lastLine, buffer.len - 1)
  let actualFirstLine = min(firstLine, actualLastLine)
  let endChar = buffer.getLine(actualLastLine).charLen
  return
    lsp.service.requestInlayHints(path, actualFirstLine, 0, actualLastLine, endChar)

proc requestSemanticTokensFull*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[Option[SemanticTokens], string] =
  ## Request full semantic tokens for a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestSemanticTokensFull(path)

proc requestSemanticTokensRange*(
    lsp: LspIntegration, buffer: TextBuffer, startLine, startChar, endLine, endChar: int
): Result[Option[SemanticTokens], string] =
  ## Request semantic tokens for a range in a buffer
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return
    lsp.service.requestSemanticTokensRange(path, startLine, startChar, endLine, endChar)

proc requestSemanticTokensForVisibleRange*(
    lsp: LspIntegration, buffer: TextBuffer, firstLine, lastLine: int
): Result[Option[SemanticTokens], string] =
  ## Request semantic tokens for the visible range of a buffer
  ## Falls back to full document request if range is not supported
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  if buffer.len == 0:
    return ok(none(SemanticTokens))

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
    return lsp.service.requestSemanticTokensRange(
      path, actualFirstLine, 0, actualLastLine, endChar
    )
  elif lsp.service.hasSemanticTokensFullSupport(langIdOpt.get):
    # Fall back to full document request
    return lsp.service.requestSemanticTokensFull(path)
  else:
    return err("Semantic tokens not supported")

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

proc requestInlineValues*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    startLine, startChar, endLine, endChar: int,
    frameId: int,
    stoppedLine, stoppedStartChar, stoppedEndLine, stoppedEndChar: int,
): Result[seq[InlineValue], string] =
  ## Request inline values for a range in a buffer during debugging
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestInlineValues(
    path, startLine, startChar, endLine, endChar, frameId, stoppedLine,
    stoppedStartChar, stoppedEndLine, stoppedEndChar,
  )

proc requestInlineValuesForVisibleRange*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    firstLine, lastLine: int,
    frameId: int,
    stoppedLine, stoppedStartChar, stoppedEndLine, stoppedEndChar: int,
): Result[seq[InlineValue], string] =
  ## Request inline values for the visible range of a buffer during debugging
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  if buffer.len == 0:
    return ok(newSeq[InlineValue]())

  let path = buffer.filePath.get
  # Clamp line numbers to valid range
  let actualLastLine = min(lastLine, buffer.len - 1)
  let actualFirstLine = min(firstLine, actualLastLine)
  let endChar = buffer.getLine(actualLastLine).charLen
  return lsp.service.requestInlineValues(
    path, actualFirstLine, 0, actualLastLine, endChar, frameId, stoppedLine,
    stoppedStartChar, stoppedEndLine, stoppedEndChar,
  )

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

proc requestCodeLens*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[seq[CodeLens], string] =
  ## Request code lenses for a buffer
  ## Code lenses represent commands shown along with source text (e.g., "5 references")
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCodeLens(path)

proc requestCodeLensResolve*(
    lsp: LspIntegration, buffer: TextBuffer, lens: CodeLens
): Result[CodeLens, string] =
  ## Resolve a code lens to get its command
  ## Used when the initial codeLens response doesn't include the command
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCodeLensResolve(path, lens)

proc requestExecuteCommand*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    command: string,
    arguments: seq[JsonNode] = @[],
): Result[JsonNode, string] =
  ## Execute a command on the LSP server (used for code lens commands)
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestExecuteCommand(path, command, arguments)

proc requestCallHierarchyPrepare*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[CallHierarchyItem], string] =
  ## Prepare call hierarchy at cursor position
  ## Returns a list of CallHierarchyItems for the symbol at the position
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCallHierarchyPrepare(path, line, column)

proc requestCallHierarchyIncomingCalls*(
    lsp: LspIntegration, buffer: TextBuffer, item: CallHierarchyItem
): Result[seq[CallHierarchyIncomingCall], string] =
  ## Request incoming calls for a CallHierarchyItem
  ## Returns all callers of the given item
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCallHierarchyIncomingCalls(path, item)

proc requestCallHierarchyOutgoingCalls*(
    lsp: LspIntegration, buffer: TextBuffer, item: CallHierarchyItem
): Result[seq[CallHierarchyOutgoingCall], string] =
  ## Request outgoing calls for a CallHierarchyItem
  ## Returns all items called by the given item
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestCallHierarchyOutgoingCalls(path, item)

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

proc requestFoldingRanges*(
    lsp: LspIntegration, buffer: TextBuffer
): Result[seq[FoldingRange], string] =
  ## Request folding ranges for a buffer
  ## Returns all foldable regions (functions, classes, comments, imports, etc.)
  if not lsp.enabled:
    return err("LSP disabled")

  if buffer.filePath.isNone:
    return err("Buffer has no file path")

  let path = buffer.filePath.get
  return lsp.service.requestFoldingRange(path)

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

proc refreshLspFolds*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    clearExisting: bool = true,
    startCollapsed: bool = false,
): Result[int, string] =
  ## Request folding ranges from LSP and apply them to buffer
  ## Returns the number of folds successfully added
  ## If clearExisting is true, removes all existing folds first
  ## If startCollapsed is false (default), folds are added in expanded state
  let rangesResult = lsp.requestFoldingRanges(buffer)
  if rangesResult.isErr:
    return err(rangesResult.error)

  let count =
    buffer.applyLspFoldingRanges(rangesResult.get, clearExisting, startCollapsed)
  return ok(count)

# Cleanup
proc shutdown*(lsp: LspIntegration) =
  ## Shutdown all LSP servers
  lsp.service.stopAll()
  lsp.openBuffers = @[]
