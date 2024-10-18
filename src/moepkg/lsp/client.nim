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

# NOTE: Language Server Protocol Specification - 3.17
# https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

import std/[strformat, strutils, json, options, os, posix, tables, times,
            logging]

import pkg/results
import pkg/[chronos, chronos/asyncproc]

import ../appinfo
import ../independentutils
import ../settings

import protocol/[enums, types]
import jsonrpc, utils, completion, progress, hover, semantictoken, inlayhint,
       definition, references, rename, typedefinition, implementation,
       callhierarchy, documenthighlight, documentlink, codelens, foldingrange,
       executecommand, selectionrange, documentsymbol, inlinevalue,
       signaturehelp, formatting

type
  LspError* = object
    code*: int
      # Error code.
    message*: string
      # Error message.
    data*: string
      # Error data.

  LspCapabilities* = object
    completion*: Option[LspCompletionOptions]
    definition*: bool
    diagnostics*: bool
    hover*: bool
    semanticTokens*: Option[SemanticTokensLegend]
    inlayHint*: bool
    inlineValue*: bool
    references*: bool
    rename*: bool
    typeDefinition*: bool
    implementation*: bool
    declaration*: bool
    callHierarchy*: bool
    documentHighlight*: bool
    documentLink*: bool
    codeLens*: bool
    executeCommand*: Option[seq[string]]
    foldingRange*: bool
    selectionRange*: bool
    documentSymbol*: bool
    signatureHelp*: Option[SignatureHelpOptions]
    formatting*: bool

  LspProgressTable* = Table[ProgressToken, ProgressReport]

  WaitLspResponse* = ref object
    bufferId*: int
    requestId*: int
    lspMethod*: LspMethod

  RequestId* = int

  LspClient* = ref object
    closed*: bool
      # Set true if the LSP server closed (crashed).
    serverProcess: AsyncProcessRef
      # LSP server process.
    serverStreams: Streams
      # Input/Output streams for the LSP server process.
    pollFd: TPollfd
      # FD for poll(2)
    capabilities*: Option[LspCapabilities]
      # LSP server capabilities
    progress*: LspProgressTable
      # Use in window/workDoneProgress
    waitingResponses*: Table[RequestId, WaitLspResponse]
      # Waiting responses from the LSP server.
    log*: LspLog
      # Request/Response log.
    lastId*: RequestId
      # Last request ID
    serverName*: string
      # The LSP server name
    command*: string
      # The LSP server start command

type
  R = Result

  LspClientReadableResult* = R[bool, string]

  initLspClientResult* = R[LspClient, string]

  LspRestartClientResult* = R[(), string]

  LspErrorParseResult* = R[LspError, string]
  LspSendRequestResult* = R[(), string]
  LspSendNotifyResult* = R[(), string]

  LspInitializeResult* = R[(), string]

proc running*(c: LspClient): bool {.inline.} =
  ## Return true if the LSP server process running.

  let r = c.serverProcess.running
  if r.isOk: return r.get
  else: false

proc serverProcessId*(c: LspClient): int {.inline.} =
  ## Return a process id of the LSP server process.

  c.serverProcess.processID

proc exit*(c: LspClient) {.inline.} =
  ## Exit a LSP server process.
  ## TODO: Send a shutdown request?

  discard c.serverProcess.terminate

proc kill*(c: LspClient): Result[(), string] =
  ## kill a LSP server process.

  let r = c.serverProcess.kill
  if r.isErr:
    return Result[(), string].err $r.error

  return Result[(), string].ok ()

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
  ## Also, if data can be read from the output stream, return true.
  ## timeout is milliseconds.

  const FdLen = 1
  let r = c.pollFd.addr.poll(FdLen.Tnfds, timeout)
  return LspClientReadableResult.ok r == 1

proc request(
  c: var LspClient,
  bufferId: int,
  lspMethod: LspMethod,
  params: JsonNode): Result[int, string] =
    ## Send a request to the LSP server and set to waitingResponse.
    ## Return request id.

    c.lastId.inc
    let req = newRequest(c.lastId, lspMethod.toLspMethodStr, params)

    c.addRequestLog(req)

    let r = c.serverProcess.stdinStream.sendRequest(req)
    if r.isErr:
      return Result[int, string].err r.error

    c.waitingResponses[c.lastId] = WaitLspResponse(
      bufferId: bufferId,
      requestId: c.lastId,
      lspMethod: lspMethod)

    return Result[int, string].ok c.lastId

proc notify(
  c: var LspClient,
  lspMethod: LspMethod,
  params: JsonNode): Result[(), string] {.inline.} =
    ## Send a notification to the LSP server.

    let notify = newNotify(lspMethod.toLspMethodStr, params)

    c.addNotifyFromClientLog(notify)

    return c.serverProcess.stdinStream.sendNotify(notify)

proc read*(c: var LspClient): JsonRpcResponseResult =
  ## Read a response from the LSP server.

  let r = jsonrpc.read(c.serverStreams.output.stream)
  if r.isOk:
    return JsonRpcResponseResult.ok r.get
  else:
    return JsonRpcResponseResult.err r.error

template isLspError*(res: JsonNode): bool = res.contains("error")

template isRequest*(res: JsonNode): bool =
  res.contains("id") and res.contains("method")

template isNotify*(res: JsonNode): bool =
  res.contains("method")

proc parseLspError*(res: JsonNode): LspErrorParseResult =
  try:
    return LspErrorParseResult.ok res["error"].to(LspError)
  except:
    return LspErrorParseResult.err fmt"Invalid error: {$res}"

proc setWaitResponse*(
  c: var LspClient,
  bufferId: int,
  lspMethod: LspMethod) {.inline.} =

    c.waitingResponses[c.lastId] = WaitLspResponse(
      bufferId: bufferId,
      requestId: c.lastId,
      lspMethod: lspMethod)

proc deleteWaitingResponse*(c: var LspClient, id: RequestId) {.inline.} =
  if c.waitingResponses.contains(id):
    c.waitingResponses.del(id)

proc isWaitingResponse*(c: var LspClient, bufferId: int): bool {.inline.} =
  for v in c.waitingResponses.values:
    if v.bufferId == bufferId:
      return true

proc isWaitingResponse*(
  c: var LspClient,
  bufferId: int,
  lspMethod: LspMethod): bool {.inline.} =

    for v in c.waitingResponses.values:
      if v.bufferId == bufferId and v.lspMethod == lspMethod:
        return true

proc isWaitingForegroundResponse*(
  c: var LspClient,
  bufferId: int): bool {.inline.} =

    for v in c.waitingResponses.values:
      if v.bufferId == bufferId and v.lspMethod.isForegroundWait:
        return true

proc getWaitingResponse*(
  c: LspClient,
  id: RequestId): Option[WaitLspResponse] {.inline.} =

    if c.waitingResponses.contains(id):
      return some(c.waitingResponses[id])

proc getWaitingResponse*(
  c: LspClient,
  bufferId: int,
  lspMethod: LspMethod): Option[WaitLspResponse] {.inline.} =

    for v in c.waitingResponses.values:
      if v.bufferId == bufferId and v.lspMethod == lspMethod:
        return some(v)

proc getLatestWaitingResponse*(c: var LspClient): Option[WaitLspResponse] =
  var latest = -1
  for k in c.waitingResponses.keys:
    if k > latest: latest = k

  if latest > -1:
    return some(c.waitingResponses[latest])

proc getForegroundWaitingResponse*(
  c: var LspClient,
  bufferId: int): Option[WaitLspResponse] =

    for v in c.waitingResponses.values:
      if v.bufferId == bufferId and v.lspMethod.isForegroundWait:
        return some(v)

template getFdStdout(c: LspClient): cint =
  c.serverStreams.output.stream.tsource.fd.cint

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
    opts: set[AsyncProcessOption] = {UsePath, EvalCommand, StdErrToStdOut}

  var c = LspClient()

  try:
    c.serverProcess = waitFor startProcess(
      commandSplit[0],
      WorkingDir,
      args,
      Env,
      opts,
      stdoutHandle = AsyncProcess.Pipe,
      stdinHandle = AsyncProcess.Pipe)
  except CatchableError as e:
    return initLspClientResult.err fmt"server start failed: {e.msg}"

  c.serverStreams = Streams(
    input: InputStream(stream: c.serverProcess.stdinStream),
    output: OutputStream(stream: c.serverProcess.stdoutStream))

  block:
    # Init pollFd.
    c.pollFd.addr.zeroMem(sizeof(c.pollFd))

    # Registers fd and events.
    c.pollFd.fd = c.getFdStdout
    c.pollFd.events = POLLIN or POLLERR

  c.serverName = commandSplit[0]

  c.command = command

  return initLspClientResult.ok c

proc restart*(c: var LspClient): LspRestartClientResult =
  ## Restart the LSP server process.
  ## Logs will be taken over.

  if c.running: c.exit

  let beforeLog = c.log

  var newClient = initLspClient(c.command)
  if newClient.isErr:
    return LspRestartClientResult.err newClient.error

  c = newClient.get
  c.log = beforeLog

  return LspRestartClientResult.ok ()

proc initInitializeParams*(
  serverName, workspaceRoot: string,
  trace: TraceValue,
  experimental: Option[JsonNode] = none(JsonNode)): InitializeParams =

    let
      path =
        if workspaceRoot.len == 0: none(string)
        else: some(workspaceRoot)
      uri =
        if workspaceRoot.len == 0: none(string)
        else: some(workspaceRoot.pathToUri)
      workspaceDir =
        if workspaceRoot.len == 0: getCurrentDir()
        else: workspaceRoot

    result = InitializeParams(
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
            dynamicRegistration: some(true)
          )),
          executeCommand: some(ExecuteCommandClientCapability(
            dynamicRegistration: some(true)
          )),
          codeLens: some(CodeLensWorkspaceClientCapabilities(
            refreshSupport: some(true)
          )),
          semanticTokens: some(SemanticTokensWorkspaceClientCapabilities(
            refreshSupport: some(true)
          )),
          inlayHint: some(InlayHintWorkspaceClientCapabilities(
            refreshSupport: some(true)
          ))
        )),
        textDocument: some(TextDocumentClientCapabilities(
          hover: some(HoverClientCapabilities(
            dynamicRegistration: some(true),
            contentFormat: some(@["plaintext"])
          )),
          signatureHelp: some(SignatureHelpClientCapabilities(
            dynamicRegistration: some(true),
            signatureInformation: some(SignatureInformationCapability(
              documentationFormat: some(@["plaintext"])
            ))
          )),
          publishDiagnostics: some(PublishDiagnosticsClientCapabilities(
            dynamicRegistration: some(true)
          )),
          formatting: some(DocumentFormattingClientCapabilities(
            dynamicRegistration: some(true)
          )),
          foldingRange: some(FoldingRangeClientCapabilities(
            dynamicRegistration: some(true),
            lineFoldingOnly: some(true)
          )),
          completion: some(CompletionClientCapabilities(
            dynamicRegistration: some(true),
            completionItem: some(CompletionItemCapability(
              snippetSupport: some(false),
              commitCharactersSupport: some(false),
              deprecatedSupport: some(false)
            )),
            contextSupport: some(true)
          )),
          selectionRange: some(SelectionRangeClientCapabilities(
            dynamicRegistration: some(true),
          )),
          semanticTokens: some(SemanticTokensClientCapabilities(
            dynamicRegistration: some(true),
            tokenTypes: @[],
            tokenModifiers: @[],
            formats: @[],
            requests: SemanticTokensClientCapabilitiesRequest(
              range: some(false),
              full: some(true))
          )),
          inlayHint: some(InlayHintClientCapabilities(
            dynamicRegistration: some(true),
            resolveSupport: none(InlayHintClientCapabilitiesResolveSupport)
          )),
          inlineValue: some(InlineValueClientCapabilitie(
            dynamicRegistration: some(true)
          )),
          declaration: some(DeclarationClientCapabilities(
            dynamicRegistration: some(true),
            linkSupport: some(false)
          )),
          definition: some(DefinitionClientCapabilities(
            dynamicRegistration: some(true)
          )),
          references: some(ReferenceClientCapabilities(
            dynamicRegistration: some(true)
          )),
          rename: some(RenameClientCapabilities(
            dynamicRegistration: some(true),
            prepareSupport: some(false)
          )),
          typeDefinition: some(TypeDefinitionClientCapabilities(
            dynamicRegistration: some(true),
            linkSupport: some(false)
          )),
          implementation: some(ImplementationClientCapabilities(
            dynamicRegistration: some(true),
            linkSupport: some(false)
          )),
          codeLens: some(CodeLensClientClientCapabilities(
            dynamicRegistration: some(true)
          )),
          documentHighlight: some(DocumentHighlightClientCapabilies(
            dynamicRegistration: some(true)
          )),
          documentLink: some(DocumentLinkClientCapabilities(
            dynamicRegistration: some(true),
            toolsopSupport: some(false),
          ))
        )),
        window: some(WindowCapabilities(
          workDoneProgress: some(false)
        )),
        experimental: experimental
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

proc setCapabilities(
  c: var LspClient,
  initResult: InitializeResult,
  settings: LspFeatureSettings) =
    ## Set server capabilities to the LspClient from InitializeResult.

    var capabilities = LspCapabilities()

    if settings.completion.enable and
       initResult.capabilities.completionProvider.isSome:
         capabilities.completion = initResult.capabilities.completionProvider

    if settings.formatting.enable and
       initResult.capabilities.documentFormattingProvider.isSome:
         if initResult.capabilities.documentFormattingProvider.get.kind == JBool:
           capabilities.formatting =
             initResult.capabilities.documentFormattingProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.documentFormattingProvider.get.to(
               DocumentFormattingOptions
             )
             capabilities.formatting = true
           except CatchableError:
             # Invalid documentFormattingProvider
             discard

    if settings.declaration.enable and
       initResult.capabilities.declarationProvider.isSome:
         if initResult.capabilities.declarationProvider.get.kind == JBool:
           capabilities.declaration =
             initResult.capabilities.declarationProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.declarationProvider.get.to(
               DeclarationOptions)
             capabilities.declaration = true
           except CatchableError:
             discard
           if not capabilities.declaration:
             try:
               discard initResult.capabilities.declarationProvider.get.to(
                 DeclarationRegistrationOptions)
               capabilities.declaration = true
             except CatchableError:
               # Invalid declarationProvider
               discard

    if settings.definition.enable and
       initResult.capabilities.definitionProvider.isSome:
         if initResult.capabilities.definitionProvider.get.kind == JBool:
           capabilities.definition =
             initResult.capabilities.definitionProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.definitionProvider.get.to(
               DefinitionOptions)
             capabilities.definition = true
           except:
             # Invalid definitionProvider
             discard

    if settings.typeDefinition.enable and
       initResult.capabilities.typeDefinitionProvider.isSome:
         if initResult.capabilities.typeDefinitionProvider.get.kind == JBool:
           capabilities.typeDefinition =
             initResult.capabilities.typeDefinitionProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.typeDefinitionProvider.get.to(
               TypeDefinitionOptions)
             capabilities.typeDefinition = true
           except:
             # Invalid typeDefinitionProvider
             discard

    if settings.implementation.enable and
       initResult.capabilities.implementationProvider.isSome:
         if initResult.capabilities.implementationProvider.get.kind == JBool:
           capabilities.implementation =
             initResult.capabilities.implementationProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.implementationProvider.get.to(
               ImplementationOptions)
             capabilities.implementation = true
           except CatchableError:
             discard
           if not capabilities.implementation:
             try:
               discard initResult.capabilities.implementationProvider.get.to(
                 TextDocumentAndStaticRegistrationOptions)
               capabilities.implementation = true
             except CatchableError:
               # Invalid implementationProvider
               discard

    if settings.diagnostics.enable and
       initResult.capabilities.diagnosticProvider.isSome:
         try:
           discard initResult.capabilities.diagnosticProvider.get.to(
             DiagnosticOptions)
           capabilities.diagnostics = true
         except CatchableError:
           discard
         if not capabilities.diagnostics:
           try:
             discard initResult.capabilities.diagnosticProvider.get.to(
               DiagnosticRegistrationOptions)
             capabilities.diagnostics = true
           except CatchableError:
             # Invalid diagnosticProvider
             discard

    if settings.signatureHelp.enable and
       initResult.capabilities.signatureHelpProvider.isSome:
         capabilities.signatureHelp =
           initResult.capabilities.signatureHelpProvider

    if settings.hover.enable and
       initResult.capabilities.hoverProvider.isSome:
         if initResult.capabilities.hoverProvider.get.kind == JBool:
           capabilities.hover =
             initResult.capabilities.hoverProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.hoverProvider.get.to(HoverOptions)
             capabilities.hover = true
           except:
             # Invalid hoverProvider
             discard

    if settings.inlayHint.enable and
       initResult.capabilities.inlayHintProvider.isSome:
         capabilities.inlayHint = true

    if settings.inlineValue.enable and
       initResult.capabilities.inlineValueProvider.isSome:
         if initResult.capabilities.inlineValueProvider.get.kind == JBool:
           capabilities.inlineValue =
            initResult.capabilities.inlineValueProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.inlineValueProvider.get.to(
               InlineValueOptions)
             capabilities.inlineValue = true
           except:
             discard
           if not capabilities.inlineValue:
             try:
               discard initResult.capabilities.inlineValueProvider.get.to(
                 InlineValueRegistrationOptions)
               capabilities.inlineValue = true
             except:
               # Invalid inlineValueProvider
               discard

    if settings.references.enable and
       initResult.capabilities.referencesProvider.isSome:
         if initResult.capabilities.referencesProvider.get.kind == JBool:
           capabilities.references =
             initResult.capabilities.referencesProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.referencesProvider.get.to(
               ReferenceOptions)
             capabilities.references = true
           except:
             # Invalid referencesProvider
             discard

    if settings.callHierarchy.enable and
       initResult.capabilities.callHierarchyProvider.isSome:
         if initResult.capabilities.callHierarchyProvider.get.kind == JBool:
           capabilities.callHierarchy =
             initResult.capabilities.callHierarchyProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.callHierarchyProvider.get.to(
               CallHierarchyOptions)
             capabilities.callHierarchy = true
           except CatchableError:
             discard
           if not capabilities.callHierarchy:
             try:
               discard initResult.capabilities.callHierarchyProvider.get.to(
                 CallHierarchyRegistrationOptions)
               capabilities.callHierarchy = true
             except CatchableError:
               # Invalid callHierarchyProvider
               discard

    if settings.documentHighlight.enable and
       initResult.capabilities.documentHighlightProvider.isSome:
         if initResult.capabilities.documentHighlightProvider.get.kind == JBool:
           capabilities.documentHighlight =
             initResult.capabilities.documentHighlightProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.documentHighlightProvider.get.to(
               DocumentHighlightOptions)
             capabilities.callHierarchy = true
           except CatchableError:
               # Invalid documentHighlightProvider
               discard

    if settings.documentLink.enable and
       initResult.capabilities.documentLinkProvider.isSome:
         capabilities.documentLink = true

    if settings.codeLens.enable and
       initResult.capabilities.codeLensProvider.isSome:
         capabilities.codeLens = true

    if settings.rename.enable and
       initResult.capabilities.renameProvider.isSome:
         if initResult.capabilities.renameProvider.get.kind == JBool:
           capabilities.rename =
             initResult.capabilities.renameProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.renameProvider.get.to(
               RenameOptions)
             capabilities.rename = true
           except CatchableError:
             # Invalid renameProvider
             discard

    if settings.semanticTokens.enable and
       initResult.capabilities.semanticTokensProvider.isSome and
       initResult.capabilities.semanticTokensProvider.get.contains("legend"):
         try:
           capabilities.semanticTokens = some(
             initResult.capabilities.semanticTokensProvider.get["legend"].to(
               SemanticTokensLegend))
         except CatchableError:
           # Invalid SemanticTokensLegend
           discard

    if settings.executeCommand.enable and
       initResult.capabilities.executeCommandProvider.isSome:
         capabilities.executeCommand = some(
           initResult.capabilities.executeCommandProvider.get.commands)

    if settings.foldingRange.enable and
       initResult.capabilities.foldingRangeProvider.isSome:
         if initResult.capabilities.foldingRangeProvider.get.kind == JBool:
           capabilities.foldingRange =
             initResult.capabilities.foldingRangeProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.foldingRangeProvider.get.to(
               FoldingRangeOptions)
             capabilities.rename = true
           except CatchableError:
             # Invalid foldingRangeProvider
             discard

    if settings.selectionRange.enable and
       initResult.capabilities.selectionRangeProvider.isSome:
         if initResult.capabilities.selectionRangeProvider.get.kind == JBool:
           capabilities.selectionRange =
             initResult.capabilities.selectionRangeProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.selectionRangeProvider.get.to(
               SelectionRangeOptions)
             capabilities.selectionRange = true
           except CatchableError:
             discard
           if not capabilities.selectionRange:
            try:
              discard initResult.capabilities.selectionRangeProvider.get.to(
                SelectionRangeRegistrationOptions)
              capabilities.selectionRange = true
            except CatchableError:
              # Invalid selectionRangeProvider
              discard

    if settings.documentSymbol.enable and
       initResult.capabilities.documentSymbolProvider.isSome:
         if initResult.capabilities.documentSymbolProvider.get.kind == JBool:
           capabilities.documentSymbol =
             initResult.capabilities.documentSymbolProvider.get.getBool
         else:
           try:
             discard initResult.capabilities.documentSymbolProvider.get.to(
               DocumentSymbolOptions)
             capabilities.documentSymbol = true
           except CatchableError:
             discard
             # Invalid documentSymbolProvider

    c.capabilities = some(capabilities)

proc cancelRequest*(
  c: var LspClient,
  bufferId: int,
  requestId: RequestId): LspSendNotifyResult =
    ## Send a cancelRequest notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#cancelRequest

    if not c.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    c.deleteWaitingResponse(requestId)

    let params = %* CancelParams(id: some(%*requestId))

    let err = c.notify(LspMethod.cancelRequest, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"cancelRequest notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc cancelRequest*(
  c: var LspClient,
  waitRes: WaitLspResponse): LspSendRequestResult {.inline.} =
    ## Send a cancel request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#cancelRequest

    c.cancelRequest(waitRes.bufferId, waitRes.requestId)

proc cancelRequest*(
  c: var LspClient,
  bufferId: int,
  lspMethod: LspMethod): LspSendRequestResult =

    let w = c.getWaitingResponse(bufferId, lspMethod)
    if w.isSome:
      return c.cancelRequest(w.get)

    return LspSendRequestResult.ok ()

proc cancelForegroundRequest*(
  c: var LspClient,
  bufferId: int): LspSendRequestResult =

    let w = c.getForegroundWaitingResponse(bufferId)
    if w.isSome:
      return c.cancelRequest(w.get)

    return LspSendRequestResult.ok ()

proc initialize*(
  c: var LspClient,
  bufferId: int,
  initParams: InitializeParams): LspSendRequestResult =
    ## Send a initialize request to the server and check server capabilities.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize

    if not c.running:
      if not c.closed: c.closed = true
      return LspSendRequestResult.err "server crashed"

    let params = %* initParams

    let r = c.request(bufferId, LspMethod.initialize, params)
    if r.isErr:
      return LspSendRequestResult.err fmt"Initialize request failed: {r.error}"

    return LspSendRequestResult.ok ()

proc initCapacities*(
  c: var LspClient,
  settings: LspFeatureSettings,
  res: JsonNode): LspInitializeResult =

    var initResult: InitializeResult
    try:
      initResult = res["result"].to(InitializeResult)
    except CatchableError as e:
      let msg = fmt"json to InitializeResult failed {e.msg}"
      return LspInitializeResult.err fmt"Initialize request failed: {msg}"

    c.setCapabilities(initResult, settings)

    c.deleteWaitingResponse(res["id"].getInt)

    return LspInitializeResult.ok ()

proc initialized*(c: var LspClient): LspSendNotifyResult =
  ## Send a initialized notification to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

  if not c.running:
    if not c.closed: c.closed = true
    return LspSendNotifyResult.err "server crashed"

  let params = %* {}

  let err = c.notify(LspMethod.initialized, params)
  if err.isErr:
    return LspSendNotifyResult.err fmt"Invalid notification failed: {err.error}"

  return LspSendNotifyResult.ok ()

proc shutdown*(c: var LspClient, bufferId: int): LspSendNotifyResult =
  ## Send a shutdown request to the server.
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#shutdown

  if not c.running:
    if not c.closed: c.closed = true
    return LspSendNotifyResult.err "server crashed"

  if not c.isInitialized:
    return R[(), string].err "lsp unavailable"

  let id = c.request(bufferId, LspMethod.shutdown, %*{})
  if id.isErr:
    return LspSendNotifyResult.err "Shutdown request failed: {id.error}"

  return LspSendNotifyResult.ok ()

proc workspaceDidChangeConfiguration*(
  c: var LspClient): LspSendNotifyResult =
    ## Send a workspace/didChangeConfiguration notification to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#workspace_didChangeConfiguration

    if not c.running:
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

    if not c.running:
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

    if not c.running:
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

    if not c.running:
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

    if not c.running:
      if not c.closed: c.closed = true
      return LspSendNotifyResult.err "server crashed"

    let params = %* initTextDocumentDidClose(text)

    let err = c.notify(LspMethod.textDocumentDidClose, params)
    if err.isErr:
      return LspSendNotifyResult.err fmt"textDocument/didClose notification failed: {err.error}"

    return LspSendNotifyResult.ok ()

proc textDocumentHover*(
  c: var LspClient,
  bufferId: int,
  path: string,
  position: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/hover request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_hover

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.hover:
      return R[(), string].err "textDocument/hover unavailable"

    let params = %* initHoverParams(path, position.toLspPosition)
    let id = c.request(bufferId, LspMethod.textDocumentHover, params)
    if id.isErr:
      return R[(), string].err fmt"textDocument/hover request failed: {id.error}"

    return R[(), string].ok ()

proc textDocumentCompletion*(
  c: var LspClient,
  bufferId: int,
  path: string,
  position: BufferPosition,
  isIncompleteTrigger: bool,
  character: string): LspSendRequestResult =
    ## Send a textDocument/completion request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_completion

    if not c.running:
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

    let id = c.request(bufferId, LspMethod.textDocumentCompletion, params)
    if id.isErr:
      return R[(), string].err fmt"textDocument/completion request failed: {id.error}"

    return R[(), string].ok ()

proc textDocumentSemanticTokens*(
  c: var LspClient,
  bufferId: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/semanticTokens/full request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if c.capabilities.get.semanticTokens.isNone:
      return R[(), string].err "textDocument/semanticTokens unavailable"

    let params = %* initSemanticTokensParams(path)

    let id = c.request(bufferId, LspMethod.textDocumentSemanticTokensFull, params)
    if id.isErr:
      return R[(), string].err fmt"textDocument/semanticTokens/full request failed: {id.error}"

    return R[(), string].ok ()

proc textDocumentInlayHint*(
  c: var LspClient,
  bufferId: int,
  path: string,
  range: BufferRange): LspSendRequestResult =
    ## Send a textDocument/inlayHint request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlayHint

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.inlayHint:
      return R[(), string].err "textDocument/inlayHint unavailable"

    let params = %* initInlayHintParams(path, range)

    let r = c.request(bufferId, LspMethod.textDocumentInlayHint, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/inlayHint request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentDefinition*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/definition request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_definition

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.definition:
      return R[(), string].err "textDocument/definition unavailable"

    let params = %* initDefinitionParams(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentDefinition, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/definition request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentReferences*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/references request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_references

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.references:
      return R[(), string].err "textDocument/references unavailable"

    let params = %* initReferenceParams(path, posi.toLspPosition)

    let r = c.request(bufferId, LspMethod.textDocumentReferences, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/references request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentRename*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition,
  newName: string): LspSendRequestResult =
    ## Send a textDocument/rename request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_rename

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.rename:
      return R[(), string].err "textDocument/rename unavailable"

    let params = %* initRenameParams(path, posi.toLspPosition, newName)

    let r = c.request(bufferId, LspMethod.textDocumentRename, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/rename request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentTypeDefinition*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/typeDefinition request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_typeDefinition

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.typeDefinition:
      return R[(), string].err "textDocument/typeDefinition unavailable"

    let params = %* initTypeDefinitionParams(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentTypeDefinition, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/typeDefinition request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentImplementation*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/implementation request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_implementation

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.implementation:
      return R[(), string].err "textDocument/implementation unavailable"

    let params = %* initImplementationParams(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentImplementation, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/implementation request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentDeclaration*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/declaration request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_declaration

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.declaration:
      return R[(), string].err "textDocument/declaration unavailable"

    let params = %* initImplementationParams(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentDeclaration, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/declaration request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentPrepareCallHierarchy*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/prepareCallHierarchy request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareCallHierarchy

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.callHierarchy:
      return R[(), string].err "textDocument/prepareCallHierarchy unavailable"

    let params = %* initCallHierarchyPrepareParams(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentPrepareCallHierarchy, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/prepareCallHierarchy request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentIncomingCalls*(
  c: var LspClient,
  bufferId: int,
  item: CallHierarchyItem): LspSendRequestResult =
    ## Send a callHierarchy/incomingCalls request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_incomingCalls

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.callHierarchy:
      return R[(), string].err "callHierarchy/incomingCalls unavailable"

    let params = %* initCallHierarchyIncomingParams(item)

    let r = c.request(bufferId, LspMethod.callHierarchyIncomingCalls, params)
    if r.isErr:
      return R[(), string].err fmt"callHierarchy/incomingCalls request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentOutgoingCalls*(
  c: var LspClient,
  bufferId: int,
  item: CallHierarchyItem): LspSendRequestResult =
    ## Send a callHierarchy/outgoingCalls request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_outgoingCalls

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.callHierarchy:
      return R[(), string].err "callHierarchy/outgoingCalls unavailable"

    let params = %* initCallHierarchyOutgoingParams(item)

    let r = c.request(bufferId, LspMethod.callHierarchyOutgoingCalls, params)
    if r.isErr:
      return R[(), string].err fmt"callHierarchy/outgoingCalls request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentDocumentHighlight*(
  c: var LspClient,
  bufferId: int,
  path: string,
  posi: BufferPosition): LspSendRequestResult =
    ## Send a textDocument/documentHighlight request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentHighlight

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.documentHighlight:
      return R[(), string].err "textDocument/documentHighlight unavailable"

    let params = %* initDocumentHighlightParamas(path, posi)

    let r = c.request(bufferId, LspMethod.textDocumentDocumentHighlight, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/documentHighlight request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentDocumentLink*(
  c: var LspClient,
  bufferId: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/documentLink request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentLink

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.documentLink:
      return R[(), string].err "textDocument/documentLink unavailable"

    let params = %* initDocumentLinkParams(path)

    let r = c.request(bufferId, LspMethod.textDocumentDocumentLink, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/documentLink request failed: {r.error}"

    return R[(), string].ok ()

proc documentLinkResolve*(
  c: var LspClient,
  bufferId: int,
  documentLink: DocumentLink): LspSendRequestResult =
    ## Send a documentLink/resolve request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#documentLink_resolve

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.documentLink:
      return R[(), string].err "textDocument/documentLink unavailable"

    let params = %* documentLink

    let r = c.request(bufferId, LspMethod.textDocumentDocumentLink, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/documentLink request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentCodeLens*(
  c: var LspClient,
  bufferId: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/codeLens request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_codeLens

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.codeLens:
      return R[(), string].err "textDocument/codeLens unavailable"

    let params = %* initCodeLensParams(path)

    let r = c.request(bufferId, LspMethod.textDocumentCodeLens, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/codeLens request failed: {r.error}"

    return R[(), string].ok ()

proc codeLensResolve*(
  c: var LspClient,
  bufferId: int,
  codeLens: CodeLens): LspSendRequestResult =
    ## Send a codeLens/resolve request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#codeLens_resolve

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.codeLens:
      return R[(), string].err "codeLens/resolve unavailable"

    let params = %* codeLens

    let r = c.request(bufferId, LspMethod.codeLensResolve, params)
    if r.isErr:
      return R[(), string].err fmt"codeLens/resolve request failed: {r.error}"

    return R[(), string].ok ()

proc workspaceExecuteCommand*(
  c: var LspClient,
  bufferId: int,
  command: string,
  args: JsonNode): LspSendRequestResult =
    ## Send a workspace/executeCommand request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#command

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if c.capabilities.get.executeCommand.isNone:
      return R[(), string].err "workspace/executeCommand unavailable"

    let params = %* initExecuteCommandParams(command, args)

    let r = c.request(bufferId, LspMethod.workspaceExecuteCommand, params)
    if r.isErr:
      return R[(), string].err fmt"workspace/executeCommand request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentFoldingRange*(
  c: var LspClient,
  bufferId: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/foldingRange request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_foldingRange

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.foldingRange:
      return R[(), string].err "textDocument/foldingRange unavailable"

    let params = %* initFoldingRangeParam(path)

    let r = c.request(bufferId, LspMethod.textDocumentFoldingRange, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/foldingRange request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentSelectionRange*(
  c: var LspClient,
  bufferId: int,
  path: string,
  positions: seq[BufferPosition]): LspSendRequestResult =
    ## Send a textDocument/selectionRange request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_selectionRange

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.selectionRange:
      return R[(), string].err "textDocument/foldingRange unavailable"

    let params = %* initSelectionRangeParams(path, positions)

    let r = c.request(bufferId, LspMethod.textDocumentSelectionRange, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/selectionRange request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentDocumentSymbol*(
  c: var LspClient,
  bufferId: int,
  path: string): LspSendRequestResult =
    ## Send a textDocument/symbol request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentSymbol

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.documentSymbol:
      return R[(), string].err "textDocument/documentSymbol unavailable"

    let params = %* initDocumentSymbolParams(path)

    let r = c.request(bufferId, LspMethod.textDocumentDocumentSymbol, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/documentSymbol request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentInlineValue*(
  c: var LspClient,
  bufferId: int,
  path: string,
  range: BufferRange): LspSendRequestResult =
    ## Send a textDocument/inlineValue request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlineValue

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.inlineValue:
      return R[(), string].err "textDocument/inlineValue unavailable"

    # TODO: Fix frameId
    let context = InlineValueContext(
      frameId: 0,
      stoppedLocation: range.toLspRange)
    let params = %* initInlineValueParams(path, range.toLspRange, context)

    let r = c.request(bufferId, LspMethod.textDocumentInlineValue, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/inlineValue request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentSignatureHelp*(
  c: var LspClient,
  bufferId: int,
  path: string,
  position: BufferPosition,
  kind: SignatureHelpTriggerKind,
  triggerChar: Option[string] = none(string),
  active: Option[SignatureHelp] = none(SignatureHelp)): LspSendRequestResult =
    ## Send a textDocument/signatureHelp request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp

    if not c.running:
      if not c.closed: c.closed = true
      return R[(), string].err "server crashed"

    if not c.isInitialized:
      return R[(), string].err "lsp unavailable"

    if not c.capabilities.get.signatureHelp.isSome:
      return R[(), string].err "textDocument/signatureHelp unavailable"

    let params = %* initSignatureHelpParams(
      path,
      position.toLspPosition,
      kind,
      triggerChar,
      active)

    let r = c.request(bufferId, LspMethod.textDocumentSignatureHelp, params)
    if r.isErr:
      return R[(), string].err fmt"textDocument/signatureHelp request failed: {r.error}"

    return R[(), string].ok ()

proc textDocumentFormatting*(
  c: var LspClient,
  bufferId: int,
  path: string,
  options: FormattingOptions): LspSendRequestResult =
    ## Send a textDocument/documentFormatting request to the server.
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_formatting

    if not c.running:
      if not c.closed: c.closed = true
      return LspSendRequestResult.err "server crashed"

    if not c.isInitialized:
      return LspSendRequestResult.err "lsp unavailable"

    if not c.capabilities.get.formatting:
      return LspSendRequestResult.err "textDocument/formatting unavailable"

    let params = %* initDocumentFormattingParams(path, options)

    let r = c.request(bufferId, LspMethod.textDocumentFormatting, params)
    if r.isErr:
      return
        LspSendRequestResult.err fmt"textDocument/formatting request failed: {r.error}"

    return LspSendRequestResult.ok ()
