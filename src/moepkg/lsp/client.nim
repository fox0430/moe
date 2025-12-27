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

## LSP Client Implementation using chronos async I/O
## Manages communication with Language Server Protocol servers

import std/[json, options, os, strutils, tables]

import pkg/results
import pkg/chronos
import pkg/chronos/asyncproc

import jsonrpc
import protocol/types
import ../appinfo
import ../logger

export types
export chronos

type
  LspServerState* = enum
    lssStopped
    lssStarting
    lssRunning
    lssShuttingDown
    lssCrashed

  WaitingResponse* = object
    id*: RequestId
    methodName*: string

  LspClient* = ref object
    state*: LspServerState
    languageId*: string
    serverCommand*: string
    serverArgs*: seq[string]
    workspaceRoot*: string
    serverProcess: AsyncProcessRef
    serverStreams: Streams
    outputStreamFuture: Future[JsonRpcResponseResult]
    rpcState: JsonRpcState
    capabilities*: Option[ServerCapabilities]
    serverInfo*: Option[ServerInfo]
    waitingResponses*: Table[RequestId, WaitingResponse]
    pendingInitRequest: Option[RequestId] # Tracks pending initialize request
    needsSendInitialized*: bool # True when we need to send "initialized" notification
    initError*: string # Error message if initialization failed
    # Callbacks for server notifications
    onDiagnostics*: proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.}
    onLogMessage*: proc(msgType: MessageType, message: string) {.gcsafe.}
    onShowMessage*: proc(msgType: MessageType, message: string) {.gcsafe.}

proc newLspClient*(
    languageId, command: string, args: seq[string] = @[], workspaceRoot: string = ""
): LspClient =
  ## Create a new LSP client
  LspClient(
    state: lssStopped,
    languageId: languageId,
    serverCommand: command,
    serverArgs: args,
    workspaceRoot:
      if workspaceRoot.len > 0:
        workspaceRoot
      else:
        getCurrentDir(),
    serverProcess: nil,
    serverStreams: nil,
    outputStreamFuture: nil,
    rpcState: newJsonRpcState(),
    capabilities: none(ServerCapabilities),
    serverInfo: none(ServerInfo),
    waitingResponses: initTable[RequestId, WaitingResponse](),
    pendingInitRequest: none(RequestId),
    needsSendInitialized: false,
    onDiagnostics: nil,
    onLogMessage: nil,
    onShowMessage: nil,
  )

proc running*(client: LspClient): bool {.inline.} =
  ## Return true if the LSP server process is running
  if client.serverProcess.isNil:
    return false
  let r = client.serverProcess.running
  if r.isOk:
    return r.get
  return false

proc isRunning*(client: LspClient): bool =
  client.state == lssRunning and client.running

proc isStopped*(client: LspClient): bool =
  client.state == lssStopped

proc isInitialized*(client: LspClient): bool =
  client.capabilities.isSome

proc isStarting*(client: LspClient): bool =
  ## Check if the client is currently starting/initializing
  client.state == lssStarting

proc isReady*(client: LspClient): bool =
  ## Check if the client is fully ready to handle requests
  client.state == lssRunning and client.running and client.capabilities.isSome

# Forward declarations
proc readable*(client: LspClient): Result[bool, string]
proc handleNotification*(client: LspClient, meth: string, params: JsonNode) {.gcsafe.}
proc deleteWaitingResponse*(client: LspClient, id: RequestId) {.inline.}

proc checkInitComplete*(client: LspClient): bool =
  ## Check if async initialization has completed (success or failure)
  ## Returns true if init is done, false if still in progress
  ## Uses a short timeout to avoid blocking the UI
  if client.state != lssStarting:
    return true

  # Check if we're waiting for init response
  if client.pendingInitRequest.isNone:
    return true

  # Check if the output future is ready
  if client.outputStreamFuture.isNil:
    return false

  # Try to wait for the future with a very short timeout (5ms)
  # This allows us to make progress without blocking the UI too long
  let completed = waitFor withTimeout(client.outputStreamFuture, 5.milliseconds)
  if not completed:
    return false

  logDebug("lsp", "checkInitComplete: got data, reading...")

  let respResult = client.outputStreamFuture.read()

  # Start reading the next message
  client.outputStreamFuture = client.serverStreams.output.read()

  if respResult.isErr:
    client.state = lssCrashed
    client.initError = "Initialize failed: " & respResult.error
    logDebug("lsp", "checkInitComplete: read error: " & respResult.error)
    return true

  let response = respResult.get
  let requestId = client.pendingInitRequest.get
  logDebug(
    "lsp",
    "checkInitComplete: got response, hasId=" & $response.hasKey("id") & " hasMethod=" &
      $response.hasKey("method"),
  )

  # Check if this is a notification - handle it and keep waiting
  if response.hasKey("method") and not response.hasKey("id"):
    logDebug("lsp", "checkInitComplete: got notification, continuing to wait...")
    try:
      client.handleNotification(
        response["method"].getStr,
        if response.hasKey("params"):
          response["params"]
        else:
          newJObject(),
      )
    except:
      discard
    return false # Keep waiting for init response

  # Check if this is the response to our initialize request
  if response.hasKey("id") and response["id"].getInt == requestId:
    # Check for error response
    if response.hasKey("error"):
      client.state = lssCrashed
      client.initError =
        "Initialize error: " & response["error"]["message"].getStr("Unknown error")
      logDebug("lsp", "checkInitComplete: init error response")
      return true

    # Parse server capabilities from result
    if response.hasKey("result"):
      let resultNode = response["result"]
      if resultNode.hasKey("capabilities"):
        client.capabilities = some(parseServerCapabilities(resultNode["capabilities"]))
      if resultNode.hasKey("serverInfo"):
        let si = resultNode["serverInfo"]
        var info = ServerInfo(name: si["name"].getStr)
        if si.hasKey("version"):
          info.version = some(si["version"].getStr)
        client.serverInfo = some(info)

    client.deleteWaitingResponse(requestId)
    client.pendingInitRequest = none(RequestId)

    # Mark that we need to send the "initialized" notification
    # This will be done by the poll loop to avoid async issues
    client.needsSendInitialized = true
    client.state = lssRunning
    logDebug("lsp", "checkInitComplete: init response received, state=" & $client.state)
    return true

  # Unexpected response - keep waiting
  return false

proc canSend*(client: LspClient): bool =
  ## Check if the client can send messages (starting or running state)
  client.state in {lssStarting, lssRunning} and client.running

proc readable*(client: LspClient): Result[bool, string] =
  ## Check if there is data available to read (non-blocking)
  if client.outputStreamFuture.isNil:
    return Result[bool, string].ok(false)
  return Result[bool, string].ok(client.outputStreamFuture.finished)

proc read*(client: LspClient): Future[JsonRpcResponseResult] {.async.} =
  ## Read a response from the LSP server
  let r = await client.outputStreamFuture
  # Start reading the next message
  client.outputStreamFuture = client.serverStreams.output.read()
  return r

proc deleteWaitingResponse*(client: LspClient, id: RequestId) {.inline.} =
  if client.waitingResponses.contains(id):
    client.waitingResponses.del(id)

proc getWaitingResponse*(client: LspClient, id: RequestId): Option[WaitingResponse] =
  if client.waitingResponses.contains(id):
    return some(client.waitingResponses[id])
  return none(WaitingResponse)

# Request/notification sending

proc sendRequest*(
    client: LspClient, meth: string, params: JsonNode
): Future[Result[RequestId, string]] {.async.} =
  ## Send a request to the server
  if not client.canSend:
    return Result[RequestId, string].err("Client not running")

  let id = client.rpcState.getNextId()
  let req = %*{"jsonrpc": "2.0", "id": id, "method": meth, "params": params}

  let sendResult = await client.serverStreams.input.sendRequest(req)
  if sendResult.isErr:
    return Result[RequestId, string].err(sendResult.error)

  client.rpcState.addPending(id, meth)
  client.waitingResponses[id] = WaitingResponse(id: id, methodName: meth)
  return Result[RequestId, string].ok(id)

proc sendNotification*(
    client: LspClient, meth: string, params: JsonNode
): Future[Result[void, string]] {.async.} =
  ## Send a notification to the server
  if not client.canSend:
    return Result[void, string].err("Client not running")

  let notify = %*{"jsonrpc": "2.0", "method": meth, "params": params}
  return await client.serverStreams.input.sendNotify(notify)

# Initialize request
proc buildClientCapabilities(): JsonNode =
  ## Build client capabilities for initialize request
  %*{
    "textDocument": {
      "synchronization": {
        "dynamicRegistration": false,
        "willSave": false,
        "willSaveWaitUntil": false,
        "didSave": true,
      },
      "completion": {
        "dynamicRegistration": false,
        "completionItem": {
          "snippetSupport": false,
          "commitCharactersSupport": true,
          "documentationFormat": ["plaintext", "markdown"],
          "deprecatedSupport": true,
          "preselectSupport": true,
        },
        "contextSupport": true,
      },
      "hover":
        {"dynamicRegistration": false, "contentFormat": ["plaintext", "markdown"]},
      "signatureHelp": {
        "dynamicRegistration": false,
        "signatureInformation": {"documentationFormat": ["plaintext", "markdown"]},
      },
      "declaration": {"dynamicRegistration": false},
      "definition": {"dynamicRegistration": false},
      "typeDefinition": {"dynamicRegistration": false},
      "implementation": {"dynamicRegistration": false},
      "references": {"dynamicRegistration": false},
      "documentHighlight": {"dynamicRegistration": false},
      "documentLink": {"dynamicRegistration": false, "tooltipSupport": true},
      "documentSymbol":
        {"dynamicRegistration": false, "hierarchicalDocumentSymbolSupport": true},
      "publishDiagnostics":
        {"relatedInformation": true, "tagSupport": {"valueSet": [1, 2]}},
      "rename": {"dynamicRegistration": false, "prepareSupport": false},
      "formatting": {"dynamicRegistration": false},
      "rangeFormatting": {"dynamicRegistration": false},
      "inlayHint": {"dynamicRegistration": false},
      "inlineValue": {"dynamicRegistration": false},
      "selectionRange": {"dynamicRegistration": false},
      "codeLens": {"dynamicRegistration": false},
      "foldingRange": {
        "dynamicRegistration": false,
        "rangeLimit": 5000,
        "lineFoldingOnly": true,
        "foldingRangeKind": {"valueSet": ["comment", "imports", "region"]},
      },
      "semanticTokens": {
        "dynamicRegistration": false,
        "requests": {"range": true, "full": {"delta": false}},
        "tokenTypes": [
          "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
          "parameter", "variable", "property", "enumMember", "event", "function",
          "method", "macro", "keyword", "modifier", "comment", "string", "number",
          "regexp", "operator", "decorator",
        ],
        "tokenModifiers": [
          "declaration", "definition", "readonly", "static", "deprecated", "abstract",
          "async", "modification", "documentation", "defaultLibrary",
        ],
        "formats": ["relative"],
        "overlappingTokenSupport": false,
        "multilineTokenSupport": true,
      },
    },
    "workspace": {"applyEdit": true, "workspaceFolders": false, "configuration": false},
  }

proc startAsync*(client: LspClient): Result[void, string] =
  ## Start the LSP server process and send initialize request (non-blocking)
  ## The response will be handled by checkInitComplete() in the poll loop
  if client.state != lssStopped:
    return Result[void, string].err("Client already started")

  client.state = lssStarting
  logDebug("lsp", "startAsync: starting LSP server")

  # Build command with args
  let commandParts = client.serverCommand.split(' ')
  let command = commandParts[0]
  var args = client.serverArgs
  if commandParts.len > 1:
    args = commandParts[1 ..^ 1] & args

  # Start server process (blocking but quick)
  const
    WorkingDir = ""
    Env = nil
  let opts: set[AsyncProcessOption] = {UsePath, StdErrToStdOut}

  try:
    client.serverProcess = waitFor startProcess(
      command,
      WorkingDir,
      args,
      Env,
      opts,
      stdoutHandle = AsyncProcess.Pipe,
      stdinHandle = AsyncProcess.Pipe,
    )
  except CatchableError as e:
    client.state = lssCrashed
    client.initError = "Failed to start LSP server: " & e.msg
    logDebug("lsp", "startAsync: failed to start process: " & e.msg)
    return Result[void, string].err(client.initError)

  logDebug("lsp", "startAsync: process started")

  # Set up streams
  client.serverStreams = Streams(
    input: InputStream(stream: client.serverProcess.stdinStream),
    output: OutputStream(stream: client.serverProcess.stdoutStream),
  )

  # Start reading from output stream
  client.outputStreamFuture = client.serverStreams.output.read()

  # Send initialize request
  let rootUri = "file://" & client.workspaceRoot
  let initParams =
    %*{
      "processId": getCurrentProcessId(),
      "clientInfo": {"name": "moe", "version": moeSemVersionStr()},
      "rootUri": rootUri,
      "rootPath": client.workspaceRoot,
      "capabilities": buildClientCapabilities(),
      "trace": "off",
    }

  let reqResult = waitFor client.sendRequest("initialize", initParams)
  if reqResult.isErr:
    client.state = lssCrashed
    client.initError = "Failed to send initialize: " & reqResult.error
    logDebug("lsp", "startAsync: failed to send initialize: " & reqResult.error)
    return Result[void, string].err(client.initError)

  # Store the request ID so checkInitComplete can match the response
  client.pendingInitRequest = some(reqResult.get)
  logDebug("lsp", "startAsync: initialize request sent, waiting for response")

  return Result[void, string].ok()

proc startInBackground*(client: LspClient) =
  ## Start the LSP server initialization in the background (non-blocking)
  ## Check isReady() or checkInitComplete() to see when initialization is done
  logDebug("lsp", "startInBackground called, current state=" & $client.state)
  if client.state != lssStopped:
    logDebug("lsp", "startInBackground: not stopped, returning")
    return

  logDebug("lsp", "startInBackground: starting...")
  let r = client.startAsync()
  if r.isErr:
    logDebug("lsp", "startInBackground: error: " & r.error)
  else:
    logDebug("lsp", "startInBackground: started, state=" & $client.state)

proc stop*(client: LspClient): Future[Result[void, string]] {.async.} =
  ## Stop the LSP server gracefully
  if client.state != lssRunning:
    return Result[void, string].ok()

  client.state = lssShuttingDown

  # Send shutdown request
  let shutdownResult = await client.sendRequest("shutdown", newJNull())
  if shutdownResult.isOk:
    # Wait briefly for response
    await sleepAsync(milliseconds(100))

  # Send exit notification
  discard await client.sendNotification("exit", %*{})

  # Kill process
  if client.serverProcess != nil:
    discard client.serverProcess.kill()

  client.state = lssStopped
  client.serverProcess = nil
  client.serverStreams = nil
  client.outputStreamFuture = nil

  return Result[void, string].ok()

proc kill*(client: LspClient) =
  ## Forcefully kill the LSP server
  if client.serverProcess != nil:
    try:
      discard client.serverProcess.kill()
    except:
      discard

  client.state = lssStopped
  client.serverProcess = nil
  client.serverStreams = nil
  client.outputStreamFuture = nil

# Document synchronization

proc didOpen*(
    client: LspClient, uri: string, languageId: string, version: int, text: string
): Future[Result[void, string]] {.async.} =
  ## Notify server that a document was opened
  if not client.isInitialized:
    return Result[void, string].err("Client not initialized")

  let params =
    %*{
      "textDocument":
        {"uri": uri, "languageId": languageId, "version": version, "text": text}
    }
  return await client.sendNotification("textDocument/didOpen", params)

proc didClose*(client: LspClient, uri: string): Future[Result[void, string]] {.async.} =
  ## Notify server that a document was closed
  if not client.isInitialized:
    return Result[void, string].err("Client not initialized")

  let params = %*{"textDocument": {"uri": uri}}
  return await client.sendNotification("textDocument/didClose", params)

proc didChange*(
    client: LspClient, uri: string, version: int, text: string
): Future[Result[void, string]] {.async.} =
  ## Notify server that a document changed (full sync)
  if not client.isInitialized:
    return Result[void, string].err("Client not initialized")

  let params =
    %*{
      "textDocument": {"uri": uri, "version": version},
      "contentChanges": [{"text": text}],
    }
  return await client.sendNotification("textDocument/didChange", params)

proc didSave*(
    client: LspClient, uri: string, text: Option[string] = none(string)
): Future[Result[void, string]] {.async.} =
  ## Notify server that a document was saved
  if not client.isInitialized:
    return Result[void, string].err("Client not initialized")

  var params = %*{"textDocument": {"uri": uri}}
  if text.isSome:
    params["text"] = %text.get
  return await client.sendNotification("textDocument/didSave", params)

# Notification handling

proc handleNotification*(client: LspClient, meth: string, params: JsonNode) {.gcsafe.} =
  ## Handle incoming notification from server
  case meth
  of "textDocument/publishDiagnostics":
    if client.onDiagnostics != nil:
      let uri = params["uri"].getStr
      var diagnostics: seq[Diagnostic] = @[]
      if params.hasKey("diagnostics"):
        for d in params["diagnostics"]:
          diagnostics.add(parseDiagnostic(d))
      client.onDiagnostics(uri, diagnostics)
  of "window/logMessage":
    if client.onLogMessage != nil:
      let msgType = MessageType(params["type"].getInt)
      let message = params["message"].getStr
      client.onLogMessage(msgType, message)
  of "window/showMessage":
    if client.onShowMessage != nil:
      let msgType = MessageType(params["type"].getInt)
      let message = params["message"].getStr
      client.onShowMessage(msgType, message)
  else:
    discard # Ignore unknown notifications

proc processResponse*(client: LspClient, response: JsonNode): Option[RequestId] =
  ## Process a response and return the request ID if it was a response
  if response.hasKey("id") and not response.hasKey("method"):
    # This is a response
    let id = response["id"].getInt
    client.deleteWaitingResponse(id)
    discard client.rpcState.removePending(id)
    return some(id)
  elif response.hasKey("method"):
    # This is a notification
    let meth = response["method"].getStr
    let params =
      if response.hasKey("params"):
        response["params"]
      else:
        newJObject()
    client.handleNotification(meth, params)
  return none(RequestId)

# Helper to send request and wait for response
proc sendAndWait*(
    client: LspClient, meth: string, params: JsonNode
): Future[Result[JsonNode, string]] {.async.} =
  ## Send a request and wait for its response
  if not client.isRunning:
    return Result[JsonNode, string].err("Client not running")

  let reqResult = await client.sendRequest(meth, params)
  if reqResult.isErr:
    return Result[JsonNode, string].err(reqResult.error)

  # Wait for the response, processing any notifications that arrive first
  var response: JsonNode
  while true:
    let respResult = await client.read()
    if respResult.isErr:
      return Result[JsonNode, string].err(respResult.error)

    response = respResult.get

    # Check if this is a notification (has method but no id)
    if response.hasKey("method") and not response.hasKey("id"):
      try:
        client.handleNotification(
          response["method"].getStr, response.getOrDefault("params")
        )
      except Exception:
        discard # Ignore notification handling errors
      continue

    # This is a response, break out of the loop
    break

  # Check for error response
  if response.hasKey("error"):
    let errMsg = response["error"]["message"].getStr("Unknown error")
    return Result[JsonNode, string].err(errMsg)

  if response.hasKey("result"):
    return Result[JsonNode, string].ok(response["result"])
  else:
    return Result[JsonNode, string].ok(newJNull())

# LSP Feature Requests

proc completion*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[CompletionItem], string]] {.async.} =
  ## Request completion at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/completion", params)
  if respResult.isErr:
    return Result[seq[CompletionItem], string].err(respResult.error)

  let resp = respResult.get
  var items: seq[CompletionItem] = @[]

  # Handle both CompletionList and CompletionItem[] responses
  if resp.kind == JArray:
    for item in resp:
      items.add(parseCompletionItem(item))
  elif resp.kind == JObject and resp.hasKey("items"):
    for item in resp["items"]:
      items.add(parseCompletionItem(item))

  return Result[seq[CompletionItem], string].ok(items)

proc hover*(
    client: LspClient, uri: string, line, character: int
): Future[Result[Option[Hover], string]] {.async.} =
  ## Request hover information at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/hover", params)
  if respResult.isErr:
    return Result[Option[Hover], string].err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return Result[Option[Hover], string].ok(none(Hover))

  return Result[Option[Hover], string].ok(some(parseHover(resp)))

proc gotoDefinition*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[Location], string]] {.async.} =
  ## Request go to definition
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/definition", params)
  if respResult.isErr:
    return Result[seq[Location], string].err(respResult.error)

  return Result[seq[Location], string].ok(parseLocations(respResult.get))

proc gotoDeclaration*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[Location], string]] {.async.} =
  ## Request go to declaration
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/declaration", params)
  if respResult.isErr:
    return Result[seq[Location], string].err(respResult.error)

  return Result[seq[Location], string].ok(parseLocations(respResult.get))

proc gotoTypeDefinition*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[Location], string]] {.async.} =
  ## Request go to type definition
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/typeDefinition", params)
  if respResult.isErr:
    return Result[seq[Location], string].err(respResult.error)

  return Result[seq[Location], string].ok(parseLocations(respResult.get))

proc gotoImplementation*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[Location], string]] {.async.} =
  ## Request go to implementation
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/implementation", params)
  if respResult.isErr:
    return Result[seq[Location], string].err(respResult.error)

  return Result[seq[Location], string].ok(parseLocations(respResult.get))

proc references*(
    client: LspClient,
    uri: string,
    line, character: int,
    includeDeclaration: bool = true,
): Future[Result[seq[Location], string]] {.async.} =
  ## Request find references
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "context": {"includeDeclaration": includeDeclaration},
    }

  let respResult = await client.sendAndWait("textDocument/references", params)
  if respResult.isErr:
    return Result[seq[Location], string].err(respResult.error)

  return Result[seq[Location], string].ok(parseLocations(respResult.get))

proc documentHighlight*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[DocumentHighlight], string]] {.async.} =
  ## Request document highlights at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/documentHighlight", params)
  if respResult.isErr:
    return Result[seq[DocumentHighlight], string].err(respResult.error)

  var highlights: seq[DocumentHighlight] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      highlights.add(parseDocumentHighlight(item))

  return Result[seq[DocumentHighlight], string].ok(highlights)

proc documentLink*(
    client: LspClient, uri: string
): Future[Result[seq[DocumentLink], string]] {.async.} =
  ## Request document links
  let params = %*{"textDocument": {"uri": uri}}

  let respResult = await client.sendAndWait("textDocument/documentLink", params)
  if respResult.isErr:
    return Result[seq[DocumentLink], string].err(respResult.error)

  var links: seq[DocumentLink] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      links.add(parseDocumentLink(item))

  return Result[seq[DocumentLink], string].ok(links)

proc documentLinkResolve*(
    client: LspClient, link: DocumentLink
): Future[Result[DocumentLink, string]] {.async.} =
  ## Resolve a document link
  let params = documentLinkToJson(link)

  let respResult = await client.sendAndWait("documentLink/resolve", params)
  if respResult.isErr:
    return Result[DocumentLink, string].err(respResult.error)

  return Result[DocumentLink, string].ok(parseDocumentLink(respResult.get))

proc signatureHelp*(
    client: LspClient, uri: string, line, character: int
): Future[Result[Option[SignatureHelp], string]] {.async.} =
  ## Request signature help at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/signatureHelp", params)
  if respResult.isErr:
    return Result[Option[SignatureHelp], string].err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return Result[Option[SignatureHelp], string].ok(none(SignatureHelp))

  return Result[Option[SignatureHelp], string].ok(some(parseSignatureHelp(resp)))

proc rename*(
    client: LspClient, uri: string, line, character: int, newName: string
): Future[Result[Option[WorkspaceEdit], string]] {.async.} =
  ## Request rename of a symbol
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "newName": newName,
    }

  let respResult = await client.sendAndWait("textDocument/rename", params)
  if respResult.isErr:
    return Result[Option[WorkspaceEdit], string].err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return Result[Option[WorkspaceEdit], string].ok(none(WorkspaceEdit))

  return Result[Option[WorkspaceEdit], string].ok(some(parseWorkspaceEdit(resp)))

proc formatting*(
    client: LspClient, uri: string, tabSize: int = 2, insertSpaces: bool = true
): Future[Result[seq[TextEdit], string]] {.async.} =
  ## Request document formatting
  let params =
    %*{
      "textDocument": {"uri": uri},
      "options": {"tabSize": tabSize, "insertSpaces": insertSpaces},
    }

  let respResult = await client.sendAndWait("textDocument/formatting", params)
  if respResult.isErr:
    return Result[seq[TextEdit], string].err(respResult.error)

  var edits: seq[TextEdit] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      edits.add(parseTextEdit(item))

  return Result[seq[TextEdit], string].ok(edits)

proc rangeFormatting*(
    client: LspClient,
    uri: string,
    startLine, startChar, endLine, endChar: int,
    tabSize: int = 2,
    insertSpaces: bool = true,
): Future[Result[seq[TextEdit], string]] {.async.} =
  ## Request range formatting
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
      "options": {"tabSize": tabSize, "insertSpaces": insertSpaces},
    }

  let respResult = await client.sendAndWait("textDocument/rangeFormatting", params)
  if respResult.isErr:
    return Result[seq[TextEdit], string].err(respResult.error)

  var edits: seq[TextEdit] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      edits.add(parseTextEdit(item))

  return Result[seq[TextEdit], string].ok(edits)

proc documentSymbol*(
    client: LspClient, uri: string
): Future[Result[DocumentSymbolResult, string]] {.async.} =
  ## Request document symbols
  let params = %*{"textDocument": {"uri": uri}}

  let respResult = await client.sendAndWait("textDocument/documentSymbol", params)
  if respResult.isErr:
    return Result[DocumentSymbolResult, string].err(respResult.error)

  return
    Result[DocumentSymbolResult, string].ok(parseDocumentSymbolResult(respResult.get))

proc inlayHints*(
    client: LspClient, uri: string, startLine, startChar, endLine, endChar: int
): Future[Result[seq[InlayHint], string]] {.async.} =
  ## Request inlay hints for a range
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
    }

  let respResult = await client.sendAndWait("textDocument/inlayHint", params)
  if respResult.isErr:
    return Result[seq[InlayHint], string].err(respResult.error)

  var hints: seq[InlayHint] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      hints.add(parseInlayHint(item))

  return Result[seq[InlayHint], string].ok(hints)

proc semanticTokensFull*(
    client: LspClient, uri: string
): Future[Result[Option[SemanticTokens], string]] {.async.} =
  ## Request full semantic tokens for a document
  let params = %*{"textDocument": {"uri": uri}}

  let respResult = await client.sendAndWait("textDocument/semanticTokens/full", params)
  if respResult.isErr:
    return Result[Option[SemanticTokens], string].err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return Result[Option[SemanticTokens], string].ok(none(SemanticTokens))

  return Result[Option[SemanticTokens], string].ok(some(parseSemanticTokens(resp)))

proc semanticTokensRange*(
    client: LspClient, uri: string, startLine, startChar, endLine, endChar: int
): Future[Result[Option[SemanticTokens], string]] {.async.} =
  ## Request semantic tokens for a range
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
    }

  let respResult = await client.sendAndWait("textDocument/semanticTokens/range", params)
  if respResult.isErr:
    return Result[Option[SemanticTokens], string].err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return Result[Option[SemanticTokens], string].ok(none(SemanticTokens))

  return Result[Option[SemanticTokens], string].ok(some(parseSemanticTokens(resp)))

proc selectionRange*(
    client: LspClient, uri: string, positions: seq[Position]
): Future[Result[seq[SelectionRange], string]] {.async.} =
  ## Request selection ranges for multiple positions
  var posArray = newJArray()
  for pos in positions:
    posArray.add(%*{"line": pos.line, "character": pos.character})

  let params = %*{"textDocument": {"uri": uri}, "positions": posArray}

  let respResult = await client.sendAndWait("textDocument/selectionRange", params)
  if respResult.isErr:
    return Result[seq[SelectionRange], string].err(respResult.error)

  var ranges: seq[SelectionRange] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      ranges.add(parseSelectionRange(item))

  return Result[seq[SelectionRange], string].ok(ranges)

proc selectionRange*(
    client: LspClient, uri: string, line, character: int
): Future[Result[Option[SelectionRange], string]] {.async.} =
  ## Request selection range for a single position
  let positions = @[Position(line: line, character: character)]
  let selResult = await client.selectionRange(uri, positions)
  if selResult.isErr:
    return Result[Option[SelectionRange], string].err(selResult.error)

  let ranges = selResult.get
  if ranges.len > 0:
    return Result[Option[SelectionRange], string].ok(some(ranges[0]))
  else:
    return Result[Option[SelectionRange], string].ok(none(SelectionRange))

proc inlineValues*(
    client: LspClient,
    uri: string,
    startLine, startChar, endLine, endChar: int,
    frameId: int,
    stoppedLine, stoppedStartChar, stoppedEndLine, stoppedEndChar: int,
): Future[Result[seq[InlineValue], string]] {.async.} =
  ## Request inline values for debugging
  let params =
    %*{
      "textDocument": {"uri": uri},
      "viewPort": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
      "context": {
        "frameId": frameId,
        "stoppedLocation": {
          "start": {"line": stoppedLine, "character": stoppedStartChar},
          "end": {"line": stoppedEndLine, "character": stoppedEndChar},
        },
      },
    }

  let respResult = await client.sendAndWait("textDocument/inlineValue", params)
  if respResult.isErr:
    return Result[seq[InlineValue], string].err(respResult.error)

  var values: seq[InlineValue] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      values.add(parseInlineValue(item))

  return Result[seq[InlineValue], string].ok(values)

proc codeLens*(
    client: LspClient, uri: string
): Future[Result[seq[CodeLens], string]] {.async.} =
  ## Request code lenses for a document
  let params = %*{"textDocument": {"uri": uri}}

  let respResult = await client.sendAndWait("textDocument/codeLens", params)
  if respResult.isErr:
    return Result[seq[CodeLens], string].err(respResult.error)

  var lenses: seq[CodeLens] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      lenses.add(parseCodeLens(item))

  return Result[seq[CodeLens], string].ok(lenses)

proc codeLensResolve*(
    client: LspClient, lens: CodeLens
): Future[Result[CodeLens, string]] {.async.} =
  ## Resolve a code lens
  let params = codeLensToJson(lens)

  let respResult = await client.sendAndWait("codeLens/resolve", params)
  if respResult.isErr:
    return Result[CodeLens, string].err(respResult.error)

  return Result[CodeLens, string].ok(parseCodeLens(respResult.get))

proc executeCommand*(
    client: LspClient, command: string, arguments: seq[JsonNode] = @[]
): Future[Result[JsonNode, string]] {.async.} =
  ## Execute a command on the server
  var args = newJArray()
  for arg in arguments:
    args.add(arg)

  let params = %*{"command": command, "arguments": args}

  let respResult = await client.sendAndWait("workspace/executeCommand", params)
  if respResult.isErr:
    return Result[JsonNode, string].err(respResult.error)

  return Result[JsonNode, string].ok(respResult.get)

proc callHierarchyPrepare*(
    client: LspClient, uri: string, line, character: int
): Future[Result[seq[CallHierarchyItem], string]] {.async.} =
  ## Prepare call hierarchy at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let respResult = await client.sendAndWait("textDocument/prepareCallHierarchy", params)
  if respResult.isErr:
    return Result[seq[CallHierarchyItem], string].err(respResult.error)

  var items: seq[CallHierarchyItem] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      items.add(parseCallHierarchyItem(item))

  return Result[seq[CallHierarchyItem], string].ok(items)

proc callHierarchyIncomingCalls*(
    client: LspClient, item: CallHierarchyItem
): Future[Result[seq[CallHierarchyIncomingCall], string]] {.async.} =
  ## Request incoming calls for a call hierarchy item
  let params = %*{"item": callHierarchyItemToJson(item)}

  let respResult = await client.sendAndWait("callHierarchy/incomingCalls", params)
  if respResult.isErr:
    return Result[seq[CallHierarchyIncomingCall], string].err(respResult.error)

  var calls: seq[CallHierarchyIncomingCall] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      calls.add(parseCallHierarchyIncomingCall(item))

  return Result[seq[CallHierarchyIncomingCall], string].ok(calls)

proc callHierarchyOutgoingCalls*(
    client: LspClient, item: CallHierarchyItem
): Future[Result[seq[CallHierarchyOutgoingCall], string]] {.async.} =
  ## Request outgoing calls for a call hierarchy item
  let params = %*{"item": callHierarchyItemToJson(item)}

  let respResult = await client.sendAndWait("callHierarchy/outgoingCalls", params)
  if respResult.isErr:
    return Result[seq[CallHierarchyOutgoingCall], string].err(respResult.error)

  var calls: seq[CallHierarchyOutgoingCall] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      calls.add(parseCallHierarchyOutgoingCall(item))

  return Result[seq[CallHierarchyOutgoingCall], string].ok(calls)

proc foldingRange*(
    client: LspClient, uri: string
): Future[Result[seq[FoldingRange], string]] {.async.} =
  ## Request folding ranges for a document
  let params = %*{"textDocument": {"uri": uri}}

  let respResult = await client.sendAndWait("textDocument/foldingRange", params)
  if respResult.isErr:
    return Result[seq[FoldingRange], string].err(respResult.error)

  var ranges: seq[FoldingRange] = @[]
  let resp = respResult.get
  if resp.kind == JArray:
    for item in resp:
      ranges.add(parseFoldingRange(item))

  return Result[seq[FoldingRange], string].ok(ranges)

# Poll for messages (processes any available notifications)
proc poll*(client: LspClient): Future[void] {.async.} =
  ## Poll for and process any available messages from the server
  if not client.isRunning:
    return

  # Check if there's a response ready
  let readableResult = client.readable()
  if readableResult.isErr or not readableResult.get:
    return

  # Read and process the message
  let respResult = await client.read()
  if respResult.isErr:
    return

  let response = respResult.get
  if response.hasKey("method"):
    # This is a notification
    let meth = response["method"].getStr
    let params =
      if response.hasKey("params"):
        response["params"]
      else:
        newJObject()
    try:
      client.handleNotification(meth, params)
    except Exception:
      discard # Ignore notification handling errors
