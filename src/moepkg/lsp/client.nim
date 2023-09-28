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

# NOTE: Language Server Protocol Specification - 3.17
# https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

import std/[strformat, strutils, json, options, os, osproc]
import pkg/results
import ../[appinfo, independentutils, unicodeext]
import protocol/types
import jsonrpc

type
  LspPosition* = types.Position

  HoverContent* = object
    title*: Runes
    description*: seq[Runes]

  LspError* = object
    code*: int
      # Error code.
    message*: string
      # Error message.
    data*: string
      # Error data.

  LspClient* = ref object
    serverProcess: Process
      # LSP server process.
    serverStreams: Streams
      # Streams for the LSP server process.
    isInitialized*: bool
      # Set true if initialized LSP client/server.

type
  R = Result

  LspErrorParseResult* = R[LspError, string]
  LspInitializeResult* = R[InitializeResult, string]
  LspInitializedResult* = R[(), string]
  LspShutdownResult* = R[(), string]
  LspDidOpenTextDocumentResult* = R[(), string]
  LspDidChangeTextDocumentResult* = R[(), string]
  LspDidCloseTextDocumentResult* = R[(), string]
  LspHoverResult* = R[Hover, string]

proc toLspPosition*(p: BufferPosition): LspPosition {.inline.} =
  LspPosition(line: p.line, character: p.column)

proc pathToUri(path: string): string =
  # This is a modified copy of encodeUrl in the uri module. This doesn't encode
  # the / character, meaning a full file path can be passed in without breaking
  # it.

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

proc serverProcessId*(c: LspClient): int {.inline.} =
  ## Return a process id of the LSP server process.

  c.serverProcess.processID

proc send(
  c: LspClient,
  id: int,
  methodName: string,
  params: JsonNode): JsonRpcResponseResult =
    ## Send a request to the LSP server and return a response.

    return c.serverStreams.sendRequest(id, methodName, params)

proc notify(
  c: LspClient,
  methodName: string,
  params: JsonNode) {.inline.} =
    ## Send a notification to the LSP server.

    c.serverStreams.sendNotify(methodName, params)

proc isLspError(res: JsonNode): bool {.inline.} = res.contains("error")

proc parseLspError*(res: JsonNode): LspErrorParseResult =
  try:
    return LspErrorParseResult.ok res["error"].to(LspError)
  except:
    return LspErrorParseResult.err fmt"Invalid error: {$res}"

proc initLspClient*(serverCommand: string): LspClient =
  ## Start a LSP server process and init streams.

  const
    WorkingDir = ""
    Env = nil
  let
    commandSplit = serverCommand.split(' ')
    args =
      if commandSplit.len > 1: commandSplit[1 .. ^1]
      else: @[]
    opts: set[ProcessOption] = {poStdErrToStdOut, poUsePath}

  result = LspClient(
    serverProcess: startProcess(commandSplit[0], WorkingDir, args, Env, opts))
  result.serverStreams = Streams(
    input: result.serverProcess.inputStream,
    output: result.serverProcess.outputStream)

proc initInitializeParams*(workspaceRoot: string): InitializeParams =
  let
    path =
      if workspaceRoot.len == 0: none(string)
      else: some(workspaceRoot)
    uri =
      if workspaceRoot.len == 0: none(string)
      else: some(workspaceRoot.pathToUri)

  # TODO: WIP. Need to set more correct parameters.
  InitializeParams(
    processId: some(%getCurrentProcessId()),
    rootPath: path,
    rootUri: uri,
    clientInfo: some(ClientInfo(
      name: "moe",
      version: some(moeSemVersionStr()))),
    capabilities: ClientCapabilities())

proc initialize*(
  c: LspClient,
  id: int,
  initParams: InitializeParams): LspInitializeResult =
    ## Send a initialize request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize

    let params = %* initParams

    let r = c.send(id, "initialize", params)
    if r.isErr:
      return LspInitializeResult.err fmt"lsp: Initialize request failed: {r.error}"

    if r.get.isLspError:
      return LspInitializeResult.err fmt"lsp: Initialize request failed: {$r.error}"

    try:
      return LspInitializeResult.ok r.get["result"].to(InitializeResult)
    except CatchableError as e:
      let msg = fmt"json to InitializeResult failed {e.msg}"
      return LspInitializeResult.err fmt"lsp: Initialize request failed: {msg}"

proc initialized*(c: LspClient): LspInitializedResult =
  ## Send a initialized notification to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

  let params = %* {}
  c.notify("initialized", params)

  c.isInitialized = true

  return LspInitializedResult.ok ()

proc shutdown*(c: LspClient, id: int): LspShutdownResult =
  ## Send a shutdown request to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown

  let r = c.send(id, "shutdown", %*{})
  if r.isErr:
    return LspShutdownResult.err "lsp: Shutdown request failed: {r.error}"

  if r.get.isLspError:
    return LspShutdownResult.err fmt"lsp: Shutdown request failed: {$r.error}"

  if r.get["result"].kind == JNull: return LspShutdownResult.ok ()
  else: return LspShutdownResult.err fmt"lsp: Shutdown request failed: {r.get}"

proc initTextDocumentDidOpenParams(
  version: int,
  uri, languageId, text: string): DidOpenTextDocumentParams {.inline.} =

    DidOpenTextDocumentParams(
      textDocument: TextDocumentItem(
        uri: uri,
        languageId: languageId,
        version: version,
        text: text))

proc textDocumentDidOpen*(
  c: LspClient,
  version: int,
  path, languageId, text: string): LspDidOpenTextDocumentResult =
    ## Send a textDocument/didOpen notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen

    let params = %* initTextDocumentDidOpenParams(
      version,
      path.pathToUri,
      languageId,
      text)
    c.notify("textDocument/didOpen", params)

    return LspDidOpenTextDocumentResult.ok ()

proc initTextDocumentDidChangeParams(
  version: int,
  text: string): DidChangeTextDocumentParams {.inline.} =

    DidChangeTextDocumentParams(
      textDocument: VersionedTextDocumentIdentifier(version: some(%version)),
      contentChanges: @[TextDocumentContentChangeEvent(text: text)])

proc textDocumentDidChange*(
  c: LspClient,
  version: int,
  text: string): LspDidChangeTextDocumentResult =
    ## Send a textDocument/didChange notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange

    let params = %* initTextDocumentDidChangeParams(version, text)
    c.notify("textDocument/didChange", params)

    return LspDidChangeTextDocumentResult.ok ()

proc initTextDocumentDidClose(
  path: string): DidCloseTextDocumentParams {.inline.} =

    DidCloseTextDocumentParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc textDocumentDidClose*(
  c: LspClient,
  text: string): LspDidCloseTextDocumentResult =
    ## Send a textDocument/didClose notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didClose

    let params = %* initTextDocumentDidClose(text)
    c.notify("textDocument/didClose", params)

    return LspDidChangeTextDocumentResult.ok ()

proc initHoverParams(
  path: string,
  position: LspPosition): HoverParams {.inline.} =

    HoverParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position)

proc toHoverContent*(hover: Hover): HoverContent =
  let contents = %*hover.contents
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

proc toRunes*(hoverContent: HoverContent): seq[Runes] =
  if hoverContent.title.len > 0:
    result.add @[hoverContent.title, ru""]

  for line in hoverContent.description:
    result.add line

proc textDocumentHover*(
  c: LspClient,
  id: int,
  path: string,
  position: BufferPosition): LspHoverResult =
    ## Send a textDocument/hover request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_hover

    let params = %* initHoverParams(path, position.toLspPosition)
    let r = c.send(id, "textDocument/hover", params)
    if r.isErr:
      return LspHoverResult.err fmt"lsp: textDocument/hover request failed: {r.error}"

    if r.get.isLspError:
      return LspHoverResult.err fmt"lsp: textDocument/hover request failed: {$r.error}"

    try:
      return LspHoverResult.ok r.get["result"].to(Hover)
    except CatchableError as e:
      let msg = fmt"json to Hover failed {e.msg}"
      return LspHoverResult.err fmt"lsp: textDocument/hover request failed: {msg}"
