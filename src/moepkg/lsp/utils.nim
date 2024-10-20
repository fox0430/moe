#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[strutils, strformat, json, uri, os, options, times]

import pkg/results

import ../independentutils

import protocol/[enums, types]

type
  LspPosition* = types.Position
  LspRange* = types.Range

  LanguageId* = string

  WaitType* = enum
    foreground
      # foreground request is canceled when a user takes action.
    background

  LspMethod* {.pure.} = enum
    cancelRequest
    initialize
    initialized
    shutdown
    windowShowMessage
    windowLogMessage
    windowWorkDnoneProgressCreate
    progress
    workspaceConfiguration
    workspaceDidChangeConfiguration
    textDocumentDidOpen
    textDocumentDidChange
    textDocumentDidSave
    textDocumentDidClose
    textDocumentPublishDiagnostics
    textDocumentHover
    textDocumentCompletion
    textDocumentSemanticTokensFull
    textDocumentSemanticTokensDelta
    workspaceSemanticTokensRefresh
    textDocumentInlayHint
    workspaceInlayHintRefresh
    textDocumentDefinition
    textDocumentReferences
    textDocumentRename
    textDocumentTypeDefinition
    textDocumentImplementation
    textDocumentDeclaration
    textDocumentPrepareCallHierarchy
    callHierarchyIncomingCalls
    callHierarchyOutgoingCalls
    textDocumentDocumentHighlight
    textDocumentDocumentLink
    documentLinkResolve
    textDocumentCodeLens
    codeLensResolve
    workspaceCodeLensRefresh
    workspaceExecuteCommand
    textDocumentFoldingRange
    textDocumentSelectionRange
    textDocumentDocumentSymbol
    textDocumentInlineValue
    textDocumentSignatureHelp
    textDocumentFormatting

  CallHierarchyType* = enum
    prepare
    incoming
    outgoing

  LspMessageKind* = enum
    request
    response
    notifyFromClient
    notifyFromServer

  LspMessage* = object
    timestamp*: DateTime
    kind*: LspMessageKind
    message*: JsonNode

  LspLog* = seq[LspMessage]

  LspMethodResult* = Result[LspMethod, string]
  LspShutdownResult* = Result[(), string]

proc pathToUri*(path: string): string =
  ## This is a modified copy of encodeUrl in the uri module. This doesn't encode
  ## the / character, meaning a full file path can be passed in without breaking
  ## it.

  # Assume 12% non-alnum-chars
  result = "file://" & newStringOfCap(path.len + path.len shr 2)

  for c in path:
    case c
      # https://tools.ietf.org/html/rfc3986#section-2.3
      of 'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/':
        result.add c
      of '\\':
        result.add '%'
        result.add toHex(ord(c), 2)
      else:
        result.add '%'
        result.add toHex(ord(c), 2)

proc uriToPath*(uri: string): Result[string, string] =
  ## Convert an RFC 8089 file URI to a native, platform-specific, absolute path.

  let parsed = uri.parseUri
  if parsed.scheme != "file":
    return Result[string, string].err fmt"Invalid scheme: {parsed.scheme}, only file is supported"
  if parsed.hostname != "":
    return Result[string, string].err fmt"Invalid hostname: {parsed.hostname}, only empty hostname is supported"

  return Result[string, string].ok normalizedPath(parsed.path).decodeUrl

proc toLspPosition*(p: BufferPosition): LspPosition {.inline.} =
  LspPosition(line: p.line, character: p.column)

proc toBufferPosition*(p: LspPosition): BufferPosition {.inline.} =
  BufferPosition(line: p.line, column: p.character)

proc toLspRange*(r: BufferRange): LspRange {.inline.} =
  LspRange(start: r.first.toLspPosition, `end`: r.last.toLspPosition)

proc toBufferRange*(r: LspRange): BufferRange {.inline.} =
  BufferRange(first: r.start.toBufferPosition, last: r.`end`.toBufferPosition)

proc toBufferLocation*(r: Location): BufferLocation {.inline.} =
  BufferLocation(path: r.uri.uriToPath.get, range: r.range.toBufferRange)

proc toLspMethodStr*(m: LspMethod): string =
  case m:
    of cancelRequest: "$/cancelRequest"
    of initialize: "initialize"
    of initialized: "initialized"
    of shutdown: "shutdown"
    of windowShowMessage: "window/showMessage"
    of windowLogMessage: "window/logMessage"
    of windowWorkDnoneProgressCreate: "window/workDoneProgress/create"
    of progress: "$/progress"
    of workspaceConfiguration: "workspace/configuration"
    of workspaceDidChangeConfiguration: "workspace/didChangeConfiguration"
    of textDocumentDidOpen: "textDocument/didOpen"
    of textDocumentDidChange: "textDocument/didChange"
    of textDocumentDidSave: "textDocument/didSave"
    of textDocumentDidClose: "textDocument/didClose"
    of textDocumentPublishDiagnostics: "textDocument/publishDiagnostics"
    of textDocumentHover: "textDocument/hover"
    of textDocumentCompletion: "textDocument/completion"
    of textDocumentSemanticTokensFull: "textDocument/semanticTokens/full"
    of textDocumentSemanticTokensDelta: "textDocument/semanticTokens/delta"
    of workspaceSemanticTokensRefresh: "workspace/semanticTokens/refresh"
    of textDocumentInlayHint: "textDocument/inlayHint"
    of workspaceInlayHintRefresh: "workspace/inlayHint/refresh"
    of textDocumentDefinition: "textDocument/definition"
    of textDocumentReferences: "textDocument/references"
    of textDocumentRename: "textDocument/rename"
    of textDocumentTypeDefinition: "textDocument/typeDefinition"
    of textDocumentImplementation: "textDocument/implementation"
    of textDocumentDeclaration: "textDocument/declaration"
    of textDocumentPrepareCallHierarchy: "textDocument/prepareCallHierarchy"
    of callHierarchyIncomingCalls: "callHierarchy/incomingCalls"
    of callHierarchyOutgoingCalls: "callHierarchy/outgoingCalls"
    of textDocumentDocumentHighlight: "textDocument/documentHighlight"
    of textDocumentDocumentLink: "textDocument/documentLink"
    of documentLinkResolve: "documentLink/resolve"
    of textDocumentCodeLens: "textDocument/codeLens"
    of codeLensResolve: "codeLens/resolve"
    of workspaceCodeLensRefresh: "workspace/codeLens/refresh"
    of workspaceExecuteCommand: "workspace/executeCommand"
    of textDocumentFoldingRange: "textDocument/foldingRange"
    of textDocumentSelectionRange: "textDocument/selectionRange"
    of textDocumentDocumentSymbol: "textDocument/documentSymbol"
    of textDocumentInlineValue: "textDocument/inlineValue"
    of textDocumentSignatureHelp: "textDocument/signatureHelp"
    of textDocumentFormatting: "textDocument/formatting"

proc parseTraceValue*(s: string): Result[TraceValue, string] =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#traceValue

  try:
    return Result[TraceValue, string].ok parseEnum[TraceValue](s)
  except ValueError:
    return Result[TraceValue, string].err "Invalid value"

proc parseShutdownResponse*(res: JsonNode): LspShutdownResult =
  if res["result"].kind == JNull: return LspShutdownResult.ok ()
  else: return LspShutdownResult.err fmt"Shutdown request failed: {res}"

proc lspMethod*(j: JsonNode): LspMethodResult =
  if not j.contains("method"): return LspMethodResult.err "Invalid value"

  case j["method"].getStr:
    of "$/cancelRequest":
      LspMethodResult.ok cancelRequest
    of "initialize":
      LspMethodResult.ok initialize
    of "initialized":
      LspMethodResult.ok initialized
    of "shutdown":
      LspMethodResult.ok shutdown
    of "window/showMessage":
      LspMethodResult.ok windowShowMessage
    of "window/logMessage":
      LspMethodResult.ok windowLogMessage
    of "window/workDoneProgress/create":
      LspMethodResult.ok windowWorkDnoneProgressCreate
    of "$/progress":
      LspMethodResult.ok progress
    of "workspace/configuration":
      LspMethodResult.ok workspaceConfiguration
    of "workspace/didChangeConfiguration":
      LspMethodResult.ok workspaceDidChangeConfiguration
    of "textDocument/didOpen":
      LspMethodResult.ok textDocumentDidOpen
    of "textDocument/didChange":
      LspMethodResult.ok textDocumentDidChange
    of "textDocument/didSave":
      LspMethodResult.ok textDocumentDidSave
    of "textDocument/didClose":
      LspMethodResult.ok textDocumentDidClose
    of "textDocument/publishDiagnostics":
      LspMethodResult.ok textDocumentPublishDiagnostics
    of "textDocument/hover":
      LspMethodResult.ok textDocumentHover
    of "textDocument/completion":
      LspMethodResult.ok textDocumentCompletion
    of "textDocument/semanticTokens/full":
      LspMethodResult.ok textDocumentSemanticTokensFull
    of "textDocument/semanticTokens/delta":
      LspMethodResult.ok textDocumentSemanticTokensDelta
    of "workspace/semanticTokens/refresh":
      LspMethodResult.ok workspaceSemanticTokensRefresh
    of "textDocument/inlayHint":
      LspMethodResult.ok textDocumentInlayHint
    of "workspace/inlayHint/refresh":
      LspMethodResult.ok workspaceInlayHintRefresh
    of "textDocument/definition":
      LspMethodResult.ok textDocumentDefinition
    of "textDocument/references":
      LspMethodResult.ok textDocumentReferences
    of "textDocument/rename":
      LspMethodResult.ok textDocumentRename
    of "textDocument/typeDefinition":
      LspMethodResult.ok textDocumentTypeDefinition
    of "textDocument/implementation":
      LspMethodResult.ok textDocumentImplementation
    of "textDocument/declaration":
      LspMethodResult.ok textDocumentDeclaration
    of "textDocument/prepareCallHierarchy":
      LspMethodResult.ok textDocumentPrepareCallHierarchy
    of "callHierarchy/incomingCalls":
      LspMethodResult.ok callHierarchyIncomingCalls
    of "callHierarchy/outgoingCalls":
      LspMethodResult.ok callHierarchyOutgoingCalls
    of "textDocument/documentHighlight":
      LspMethodResult.ok textDocumentDocumentHighlight
    of "textDocument/documentLink":
      LspMethodResult.ok textDocumentDocumentLink
    of "documentLink/resolve":
      LspMethodResult.ok documentLinkResolve
    of "textDocument/codeLens":
      LspMethodResult.ok textDocumentCodeLens
    of "codeLens/resolve":
      LspMethodResult.ok codeLensResolve
    of "workspace/codeLens/refresh":
      LspMethodResult.ok workspaceCodeLensRefresh
    of "workspace/executeCommand":
     LspMethodResult.ok workspaceExecuteCommand
    of "textDocument/foldingRange":
      LspMethodResult.ok textDocumentFoldingRange
    of "textDocument/selectionRange":
      LspMethodResult.ok textDocumentSelectionRange
    of "textDocument/documentSymbol":
      LspMethodResult.ok textDocumentDocumentSymbol
    of "textDocument/inlineValue":
      LspMethodResult.ok textDocumentInlineValue
    of "textDocument/signatureHelp":
      LspMethodResult.ok textDocumentSignatureHelp
    of "textDocument/formatting":
      LspMethodResult.ok textDocumentFormatting
    else:
      LspMethodResult.err "Not supported: " & j["method"].getStr

proc isLspResponse*(res: JsonNode): bool {.inline.} = res.contains("id")

proc getWaitingType*(lspMethod: LspMethod): Option[WaitType] =
  case lspMethod:
    of initialize: some(WaitType.background)
    of shutdown: some(WaitType.background)
    of textDocumentHover: some(WaitType.foreground)
    of textDocumentCompletion: some(WaitType.foreground)
    of textDocumentSemanticTokensFull: some(WaitType.background)
    of textDocumentSemanticTokensDelta: some(WaitType.background)
    of textDocumentInlayHint: some(WaitType.background)
    of textDocumentDefinition: some(WaitType.foreground)
    of textDocumentReferences: some(WaitType.foreground)
    of textDocumentRename: some(WaitType.foreground)
    of textDocumentTypeDefinition: some(WaitType.foreground)
    of textDocumentImplementation: some(WaitType.foreground)
    of textDocumentDeclaration: some(WaitType.foreground)
    of textDocumentPrepareCallHierarchy : some(WaitType.foreground)
    of callHierarchyIncomingCalls: some(WaitType.foreground)
    of callHierarchyOutgoingCalls: some(WaitType.foreground)
    of textDocumentDocumentHighlight: some(WaitType.foreground)
    of textDocumentDocumentLink: some(WaitType.foreground)
    of documentLinkResolve: some(WaitType.foreground)
    of textDocumentCodeLens: some(WaitType.foreground)
    of codeLensResolve: some(WaitType.foreground)
    of workspaceExecuteCommand: some(WaitType.foreground)
    of textDocumentFoldingRange: some(WaitType.foreground)
    of textDocumentSelectionRange: some(WaitType.foreground)
    of textDocumentDocumentSymbol: some(WaitType.foreground)
    of textDocumentFormatting : some(WaitType.foreground)
    else: none(WaitType)

proc isForegroundWait*(lspMethod: LspMethod): bool {.inline.} =
  getWaitingType(lspMethod) == some(WaitType.foreground)

proc isBackgroundWait*(lspMethod: LspMethod): bool {.inline.} =
  getWaitingType(lspMethod) == some(WaitType.background)
