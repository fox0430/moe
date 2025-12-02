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

import std/[options, json, strutils]

import pkg/results

import buffer, types, lspservice
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
