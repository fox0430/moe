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

import std/[strformat, strutils, json, options, os, osproc, posix]
import pkg/results

import ../appinfo
import ../independentutils

import protocol/[enums, types]
import jsonrpc, utils

type
  LspError* = object
    code*: int
      # Error code.
    message*: string
      # Error message.
    data*: string
      # Error data.

  LspMessageKind* = enum
    request
    response
    notifyFromClient
    notifyFromServer

  LspMessage* = object
    kind*: LspMessageKind
    message*: JsonNode

  LspLog* = seq[LspMessage]

  LspCapabilities* = object
    hover*: bool

  LspClient* = ref object
    serverProcess: Process
      # LSP server process.
    serverStreams: Streams
      # Input/Output streams for the LSP server process.
    capabilities*: Option[LspCapabilities]
      # LSP server capabilities
    waitingResponse*: Option[LspMethod]
      # The waiting response from the LSP server.
    log*: LspLog
      # Request/Response log.

type
  R = Result

  LspClientReadableResult* = R[bool, string]

  initLspClientResult* = R[LspClient, string]

  LspErrorParseResult* = R[LspError, string]
  LspSendRequestResult* = R[(), string]
  LspSendNotifyResult* = R[(), string]

  LspInitializeResult* = R[(), string]

proc pathToUri(path: string): string =
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

proc running*(c: LspClient): bool {.inline.} =
  ## Return true if the LSP server process running.

  c.serverProcess.running

proc serverProcessId*(c: LspClient): int {.inline.} =
  ## Return a process id of the LSP server process.

  c.serverProcess.processID

proc exit*(c: LspClient) {.inline.} =
  ## Exit a LSP server process.
  ## TODO: Send a shutdown request?

  c.serverProcess.terminate

template isInitialized*(c: LspClient): bool = c.capabilities.isSome

proc addRequestLog*(c: var LspClient, m: JsonNode) {.inline.} =
  c.log.add LspMessage(kind: LspMessageKind.request, message: m)

proc addResponseLog*(c: var LspClient, m: JsonNode) {.inline.} =
  c.log.add LspMessage(kind: LspMessageKind.response, message: m)

proc addNotifyFromClientLog*(c: var LspClient, m: JsonNode) {.inline.} =
  c.log.add LspMessage(kind: LspMessageKind.notifyFromClient, message: m)

proc addNotifyFromServerLog*(c: var LspClient, m: JsonNode) {.inline.} =
  c.log.add LspMessage(kind: LspMessageKind.notifyFromServer, message: m)

proc clearWaitingResponse*(c: var LspClient) {.inline.} =
  c.waitingResponse = none(LspMethod)

proc readable*(c: LspClient, timeout: int = 1): LspClientReadableResult =
  ## Return when output is written from the LSP server or timesout.
  ## Wait for the output from process to be written using poll(2).
  ## Return true if readable and Return false if timeout.
  ## timeout is milliseconds.

  # Init pollFd.
  var pollFd: TPollfd
  pollFd.addr.zeroMem(sizeof(pollFd))

  # Registers fd and events.
  pollFd.fd = c.serverProcess.outputHandle.cint
  pollFd.events = POLLIN or POLLERR

  # Wait a server response.
  const FdLen = 1
  let r = pollFd.addr.poll(FdLen.Tnfds, timeout)
  if r == 1:
    return LspClientReadableResult.ok true
  else:
    # Timeout
    return LspClientReadableResult.ok false

proc request(
  c: var LspClient,
  id: int,
  lspMethod: LspMethod,
  params: JsonNode): Result[(), string] =
    ## Send a request to the LSP server and set to waitingResponse.

    let r = c.serverStreams.sendRequest(id, lspMethod.toLspMethodStr, params)
    if r.isErr:
      return Result[(), string].err r.error

    c.waitingResponse = some(lspMethod)

    return Result[(), string].ok ()

proc notify(
  c: LspClient,
  lspMethod: LspMethod,
  params: JsonNode): Result[(), string] {.inline.} =
    ## Send a notification to the LSP server.

    return c.serverStreams.sendNotify(lspMethod.toLspMethodStr, params)

proc read*(c: var LspClient): JsonRpcResponseResult =
  ## Read a response from the LSP server.

  let r = c.serverStreams.output.read
  if r.isOk:
    return JsonRpcResponseResult.ok r.get
  else:
    return JsonRpcResponseResult.err r.error

template isLspError*(res: JsonNode): bool = res.contains("error")

template isServerNotify*(res: JsonNode): bool = res.contains("method")

proc parseLspError*(res: JsonNode): LspErrorParseResult =
  try:
    return LspErrorParseResult.ok res["error"].to(LspError)
  except:
    return LspErrorParseResult.err fmt"Invalid error: {$res}"

proc setNonBlockingOutput(p: Process): Result[(), string] =
  if fcntl(p.outputHandle.cint, F_SETFL, O_NONBLOCK) < 0:
    return Result[(), string].err "fcntl failed"

  return Result[(), string].ok ()

proc initLspClient*(command: string): initLspClientResult =
  ## Start a LSP server process and init streams.

  const
    WorkingDir = ""
    Env = nil
  let
    commandSplit = command.split(' ')
    args =
      if commandSplit.len > 1: commandSplit[1 .. ^1]
      else: @[]
    opts: set[ProcessOption] = {poStdErrToStdOut, poUsePath}

  var c = LspClient()

  try:
    c.serverProcess = startProcess(
      commandSplit[0],
      WorkingDir,
      args,
      Env,
      opts)
  except CatchableError as e:
    return initLspClientResult.err fmt"server start failed: {e.msg}"

  block:
    let r = c.serverProcess.setNonBlockingOutput
    if r.isErr:
      return initLspClientResult.err fmt"setNonBlockingOutput failed: {r.error}"

  c.serverStreams = Streams(
    input: InputStream(stream: c.serverProcess.inputStream),
    output: OutputStream(stream: c.serverProcess.outputStream))

  return initLspClientResult.ok c

proc initInitializeParams*(
  workspaceRoot: string,
  trace: TraceValue): InitializeParams =
    let
      path =
        if workspaceRoot.len == 0: none(string)
        else: some(workspaceRoot)
      uri =
        if workspaceRoot.len == 0: none(string)
        else: some(workspaceRoot.pathToUri)

      workspaceDir = getCurrentDir()

    # TODO: WIP. Need to set more correct parameters.
    InitializeParams(
      processId: some(%getCurrentProcessId()),
      rootPath: path,
      rootUri: uri,
      locale: some("en_US"),
      clientInfo: some(ClientInfo(
        name: "moe",
        version: some(moeSemVersionStr())
      )),
      capabilities: ClientCapabilities(
        workspace: some(WorkspaceClientCapabilities(
          applyEdit: some(true)
        )),
        textDocument: some(TextDocumentClientCapabilities(
          hover: some(HoverCapability(
            dynamicRegistration: some(true),
            contentFormat: some(@["plaintext"])
          ))
        ))
      ),
      workspaceFolders: some(
        @[
          WorkspaceFolder(
            uri: workspaceDir.pathToUri,
            name: workspaceDir.splitPath.tail)
        ]
      ),
      trace: some($trace)
    )

proc setCapabilities(c: var LspClient, initResult: InitializeResult) =
  ## Set server capabilities to the LspClient from InitializeResult.

  if initResult.capabilities.hoverProvider == some(true):
    c.capabilities = some(LspCapabilities(hover: true))

proc initialize*(
  c: var LspClient,
  id: int,
  initParams: InitializeParams): LspSendRequestResult =
    ## Send a initialize request to the server and check server capabilities.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize

    if not c.serverProcess.running:
      return LspSendRequestResult.err fmt"server crashed"

    let params = %* initParams

    let r = c.request(id, LspMethod.initialize, params)
    if r.isErr:
      return LspSendRequestResult.err fmt"Initialize request failed: {r.error}"

    return LspSendRequestResult.ok ()

proc initCapacities*(
  c: var LspClient,
  res: JsonNode): LspInitializeResult =
    defer:
      c.clearWaitingResponse

    var initResult: InitializeResult
    try:
      initResult = res["result"].to(InitializeResult)
    except CatchableError as e:
      let msg = fmt"json to InitializeResult failed {e.msg}"
      return LspInitializeResult.err fmt"Initialize request failed: {msg}"

    c.setCapabilities(initResult)

    return LspInitializeResult.ok ()

proc initialized*(c: LspClient): LspSendNotifyResult =
  ## Send a initialized notification to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

  if not c.serverProcess.running:
    return LspSendNotifyResult.err fmt"server crashed"

  let params = %* {}

  let err = c.notify(LspMethod.initialized, params)
  if err.isErr:
    return LspSendNotifyResult.err fmt"Invalid notification failed: {err.error}"

  return LspSendNotifyResult.ok ()

proc shutdown*(c: var LspClient, id: int): LspSendNotifyResult =
  ## Send a shutdown request to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown

  if not c.serverProcess.running:
    return LspSendNotifyResult.err fmt"server crashed"

  let r = c.request(id, LspMethod.shutdown, %*{})
  if r.isErr:
    return LspSendNotifyResult.err "Shutdown request failed: {r.error}"

  c.waitingResponse = some(LspMethod.shutdown)

  return LspSendNotifyResult.ok ()

proc workspaceDidChangeConfiguration*(
  c: LspClient): LspSendNotifyResult =
    ## Send a workspace/didChangeConfiguration notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_didChangeConfiguration

    if not c.serverProcess.running:
      return LspSendNotifyResult.err fmt"server crashed"

    let params = %* DidChangeConfigurationParams()

    let err = c.notify(LspMethod.workspaceDidChangeConfiguration, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"Invalid workspace/didChangeConfiguration failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initTextDocumentDidOpenParams(
  uri, languageId, text: string): DidOpenTextDocumentParams {.inline.} =

    DidOpenTextDocumentParams(
      textDocument: TextDocumentItem(
        uri: uri,
        languageId: languageId,
        version: 1,
        text: text))

proc textDocumentDidOpen*(
  c: LspClient,
  path, languageId, text: string): LspSendNotifyResult =
    ## Send a textDocument/didOpen notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen

    if not c.serverProcess.running:
      return LspSendNotifyResult.err fmt"server crashed"

    let params = %* initTextDocumentDidOpenParams(
      path.pathToUri,
      languageId,
      text)

    let err = c.notify(LspMethod.textDocumentDidOpen, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didOpen notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initTextDocumentDidChangeParams(
  version: Natural,
  path, text: string): DidChangeTextDocumentParams {.inline.} =

    DidChangeTextDocumentParams(
      textDocument: VersionedTextDocumentIdentifier(
        uri: path.pathToUri,
        version: some(%version)),
      contentChanges: @[TextDocumentContentChangeEvent(text: text)])

proc textDocumentDidChange*(
  c: LspClient,
  version: Natural,
  path, text: string): LspSendNotifyResult =
    ## Send a textDocument/didChange notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange

    if not c.serverProcess.running:
      return LspSendNotifyResult.err fmt"server crashed"

    let params = %* initTextDocumentDidChangeParams(version, path, text)

    let err = c.notify(LspMethod.textDocumentDidChange, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didChange notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initTextDocumentDidClose(
  path: string): DidCloseTextDocumentParams {.inline.} =

    DidCloseTextDocumentParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc textDocumentDidClose*(
  c: LspClient,
  text: string): LspSendNotifyResult =
    ## Send a textDocument/didClose notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didClose

    if not c.serverProcess.running:
      return LspSendNotifyResult.err fmt"server crashed"

    let params = %* initTextDocumentDidClose(text)

    let err = c.notify(LspMethod.textDocumentDidClose, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didClose notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initHoverParams(
  path: string,
  position: LspPosition): HoverParams {.inline.} =

    HoverParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position)

proc textDocumentHover*(
  c: var LspClient,
  id: int,
  path: string,
  position: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/hover request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_hover

    if not c.serverProcess.running:
      return R[(), string].err fmt"server crashed"

    if not c.capabilities.get.hover:
      return R[(), string].err fmt"textDocument/hover unavailable"

    let params = %* initHoverParams(path, position.toLspPosition)
    let r = c.request(id, LspMethod.textDocumentHover, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/hover request failed: {r.error}"

    c.waitingResponse = some(LspMethod.textDocumentHover)

    return R[(), string].ok ()
