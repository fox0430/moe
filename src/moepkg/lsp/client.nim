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

import std/[strformat, strutils, json, options, os, osproc, posix, tables,
            times]

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
    timestamp*: DateTime
    kind*: LspMessageKind
    message*: JsonNode

  LspLog* = seq[LspMessage]

  LspCapabilities* = object
    hover*: bool
    completion*: Option[LspCompletionOptions]
    semanticTokens*: Option[SemanticTokensLegend]

  LspProgressTable* = Table[ProgressToken, ProgressReport]

  LspClient* = ref object
    closed*: bool
      # Set true if the LSP server closed (crashed).
    serverProcess: Process
      # LSP server process.
    serverStreams: Streams
      # Input/Output streams for the LSP server process.
    pollFd: TPollfd
      # FD for poll(2)
    capabilities*: Option[LspCapabilities]
      # LSP server capabilities
    progress*: LspProgressTable
      # Use in window/workDoneProgress
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

template addRequestLog*(c: var LspClient, m: JsonNode) =
  c.log.add LspMessage(
    timestamp: now(),
    kind: LspMessageKind.request,
    message: m)

template addResponseLog*(c: var LspClient, m: JsonNode) =
  c.log.add LspMessage(
    timestamp: now(),
    kind: LspMessageKind.response,
    message: m)

template addNotifyFromClientLog*(c: var LspClient, m: JsonNode) =
  c.log.add LspMessage(
    timestamp: now(),
    kind: LspMessageKind.notifyFromClient,
    message: m)

template addNotifyFromServerLog*(c: var LspClient, m: JsonNode) =
  c.log.add LspMessage(
    timestamp: now(),
    kind: LspMessageKind.notifyFromServer,
    message: m)

proc clearWaitingResponse*(c: var LspClient) {.inline.} =
  c.waitingResponse = none(LspMethod)

proc createProgress*(c: var LspClient, token: ProgressToken) =
  ## Add a new progress to the `LspClint.progress`.

  if not c.progress.contains(token):
    c.progress[token] = ProgressReport(state: ProgressState.create)

proc beginProgress*(
  c: var LspClient,
  token: ProgressToken,
  p: WorkDoneProgressBegin): Result[(), string] =
    ## Begin the progress in the `LspClint.progress`.

    if not c.progress.contains(token):
      return Result[(), string].err "token not found"

    c.progress[token].state = ProgressState.begin
    c.progress[token].title = p.title
    if p.message.isSome:
      c.progress[token].message = p.message.get
    if p.percentage.isSome:
      c.progress[token].percentage = some(p.percentage.get.Natural)

    return Result[(), string].ok ()

proc reportProgress*(
  c: var LspClient,
  token: ProgressToken,
  report: WorkDoneProgressReport): Result[(), string] =
    ## Update the progress in the `LspClint.progress`.

    if not c.progress.contains(token):
      return Result[(), string].err "token not found"

    if ProgressState.report != c.progress[token].state:
      c.progress[token].state = ProgressState.report

    if report.message.isSome:
      c.progress[token].message = report.message.get
    if report.percentage.isSome:
      c.progress[token].percentage = some(report.percentage.get.Natural)

    return Result[(), string].ok ()

proc endProgress*(
  c: var LspClient,
  token: ProgressToken,
  p: WorkDoneProgressEnd): Result[(), string] =
    ## End the progress in the `LspClint.progress`.

    if not c.progress.contains(token):
      return Result[(), string].err "token not found"

    c.progress[token].state = ProgressState.end

    if p.message.isSome:
      c.progress[token].message = p.message.get

    return Result[(), string].ok ()

proc delProgress*(c: var LspClient, token: ProgressToken): Result[(), string] =
  ## Delete the progress from the `LspClint.progress`.

  if not c.progress.contains(token):
    return Result[(), string].err "token not found"

  c.progress.del(token)

  return Result[(), string].ok ()

proc readable*(c: LspClient, timeout: int = 1): LspClientReadableResult =
  ## Return when output is written from the LSP server or timesout.
  ## Wait for the output from process to be written using poll(2).
  ## Return true if readable and Return false if timeout.
  ## timeout is milliseconds.

  # Wait a server response.
  const FdLen = 1
  let r = c.pollFd.addr.poll(FdLen.Tnfds, timeout)
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

    let req = newReqest(id, lspMethod.toLspMethodStr, params)

    c.addRequestLog(req)

    let r = c.serverStreams.sendRequest(req)
    if r.isErr:
      return Result[(), string].err r.error

    c.waitingResponse = some(lspMethod)

    return Result[(), string].ok ()

proc notify(
  c: var LspClient,
  lspMethod: LspMethod,
  params: JsonNode): Result[(), string] {.inline.} =
    ## Send a notification to the LSP server.

    let notify = newNotify(lspMethod.toLspMethodStr, params)

    c.addNotifyFromClientLog(notify)

    return c.serverStreams.sendNotify(notify)

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
  if fcntl(p.outputHandle.cint, F_SETFL, 0) < 0:
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
    opts: set[ProcessOption] = {poUsePath}

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

  block:
    # Init pollFd.
    c.pollFd.addr.zeroMem(sizeof(c.pollFd))

    # Registers fd and events.
    c.pollFd.fd = c.serverProcess.outputHandle.cint
    c.pollFd.events = POLLIN or POLLERR

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
          applyEdit: some(true),
          didChangeConfiguration: some(DidChangeConfigurationCapability(
            dynamicRegistration: some(true)))
        )),
        textDocument: some(TextDocumentClientCapabilities(
          hover: some(HoverCapability(
            dynamicRegistration: some(true),
            contentFormat: some(@["plaintext"])
          )),
          publishDiagnostics: some(PublishDiagnosticsCapability(
            dynamicRegistration: some(true)
          )),
          completion: some(CompletionCapability(
            dynamicRegistration: some(true),
            completionItem: some(CompletionItemCapability(
              snippetSupport: some(false),
              commitCharactersSupport: some(false),
              deprecatedSupport: some(false)
            )),
            contextSupport: some(true)
          )),
          semanticTokens: some(SemanticTokensClientCapabilities(
            dynamicRegistration: some(true),
            tokenTypes: @[],
            tokenModifiers: @[],
            formats: @[],
            requests: SemanticTokensClientCapabilitiesRequest(
              range: some(false),
              full: some(true))
            ))
        )),
        window: some(WindowCapabilities(
          workDoneProgress: some(true)
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

  var capabilities = LspCapabilities()

  if initResult.capabilities.hoverProvider == some(true):
    capabilities.hover = true

  if initResult.capabilities.completionProvider.isSome:
    capabilities.completion = initResult.capabilities.completionProvider

  if initResult.capabilities.semanticTokensProvider.isSome:
    if initResult.capabilities.semanticTokensProvider.get.contains("legend"):
      try:
        capabilities.semanticTokens = some(
          initResult.capabilities.semanticTokensProvider.get["legend"].to(
            SemanticTokensLegend))
      except CatchableError:
        # Invalid SemanticTokensLegend
        discard

  c.capabilities = some(capabilities)

proc initialize*(
  c: var LspClient,
  id: int,
  initParams: InitializeParams): LspSendRequestResult =
    ## Send a initialize request to the server and check server capabilities.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendRequestResult.err "server crashed"

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

proc initialized*(c: var LspClient): LspSendNotifyResult =
  ## Send a initialized notification to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

  if not c.serverProcess.running:
    if not c.closed: c.closed = true
    return LspSendNotifyResult.err "server crashed"

  let params = %* {}

  let err = c.notify(LspMethod.initialized, params)
  if err.isErr:
    return LspSendNotifyResult.err fmt"Invalid notification failed: {err.error}"

  return LspSendNotifyResult.ok ()

proc shutdown*(c: var LspClient, id: int): LspSendNotifyResult =
  ## Send a shutdown request to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown

  if not c.serverProcess.running:
    if not c.closed: c.closed = true
    return LspSendNotifyResult.err "server crashed"

  if not c.isInitialized:
    return R[(), string].err "lsp unavailable"

  let r = c.request(id, LspMethod.shutdown, %*{})
  if r.isErr:
    return LspSendNotifyResult.err "Shutdown request failed: {r.error}"

  c.waitingResponse = some(LspMethod.shutdown)

  return LspSendNotifyResult.ok ()

proc workspaceDidChangeConfiguration*(
  c: var LspClient): LspSendNotifyResult =
    ## Send a workspace/didChangeConfiguration notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_didChangeConfiguration

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

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
  c: var LspClient,
  path, languageId, text: string): LspSendNotifyResult =
    ## Send a textDocument/didOpen notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

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
  path, text: string,
  range: Option[BufferRange] = none(BufferRange)): DidChangeTextDocumentParams {.inline.} =

    if range.isSome:
      ## Send range
      return DidChangeTextDocumentParams(
        textDocument: VersionedTextDocumentIdentifier(
          uri: path.pathToUri,
          version: some(%version)),
        contentChanges: @[
          TextDocumentContentChangeEvent(
            text: text,
            range: some(range.get.toLspRange))
        ])
    else:
      ## Send all text
      return DidChangeTextDocumentParams(
        textDocument: VersionedTextDocumentIdentifier(
          uri: path.pathToUri,
          version: some(%version)),
        contentChanges: @[TextDocumentContentChangeEvent(text: text)])

proc textDocumentDidChange*(
  c: var LspClient,
  version: Natural,
  path, text: string,
  range: Option[BufferRange] = none(BufferRange)): LspSendNotifyResult =
    ## Send a textDocument/didChange notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    let params = %* initTextDocumentDidChangeParams(version, path, text, range)

    let err = c.notify(LspMethod.textDocumentDidChange, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didChange notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initTextDocumentDidSaveParams(
  version: Natural,
  path, text: string): DidSaveTextDocumentParams {.inline.} =

    DidSaveTextDocumentParams(
      textDocument: VersionedTextDocumentIdentifier(
        uri: path.pathToUri,
        version: some(%version)),
      text: some(text))

proc textDocumentDidSave*(
  c: var LspClient,
  version: Natural,
  path, text: string): LspSendNotifyResult =
    ## Send a textDocument/didSave notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didSave

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    let params = %* initTextDocumentDidSaveParams(version, path, text)

    let err = c.notify(LspMethod.textDocumentDidChange, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didSave notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc initTextDocumentDidClose(
  path: string): DidCloseTextDocumentParams {.inline.} =

    DidCloseTextDocumentParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc textDocumentDidClose*(
  c: var LspClient,
  text: string): LspSendNotifyResult =
    ## Send a textDocument/didClose notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didClose

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

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
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.hover:
      return R[(), string].err "textDocument/hover unavailable"

    let params = %* initHoverParams(path, position.toLspPosition)
    let r = c.request(id, LspMethod.textDocumentHover, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/hover request failed: {r.error}"

    c.waitingResponse = some(LspMethod.textDocumentHover)

    return R[(), string].ok ()

proc initCompletionParams*(
  path: string,
  position: BufferPosition,
  options: LspCompletionOptions,
  isIncompleteTrigger: bool,
  character: string): CompletionParams =

    let
      triggerChar =
        if isTriggerCharacter(options, character): some(character)
        else: none(string)

      triggerKind =
        if triggerChar.isSome:
          CompletionTriggerKind.TriggerCharacter.int
        elif isIncompleteTrigger:
          CompletionTriggerKind.TriggerForIncompleteCompletions.int
        else:
          CompletionTriggerKind.Invoked.int

    return CompletionParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position.toLspPosition,
      context: some(CompletionContext(
        triggerKind: triggerKind,
        triggerCharacter: triggerChar)))

proc textDocumentCompletion*(
  c: var LspClient,
  id: int,
  path: string,
  position: BufferPosition,
  isIncompleteTrigger: bool,
  character: string): LspSendRequestResult =
    ## Send a textDocument/completion request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_completion

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.completion.isSome:
      return R[(), string].err "textDocument/completion unavailable"

    let params = %* initCompletionParams(
      path,
      position,
      c.capabilities.get.completion.get,
      isIncompleteTrigger,
      character)

    let r = c.request(id, LspMethod.textDocumentCompletion, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/completion request failed: {r.error}"

    c.waitingResponse = some(LspMethod.textDocumentCompletion)

    return R[(), string].ok ()

proc initSemanticTokensParams*(path: string): SemanticTokensParams =
  SemanticTokensParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc textDocumentSemanticTokens*(
  c: var LspClient,
  id: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/semanticTokens/full request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens

    if not c.serverProcess.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if c.capabilities.get.semanticTokens.isNone:
      return R[(), string].err "textDocument/semanticTokens unavailable"

    let params = %* initSemanticTokensParams(path)

    let r = c.request(id, LspMethod.textDocumentSemanticTokensFull, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/semanticTokens/full request failed: {r.error}"

    c.waitingResponse = some(LspMethod.textDocumentSemanticTokensFull)

    return R[(), string].ok ()
