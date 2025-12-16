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

proc newLspIntegration*(workspaceRoot: string = ""): LspIntegration =
  ## Create a new LSP integration
  let svc = newLspService(workspaceRoot)

  result = LspIntegration(service: svc, enabled: true, openBuffers: @[])

proc setDiagnosticsCallback*(
    lsp: LspIntegration, callback: proc(uri: string, diagnostics: seq[Diagnostic])
) =
  ## Set callback for diagnostics updates
  lsp.service.onDiagnosticsUpdate = callback

proc setLogCallback*(
    lsp: LspIntegration,
    callback: proc(langId: string, msgType: MessageType, message: string),
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

# Feature requests
proc requestCompletion*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Result[seq[CompletionItem], string] =
  ## Request completion at cursor position
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
  lsp.service.getClient(langIdOpt.get).isSome

# Cleanup
proc shutdown*(lsp: LspIntegration) =
  ## Shutdown all LSP servers
  lsp.service.stopAll()
  lsp.openBuffers = @[]
