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

## LSP Service Layer
## Manages multiple LSP workers and provides high-level API for editor integration
## Uses thread-based workers to avoid blocking the UI event loop

import std/[tables, options, os, strutils, json, times]

import pkg/results

import lsp/worker
import lsp/protocol/types

export worker
export types

const DefaultRequestTimeoutMs* = 5000 # 5 second timeout for LSP requests

type
  LanguageServerConfig* = object ## Configuration for a language server
    command*: string
    args*: seq[string]
    extensions*: seq[string]
    enabled*: bool

  LspResponseStatus* = enum
    lrsPending # Response not yet received
    lrsSuccess # Response received successfully
    lrsError # Error response received
    lrsTimeout # Request timed out

  LspPendingRequest* = object ## Tracking info for a pending async request
    requestId*: int
    langId*: string
    methodName*: string
    startTime*: float
    timeoutMs*: int

  LspService* = ref object
    ## Service for managing LSP workers.
    ## NOTE: This type is NOT thread-safe. All methods must be called from the
    ## main thread only. The workers themselves handle thread communication
    ## internally via thread-safe queues.
    workers: Table[string, LspWorker] # languageId -> worker
    configs: Table[string, LanguageServerConfig] # languageId -> config
    capabilities: Table[string, ServerCapabilities] # languageId -> capabilities
    serverInfo: Table[string, tuple[name: string, version: Option[string]]]
      # languageId -> server info
    workspaceRoot: string
    enabled*: bool
    # Pending request responses (requestId -> response)
    pendingResponses: Table[int, tuple[result: Option[JsonNode], error: Option[string]]]
    # Active pending requests for timeout tracking
    activeRequests*: Table[int, LspPendingRequest]
    # Global callbacks (forwarded from individual workers)
    onDiagnosticsUpdate*: proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.}
    onLogMessage*:
      proc(langId: string, msgType: MessageType, message: string) {.gcsafe.}

proc newLspService*(workspaceRoot: string = ""): LspService =
  ## Create a new LSP service
  result = LspService(
    workers: initTable[string, LspWorker](),
    configs: initTable[string, LanguageServerConfig](),
    capabilities: initTable[string, ServerCapabilities](),
    serverInfo: initTable[string, tuple[name: string, version: Option[string]]](),
    workspaceRoot:
      if workspaceRoot.len > 0:
        workspaceRoot
      else:
        getCurrentDir(),
    enabled: true,
    pendingResponses:
      initTable[int, tuple[result: Option[JsonNode], error: Option[string]]](),
    activeRequests: initTable[int, LspPendingRequest](),
    onDiagnosticsUpdate: nil,
    onLogMessage: nil,
  )

  # Default language server configurations
  result.configs["nim"] = LanguageServerConfig(
    command: "nimlangserver",
    args: @[],
    extensions: @["nim", "nims", "nimble"],
    enabled: true,
  )

  result.configs["rust"] = LanguageServerConfig(
    command: "rust-analyzer", args: @[], extensions: @["rs"], enabled: true
  )

  result.configs["python"] = LanguageServerConfig(
    command: "pylsp", args: @[], extensions: @["py", "pyw"], enabled: true
  )

  result.configs["typescript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["ts", "tsx"],
    enabled: true,
  )

  result.configs["javascript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["js", "jsx", "mjs"],
    enabled: true,
  )

  result.configs["go"] = LanguageServerConfig(
    command: "gopls", args: @[], extensions: @["go"], enabled: true
  )

  result.configs["c"] = LanguageServerConfig(
    command: "clangd", args: @[], extensions: @["c", "h"], enabled: true
  )

  result.configs["cpp"] = LanguageServerConfig(
    command: "clangd",
    args: @[],
    extensions: @["cpp", "hpp", "cc", "hh", "cxx", "hxx"],
    enabled: true,
  )

proc setConfig*(svc: LspService, langId: string, config: LanguageServerConfig) =
  ## Set configuration for a language server
  svc.configs[langId] = config

proc getConfig*(svc: LspService, langId: string): Option[LanguageServerConfig] =
  ## Get configuration for a language server
  if langId in svc.configs:
    return some(svc.configs[langId])
  return none(LanguageServerConfig)

proc getLanguageIdFromPath*(svc: LspService, path: string): Option[string] =
  ## Determine language ID from file path extension
  let ext = path.splitFile().ext.strip(chars = {'.'}).toLowerAscii()
  if ext.len == 0:
    return none(string)

  for langId, config in svc.configs:
    if config.enabled and ext in config.extensions:
      return some(langId)

  return none(string)

proc getLanguageIdFromExtension*(svc: LspService, ext: string): Option[string] =
  ## Determine language ID from file extension
  let cleanExt = ext.strip(chars = {'.'}).toLowerAscii()

  for langId, config in svc.configs:
    if config.enabled and cleanExt in config.extensions:
      return some(langId)

  return none(string)

proc pathToUri*(path: string): string =
  ## Convert file path to URI
  if path.startsWith("file://"):
    return path
  return "file://" & path.absolutePath()

proc uriToPath*(uri: string): string =
  ## Convert URI to file path
  if uri.startsWith("file://"):
    return uri[7 ..^ 1]
  return uri

proc getWorker*(svc: LspService, langId: string): Option[LspWorker] =
  ## Get existing worker for a language (running or starting)
  if langId in svc.workers:
    let worker = svc.workers[langId]
    # Return worker if it's running or still starting
    if worker.isRunning or worker.isStarting:
      return some(worker)
  return none(LspWorker)

proc startWorker*(svc: LspService, langId: string): Result[LspWorker, string] =
  ## Start a worker for a language (or return existing one)
  if not svc.enabled:
    return err("LSP service is disabled")

  # Check if worker already exists (running or starting)
  if langId in svc.workers:
    let worker = svc.workers[langId]
    if worker.isRunning or worker.isStarting:
      return ok(worker)

  # Get config
  if langId notin svc.configs:
    return err("No LSP configuration for language: " & langId)

  let config = svc.configs[langId]
  if not config.enabled:
    return err("LSP disabled for language: " & langId)

  # Create new worker
  let workerResult = newLspWorker(langId)
  if workerResult.isErr:
    return err("Failed to create worker: " & workerResult.error)
  let worker = workerResult.get

  # Start worker thread
  worker.start()

  # Start the LSP server
  worker.startServer(config.command, config.args, svc.workspaceRoot)

  svc.workers[langId] = worker

  # Notify via log callback that server is starting
  if svc.onLogMessage != nil:
    svc.onLogMessage(langId, mtInfo, "Starting language server: " & config.command)

  return ok(worker)

proc getOrStartWorker*(svc: LspService, langId: string): Result[LspWorker, string] =
  ## Get existing worker or start a new one
  let existing = svc.getWorker(langId)
  if existing.isSome:
    return ok(existing.get)
  return svc.startWorker(langId)

proc getWorkerForPath*(svc: LspService, path: string): Result[LspWorker, string] =
  ## Get or start worker for a file path
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return err("No LSP support for file: " & path)
  return svc.getOrStartWorker(langIdOpt.get)

proc isWorkerReady*(svc: LspService, langId: string): bool =
  ## Check if a worker is ready (running and initialized)
  if langId in svc.workers:
    return svc.workers[langId].isRunning
  return false

proc stopWorker*(svc: LspService, langId: string): Result[void, string] =
  ## Stop a worker for a language
  if langId notin svc.workers:
    return ok()

  let worker = svc.workers[langId]
  worker.stop()
  svc.workers.del(langId)
  svc.capabilities.del(langId)
  svc.serverInfo.del(langId)
  return ok()

proc stopAll*(svc: LspService) =
  ## Stop all workers
  for langId, worker in svc.workers:
    worker.stop()
  svc.workers.clear()
  svc.capabilities.clear()
  svc.serverInfo.clear()

proc poll*(svc: LspService, timeoutMs: int = 0) =
  ## Poll all workers - process events from worker threads
  ## This is non-blocking - it only processes events that have been queued

  # Skip if no workers
  if svc.workers.len == 0:
    return

  for langId, worker in svc.workers:
    # Get all pending events from this worker
    let events = worker.pollEvents()

    for evt in events:
      case evt.kind
      of levInitialized:
        if svc.onLogMessage != nil:
          svc.onLogMessage(langId, mtInfo, "Language server initialized")
      of levError:
        if svc.onLogMessage != nil:
          svc.onLogMessage(langId, mtError, evt.errorMsg)
      of levDiagnostics:
        if svc.onDiagnosticsUpdate != nil:
          svc.onDiagnosticsUpdate(evt.diagUri, evt.diagnostics)
      of levLogMessage:
        if svc.onLogMessage != nil:
          svc.onLogMessage(langId, evt.msgType, evt.message)
      of levShowMessage:
        if svc.onLogMessage != nil:
          svc.onLogMessage(langId, evt.msgType, evt.message)
      of levServerInfo:
        svc.serverInfo[langId] = (name: evt.serverName, version: evt.serverVersion)
        if svc.onLogMessage != nil:
          var msg = "Server: " & evt.serverName
          if evt.serverVersion.isSome:
            msg &= " v" & evt.serverVersion.get
          svc.onLogMessage(langId, mtInfo, msg)
      of levCapabilities:
        svc.capabilities[langId] = evt.capabilities
      of levResponse:
        svc.pendingResponses[evt.requestId] =
          (result: evt.responseResult, error: evt.responseError)

# Non-blocking response checking
proc checkResponse*(
    svc: LspService, requestId: int
): tuple[status: LspResponseStatus, result: Option[JsonNode], error: Option[string]] =
  ## Non-blocking check if a response has arrived
  ## Returns (lrsPending, none, none) if not yet received
  ## Returns (lrsSuccess, some(result), none) on success
  ## Returns (lrsError, none, some(error)) on error
  ## Returns (lrsTimeout, none, some("timeout")) if timed out

  # Check if response has arrived
  if requestId in svc.pendingResponses:
    let resp = svc.pendingResponses[requestId]
    svc.pendingResponses.del(requestId)
    svc.activeRequests.del(requestId)

    if resp.error.isSome:
      return (lrsError, none(JsonNode), resp.error)
    elif resp.result.isSome:
      return (lrsSuccess, resp.result, none(string))
    else:
      return (lrsSuccess, some(newJNull()), none(string))

  # Check timeout
  if requestId in svc.activeRequests:
    let req = svc.activeRequests[requestId]
    let elapsed = (epochTime() - req.startTime) * 1000.0
    if elapsed > req.timeoutMs.float:
      svc.activeRequests.del(requestId)
      return (lrsTimeout, none(JsonNode), some("Request timed out"))

  return (lrsPending, none(JsonNode), none(string))

proc hasPendingRequests*(svc: LspService): bool =
  ## Check if there are any pending requests waiting for responses
  svc.activeRequests.len > 0

proc getPendingRequestCount*(svc: LspService): int =
  ## Get the number of pending requests
  svc.activeRequests.len

proc cleanupTimedOutRequests*(svc: LspService) =
  ## Clean up any timed out requests
  var toRemove: seq[int] = @[]
  let now = epochTime()
  for reqId, req in svc.activeRequests:
    let elapsed = (now - req.startTime) * 1000.0
    if elapsed > req.timeoutMs.float:
      toRemove.add(reqId)
  for reqId in toRemove:
    svc.activeRequests.del(reqId)

# Request-response helper (BLOCKING - use only when necessary)
proc waitForResponse(
    svc: LspService, requestId: int, timeoutMs: int = DefaultRequestTimeoutMs
): Result[JsonNode, string] =
  ## Wait for a response to a request, polling until it arrives or timeout
  ## WARNING: This blocks the main thread! Use checkResponse for non-blocking checks.
  let startTime = epochTime()
  let timeoutSec = timeoutMs.float / 1000.0

  while true:
    # Poll for new events
    svc.poll()

    # Check if response has arrived
    if requestId in svc.pendingResponses:
      let resp = svc.pendingResponses[requestId]
      svc.pendingResponses.del(requestId)
      svc.activeRequests.del(requestId)

      if resp.error.isSome:
        return err(resp.error.get)
      elif resp.result.isSome:
        return ok(resp.result.get)
      else:
        return ok(newJNull())

    # Check timeout
    if epochTime() - startTime > timeoutSec:
      svc.activeRequests.del(requestId)
      return err("Request timed out")

    # Brief sleep to avoid busy loop (1ms)
    sleep(1)

# Helper to start a tracked request
proc startTrackedRequest(
    svc: LspService,
    worker: LspWorker,
    methodName: string,
    params: JsonNode,
    timeoutMs: int = DefaultRequestTimeoutMs,
): int =
  ## Start a request and track it for timeout checking
  let requestId = worker.sendRequest(methodName, params)
  svc.activeRequests[requestId] = LspPendingRequest(
    requestId: requestId,
    langId: worker.languageId,
    methodName: methodName,
    startTime: epochTime(),
    timeoutMs: timeoutMs,
  )
  return requestId

# High-level document operations
proc notifyDocumentOpened*(
    svc: LspService, path: string, text: string
): Result[void, string] =
  ## Notify that a document was opened (non-blocking)
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  let langId = worker.languageId
  let uri = pathToUri(path)
  worker.didOpen(uri, langId, 1, text)
  return ok()

proc notifyDocumentChanged*(
    svc: LspService, path: string, version: int, text: string
): Result[void, string] =
  ## Notify that a document changed (non-blocking)
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok() # No LSP for this file type

  let workerOpt = svc.getWorker(langIdOpt.get)
  if workerOpt.isNone:
    return ok() # Worker not started

  let worker = workerOpt.get
  let uri = pathToUri(path)
  worker.didChange(uri, version, text)
  return ok()

proc notifyDocumentClosed*(svc: LspService, path: string): Result[void, string] =
  ## Notify that a document was closed (non-blocking)
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok()

  let workerOpt = svc.getWorker(langIdOpt.get)
  if workerOpt.isNone:
    return ok()

  let worker = workerOpt.get
  let uri = pathToUri(path)
  worker.didClose(uri)
  return ok()

proc notifyDocumentSaved*(
    svc: LspService, path: string, text: Option[string] = none(string)
): Result[void, string] =
  ## Notify that a document was saved (non-blocking)
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok()

  let workerOpt = svc.getWorker(langIdOpt.get)
  if workerOpt.isNone:
    return ok()

  let worker = workerOpt.get
  let uri = pathToUri(path)
  worker.didSave(uri, text)
  return ok()

# High-level async (non-blocking) feature requests
# These return a request ID immediately. Use poll() and checkResponse() to get results.

proc startCompletionRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a completion request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/completion", params)
  return ok(requestId)

proc startHoverRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a hover request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/hover", params)
  return ok(requestId)

proc startDefinitionRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a definition request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/definition", params)
  return ok(requestId)

proc startReferencesRequest*(
    svc: LspService, path: string, line, character: int, includeDeclaration: bool = true
): Result[int, string] =
  ## Start a references request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "context": {"includeDeclaration": includeDeclaration},
    }

  let requestId = svc.startTrackedRequest(worker, "textDocument/references", params)
  return ok(requestId)

proc startSignatureHelpRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a signature help request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/signatureHelp", params)
  return ok(requestId)

proc startDocumentHighlightRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a document highlight request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/documentHighlight", params)
  return ok(requestId)

proc startCodeLensRequest*(svc: LspService, path: string): Result[int, string] =
  ## Start a code lens request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/codeLens", params)
  return ok(requestId)

# Response parsing helpers for async requests
proc parseCompletionResponse*(resp: JsonNode): seq[CompletionItem] =
  ## Parse a completion response JSON into CompletionItem sequence
  var items: seq[CompletionItem] = @[]
  if resp.kind == JArray:
    for item in resp:
      items.add(parseCompletionItem(item))
  elif resp.kind == JObject and resp.hasKey("items"):
    for item in resp["items"]:
      items.add(parseCompletionItem(item))
  return items

proc parseHoverResponse*(resp: JsonNode): Option[Hover] =
  ## Parse a hover response JSON
  if resp.kind == JNull:
    return none(Hover)
  return some(parseHover(resp))

proc parseLocationsResponse*(resp: JsonNode): seq[Location] =
  ## Parse a locations response (definition, references, etc.)
  return parseLocations(resp)

proc parseSignatureHelpResponse*(resp: JsonNode): Option[SignatureHelp] =
  ## Parse a signature help response JSON
  if resp.kind == JNull:
    return none(SignatureHelp)
  return some(parseSignatureHelp(resp))

proc parseDocumentHighlightResponse*(resp: JsonNode): seq[DocumentHighlight] =
  ## Parse a document highlight response JSON
  var highlights: seq[DocumentHighlight] = @[]
  if resp.kind == JArray:
    for item in resp:
      highlights.add(parseDocumentHighlight(item))
  return highlights

proc parseCodeLensResponse*(resp: JsonNode): seq[CodeLens] =
  ## Parse a code lens response JSON
  var lenses: seq[CodeLens] = @[]
  if resp.kind == JArray:
    for item in resp:
      lenses.add(parseCodeLens(item))
  return lenses

# High-level blocking feature requests
# WARNING: These block the main thread until response arrives!
proc requestCompletion*(
    svc: LspService, path: string, line, character: int
): Result[seq[CompletionItem], string] =
  ## Request completion at a position (BLOCKING)
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/completion", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseCompletionResponse(respResult.get))

proc requestHover*(
    svc: LspService, path: string, line, character: int
): Result[Option[Hover], string] =
  ## Request hover information at a position
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/hover", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return ok(none(Hover))

  return ok(some(parseHover(resp)))

proc requestDefinition*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to definition
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/definition", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseLocations(respResult.get))

proc requestDeclaration*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to declaration
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/declaration", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseLocations(respResult.get))

proc requestTypeDefinition*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to type definition
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/typeDefinition", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseLocations(respResult.get))

proc requestImplementation*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to implementation
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/implementation", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseLocations(respResult.get))

proc requestReferences*(
    svc: LspService, path: string, line, character: int, includeDeclaration: bool = true
): Result[seq[Location], string] =
  ## Request references to a symbol
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "context": {"includeDeclaration": includeDeclaration},
    }

  let requestId = svc.startTrackedRequest(worker, "textDocument/references", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseLocations(respResult.get))

proc requestDocumentHighlight*(
    svc: LspService, path: string, line, character: int
): Result[seq[DocumentHighlight], string] =
  ## Request document highlights at a position
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/documentHighlight", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var highlights: seq[DocumentHighlight] = @[]
  if resp.kind == JArray:
    for item in resp:
      highlights.add(parseDocumentHighlight(item))

  return ok(highlights)

proc requestDocumentLinks*(
    svc: LspService, path: string
): Result[seq[DocumentLink], string] =
  ## Request document links for a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/documentLink", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var links: seq[DocumentLink] = @[]
  if resp.kind == JArray:
    for item in resp:
      links.add(parseDocumentLink(item))

  return ok(links)

proc requestDocumentLinkResolve*(
    svc: LspService, path: string, link: DocumentLink
): Result[DocumentLink, string] =
  ## Resolve a document link to get its target URI
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  # Convert DocumentLink to JSON params
  let params =
    %*{
      "range": {
        "start":
          {"line": link.range.start.line, "character": link.range.start.character},
        "end": {"line": link.range.`end`.line, "character": link.range.`end`.character},
      }
    }
  if link.target.isSome:
    params["target"] = %link.target.get
  if link.data.isSome:
    params["data"] = link.data.get

  let requestId = svc.startTrackedRequest(worker, "documentLink/resolve", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseDocumentLink(respResult.get))

proc requestSignatureHelp*(
    svc: LspService, path: string, line, character: int
): Result[Option[SignatureHelp], string] =
  ## Request signature help at a position
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/signatureHelp", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return ok(none(SignatureHelp))

  return ok(some(parseSignatureHelp(resp)))

proc requestRename*(
    svc: LspService, path: string, line, character: int, newName: string
): Result[Option[WorkspaceEdit], string] =
  ## Request rename of a symbol
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "newName": newName,
    }

  let requestId = svc.startTrackedRequest(worker, "textDocument/rename", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return ok(none(WorkspaceEdit))

  return ok(some(parseWorkspaceEdit(resp)))

proc requestFormatting*(
    svc: LspService, path: string, tabSize: int = 2, insertSpaces: bool = true
): Result[seq[TextEdit], string] =
  ## Request document formatting
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "options": {"tabSize": tabSize, "insertSpaces": insertSpaces},
    }

  let requestId = svc.startTrackedRequest(worker, "textDocument/formatting", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var edits: seq[TextEdit] = @[]
  if resp.kind == JArray:
    for item in resp:
      edits.add(parseTextEdit(item))

  return ok(edits)

proc requestRangeFormatting*(
    svc: LspService,
    path: string,
    startLine, startChar, endLine, endChar: int,
    tabSize: int = 2,
    insertSpaces: bool = true,
): Result[seq[TextEdit], string] =
  ## Request range formatting
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
      "options": {"tabSize": tabSize, "insertSpaces": insertSpaces},
    }

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/rangeFormatting", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var edits: seq[TextEdit] = @[]
  if resp.kind == JArray:
    for item in resp:
      edits.add(parseTextEdit(item))

  return ok(edits)

# Capability checking - uses capabilities received from worker events
proc hasCompletionSupport*(svc: LspService, langId: string): bool =
  ## Check if completion is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].completionProvider.isSome

proc hasHoverSupport*(svc: LspService, langId: string): bool =
  ## Check if hover is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].hoverProvider.isSome

proc hasDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to definition is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].definitionProvider.isSome

proc hasDeclarationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to declaration is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].declarationProvider.isSome

proc hasTypeDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to type definition is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].typeDefinitionProvider.isSome

proc hasImplementationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to implementation is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].implementationProvider.isSome

proc hasReferencesSupport*(svc: LspService, langId: string): bool =
  ## Check if find references is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].referencesProvider.isSome

proc hasDocumentHighlightSupport*(svc: LspService, langId: string): bool =
  ## Check if document highlight is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].documentHighlightProvider.isSome

proc hasDocumentLinkSupport*(svc: LspService, langId: string): bool =
  ## Check if document link is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].documentLinkProvider.isSome

proc hasDocumentLinkResolveSupport*(svc: LspService, langId: string): bool =
  ## Check if document link resolve is supported for a language
  if langId notin svc.capabilities:
    return false

  let provider = svc.capabilities[langId].documentLinkProvider
  if provider.isNone:
    return false

  # Check if resolveProvider is true in the provider options
  let providerNode = provider.get
  if providerNode.kind == JObject and providerNode.hasKey("resolveProvider"):
    return providerNode["resolveProvider"].getBool(false)

  return false

proc hasSignatureHelpSupport*(svc: LspService, langId: string): bool =
  ## Check if signature help is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].signatureHelpProvider.isSome

proc hasRenameSupport*(svc: LspService, langId: string): bool =
  ## Check if rename is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].renameProvider.isSome

proc hasFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if document formatting is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].documentFormattingProvider.isSome

proc hasRangeFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if range formatting is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].documentRangeFormattingProvider.isSome

proc hasDocumentSymbolSupport*(svc: LspService, langId: string): bool =
  ## Check if document symbol is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].documentSymbolProvider.isSome

proc requestDocumentSymbols*(
    svc: LspService, path: string
): Result[DocumentSymbolResult, string] =
  ## Request document symbols for a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/documentSymbol", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseDocumentSymbolResult(respResult.get))

proc hasInlayHintSupport*(svc: LspService, langId: string): bool =
  ## Check if inlay hints is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].inlayHintProvider.isSome

proc requestInlayHints*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[seq[InlayHint], string] =
  ## Request inlay hints for a range in a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
    }

  let requestId = svc.startTrackedRequest(worker, "textDocument/inlayHint", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var hints: seq[InlayHint] = @[]
  if resp.kind == JArray:
    for item in resp:
      hints.add(parseInlayHint(item))

  return ok(hints)

proc hasSemanticTokensSupport*(svc: LspService, langId: string): bool =
  ## Check if semantic tokens is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].semanticTokensProvider.isSome

proc hasSemanticTokensFullSupport*(svc: LspService, langId: string): bool =
  ## Check if full semantic tokens is supported for a language
  if langId notin svc.capabilities:
    return false
  let provider = svc.capabilities[langId].semanticTokensProvider
  if provider.isNone:
    return false
  return provider.get.full.isSome

proc hasSemanticTokensRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if range semantic tokens is supported for a language
  if langId notin svc.capabilities:
    return false
  let provider = svc.capabilities[langId].semanticTokensProvider
  if provider.isNone:
    return false
  return provider.get.range.isSome

proc getSemanticTokensLegend*(
    svc: LspService, langId: string
): Option[SemanticTokensLegend] =
  ## Get the semantic tokens legend for a language
  if langId notin svc.capabilities:
    return none(SemanticTokensLegend)
  let provider = svc.capabilities[langId].semanticTokensProvider
  if provider.isNone:
    return none(SemanticTokensLegend)
  return some(provider.get.legend)

proc requestSemanticTokensFull*(
    svc: LspService, path: string
): Result[Option[SemanticTokens], string] =
  ## Request full semantic tokens for a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/semanticTokens/full", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return ok(none(SemanticTokens))

  return ok(some(parseSemanticTokens(resp)))

proc requestSemanticTokensRange*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[Option[SemanticTokens], string] =
  ## Request semantic tokens for a range in a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params =
    %*{
      "textDocument": {"uri": uri},
      "range": {
        "start": {"line": startLine, "character": startChar},
        "end": {"line": endLine, "character": endChar},
      },
    }

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/semanticTokens/range", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  if resp.kind == JNull:
    return ok(none(SemanticTokens))

  return ok(some(parseSemanticTokens(resp)))

proc hasSelectionRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if selection range is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].selectionRangeProvider.isSome

proc hasInlineValueSupport*(svc: LspService, langId: string): bool =
  ## Check if inline value is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].inlineValueProvider.isSome

proc requestSelectionRange*(
    svc: LspService, path: string, positions: seq[Position]
): Result[seq[SelectionRange], string] =
  ## Request selection ranges for given positions in a file (not yet implemented)
  err("Selection range not yet supported with worker model")

proc requestSelectionRange*(
    svc: LspService, path: string, line, character: int
): Result[Option[SelectionRange], string] =
  ## Request selection range for a single position in a file (not yet implemented)
  err("Selection range not yet supported with worker model")

# Status information
proc getRunningLanguages*(svc: LspService): seq[string] =
  ## Get list of languages with running LSP servers
  for langId, worker in svc.workers:
    if worker.isRunning:
      result.add(langId)

proc getServerInfo*(svc: LspService, langId: string): Option[ServerInfo] =
  ## Get server information for a language
  if langId notin svc.serverInfo:
    return none(ServerInfo)
  let info = svc.serverInfo[langId]
  return some(ServerInfo(name: info.name, version: info.version))

proc requestInlineValues*(
    svc: LspService,
    path: string,
    startLine, startChar, endLine, endChar: int,
    frameId: int,
    stoppedLine, stoppedStartChar, stoppedEndLine, stoppedEndChar: int,
): Result[seq[InlineValue], string] =
  ## Request inline values for a range in a file during debugging (not yet implemented)
  err("Inline values not yet supported with worker model")

# CodeLens support
proc hasCodeLensSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].codeLensProvider.isSome

proc hasCodeLensResolveSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens resolve is supported for a language
  if langId notin svc.capabilities:
    return false

  let provider = svc.capabilities[langId].codeLensProvider
  if provider.isNone:
    return false

  # Check if resolveProvider is true in the provider options
  let providerNode = provider.get
  if providerNode.kind == JObject and providerNode.hasKey("resolveProvider"):
    return providerNode["resolveProvider"].getBool(false)

  return false

proc requestCodeLens*(svc: LspService, path: string): Result[seq[CodeLens], string] =
  ## Request code lenses for a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/codeLens", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var lenses: seq[CodeLens] = @[]
  if resp.kind == JArray:
    for item in resp:
      lenses.add(parseCodeLens(item))

  return ok(lenses)

proc requestCodeLensResolve*(
    svc: LspService, path: string, lens: CodeLens
): Result[CodeLens, string] =
  ## Resolve a code lens to get its command
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  # Convert CodeLens to JSON params
  let params = codeLensToJson(lens)

  let requestId = svc.startTrackedRequest(worker, "codeLens/resolve", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(parseCodeLens(respResult.get))

proc requestExecuteCommand*(
    svc: LspService, path: string, command: string, arguments: seq[JsonNode] = @[]
): Result[JsonNode, string] =
  ## Execute a command on the LSP server
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let params = %*{"command": command, "arguments": arguments}

  let requestId = svc.startTrackedRequest(worker, "workspace/executeCommand", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  return ok(respResult.get)

proc hasCallHierarchySupport*(svc: LspService, langId: string): bool =
  ## Check if call hierarchy is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].callHierarchyProvider.isSome

proc hasFoldingRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if folding range is supported for a language
  if langId notin svc.capabilities:
    return false
  return svc.capabilities[langId].foldingRangeProvider.isSome

proc requestCallHierarchyPrepare*(
    svc: LspService, path: string, line, character: int
): Result[seq[CallHierarchyItem], string] =
  ## Prepare call hierarchy at a given position (not yet implemented)
  err("Call hierarchy not yet supported with worker model")

proc requestCallHierarchyIncomingCalls*(
    svc: LspService, path: string, item: CallHierarchyItem
): Result[seq[CallHierarchyIncomingCall], string] =
  ## Request incoming calls for a CallHierarchyItem (not yet implemented)
  err("Call hierarchy not yet supported with worker model")

proc requestCallHierarchyOutgoingCalls*(
    svc: LspService, path: string, item: CallHierarchyItem
): Result[seq[CallHierarchyOutgoingCall], string] =
  ## Request outgoing calls for a CallHierarchyItem (not yet implemented)
  err("Call hierarchy not yet supported with worker model")

proc requestFoldingRange*(
    svc: LspService, path: string
): Result[seq[FoldingRange], string] =
  ## Request folding ranges for a file
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}

  let requestId = svc.startTrackedRequest(worker, "textDocument/foldingRange", params)
  let respResult = svc.waitForResponse(requestId)

  if respResult.isErr:
    return err(respResult.error)

  let resp = respResult.get
  var ranges: seq[FoldingRange] = @[]
  if resp.kind == JArray:
    for item in resp:
      ranges.add(parseFoldingRange(item))

  return ok(ranges)
