#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[strutils, strformat, json, options, uri, os]
import pkg/results

import ../independentutils
import ../unicodeext

import protocol/[enums, types]

type
  LspPosition* = types.Position

  LspCompletionItem* = types.CompletionItem
  LspCompletionList* = types.CompletionList

  LspCompletionTriggerKind* = enums.CompletionTriggerKind

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

  ProgressToken* = string
    # ProgressParams.token
    # Can be also int but the editor only use string.

  ProgressState* = enum
    create
    begin
    report
    `end`

  ProgressReport* = ref object
    state*: ProgressState
    title*: string
    message*: string
    percentage*: Option[Natural]

  LspMessageType* = enum
    error
    warn
    info
    log
    debug

  Diagnostics* = object
    path*: string
      # File path
    diagnostics*: seq[Diagnostic]
      # Diagnostics results

  ServerMessage* = object
    messageType*: LspMessageType
    message*: string

  HoverContent* = object
    title*: Runes
    description*: seq[Runes]
    range*: BufferRange

  R = Result
  parseLspMessageTypeResult* = R[LspMessageType, string]
  LspMethodResult* = R[LspMethod, string]
  LspShutdownResult* = R[(), string]
  LspWindowShowMessageResult* = R[ServerMessage, string]
  LspWindowLogMessageResult* = R[ServerMessage, string]
  LspWindowWorkDnoneProgressCreateResult* = R[ProgressToken, string]
  LspWorkDoneProgressBeginResult* = R[WorkDoneProgressBegin, string]
  LspWorkDoneProgressReportResult* = R[WorkDoneProgressReport, string]
  LspWorkDoneProgressEndResult* = R[WorkDoneProgressEnd, string]
  LspDiagnosticsResult* = R[Option[Diagnostics], string]
  LspHoverResult* = R[Option[Hover], string]
  LspCompletionResut* = R[seq[CompletionItem], string]

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
    else:
      LspMethodResult.err "Not supported: " & j["method"].getStr

proc parseLspMessageType*(num: int): parseLspMessageTypeResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#messageType

  case num:
    of 1: parseLspMessageTypeResult.ok LspMessageType.error
    of 2: parseLspMessageTypeResult.ok LspMessageType.warn
    of 3: parseLspMessageTypeResult.ok LspMessageType.info
    of 4: parseLspMessageTypeResult.ok LspMessageType.log
    of 5: parseLspMessageTypeResult.ok LspMessageType.debug
    else: parseLspMessageTypeResult.err "Invalid value"

proc parseWindowShowMessageNotify*(n: JsonNode): LspWindowShowMessageResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_showMessageRequest

  # TODO: Add "ShowMessageRequestParams.actions" support.
  if n.contains("params") and
     n["params"].contains("type") and n["params"]["type"].kind == JInt and
     n["params"].contains("message") and n["params"]["message"].kind == JString:
       let messageType = n["params"]["type"].getInt.parseLspMessageType
       if messageType.isErr:
         return LspWindowShowMessageResult.err messageType.error

       return LspWindowShowMessageResult.ok ServerMessage(
         messageType: messageType.get,
         message: n["params"]["message"].getStr)

  return LspWindowShowMessageResult.err "Invalid notify"

proc parseWindowLogMessageNotify*(n: JsonNode): LspWindowLogMessageResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_logMessage

  if n.contains("params") and
     n["params"].contains("type") and n["params"]["type"].kind == JInt and
     n["params"].contains("message") and n["params"]["message"].kind == JString:
       let messageType = n["params"]["type"].getInt.parseLspMessageType
       if messageType.isErr:
         return LspWindowLogMessageResult.err messageType.error

       return LspWindowLogMessageResult.ok ServerMessage(
         messageType: messageType.get,
         message: n["params"]["message"].getStr)

  return LspWindowLogMessageResult.err "Invalid notify"

proc parseWindowWorkDnoneProgressCreateNotify*(
  n: JsonNode): LspWindowWorkDnoneProgressCreateResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_workDoneProgress_create

    if not n.contains("params") or n["params"].kind != JObject:
      return LspWindowWorkDnoneProgressCreateResult.err "Invalid notify"

    var params: WorkDoneProgressCreateParams
    try:
      params = n["params"].to(WorkDoneProgressCreateParams)
    except CatchableError as e:
      return LspWindowWorkDnoneProgressCreateResult.err fmt"Invalid notify: {e.msg}"

    if params.token.isNone:
      return LspWindowWorkDnoneProgressCreateResult.err fmt"Invalid notify: token is empty"

    return LspWindowWorkDnoneProgressCreateResult.ok params.token.get.getStr

template isProgressNotify(j: JsonNode): bool =
  ## `$/ptgoress` notification

  j.contains("params") and
  j["params"].kind == JObject and
  j["params"].contains("token") and
  j["params"].contains("value") and
  j["params"]["value"].contains("kind") and
  j["params"]["value"]["kind"].kind == JString

template isWorkDoneProgressBegin*(j: JsonNode): bool =
  isProgressNotify(j) and
  "begin" == j["params"]["value"]["kind"].getStr

template isWorkDoneProgressReport*(j: JsonNode): bool =
  isProgressNotify(j) and
  "report" == j["params"]["value"]["kind"].getStr

template isWorkDoneProgressEnd*(j: JsonNode): bool =
  isProgressNotify(j) and
  "end" == j["params"]["value"]["kind"].getStr

template workDoneProgressToken*(j: JsonNode): string =
  j["params"]["token"].getStr

proc parseWorkDoneProgressBegin*(
  n: JsonNode): LspWorkDoneProgressBeginResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressBegin(n):
      return LspWorkDoneProgressBeginResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressBeginResult.ok n["params"]["value"].to(
        WorkDoneProgressBegin)
    except CatchableError as e:
      return LspWorkDoneProgressBeginResult.err fmt"Invalid notify: {e.msg}"

proc parseWorkDoneProgressReport*(
  n: JsonNode): LspWorkDoneProgressReportResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressReport(n):
      return LspWorkDoneProgressReportResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressReportResult.ok n["params"]["value"].to(
        WorkDoneProgressReport)
    except CatchableError as e:
      return LspWorkDoneProgressReportResult.err fmt"Invalid notify: {e.msg}"

proc parseWorkDoneProgressEnd*(
  n: JsonNode): LspWorkDoneProgressEndResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressEnd(n):
      return LspWorkDoneProgressEndResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressEndResult.ok n["params"]["value"].to(
        WorkDoneProgressEnd)
    except CatchableError as e:
      return LspWorkDoneProgressEndResult.err fmt"Invalid notify: {e.msg}"

template isCancellable*(
  p: WorkDoneProgressBegin | WorkDoneProgressReport): bool =

    some(true) == p.cancellable

proc parseTextDocumentPublishDiagnosticsNotify*(
  n: JsonNode): LspDiagnosticsResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#publishDiagnosticsParams

    if not n.contains("params") or n["params"].kind != JObject:
      return LspDiagnosticsResult.err "Invalid notify"

    var params: PublishDiagnosticsParams
    try:
      params = n["params"].to(PublishDiagnosticsParams)
    except CatchableError as e:
      return LspDiagnosticsResult.err fmt"Invalid notify: {e.msg}"

    if params.diagnostics.isNone:
      return LspDiagnosticsResult.ok none(Diagnostics)

    let path = params.uri.uriToPath
    if path.isErr:
      return LspDiagnosticsResult.err fmt"Invalid uri: {path.error}"

    return LspDiagnosticsResult.ok some(Diagnostics(
      path: path.get,
      diagnostics: params.diagnostics.get))

proc parseTextDocumentHoverResponse*(res: JsonNode): LspHoverResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#hover
  if not res.contains("result"):
    return LspHoverResult.err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    return LspHoverResult.ok none(Hover)
  try:
    return LspHoverResult.ok some(res["result"].to(Hover))
  except CatchableError as e:
    let msg = fmt"json to Hover failed {e.msg}"
    return LspHoverResult.err fmt"Invalid response: {msg}"

proc toHoverContent*(hover: Hover): HoverContent =
  let contents = %*hover.contents
  case contents.kind:
    of JArray:
      if contents.len == 1:
        if contents[0].contains("value"):
          result.description = contents[0]["value"].getStr.splitLines.toSeqRunes
      else:
        if contents[0].contains("value"):
          result.title = contents[0]["value"].getStr.toRunes

        for i in 1 ..< contents.len:
          if contents[i].contains("value"):
            result.description.add contents[i]["value"].getStr.splitLines.toSeqRunes
            if i < contents.len - 1: result.description.add ru""
    else:
      result.description = contents["value"].getStr.splitLines.toSeqRunes

  if hover.range.isSome:
    let range = %*hover.range
    result.range.first = BufferPosition(
      line: range["start"]["line"].getInt,
      column: range["start"]["character"].getInt)
    result.range.last = BufferPosition(
      line: range["end"]["line"].getInt,
      column: range["end"]["character"].getInt)

proc parseTextDocumentCompletionResponse*(res: JsonNode): LspCompletionResut =
  if not res.contains("result"):
    return Result[seq[CompletionItem], string].err fmt"Invalid response: {res}"

  if res["result"].kind == JObject:
    var list: CompletionList

    try:
      list = res["result"].to(CompletionList)
    except CatchableError as e:
      return Result[seq[CompletionItem], string].err fmt"Invalid response: {e.msg}"

    if list.items.isSome:
      return Result[seq[CompletionItem], string].ok list.items.get
    else:
      # Not found
      return Result[seq[CompletionItem], string].ok @[]
  else:
    # Old LSP verions?
    var items: seq[CompletionItem]
    try:
      items = res["result"].to(seq[CompletionItem])
    except CatchableError as e:
      return Result[seq[CompletionItem], string].err fmt"Invalid response: {e.msg}"

    if items.len > 0:
      return Result[seq[CompletionItem], string].ok items
    else:
      # Not found
      return Result[seq[CompletionItem], string].ok @[]
