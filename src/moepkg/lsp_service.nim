#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import std/[tables, options, os, strutils, json, times, uri]

import pkg/[results, chronos]

import lsp/worker
import lsp/protocol/types

export worker, types

const
  DefaultRequestTimeoutMs* = 5000 ## 5 second timeout for LSP requests
  PollIntervalMs = 5 ## Polling interval for async response waiting

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
    ##
    ## Thread Safety:
    ## - This type is NOT thread-safe. All public methods must be called from
    ##   the main thread only.
    ## - The workers handle thread communication internally via thread-safe queues.
    ## - Callbacks (onDiagnosticsUpdate, onLogMessage, etc.) are invoked from the
    ##   main thread during poll() calls, NOT from worker threads.
    ## - The {.gcsafe.} pragma on callbacks is required because they may reference
    ##   global state, but actual invocation is always single-threaded.
    workers: Table[string, LspWorker] # languageId -> worker
    configs: Table[string, LanguageServerConfig] # languageId -> config
    capabilities: Table[string, ServerCapabilities] # languageId -> capabilities
    serverInfo: Table[string, tuple[name: string, version: Option[string]]]
      # languageId -> server info
    # Dynamic registrations: languageId -> (registrationId -> Registration)
    dynamicRegistrations: Table[string, Table[string, Registration]]
    workspaceRoot: string
    enabled*: bool
    # Pending request responses (requestId -> response)
    pendingResponses: Table[int, tuple[result: Option[JsonNode], error: Option[string]]]
    # Active pending requests for timeout tracking
    activeRequests*: Table[int, LspPendingRequest]
    # Single request-ID counter shared by all workers. Both tables above are
    # keyed by the bare ID, so letting each worker allocate its own IDs
    # (starting at 1) would collide as soon as two language servers run
    # concurrently and responses could be attributed to the wrong request.
    nextRequestId: int
    # Global callbacks (forwarded from individual workers)
    onDiagnosticsUpdate*: proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.}
    onLogMessage*:
      proc(langId: string, msgType: MessageType, message: string) {.gcsafe.}
    onProgress*:
      proc(langId: string, token: string, progress: WorkDoneProgress) {.gcsafe.}
    onStatusUpdate*: proc(
      langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
    ) {.gcsafe.}

proc newLspService*(workspaceRoot: string = ""): LspService =
  ## Create a new LSP service
  result = LspService(
    workers: initTable[string, LspWorker](),
    configs: initTable[string, LanguageServerConfig](),
    capabilities: initTable[string, ServerCapabilities](),
    serverInfo: initTable[string, tuple[name: string, version: Option[string]]](),
    dynamicRegistrations: initTable[string, Table[string, Registration]](),
    workspaceRoot:
      if workspaceRoot.len > 0:
        workspaceRoot
      else:
        getCurrentDir(),
    enabled: true,
    pendingResponses:
      initTable[int, tuple[result: Option[JsonNode], error: Option[string]]](),
    activeRequests: initTable[int, LspPendingRequest](),
    nextRequestId: 1,
    # Default no-op callbacks to avoid nil checks throughout the code
    onDiagnosticsUpdate: proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.} =
      discard,
    onLogMessage: proc(
        langId: string, msgType: MessageType, message: string
    ) {.gcsafe.} =
      discard,
    onProgress: proc(
        langId: string, token: string, progress: WorkDoneProgress
    ) {.gcsafe.} =
      discard,
    onStatusUpdate: proc(
        langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
    ) {.gcsafe.} =
      discard,
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
  ## Convert file path to a percent-encoded file:// URI.
  ## Encoding is applied per path segment (encodeUrl would also encode the
  ## separators). Servers echo URIs back percent-encoded, so without proper
  ## encoding/decoding paths with spaces or non-ASCII characters fail to
  ## match open buffers.
  if path.startsWith("file://"):
    return path
  var segments: seq[string]
  for segment in path.absolutePath().split('/'):
    segments.add(encodeUrl(segment, usePlus = false))
  return "file://" & segments.join("/")

proc uriToPath*(uri: string): string =
  ## Convert a file:// URI to a file path, percent-decoding it
  if uri.startsWith("file://"):
    return decodeUrl(uri[7 ..^ 1], decodePlus = false)
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

  # Return existing worker if present. stopWorker removes from table,
  # so any worker in the table is active (thread running).
  if langId in svc.workers:
    return ok(svc.workers[langId])

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
  svc.dynamicRegistrations.del(langId)

  # Clean up pending requests for this language
  var toRemove: seq[int] = @[]
  for reqId, req in svc.activeRequests:
    if req.langId == langId:
      toRemove.add(reqId)
  for reqId in toRemove:
    svc.activeRequests.del(reqId)
    svc.pendingResponses.del(reqId)

  return ok()

proc stopAll*(svc: LspService) =
  ## Stop all workers
  for langId, worker in svc.workers:
    worker.stop()
  svc.workers.clear()
  svc.capabilities.clear()
  svc.serverInfo.clear()
  svc.dynamicRegistrations.clear()
  svc.activeRequests.clear()
  svc.pendingResponses.clear()

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
        svc.onLogMessage(langId, mtInfo, "Language server initialized")
      of levError:
        svc.onLogMessage(langId, mtError, evt.errorMsg)
      of levDiagnostics:
        svc.onDiagnosticsUpdate(evt.diagUri, evt.diagnostics)
      of levLogMessage:
        svc.onLogMessage(langId, evt.msgType, evt.message)
      of levShowMessage:
        svc.onLogMessage(langId, evt.msgType, evt.message)
      of levServerInfo:
        svc.serverInfo[langId] = (name: evt.serverName, version: evt.serverVersion)
        var msg = "Server: " & evt.serverName
        if evt.serverVersion.isSome:
          msg &= " v" & evt.serverVersion.get
        svc.onLogMessage(langId, mtInfo, msg)
      of levCapabilities:
        svc.capabilities[langId] = evt.capabilities
      of levResponse:
        svc.pendingResponses[evt.requestId] =
          (result: evt.responseResult, error: evt.responseError)
      of levRawJson:
        let timestamp = now().format("HH:mm:ss'.'fff")
        let direction = if evt.jsonDirection == ljdSent: ">>> " else: "<<< "
        # Split multi-line JSON into separate log entries
        let lines = evt.rawJson.splitLines()
        for i, line in lines:
          if i == 0:
            svc.onLogMessage(langId, mtLog, "[" & timestamp & "] " & direction & line)
          else:
            svc.onLogMessage(langId, mtLog, "    " & line)
        # Add blank line after each JSON block
        svc.onLogMessage(langId, mtLog, "")
      of levProgress:
        svc.onProgress(langId, evt.progressToken, evt.progress)
      of levDynamicRegister:
        # Dynamic capability registration
        if langId notin svc.dynamicRegistrations:
          svc.dynamicRegistrations[langId] = initTable[string, Registration]()
        for reg in evt.registrations:
          svc.dynamicRegistrations[langId][reg.id] = reg
          svc.onLogMessage(
            langId,
            mtInfo,
            "Dynamic registration: " & reg.`method` & " (id: " & reg.id & ")",
          )
      of levDynamicUnregister:
        # Dynamic capability unregistration
        if langId in svc.dynamicRegistrations:
          for unreg in evt.unregistrations:
            if unreg.id in svc.dynamicRegistrations[langId]:
              svc.dynamicRegistrations[langId].del(unreg.id)
              svc.onLogMessage(
                langId,
                mtInfo,
                "Dynamic unregistration: " & unreg.`method` & " (id: " & unreg.id & ")",
              )
      of levStatusUpdate:
        svc.onStatusUpdate(
          langId, evt.statusHealth, evt.statusQuiescent, evt.statusMessage
        )

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
    svc.pendingResponses.del(reqId)

proc cancelRequest*(svc: LspService, requestId: int) =
  ## Cancel a pending request: send $/cancelRequest to the LSP server and
  ## clean up tracking state. If the response has already arrived, it is
  ## discarded silently.
  if requestId in svc.activeRequests:
    let req = svc.activeRequests[requestId]
    # Send $/cancelRequest notification to the LSP server
    if req.langId in svc.workers:
      let worker = svc.workers[req.langId]
      if worker.isRunning:
        worker.sendNotification("$/cancelRequest", %*{"id": requestId})
    svc.activeRequests.del(requestId)
  svc.pendingResponses.del(requestId)

# Request-response helper (async, non-blocking)
proc waitForResponse*(
    svc: LspService, requestId: int, timeoutMs: int = DefaultRequestTimeoutMs
): Future[Result[JsonNode, string]] {.async: (raises: [CancelledError]).} =
  ## Wait for response asynchronously - uses async sleep instead of blocking
  let startTime = epochTime()
  let timeoutSec = timeoutMs.float / 1000.0

  while true:
    # Poll for new events
    # Note: poll() should not raise exceptions, but we handle them defensively
    # and log any unexpected errors via the service's log callback
    {.cast(raises: []).}:
      try:
        svc.poll()
      except CatchableError as e:
        svc.onLogMessage("", mtError, "Unexpected error in poll: " & e.msg)
      except Defect as e:
        svc.onLogMessage("", mtError, "Defect in poll: " & e.msg)
        raise

    # Check if response has arrived
    {.cast(raises: []).}:
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
      {.cast(raises: []).}:
        svc.activeRequests.del(requestId)
      return err("Request timed out")

    # Async sleep to yield to other tasks
    await sleepAsync(timer.milliseconds(PollIntervalMs))

# Helper to start a tracked request
proc startTrackedRequest(
    svc: LspService,
    worker: LspWorker,
    methodName: string,
    params: JsonNode,
    timeoutMs: int = DefaultRequestTimeoutMs,
): int =
  ## Start a request and track it for timeout checking
  ## IDs are allocated from the service-wide counter so requests to
  ## different workers never share an ID in the tracking tables.
  let requestId = svc.nextRequestId
  inc svc.nextRequestId
  worker.sendRequest(requestId, methodName, params)
  svc.activeRequests[requestId] = LspPendingRequest(
    requestId: requestId,
    langId: worker.languageId,
    methodName: methodName,
    startTime: epochTime(),
    timeoutMs: timeoutMs,
  )
  return requestId

# Helper for position-based LSP requests (reduces boilerplate)
proc startPositionRequest(
    svc: LspService, path: string, line, character: int, methodName: string
): Result[int, string] =
  ## Common helper for position-based LSP requests
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)
  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")
  let uri = pathToUri(path)
  let params =
    %*{"textDocument": {"uri": uri}, "position": {"line": line, "character": character}}
  ok(svc.startTrackedRequest(worker, methodName, params))

# Helper for document-based LSP requests (path only, no position)
proc startDocumentRequest(
    svc: LspService, path: string, methodName: string
): Result[int, string] =
  ## Common helper for document-based LSP requests
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)
  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")
  let uri = pathToUri(path)
  let params = %*{"textDocument": {"uri": uri}}
  ok(svc.startTrackedRequest(worker, methodName, params))

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
  svc.startPositionRequest(path, line, character, "textDocument/completion")

proc startCompletionResolveRequest*(
    svc: LspService, path: string, itemJson: JsonNode
): Result[int, string] =
  ## Start a completionItem/resolve request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)
  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")
  ok(svc.startTrackedRequest(worker, "completionItem/resolve", itemJson))

proc startHoverRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a hover request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/hover")

proc startDefinitionRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a definition request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/definition")

proc startDeclarationRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a declaration request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/declaration")

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
  let params = %*{
    "textDocument": {"uri": uri},
    "position": {"line": line, "character": character},
    "context": {"includeDeclaration": includeDeclaration},
  }

  let requestId = svc.startTrackedRequest(worker, "textDocument/references", params)
  return ok(requestId)

proc startTypeDefinitionRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a type definition request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/typeDefinition")

proc startImplementationRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start an implementation request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/implementation")

proc startDocumentSymbolsRequest*(svc: LspService, path: string): Result[int, string] =
  ## Start a document symbols request (non-blocking). Returns request ID.
  svc.startDocumentRequest(path, "textDocument/documentSymbol")

proc startSelectionRangeRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a selection range request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{
    "textDocument": {"uri": uri}, "positions": [{"line": line, "character": character}]
  }

  let requestId = svc.startTrackedRequest(worker, "textDocument/selectionRange", params)
  return ok(requestId)

proc startSignatureHelpRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a signature help request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/signatureHelp")

proc startDocumentHighlightRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a document highlight request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/documentHighlight")

proc startCodeLensRequest*(svc: LspService, path: string): Result[int, string] =
  ## Start a code lens request (non-blocking). Returns request ID.
  svc.startDocumentRequest(path, "textDocument/codeLens")

proc startDocumentLinkRequest*(svc: LspService, path: string): Result[int, string] =
  ## Start a document link request (non-blocking). Returns request ID.
  svc.startDocumentRequest(path, "textDocument/documentLink")

proc startDocumentLinkResolveRequest*(
    svc: LspService, path: string, link: DocumentLink
): Result[int, string] =
  ## Start a document link resolve request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let params = documentLinkToJson(link)
  ok(svc.startTrackedRequest(worker, "documentLink/resolve", params))

proc startSemanticTokensFullRequest*(
    svc: LspService, path: string
): Result[int, string] =
  ## Start a semantic tokens full request (non-blocking). Returns request ID.
  svc.startDocumentRequest(path, "textDocument/semanticTokens/full")

proc startSemanticTokensRangeRequest*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[int, string] =
  ## Start a semantic tokens range request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let uri = pathToUri(path)
  let params = %*{
    "textDocument": {"uri": uri},
    "range": {
      "start": {"line": startLine, "character": startChar},
      "end": {"line": endLine, "character": endChar},
    },
  }

  let requestId =
    svc.startTrackedRequest(worker, "textDocument/semanticTokens/range", params)
  return ok(requestId)

proc startCallHierarchyPrepareRequest*(
    svc: LspService, path: string, line, character: int
): Result[int, string] =
  ## Start a call hierarchy prepare request (non-blocking). Returns request ID.
  svc.startPositionRequest(path, line, character, "textDocument/prepareCallHierarchy")

proc startCallHierarchyIncomingCallsRequest*(
    svc: LspService, path: string, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy incoming calls request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let params = %*{"item": callHierarchyItemToJson(item)}

  let requestId = svc.startTrackedRequest(worker, "callHierarchy/incomingCalls", params)
  return ok(requestId)

proc startCallHierarchyOutgoingCallsRequest*(
    svc: LspService, path: string, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy outgoing calls request (non-blocking). Returns request ID.
  let workerResult = svc.getWorkerForPath(path)
  if workerResult.isErr:
    return err(workerResult.error)

  let worker = workerResult.get
  if not worker.isRunning:
    return err("Server not ready")

  let params = %*{"item": callHierarchyItemToJson(item)}

  let requestId = svc.startTrackedRequest(worker, "callHierarchy/outgoingCalls", params)
  return ok(requestId)

# Response parsing helpers for async requests
proc parseCompletionResponse*(
    resp: JsonNode
): tuple[items: seq[CompletionItem], rawJsonItems: seq[JsonNode], isIncomplete: bool] =
  ## Parse a completion response JSON into CompletionItem sequence
  var items: seq[CompletionItem] = @[]
  var rawJsonItems: seq[JsonNode] = @[]
  var isIncomplete = false
  if resp.kind == JArray:
    for item in resp:
      items.add(parseCompletionItem(item))
      rawJsonItems.add(item)
  elif resp.kind == JObject and resp.hasKey("items"):
    if resp.hasKey("isIncomplete"):
      isIncomplete = resp["isIncomplete"].getBool
    for item in resp["items"]:
      items.add(parseCompletionItem(item))
      rawJsonItems.add(item)
  return (items, rawJsonItems, isIncomplete)

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

proc parseCallHierarchyPrepareResponse*(resp: JsonNode): seq[CallHierarchyItem] =
  ## Parse a call hierarchy prepare response JSON
  var items: seq[CallHierarchyItem] = @[]
  if resp.kind == JArray:
    for item in resp:
      items.add(parseCallHierarchyItem(item))
  return items

proc parseCallHierarchyIncomingCallsResponse*(
    resp: JsonNode
): seq[CallHierarchyIncomingCall] =
  ## Parse a call hierarchy incoming calls response JSON
  var calls: seq[CallHierarchyIncomingCall] = @[]
  if resp.kind == JArray:
    for item in resp:
      calls.add(parseCallHierarchyIncomingCall(item))
  return calls

proc parseCallHierarchyOutgoingCallsResponse*(
    resp: JsonNode
): seq[CallHierarchyOutgoingCall] =
  ## Parse a call hierarchy outgoing calls response JSON
  var calls: seq[CallHierarchyOutgoingCall] = @[]
  if resp.kind == JArray:
    for item in resp:
      calls.add(parseCallHierarchyOutgoingCall(item))
  return calls

proc parseDocumentSymbolsResponse*(resp: JsonNode): DocumentSymbolResult =
  ## Parse a document symbols response JSON
  return parseDocumentSymbolResult(resp)

proc parseSelectionRangeResponse*(resp: JsonNode): seq[SelectionRange] =
  ## Parse a selection range response JSON
  var ranges: seq[SelectionRange] = @[]
  if resp.kind == JArray:
    for item in resp:
      ranges.add(parseSelectionRange(item))
  return ranges

proc parseDocumentLinksResponse*(resp: JsonNode): seq[DocumentLink] =
  ## Parse a document links response JSON
  var links: seq[DocumentLink] = @[]
  if resp.kind == JArray:
    for item in resp:
      links.add(parseDocumentLink(item))
  return links

proc parseDocumentLinkResolveResponse*(resp: JsonNode): DocumentLink =
  ## Parse a document link resolve response JSON
  parseDocumentLink(resp)

# Capability checking - uses capabilities received from worker events

proc hasDynamicRegistration*(svc: LspService, langId, methodName: string): bool =
  ## Check if a method has been dynamically registered for a language
  if langId notin svc.dynamicRegistrations:
    return false
  for id, reg in svc.dynamicRegistrations[langId]:
    if reg.`method` == methodName:
      return true
  return false

proc getDynamicRegistration*(
    svc: LspService, langId, methodName: string
): Option[Registration] =
  ## Get dynamic registration for a method if it exists
  if langId notin svc.dynamicRegistrations:
    return none(Registration)
  for id, reg in svc.dynamicRegistrations[langId]:
    if reg.`method` == methodName:
      return some(reg)
  return none(Registration)

proc getDynamicRegistrations*(svc: LspService, langId: string): seq[Registration] =
  ## Get all dynamic registrations for a language
  if langId notin svc.dynamicRegistrations:
    return @[]
  for id, reg in svc.dynamicRegistrations[langId]:
    result.add(reg)

# Template for standard capability checks (dynamic registration + static capability)
template hasCapabilitySupport(
    svc: LspService, langId: string, methodName: string, capability: untyped
): bool =
  if svc.hasDynamicRegistration(langId, methodName):
    true
  elif langId notin svc.capabilities:
    false
  else:
    svc.capabilities[langId].capability.isSome

proc hasCompletionSupport*(svc: LspService, langId: string): bool =
  ## Check if completion is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/completion", completionProvider)

proc hasHoverSupport*(svc: LspService, langId: string): bool =
  ## Check if hover is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/hover", hoverProvider)

proc hasDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to definition is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/definition", definitionProvider)

proc hasDeclarationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to declaration is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/declaration", declarationProvider)

proc hasTypeDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to type definition is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/typeDefinition", typeDefinitionProvider
  )

proc hasImplementationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to implementation is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/implementation", implementationProvider
  )

proc hasReferencesSupport*(svc: LspService, langId: string): bool =
  ## Check if find references is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/references", referencesProvider)

proc hasDocumentHighlightSupport*(svc: LspService, langId: string): bool =
  ## Check if document highlight is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/documentHighlight", documentHighlightProvider
  )

proc hasDocumentLinkSupport*(svc: LspService, langId: string): bool =
  ## Check if document link is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/documentLink", documentLinkProvider)

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
  ## Check if signature help is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/signatureHelp", signatureHelpProvider)

proc hasRenameSupport*(svc: LspService, langId: string): bool =
  ## Check if rename is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/rename", renameProvider)

proc hasFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if document formatting is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/formatting", documentFormattingProvider
  )

proc hasRangeFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if range formatting is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/rangeFormatting", documentRangeFormattingProvider
  )

proc hasDocumentSymbolSupport*(svc: LspService, langId: string): bool =
  ## Check if document symbol is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/documentSymbol", documentSymbolProvider
  )

proc hasInlayHintSupport*(svc: LspService, langId: string): bool =
  ## Check if inlay hints is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/inlayHint", inlayHintProvider)

proc hasSemanticTokensSupport*(svc: LspService, langId: string): bool =
  ## Check if semantic tokens is supported for a language (static or dynamic)
  if svc.hasDynamicRegistration(langId, "textDocument/semanticTokens"):
    return true
  if svc.hasDynamicRegistration(langId, "textDocument/semanticTokens/full"):
    return true
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

proc hasSelectionRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if selection range is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/selectionRange", selectionRangeProvider
  )

proc hasInlineValueSupport*(svc: LspService, langId: string): bool =
  ## Check if inline value is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/inlineValue", inlineValueProvider)

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

# CodeLens support
proc hasCodeLensSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/codeLens", codeLensProvider)

proc hasCodeLensResolveSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens resolve is supported for a language (static or dynamic)
  # Check dynamic registration first
  let dynReg = svc.getDynamicRegistration(langId, "textDocument/codeLens")
  if dynReg.isSome and dynReg.get.registerOptions.isSome:
    let opts = dynReg.get.registerOptions.get
    if opts.kind == JObject and opts.hasKey("resolveProvider"):
      return opts["resolveProvider"].getBool(false)

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

proc hasCallHierarchySupport*(svc: LspService, langId: string): bool =
  ## Check if call hierarchy is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(
    langId, "textDocument/prepareCallHierarchy", callHierarchyProvider
  )

proc hasFoldingRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if folding range is supported for a language (static or dynamic)
  svc.hasCapabilitySupport(langId, "textDocument/foldingRange", foldingRangeProvider)

proc hasExecuteCommandSupport*(svc: LspService, langId: string): bool =
  ## Check if execute command is supported for a language
  svc.hasCapabilitySupport(langId, "workspace/executeCommand", executeCommandProvider)

proc requestCompletion*(
    svc: LspService, path: string, line, character: int
): Future[Result[seq[CompletionItem], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestCompletion
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri}, "position": {"line": line, "character": character}
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/completion", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(parseCompletionResponse(respResult.get).items)

proc requestHover*(
    svc: LspService, path: string, line, character: int
): Future[Result[Option[Hover], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestHover
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri}, "position": {"line": line, "character": character}
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/hover", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    let resp = respResult.get
    if resp.kind == JNull:
      return ok(none(Hover))

    return ok(some(parseHover(resp)))

proc requestFormatting*(
    svc: LspService, path: string, tabSize: int = 2, insertSpaces: bool = true
): Future[Result[seq[TextEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestFormatting
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri},
      "options": {"tabSize": tabSize, "insertSpaces": insertSpaces},
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/formatting", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    let resp = respResult.get
    var edits: seq[TextEdit] = @[]
    if resp.kind == JArray:
      for item in resp:
        edits.add(parseTextEdit(item))

    return ok(edits)

proc requestRename*(
    svc: LspService, path: string, line, character: int, newName: string
): Future[Result[Option[WorkspaceEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestRename
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "newName": newName,
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/rename", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    let resp = respResult.get
    if resp.kind == JNull:
      return ok(none(WorkspaceEdit))

    return ok(some(parseWorkspaceEdit(resp)))

proc requestDefinition*(
    svc: LspService, path: string, line, character: int
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestDefinition
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri}, "position": {"line": line, "character": character}
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/definition", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(parseLocations(respResult.get))

proc requestReferences*(
    svc: LspService, path: string, line, character: int, includeDeclaration: bool = true
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestReferences
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character},
      "context": {"includeDeclaration": includeDeclaration},
    }

    let requestId = svc.startTrackedRequest(worker, "textDocument/references", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(parseLocations(respResult.get))

proc requestDocumentSymbols*(
    svc: LspService, path: string
): Future[Result[DocumentSymbolResult, string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestDocumentSymbols
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{"textDocument": {"uri": uri}}

    let requestId =
      svc.startTrackedRequest(worker, "textDocument/documentSymbol", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(parseDocumentSymbolResult(respResult.get))

proc requestFoldingRange*(
    svc: LspService, path: string
): Future[Result[seq[FoldingRange], string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestFoldingRange
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let uri = pathToUri(path)
    let params = %*{"textDocument": {"uri": uri}}

    let requestId = svc.startTrackedRequest(worker, "textDocument/foldingRange", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    let resp = respResult.get
    var ranges: seq[FoldingRange] = @[]
    if resp.kind == JArray:
      for item in resp:
        ranges.add(parseFoldingRange(item))

    return ok(ranges)

proc requestCodeLensResolve*(
    svc: LspService, path: string, lens: CodeLens
): Future[Result[CodeLens, string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestCodeLensResolve
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let params = codeLensToJson(lens)

    let requestId = svc.startTrackedRequest(worker, "codeLens/resolve", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(parseCodeLens(respResult.get))

proc requestExecuteCommand*(
    svc: LspService, path: string, command: string, arguments: seq[JsonNode] = @[]
): Future[Result[JsonNode, string]] {.async: (raises: [CancelledError]).} =
  ## Async version of requestExecuteCommand
  {.cast(raises: [CancelledError]).}:
    let workerResult = svc.getWorkerForPath(path)
    if workerResult.isErr:
      return err(workerResult.error)

    let worker = workerResult.get
    if not worker.isRunning:
      return err("Server not ready")

    let params = %*{"command": command, "arguments": arguments}

    let requestId = svc.startTrackedRequest(worker, "workspace/executeCommand", params)
    let respResult = await svc.waitForResponse(requestId)

    if respResult.isErr:
      return err(respResult.error)

    return ok(respResult.get)
