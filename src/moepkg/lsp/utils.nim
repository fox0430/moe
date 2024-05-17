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

import std/[strutils, strformat, json, uri, os]

import pkg/results

import ../independentutils

import protocol/[enums, types]

type
  LspPosition* = types.Position
  LspRange* = types.Range

  LanguageId* = string

  LspMethod* {.pure.} = enum
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
    textDocumentInlayHint
    textDocumentDefinition
    textDocumentReferences

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

proc toLspMethodStr*(m: LspMethod): string =
  case m:
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
    of textDocumentInlayHint: "textDocument/inlayHint"
    of textDocumentDefinition: "textDocument/definition"
    of textDocumentReferences: "textDocument/references"

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
    of "textDocument/inlayHint":
      LspMethodResult.ok textDocumentInlayHint
    of "textDocument/definition":
      LspMethodResult.ok textDocumentDefinition
    of "textDocument/references":
      LspMethodResult.ok textDocumentReferences
    else:
      LspMethodResult.err "Not supported: " & j["method"].getStr

proc isLspResponse*(res: JsonNode): bool {.inline.} = res.contains("id")
