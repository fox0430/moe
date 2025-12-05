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

## LSP Client Implementation
## Manages communication with Language Server Protocol servers

import std/[osproc, streams, json, options, os, strutils, posix, times]

import pkg/results

import jsonrpc
import protocol/types

export types

type
  LspServerState* = enum
    lssStopped
    lssStarting
    lssRunning
    lssShuttingDown
    lssCrashed

  LspClient* = ref object
    state*: LspServerState
    languageId*: string
    serverCommand*: string
    serverArgs*: seq[string]
    workspaceRoot*: string
    process: Process
    inputStream: Stream # Write to server (server's stdin)
    outputStream: Stream # Read from server (server's stdout)
    rpcState: JsonRpcState
    messageReader: MessageReader
    capabilities*: Option[ServerCapabilities]
    serverInfo*: Option[ServerInfo]
    # Callbacks for server notifications
    onDiagnostics*: proc(uri: string, diagnostics: seq[Diagnostic])
    onLogMessage*: proc(msgType: MessageType, message: string)
    onShowMessage*: proc(msgType: MessageType, message: string)
    # Pending responses
    pendingResponses*: seq[JsonRpcMessage]

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
    process: nil,
    inputStream: nil,
    outputStream: nil,
    rpcState: newJsonRpcState(),
    messageReader: newMessageReader(),
    capabilities: none(ServerCapabilities),
    serverInfo: none(ServerInfo),
    onDiagnostics: nil,
    onLogMessage: nil,
    onShowMessage: nil,
    pendingResponses: @[],
  )

proc isRunning*(client: LspClient): bool =
  client.state == lssRunning and client.process != nil and client.process.running

proc isStopped*(client: LspClient): bool =
  client.state == lssStopped

proc sendRaw(client: LspClient, data: string): Result[void, string] =
  ## Send raw data to the server
  if not client.isRunning:
    return err("Client not running")

  try:
    client.inputStream.write(data)
    client.inputStream.flush()
    return ok()
  except IOError as e:
    return err("Failed to write to server: " & e.msg)

proc sendRequest*(
    client: LspClient, meth: string, params: JsonNode
): Result[RequestId, string] =
  ## Send a request to the server
  let id = client.rpcState.getNextId()
  let message = encodeRequest(id, meth, params)
  let sendResult = client.sendRaw(message)
  if sendResult.isErr:
    return err(sendResult.error)
  client.rpcState.addPending(id, meth)
  return ok(id)

proc sendNotification*(
    client: LspClient, meth: string, params: JsonNode
): Result[void, string] =
  ## Send a notification to the server
  let message = encodeNotification(meth, params)
  return client.sendRaw(message)

proc handleNotification(client: LspClient, meth: string, params: JsonNode) =
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

proc processMessage(client: LspClient, msg: JsonRpcMessage) =
  ## Process a received JSON-RPC message
  case msg.kind
  of jrmkResponse:
    # Store response for later retrieval
    discard client.rpcState.removePending(msg.respId)
    client.pendingResponses.add(msg)
  of jrmkError:
    # Store error response
    if msg.errId.isSome:
      discard client.rpcState.removePending(msg.errId.get)
    client.pendingResponses.add(msg)
  of jrmkNotification:
    client.handleNotification(msg.notifyMethod, msg.notifyParams)
  of jrmkRequest:
    # Server-initiated requests (rare, but some servers use them)
    discard

proc tryReadByte(stream: Stream): Option[char] =
  ## Try to read a single byte without blocking
  ## Returns none if no data available or on error
  try:
    if not stream.atEnd:
      return some(stream.readChar())
  except IOError:
    discard
  return none(char)

proc poll*(client: LspClient, timeoutMs: int = 0): Result[void, string] =
  ## Poll for incoming messages from the server
  ## timeoutMs: 0 = non-blocking, -1 = block forever, >0 = timeout in ms
  if not client.isRunning:
    return err("Client not running")

  # Try to read available data
  var buffer = ""
  var bytesRead = 0
  const MaxReadPerPoll = 65536

  # Non-blocking read attempt
  while bytesRead < MaxReadPerPoll:
    let byteOpt = tryReadByte(client.outputStream)
    if byteOpt.isNone:
      break
    buffer.add(byteOpt.get)
    inc bytesRead

  if buffer.len == 0:
    return ok()

  # Process buffer line by line for headers, then bytes for body
  var pos = 0
  while pos < buffer.len:
    case client.messageReader.state
    of rsReadingHeaders:
      # Find end of line
      var lineEnd = pos
      while lineEnd < buffer.len and buffer[lineEnd] != '\n':
        inc lineEnd

      if lineEnd >= buffer.len:
        # Incomplete line, save for next poll
        break

      let line = buffer[pos .. lineEnd].strip(chars = {'\r', '\n'})
      pos = lineEnd + 1

      let feedResult = client.messageReader.feedLine(line)
      if feedResult.isErr:
        # Reset reader and continue
        client.messageReader.reset()
    of rsReadingBody:
      let remaining = client.messageReader.remainingBytes()
      let available = min(remaining, buffer.len - pos)
      let chunk = buffer[pos ..< pos + available]
      pos += available

      let feedResult = client.messageReader.feedBytes(chunk)
      if feedResult.isErr:
        client.messageReader.reset()
        continue

      if feedResult.get.isSome:
        let body = feedResult.get.get
        let parseResult = parseJsonRpcMessage(body)
        if parseResult.isOk:
          client.processMessage(parseResult.get)

  return ok()

proc waitForResponse*(
    client: LspClient, id: RequestId, timeoutMs: int = 30000
): Result[JsonNode, string] =
  ## Wait for a response to a specific request
  let startTime = epochTime()
  let timeoutSec = timeoutMs.float / 1000.0

  while true:
    # Check if we already have the response
    var foundIdx = -1
    for i, resp in client.pendingResponses:
      case resp.kind
      of jrmkResponse:
        if resp.respId == id:
          foundIdx = i
          break
      of jrmkError:
        if resp.errId.isSome and resp.errId.get == id:
          foundIdx = i
          break
      else:
        discard

    if foundIdx >= 0:
      let resp = client.pendingResponses[foundIdx]
      client.pendingResponses.delete(foundIdx)
      case resp.kind
      of jrmkResponse:
        return ok(resp.respResult)
      of jrmkError:
        return err("Server error " & $resp.error.code & ": " & resp.error.message)
      else:
        return err("Unexpected response type")

    # Check timeout
    if timeoutMs > 0 and epochTime() - startTime > timeoutSec:
      discard client.rpcState.removePending(id)
      return err("Request timed out")

    # Poll for more data
    let pollResult = client.poll(100)
    if pollResult.isErr:
      return err(pollResult.error)

    # Small sleep to avoid busy waiting
    sleep(10)

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
      "definition": {"dynamicRegistration": false},
      "references": {"dynamicRegistration": false},
      "documentSymbol":
        {"dynamicRegistration": false, "hierarchicalDocumentSymbolSupport": true},
      "publishDiagnostics":
        {"relatedInformation": true, "tagSupport": {"valueSet": [1, 2]}},
    },
    "workspace": {"applyEdit": false, "workspaceFolders": false, "configuration": false},
  }

proc start*(client: LspClient): Result[void, string] =
  ## Start the LSP server and perform initialization handshake
  if client.state != lssStopped:
    return err("Client already started")

  client.state = lssStarting

  # Start server process
  try:
    let options = {poUsePath, poStdErrToStdOut}
    client.process = startProcess(
      client.serverCommand, client.workspaceRoot, client.serverArgs, nil, options
    )
    client.inputStream = client.process.inputStream
    client.outputStream = client.process.outputStream
  except OSError as e:
    client.state = lssCrashed
    return err("Failed to start LSP server: " & e.msg)

  # Send initialize request
  let rootUri = "file://" & client.workspaceRoot
  let initParams =
    %*{
      "processId": getCurrentProcessId(),
      "clientInfo": {"name": "moe", "version": "0.3.0"},
      "rootUri": rootUri,
      "rootPath": client.workspaceRoot,
      "capabilities": buildClientCapabilities(),
      "trace": "off",
    }

  let reqResult = client.sendRequest("initialize", initParams)
  if reqResult.isErr:
    client.state = lssCrashed
    return err("Failed to send initialize: " & reqResult.error)

  let respResult = client.waitForResponse(reqResult.get, 30000)
  if respResult.isErr:
    client.state = lssCrashed
    return err("Initialize failed: " & respResult.error)

  # Parse server capabilities
  let response = respResult.get
  if response.hasKey("capabilities"):
    client.capabilities = some(parseServerCapabilities(response["capabilities"]))
  if response.hasKey("serverInfo"):
    let si = response["serverInfo"]
    var info = ServerInfo(name: si["name"].getStr)
    if si.hasKey("version"):
      info.version = some(si["version"].getStr)
    client.serverInfo = some(info)

  # Send initialized notification
  let initedResult = client.sendNotification("initialized", %*{})
  if initedResult.isErr:
    client.state = lssCrashed
    return err("Failed to send initialized: " & initedResult.error)

  client.state = lssRunning
  return ok()

proc stop*(client: LspClient): Result[void, string] =
  ## Stop the LSP server gracefully
  if client.state != lssRunning:
    return ok()

  client.state = lssShuttingDown

  # Send shutdown request
  let shutdownResult = client.sendRequest("shutdown", newJNull())
  if shutdownResult.isOk:
    # Wait for response (with short timeout)
    discard client.waitForResponse(shutdownResult.get, 5000)

  # Send exit notification
  discard client.sendNotification("exit", %*{})

  # Close streams and process
  if client.inputStream != nil:
    client.inputStream.close()
  if client.outputStream != nil:
    client.outputStream.close()
  if client.process != nil:
    client.process.terminate()
    client.process.close()

  client.state = lssStopped
  client.process = nil
  client.inputStream = nil
  client.outputStream = nil

  return ok()

proc kill*(client: LspClient) =
  ## Forcefully kill the LSP server
  if client.process != nil:
    try:
      client.process.kill()
      client.process.close()
    except:
      discard

  client.state = lssStopped
  client.process = nil
  client.inputStream = nil
  client.outputStream = nil

# Document synchronization
proc didOpen*(
    client: LspClient, uri: string, languageId: string, version: int, text: string
): Result[void, string] =
  ## Notify server that a document was opened
  let params =
    %*{
      "textDocument":
        {"uri": uri, "languageId": languageId, "version": version, "text": text}
    }
  return client.sendNotification("textDocument/didOpen", params)

proc didClose*(client: LspClient, uri: string): Result[void, string] =
  ## Notify server that a document was closed
  let params = %*{"textDocument": {"uri": uri}}
  return client.sendNotification("textDocument/didClose", params)

proc didChange*(
    client: LspClient, uri: string, version: int, text: string
): Result[void, string] =
  ## Notify server that a document changed (full sync)
  let params =
    %*{
      "textDocument": {"uri": uri, "version": version},
      "contentChanges": [{"text": text}],
    }
  return client.sendNotification("textDocument/didChange", params)

proc didSave*(
    client: LspClient, uri: string, text: Option[string] = none(string)
): Result[void, string] =
  ## Notify server that a document was saved
  var params = %*{"textDocument": {"uri": uri}}
  if text.isSome:
    params["text"] = %text.get
  return client.sendNotification("textDocument/didSave", params)

# Feature requests
proc completion*(
    client: LspClient, uri: string, line, character: int
): Result[seq[CompletionItem], string] =
  ## Request completion at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let reqResult = client.sendRequest("textDocument/completion", params)
  if reqResult.isErr:
    return err(reqResult.error)

  let respResult = client.waitForResponse(reqResult.get)
  if respResult.isErr:
    return err(respResult.error)

  var items: seq[CompletionItem] = @[]
  let response = respResult.get

  if response.kind == JNull:
    return ok(items)

  # Handle both CompletionList and CompletionItem[]
  let itemsArray =
    if response.hasKey("items"):
      response["items"]
    else:
      response

  if itemsArray.kind == JArray:
    for item in itemsArray:
      items.add(parseCompletionItem(item))

  return ok(items)

proc hover*(
    client: LspClient, uri: string, line, character: int
): Result[Option[Hover], string] =
  ## Request hover information at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let reqResult = client.sendRequest("textDocument/hover", params)
  if reqResult.isErr:
    return err(reqResult.error)

  let respResult = client.waitForResponse(reqResult.get)
  if respResult.isErr:
    return err(respResult.error)

  let response = respResult.get
  if response.kind == JNull:
    return ok(none(Hover))

  return ok(some(parseHover(response)))

proc signatureHelp*(
    client: LspClient, uri: string, line, character: int
): Result[Option[SignatureHelp], string] =
  ## Request signature help at a position
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let reqResult = client.sendRequest("textDocument/signatureHelp", params)
  if reqResult.isErr:
    return err(reqResult.error)

  let respResult = client.waitForResponse(reqResult.get)
  if respResult.isErr:
    return err(respResult.error)

  let response = respResult.get
  if response.kind == JNull:
    return ok(none(SignatureHelp))

  return ok(some(parseSignatureHelp(response)))

proc gotoDefinition*(
    client: LspClient, uri: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to definition
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let reqResult = client.sendRequest("textDocument/definition", params)
  if reqResult.isErr:
    return err(reqResult.error)

  let respResult = client.waitForResponse(reqResult.get)
  if respResult.isErr:
    return err(respResult.error)

  var locations: seq[Location] = @[]
  let response = respResult.get

  if response.kind == JNull:
    return ok(locations)

  # Handle both Location and Location[]
  if response.kind == JArray:
    for loc in response:
      locations.add(parseLocation(loc))
  elif response.hasKey("uri"):
    locations.add(parseLocation(response))

  return ok(locations)

proc references*(
    client: LspClient,
    uri: string,
    line, character: int,
    includeDeclaration: bool = true,
): Result[seq[Location], string] =
  ## Request references to a symbol
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "context": {"includeDeclaration": includeDeclaration},
    }

  let reqResult = client.sendRequest("textDocument/references", params)
  if reqResult.isErr:
    return err(reqResult.error)

  let respResult = client.waitForResponse(reqResult.get)
  if respResult.isErr:
    return err(respResult.error)

  var locations: seq[Location] = @[]
  let response = respResult.get

  if response.kind == JNull:
    return ok(locations)

  if response.kind == JArray:
    for loc in response:
      locations.add(parseLocation(loc))

  return ok(locations)
