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

## LSP Worker Thread
## Runs chronos event loop in a separate thread to avoid blocking the UI

import std/[json, options, os, strutils, strtabs, locks, tables, atomics, deques, uri]
import std/times except milliseconds

import pkg/[results, chronos]
import pkg/chronos/[asyncproc, threadsync, selectors2]

import jsonrpc
import protocol/types

export types

proc pathToFileUri*(path: string): string =
  ## Build a percent-encoded file:// URI from an absolute path. Encoding is
  ## per segment so the separators survive; without it a workspace path
  ## containing spaces or non-ASCII characters produces an invalid rootUri
  ## that strict servers reject. Mirrors lsp_service.pathToUri (kept local
  ## to avoid a dependency cycle).
  var segments: seq[string]
  for segment in path.split('/'):
    segments.add(encodeUrl(segment, usePlus = false))
  "file://" & segments.join("/")

const
  # Signal wait timeouts
  SignalTimeoutRunningMs* = 50 # Short timeout when LSP server is running
  SignalTimeoutIdleMs* = 500 # Longer timeout when idle
  # Request timeout in seconds
  RequestTimeoutSec* = 30

type
  LspWorkerState* = enum
    lwsStopped = 0
    lwsStarting = 1
    lwsRunning = 2
    lwsShuttingDown = 3
    lwsCrashed = 4

  # Thread-safe shared state using atomics
  SharedState = object
    running: Atomic[bool]
    stateVal: Atomic[int] # LspWorkerState stored as int for atomic access

  # Messages from main thread to worker thread
  LspCommandKind* = enum
    lcmdStart # Start LSP server
    lcmdStop # Stop LSP server
    lcmdShutdown # Shutdown worker thread
    lcmdDidOpen # textDocument/didOpen
    lcmdDidClose # textDocument/didClose
    lcmdDidChange # textDocument/didChange
    lcmdDidSave # textDocument/didSave
    lcmdRequest # Generic request with response tracking
    lcmdNotification # Generic notification (no response expected)
    lcmdCancel # Cancel a tracked request ($/cancelRequest)

  LspCommand* = object
    case kind*: LspCommandKind
    of lcmdStart:
      languageId*: string
      command*: string
      args*: seq[string]
      workspaceRoot*: string
      initializationOptions*: string # Serialized JSON ("" = none)
    of lcmdStop, lcmdShutdown:
      discard
    of lcmdDidOpen:
      openUri*: string
      openLangId*: string
      openVersion*: int
      openText*: string
    of lcmdDidClose:
      closeUri*: string
    of lcmdDidChange:
      changeUri*: string
      changeVersion*: int
      changeText*: string
    of lcmdDidSave:
      saveUri*: string
      saveText*: Option[string]
    of lcmdRequest:
      requestId*: int # ID for tracking response
      reqMethod*: string
      reqParamsJson*: string # JSON-serialized params (see note below)
    of lcmdNotification:
      notifyMethod*: string
      notifyParamsJson*: string # JSON-serialized params (see note below)
    of lcmdCancel:
      cancelRequestId*: int # Tracking ID (the service-side id) to cancel

  # Messages from worker thread to main thread
  LspEventKind* = enum
    levInitialized # LSP server initialized
    levError # Error occurred
    levDiagnostics # Diagnostics received
    levLogMessage # Log message from server
    levShowMessage # Show message from server
    levServerInfo # Server info after init
    levCapabilities # Server capabilities after init
    levResponse # Response to a request
    levRawJson # Raw JSON sent/received for debugging
    levProgress # Work done progress notification
    levDynamicRegister # Dynamic capability registration
    levDynamicUnregister # Dynamic capability unregistration
    levStatusUpdate # Server status notification (experimental/serverStatus)

  # Server health status from experimental/serverStatus
  ServerHealth* = enum
    shOk = "ok"
    shWarning = "warning"
    shError = "error"

  LspJsonDirection* = enum
    ljdSent # JSON sent to server
    ljdReceived # JSON received from server

  # NOTE on thread safety: LspCommand/LspEvent cross the worker-thread
  # boundary via the deques below. The objects themselves are copied under
  # the queue lock, but any GC-managed *ref* embedded in them (JsonNode in
  # particular, including those buried in Diagnostic.code/data,
  # ServerCapabilities and Registration.registerOptions) would still be
  # shared between threads. Under --mm:orc the reference counts are not
  # atomic, so concurrent incRef/decRef from both threads can corrupt
  # memory. Therefore all JSON payloads are serialized to strings at the
  # boundary and parsed on the receiving thread.
  LspEvent* = object
    case kind*: LspEventKind
    of levInitialized:
      discard
    of levError:
      errorMsg*: string
    of levDiagnostics:
      diagUri*: string
      diagnosticsJson*: string # JSON array of LSP Diagnostic objects
    of levLogMessage, levShowMessage:
      msgType*: MessageType
      message*: string
    of levServerInfo:
      serverName*: string
      serverVersion*: Option[string]
    of levCapabilities:
      capabilitiesJson*: string # JSON object (ServerCapabilities)
    of levResponse:
      requestId*: int
      responseResultJson*: Option[string] # JSON-serialized result
      responseError*: Option[string]
    of levRawJson:
      jsonDirection*: LspJsonDirection
      rawJson*: string
    of levProgress:
      progressToken*: string # Progress token (int or string converted to string)
      progress*: WorkDoneProgress # Progress data (begin/report/end)
    of levDynamicRegister:
      registrationsJson*: string # JSON-serialized RegistrationParams
    of levDynamicUnregister:
      unregistrationsJson*: string # JSON-serialized UnregistrationParams
    of levStatusUpdate:
      statusHealth*: ServerHealth
      statusQuiescent*: bool
      statusMessage*: Option[string]

  # Thread-safe queues using locks and deques for O(1) operations
  CommandQueue = object
    lock: Lock
    queue: Deque[LspCommand]

  EventQueue = object
    lock: Lock
    queue: Deque[LspEvent]

  LspWorkerContext = object
    commandQueue: ptr CommandQueue
    eventQueue: ptr EventQueue
    sharedState: ptr SharedState
    signal: ThreadSignalPtr # Signal for event-driven wakeup
    tempDir: string
    rawJsonLog: bool # Emit levRawJson events for every frame (debug only)

  LspWorker* = ref object
    thread: Thread[LspWorkerContext]
    threadStarted: bool
    stopped: bool
    commandQueue: CommandQueue
    eventQueue: EventQueue
    sharedState: SharedState
    signal: ThreadSignalPtr # Signal for event-driven wakeup
    languageId*: string
    nextRequestId: int # For generating unique request IDs
    rawJsonLog: bool # Forwarded to the worker context on start()

# Atomic state accessors
proc loadRunning(s: ptr SharedState): bool {.inline.} =
  s[].running.load(moAcquire)

proc storeRunning(s: ptr SharedState, val: bool) {.inline.} =
  s[].running.store(val, moRelease)

proc loadState(s: ptr SharedState): LspWorkerState {.inline.} =
  LspWorkerState(s[].stateVal.load(moAcquire))

proc storeState(s: ptr SharedState, val: LspWorkerState) {.inline.} =
  s[].stateVal.store(val.ord, moRelease)

# Queue operations
proc initCommandQueue(): CommandQueue =
  result.lock.initLock()
  result.queue = initDeque[LspCommand]()

proc initEventQueue(): EventQueue =
  result.lock.initLock()
  result.queue = initDeque[LspEvent]()

proc pushAndSignal(q: var CommandQueue, cmd: LspCommand, signal: ThreadSignalPtr) =
  ## Push command and signal the worker thread
  withLock(q.lock):
    q.queue.addLast(cmd)
  # Signal after releasing lock to avoid holding lock during syscall
  # Ignore signal errors - command is already queued and will be processed
  let signalResult = signal.fireSync()
  if signalResult.isErr:
    discard # Signal failed but command is queued; worker will pick it up on next timeout

proc pop(q: var CommandQueue): Option[LspCommand] =
  withLock(q.lock):
    if q.queue.len > 0:
      result = some(q.queue.popFirst())
    else:
      result = none(LspCommand)

proc hasPendingStopOrShutdown(q: var CommandQueue): bool =
  ## True if a stop/shutdown command is waiting in the queue. Used to abort
  ## long waits (e.g. the initialize handshake) so a queued stop can be
  ## processed promptly; commands are handled serially, so a blocked wait
  ## would otherwise stall editor exit on joinThread.
  withLock(q.lock):
    for cmd in q.queue.items:
      if cmd.kind in {lcmdStop, lcmdShutdown}:
        return true
  false

proc push(q: var EventQueue, evt: LspEvent) =
  withLock(q.lock):
    q.queue.addLast(evt)

proc popAll*(q: var EventQueue): seq[LspEvent] =
  withLock(q.lock):
    result = newSeqOfCap[LspEvent](q.queue.len)
    while q.queue.len > 0:
      result.add(q.queue.popFirst())

# Client capabilities
proc buildClientCapabilities(): JsonNode =
  %*{
    "textDocument": {
      "synchronization": {
        "dynamicRegistration": true,
        "willSave": false,
        "willSaveWaitUntil": false,
        "didSave": true,
      },
      "completion": {
        "dynamicRegistration": true,
        "completionItem": {
          "snippetSupport": true,
          "commitCharactersSupport": true,
          "documentationFormat": ["plaintext", "markdown"],
          "deprecatedSupport": true,
          "preselectSupport": true,
        },
        "contextSupport": true,
      },
      "hover": {"dynamicRegistration": true, "contentFormat": ["plaintext", "markdown"]},
      "signatureHelp": {
        "dynamicRegistration": true,
        "signatureInformation": {"documentationFormat": ["plaintext", "markdown"]},
      },
      "declaration": {"dynamicRegistration": true},
      "definition": {"dynamicRegistration": true},
      "typeDefinition": {"dynamicRegistration": true},
      "implementation": {"dynamicRegistration": true},
      "references": {"dynamicRegistration": true},
      "documentHighlight": {"dynamicRegistration": true},
      "documentLink": {"dynamicRegistration": true, "tooltipSupport": true},
      "documentSymbol":
        {"dynamicRegistration": true, "hierarchicalDocumentSymbolSupport": true},
      "publishDiagnostics":
        {"relatedInformation": true, "tagSupport": {"valueSet": [1, 2]}},
      "rename": {"dynamicRegistration": true, "prepareSupport": false},
      "codeAction": {
        "dynamicRegistration": true,
        "codeActionLiteralSupport": {
          "codeActionKind": {
            "valueSet": [
              "", "quickfix", "refactor", "refactor.extract", "refactor.inline",
              "refactor.rewrite", "source", "source.organizeImports", "source.fixAll",
            ]
          }
        },
        "isPreferredSupport": true,
        "disabledSupport": true,
        "dataSupport": true,
        "resolveSupport": {"properties": ["edit"]},
      },
      "formatting": {"dynamicRegistration": true},
      "rangeFormatting": {"dynamicRegistration": true},
      "inlayHint": {"dynamicRegistration": true},
      "selectionRange": {"dynamicRegistration": true},
      "codeLens": {"dynamicRegistration": true},
      "callHierarchy": {"dynamicRegistration": true},
      "foldingRange": {
        "dynamicRegistration": true,
        "rangeLimit": 5000,
        "lineFoldingOnly": true,
        "foldingRangeKind": {"valueSet": ["comment", "imports", "region"]},
      },
      "semanticTokens": {
        "dynamicRegistration": true,
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
    "workspace": {"applyEdit": true, "workspaceFolders": true, "configuration": false},
    "window": {"workDoneProgress": true},
    # rust-analyzer only emits its run/debug CodeLenses when the client declares
    # it can execute the corresponding client-side commands. Advertise the ones
    # moe handles (see editor_codelens.executeCodeLensItem); the actual
    # run/debug lens visibility is still gated per-setting via the server's
    # initializationOptions (lens.run/lens.debug).
    "experimental": {
      "commands": {"commands": ["rust-analyzer.runSingle", "rust-analyzer.debugSingle"]}
    },
  }

# Worker thread main loop
proc workerThreadProc(ctx: LspWorkerContext) {.thread.} =
  var
    serverProcess: AsyncProcessRef = nil
    serverStreams: Streams = nil
    outputFuture: Future[JsonRpcResponseResult] = nil
    # Drains the server's stderr pipe so it never blocks the child and its
    # output never corrupts the JSON-RPC stdout stream
    stderrDrainFut: Future[void] = nil
    lastId = 0
    # Pending document notifications to send after initialization
    pendingDidOpen: seq[LspCommand] = @[]
    # Map LSP request ID to (our request ID, timestamp) for response tracking
    pendingRequests: Table[int, tuple[requestId: int, timestamp: Time]]

  proc sendEvent(kind: LspEventKind) =
    var evt = LspEvent(kind: kind)
    ctx.eventQueue[].push(evt)

  proc sendError(msg: string) =
    var evt = LspEvent(kind: levError, errorMsg: msg)
    ctx.eventQueue[].push(evt)

  proc sendLogMessage(msgType: MessageType, msg: string) =
    var evt = LspEvent(kind: levLogMessage, msgType: msgType, message: msg)
    ctx.eventQueue[].push(evt)

  proc sendDiagnostics(uri: string, diagsJson: string) =
    var evt = LspEvent(kind: levDiagnostics, diagUri: uri, diagnosticsJson: diagsJson)
    ctx.eventQueue[].push(evt)

  proc sendCapabilities(capsJson: string) =
    var evt = LspEvent(kind: levCapabilities, capabilitiesJson: capsJson)
    ctx.eventQueue[].push(evt)

  proc sendServerInfo(name: string, version: Option[string]) =
    var evt = LspEvent(kind: levServerInfo, serverName: name, serverVersion: version)
    ctx.eventQueue[].push(evt)

  proc sendResponse(reqId: int, result: Option[JsonNode], error: Option[string]) =
    # Serialize on this side of the boundary; the JsonNode stays owned by
    # the worker thread
    let resultJson =
      if result.isSome:
        some($result.get)
      else:
        none(string)
    var evt = LspEvent(
      kind: levResponse,
      requestId: reqId,
      responseResultJson: resultJson,
      responseError: error,
    )
    ctx.eventQueue[].push(evt)

  proc sendRawJson(direction: LspJsonDirection, node: JsonNode) =
    # Gate on the debug flag: pretty-printing every frame (a full-document
    # didChange on each keystroke under full sync) and pushing it through the
    # event queue is expensive and the in-memory log grows unbounded, so skip
    # the work entirely unless raw-JSON logging was explicitly enabled.
    if not ctx.rawJsonLog:
      return
    var evt = LspEvent(kind: levRawJson, jsonDirection: direction, rawJson: node.pretty)
    ctx.eventQueue[].push(evt)

  proc sendDynamicRegister(paramsJson: string) =
    var evt = LspEvent(kind: levDynamicRegister, registrationsJson: paramsJson)
    ctx.eventQueue[].push(evt)

  proc sendDynamicUnregister(paramsJson: string) =
    var evt = LspEvent(kind: levDynamicUnregister, unregistrationsJson: paramsJson)
    ctx.eventQueue[].push(evt)

  proc handleServerRequest(
      meth: string, reqId: JsonNode, params: JsonNode
  ): Future[JsonNode] {.async.} =
    ## Handle server-initiated requests. Returns the response to send.
    case meth
    of "window/workDoneProgress/create":
      # Accept the progress token creation (respond with null/empty result)
      return %*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()}
    of "client/registerCapability":
      # Dynamic capability registration. Validate here so a malformed
      # request is rejected to the server; the main thread re-parses the
      # serialized params when it processes the event.
      try:
        discard parseRegistrationParams(params)
        sendDynamicRegister($params)
        return %*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()}
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse registerCapability: " & e.msg)
        return %*{
          "jsonrpc": "2.0",
          "id": reqId,
          "error": {"code": -32602, "message": "Invalid params: " & e.msg},
        }
    of "client/unregisterCapability":
      # Dynamic capability unregistration (validated as above)
      try:
        discard parseUnregistrationParams(params)
        sendDynamicUnregister($params)
        return %*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()}
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse unregisterCapability: " & e.msg)
        return %*{
          "jsonrpc": "2.0",
          "id": reqId,
          "error": {"code": -32602, "message": "Invalid params: " & e.msg},
        }
    else:
      # Unknown server request - respond with method not found error
      sendLogMessage(mtInfo, "Unknown server request: " & meth)
      return %*{
        "jsonrpc": "2.0",
        "id": reqId,
        "error": {"code": -32601, "message": "Method not found: " & meth},
      }

  proc handleNotification(meth: string, params: JsonNode) =
    case meth
    of "textDocument/publishDiagnostics":
      let uri = params["uri"].getStr
      # Serialize the raw diagnostics array; the main thread parses it
      # (Diagnostic carries JsonNode fields that must not cross threads)
      let diagsJson =
        if params.hasKey("diagnostics"):
          $params["diagnostics"]
        else:
          "[]"
      sendDiagnostics(uri, diagsJson)
    of "window/logMessage":
      var evt = LspEvent(
        kind: levLogMessage,
        msgType: toEnumOr[MessageType](params["type"].getInt, mtLog),
        message: params["message"].getStr,
      )
      ctx.eventQueue[].push(evt)
    of "window/showMessage":
      var evt = LspEvent(
        kind: levShowMessage,
        msgType: toEnumOr[MessageType](params["type"].getInt, mtLog),
        message: params["message"].getStr,
      )
      ctx.eventQueue[].push(evt)
    of "$/logTrace":
      var message = params["message"].getStr
      if params.hasKey("verbose"):
        message &= "\n" & params["verbose"].getStr
      var evt = LspEvent(kind: levLogMessage, msgType: mtInfo, message: message)
      ctx.eventQueue[].push(evt)
    of "$/progress":
      try:
        let progressParams = parseWorkDoneProgressParams(params)
        var evt = LspEvent(
          kind: levProgress,
          progressToken: getProgressToken(progressParams),
          progress: progressParams.value,
        )
        ctx.eventQueue[].push(evt)
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse $/progress: " & e.msg)
    of "experimental/serverStatus":
      # rust-analyzer style status notification
      try:
        let health =
          case params["health"].getStr
          of "warning": shWarning
          of "error": shError
          else: shOk
        let quiescent = params.getOrDefault("quiescent").getBool(true)
        let message =
          if params.hasKey("message") and params["message"].kind == JString:
            some(params["message"].getStr)
          else:
            none(string)
        var evt = LspEvent(
          kind: levStatusUpdate,
          statusHealth: health,
          statusQuiescent: quiescent,
          statusMessage: message,
        )
        ctx.eventQueue[].push(evt)
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse experimental/serverStatus: " & e.msg)
    of "extension/statusUpdate":
      # nimlangserver style status notification
      try:
        # Determine health from projectErrors
        let health =
          if params.hasKey("projectErrors") and params["projectErrors"].len > 0:
            shWarning
          else:
            shOk
        # Determine quiescent from pendingRequests
        let quiescent =
          if params.hasKey("pendingRequests"):
            params["pendingRequests"].len == 0
          else:
            true
        # Build message from projectErrors if any
        var message = none(string)
        if params.hasKey("projectErrors") and params["projectErrors"].len > 0:
          var errors: seq[string] = @[]
          for err in params["projectErrors"]:
            if err.kind == JString:
              errors.add(err.getStr)
          if errors.len > 0:
            message = some(errors[0]) # Show first error
        var evt = LspEvent(
          kind: levStatusUpdate,
          statusHealth: health,
          statusQuiescent: quiescent,
          statusMessage: message,
        )
        ctx.eventQueue[].push(evt)
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse extension/statusUpdate: " & e.msg)
    else:
      # Log unknown notifications for debugging
      sendLogMessage(mtInfo, "Unknown LSP notification: " & meth)

  proc sendRequest(
      meth: string, params: JsonNode
  ): Future[Result[int, string]] {.async.} =
    if serverStreams.isNil:
      return Result[int, string].err("Server not running")

    lastId.inc
    let req = %*{"jsonrpc": "2.0", "id": lastId, "method": meth, "params": params}
    # Log outgoing request JSON (pretty formatted)
    sendRawJson(ljdSent, req)
    let sendResult = await serverStreams.input.sendRequest(req)
    if sendResult.isErr:
      return Result[int, string].err(sendResult.error)
    return Result[int, string].ok(lastId)

  proc sendNotification(
      meth: string, params: JsonNode
  ): Future[Result[void, string]] {.async.} =
    if serverStreams.isNil:
      return Result[void, string].err("Server not running")

    let notify = %*{"jsonrpc": "2.0", "method": meth, "params": params}
    # Log outgoing notification JSON (pretty formatted)
    sendRawJson(ljdSent, notify)
    return await serverStreams.input.sendNotify(notify)

  proc sendNotificationLog(meth: string, params: JsonNode): Future[void] {.async.} =
    ## Send notification and log any errors (non-critical)
    let sendResult = await sendNotification(meth, params)
    if sendResult.isErr:
      sendLogMessage(mtWarning, "Failed to send " & meth & ": " & sendResult.error)

  let lspWorkingDir = ctx.tempDir

  proc cleanupProcess(): Future[void] {.async.} =
    ## Kill the server process, release its handles, and fail any requests
    ## still waiting on it. Does not change the worker state; callers set
    ## lwsStopped/lwsCrashed as appropriate.
    try:
      if serverProcess != nil:
        discard serverProcess.kill()
    except CatchableError as e:
      sendLogMessage(mtWarning, "Failed to kill LSP server process: " & e.msg)

    # Stop the stderr drain loop before closing its pipe
    if not stderrDrainFut.isNil and not stderrDrainFut.finished:
      try:
        await stderrDrainFut.cancelAndWait()
      except CatchableError:
        discard
    stderrDrainFut = nil

    if serverProcess != nil:
      # Close process pipe FDs and streams (must be called explicitly)
      try:
        await serverProcess.closeWait()
      except CatchableError:
        discard

    serverProcess = nil
    serverStreams = nil
    outputFuture = nil
    # Fail pending requests instead of leaving the main thread to hit its
    # own response timeout for each of them
    for lspId, (ourId, _) in pendingRequests.pairs:
      sendResponse(ourId, none(JsonNode), some("LSP server stopped"))
    pendingRequests.clear()

  proc startServer(cmd: LspCommand): Future[void] {.async.} =
    ctx.sharedState.storeState(lwsStarting)

    let commandParts = cmd.command.split(' ')
    let command = commandParts[0]
    var args = cmd.args
    if commandParts.len > 1:
      args = commandParts[1 ..^ 1] & args

    # Use temp dir as working directory to prevent nimlangserver from
    # detecting a project based on moe's current working directory
    let workingDir = lspWorkingDir
    let env: StringTableRef = nil
    # stderr gets its own pipe: merging it into stdout (StdErrToStdOut) would
    # interleave server log output with the JSON-RPC framing stream and
    # permanently desynchronize it.
    let opts: set[AsyncProcessOption] = {UsePath}

    try:
      serverProcess = await startProcess(
        command,
        workingDir,
        args,
        env,
        opts,
        stdoutHandle = AsyncProcess.Pipe,
        stdinHandle = AsyncProcess.Pipe,
        stderrHandle = AsyncProcess.Pipe,
      )
    except CatchableError as e:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to start LSP server: " & e.msg)
      return

    serverStreams = Streams(
      input: InputStream(stream: serverProcess.stdinStream),
      output: OutputStream(stream: serverProcess.stdoutStream),
    )

    proc drainStderr() {.async.} =
      ## Keep reading stderr so the child never blocks on a full pipe.
      ## Lines are forwarded to the message log.
      let stderrStream = serverProcess.stderrStream
      while true:
        try:
          var line = await stderrStream.readLine(sep = "\n")
          if line.len == 0 and stderrStream.atEof():
            break
          if line.len > 0 and line[^1] == '\r':
            line.setLen(line.len - 1)
          if line.len > 0:
            sendLogMessage(mtLog, "[lsp stderr] " & line)
        except CatchableError:
          break

    stderrDrainFut = drainStderr()

    outputFuture = serverStreams.output.read()

    # Send initialize request
    # Use workspaceRoot if provided, otherwise null
    let rootUri =
      if cmd.workspaceRoot.len > 0:
        newJString(pathToFileUri(cmd.workspaceRoot))
      else:
        newJNull()
    let rootPath =
      if cmd.workspaceRoot.len > 0:
        newJString(cmd.workspaceRoot)
      else:
        newJNull()

    var initParams = %*{
      "processId": getCurrentProcessId(),
      "clientInfo": {"name": "moe", "version": "0.3.0"},
      "rootUri": rootUri,
      "rootPath": rootPath,
      "workspaceFolders": newJNull(),
      "capabilities": buildClientCapabilities(),
      # Only ask the server for verbose $/logTrace traffic when raw-JSON
      # logging is enabled; otherwise it floods the event queue for nothing.
      "trace": (if ctx.rawJsonLog: "verbose" else: "off"),
    }

    # Forward server-specific initializationOptions (e.g. rust-analyzer lens
    # config). Carried as a serialized string across the thread boundary.
    if cmd.initializationOptions.len > 0:
      try:
        initParams["initializationOptions"] = parseJson(cmd.initializationOptions)
      except JsonParsingError:
        discard

    let reqResult = await sendRequest("initialize", initParams)
    if reqResult.isErr:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to send initialize: " & reqResult.error)
      await cleanupProcess()
      return

    # Wait for initialize response (bounded).
    # An unresponsive server must not hang this loop: commands are processed
    # serially, so a pending lcmdShutdown would never run and worker.stop()'s
    # joinThread would block editor exit. Note: withTimeout is unsuitable
    # here because it cancels the stream read on timeout, which would corrupt
    # the framing; race + an explicitly cancelled sleeper keeps the read
    # future alive across wait rounds.
    const InitializeTimeoutSec = 30
    let initDeadline = Moment.now() + chronos.seconds(InitializeTimeoutSec)
    while true:
      while not outputFuture.finished:
        let sleeper = sleepAsync(chronos.seconds(1))
        discard await race(outputFuture, sleeper)
        if not sleeper.finished:
          await sleeper.cancelAndWait()
        if ctx.commandQueue[].hasPendingStopOrShutdown():
          sendLogMessage(mtWarning, "LSP initialize aborted by stop request")
          await cleanupProcess()
          ctx.sharedState.storeState(lwsStopped)
          return
        if Moment.now() > initDeadline:
          ctx.sharedState.storeState(lwsCrashed)
          sendError(
            "LSP server initialize timed out after " & $InitializeTimeoutSec & "s"
          )
          await cleanupProcess()
          return

      let respResult = outputFuture.read()

      if respResult.isErr:
        ctx.sharedState.storeState(lwsCrashed)
        sendError("Failed to read initialize response: " & respResult.error)
        await cleanupProcess()
        return

      outputFuture = serverStreams.output.read()

      let response = respResult.get
      # Log received JSON (pretty formatted)
      sendRawJson(ljdReceived, response)

      # Handle notification
      if response.hasKey("method") and not response.hasKey("id"):
        handleNotification(
          response["method"].getStr,
          if response.hasKey("params"):
            response["params"]
          else:
            newJObject(),
        )
        continue

      # Handle server request (has both "method" and "id")
      if response.hasKey("method") and response.hasKey("id"):
        let meth = response["method"].getStr
        let reqId = response["id"]
        let params =
          if response.hasKey("params"):
            response["params"]
          else:
            newJObject()
        let resp = await handleServerRequest(meth, reqId, params)
        sendRawJson(ljdSent, resp)
        discard await serverStreams.input.sendRequest(resp)
        continue

      # Check for error
      if response.hasKey("error"):
        ctx.sharedState.storeState(lwsCrashed)
        sendError(
          "Initialize error: " & response["error"]["message"].getStr("Unknown error")
        )
        await cleanupProcess()
        return

      # Forward capabilities (parsed on the main thread)
      if response.hasKey("result"):
        let resultNode = response["result"]
        if resultNode.hasKey("capabilities"):
          sendCapabilities($resultNode["capabilities"])
        if resultNode.hasKey("serverInfo"):
          let si = resultNode["serverInfo"]
          var version: Option[string] = none(string)
          if si.hasKey("version"):
            version = some(si["version"].getStr)
          sendServerInfo(si["name"].getStr, version)

      break

    # Send initialized notification
    let initedResult = await sendNotification("initialized", %*{})
    if initedResult.isErr:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to send initialized: " & initedResult.error)
      await cleanupProcess()
      return

    # Send workspace/didChangeConfiguration (some servers need this)
    await sendNotificationLog("workspace/didChangeConfiguration", %*{"settings": {}})

    ctx.sharedState.storeState(lwsRunning)
    sendEvent(levInitialized)

    # Send all pending didOpen notifications now that server is running
    for cmd in pendingDidOpen:
      let params = %*{
        "textDocument": {
          "uri": cmd.openUri,
          "languageId": cmd.openLangId,
          "version": cmd.openVersion,
          "text": cmd.openText,
        }
      }
      await sendNotificationLog("textDocument/didOpen", params)
    pendingDidOpen = @[]

  proc stopServer(): Future[void] {.async.} =
    if serverProcess.isNil:
      return

    ctx.sharedState.storeState(lwsShuttingDown)

    # Kill the LSP server process immediately without waiting for shutdown RPC
    # response. The graceful shutdown handshake can block for up to 30 seconds
    # if the server is unresponsive, which delays editor exit unnecessarily.
    await cleanupProcess()
    ctx.sharedState.storeState(lwsStopped)

  proc processCommand(cmd: LspCommand): Future[void] {.async.} =
    case cmd.kind
    of lcmdStart:
      await startServer(cmd)
    of lcmdStop:
      await stopServer()
    of lcmdShutdown:
      await stopServer()
      ctx.sharedState.storeRunning(false)
    of lcmdDidOpen:
      if ctx.sharedState.loadState() == lwsRunning:
        let params = %*{
          "textDocument": {
            "uri": cmd.openUri,
            "languageId": cmd.openLangId,
            "version": cmd.openVersion,
            "text": cmd.openText,
          }
        }
        await sendNotificationLog("textDocument/didOpen", params)
      else:
        let currentState = ctx.sharedState.loadState()
        if currentState == lwsStarting or currentState == lwsStopped:
          # Queue didOpen to send after initialization completes
          # Also handle lwsStopped because lcmdStart may still be pending in queue
          pendingDidOpen.add(cmd)
    of lcmdDidClose:
      if ctx.sharedState.loadState() == lwsRunning:
        let params = %*{"textDocument": {"uri": cmd.closeUri}}
        await sendNotificationLog("textDocument/didClose", params)
    of lcmdDidChange:
      let changeState = ctx.sharedState.loadState()
      if changeState == lwsRunning:
        let params = %*{
          "textDocument": {"uri": cmd.changeUri, "version": cmd.changeVersion},
          "contentChanges": [{"text": cmd.changeText}],
        }
        await sendNotificationLog("textDocument/didChange", params)
      elif changeState == lwsStarting or changeState == lwsStopped:
        # Queue as didOpen with latest content (replaces any pending didOpen for same URI)
        # Also handle lwsStopped because lcmdStart may still be pending in queue
        var found = false
        for i in 0 ..< pendingDidOpen.len:
          if pendingDidOpen[i].openUri == cmd.changeUri:
            # Update the pending didOpen with new content
            pendingDidOpen[i] = LspCommand(
              kind: lcmdDidOpen,
              openUri: cmd.changeUri,
              openLangId: pendingDidOpen[i].openLangId,
              openVersion: cmd.changeVersion,
              openText: cmd.changeText,
            )
            found = true
            break
        if not found:
          # No pending didOpen for this URI, can't send didChange without prior didOpen
          sendLogMessage(
            mtWarning,
            "didChange received for URI without prior didOpen: " & cmd.changeUri,
          )
    of lcmdDidSave:
      if ctx.sharedState.loadState() == lwsRunning:
        var params = %*{"textDocument": {"uri": cmd.saveUri}}
        if cmd.saveText.isSome:
          params["text"] = %cmd.saveText.get
        await sendNotificationLog("textDocument/didSave", params)
    of lcmdRequest:
      if ctx.sharedState.loadState() == lwsRunning:
        var params: JsonNode
        try:
          params = parseJson(cmd.reqParamsJson)
        except CatchableError as e:
          sendResponse(
            cmd.requestId, none(JsonNode), some("Invalid request params: " & e.msg)
          )
          return
        let lspIdResult = await sendRequest(cmd.reqMethod, params)
        if lspIdResult.isOk:
          # Track mapping from LSP request ID to our request ID with timestamp
          pendingRequests[lspIdResult.get] = (cmd.requestId, getTime())
        else:
          # Send error response immediately
          sendResponse(cmd.requestId, none(JsonNode), some(lspIdResult.error))
      else:
        sendResponse(cmd.requestId, none(JsonNode), some("Server not running"))
    of lcmdNotification:
      if ctx.sharedState.loadState() == lwsRunning:
        var params: JsonNode
        try:
          params = parseJson(cmd.notifyParamsJson)
        except CatchableError as e:
          sendLogMessage(
            mtWarning, "Invalid params for " & cmd.notifyMethod & ": " & e.msg
          )
          return
        await sendNotificationLog(cmd.notifyMethod, params)
    of lcmdCancel:
      # Translate the service-side tracking id to the JSON-RPC id actually
      # sent to the server (pendingRequests maps lspId -> tracking id), then
      # send $/cancelRequest with that id. Drop the mapping so the eventual
      # response is treated as a late/unknown response and ignored.
      var lspId = -1
      for id, (ourId, _) in pendingRequests:
        if ourId == cmd.cancelRequestId:
          lspId = id
          break
      if lspId >= 0:
        pendingRequests.del(lspId)
        if ctx.sharedState.loadState() == lwsRunning:
          await sendNotificationLog("$/cancelRequest", %*{"id": lspId})

  proc processMessages(): Future[void] {.async.} =
    if outputFuture.isNil:
      return

    if not outputFuture.finished:
      return

    let respResult = outputFuture.read()

    if respResult.isErr:
      # The read failed: the server closed stdout (crashed or exited) or the
      # pipe broke. Do NOT re-arm the read — it would fail again instantly
      # and spin an error event every tick. Mark the worker crashed and
      # reap the process so the service can restart it.
      outputFuture = nil
      ctx.sharedState.storeState(lwsCrashed)
      sendError("LSP server connection lost: " & respResult.error)
      await cleanupProcess()
      return

    # Re-arm only after a successful read
    outputFuture = serverStreams.output.read()

    let response = respResult.get
    # Log received JSON (pretty formatted)
    sendRawJson(ljdReceived, response)

    # Check if this is a notification (has "method", no "id")
    if response.hasKey("method") and not response.hasKey("id"):
      let meth = response["method"].getStr
      handleNotification(
        meth,
        if response.hasKey("params"):
          response["params"]
        else:
          newJObject(),
      )
      return

    # Check if this is a server request (has both "method" and "id")
    if response.hasKey("method") and response.hasKey("id"):
      let meth = response["method"].getStr
      let reqId = response["id"]
      let params =
        if response.hasKey("params"):
          response["params"]
        else:
          newJObject()

      let resp = await handleServerRequest(meth, reqId, params)
      sendRawJson(ljdSent, resp)
      discard await serverStreams.input.sendRequest(resp)
      return

    # Check if this is a response (has "id", no "method")
    if response.hasKey("id") and not response.hasKey("method"):
      let lspId = response["id"].getInt
      if lspId in pendingRequests:
        let (ourId, _) = pendingRequests[lspId]
        pendingRequests.del(lspId)

        # Check for error
        if response.hasKey("error"):
          let errMsg = response["error"]["message"].getStr("Unknown error")
          sendResponse(ourId, none(JsonNode), some(errMsg))
        elif response.hasKey("result"):
          sendResponse(ourId, some(response["result"]), none(string))
        else:
          # Empty result (e.g., for void responses)
          sendResponse(ourId, some(newJNull()), none(string))
      else:
        # Response for unknown/timed-out request
        sendLogMessage(
          mtInfo, "Received late response for timed-out request (id=" & $lspId & ")"
        )

  proc checkRequestTimeouts() =
    ## Check for timed out requests and send error responses
    let now = getTime()
    var timedOutIds: seq[int] = @[]

    for lspId, (ourId, timestamp) in pendingRequests.pairs:
      if (now - timestamp).inSeconds >= RequestTimeoutSec:
        timedOutIds.add(lspId)
        sendResponse(ourId, none(JsonNode), some("Request timed out"))
        sendLogMessage(mtWarning, "LSP request timed out (id=" & $lspId & ")")

    for lspId in timedOutIds:
      pendingRequests.del(lspId)

  proc mainLoop() {.async.} =
    while ctx.sharedState.loadRunning():
      # Process any pending commands
      while true:
        let cmdOpt = ctx.commandQueue[].pop()
        if cmdOpt.isNone:
          break
        try:
          await processCommand(cmdOpt.get)
        except CatchableError as e:
          sendError("Command processing error: " & e.msg)
          # Don't crash the worker, continue processing

      # Drain all messages the server has already delivered. The signal only
      # fires on main-thread command enqueue, not on server data, so handling
      # a single message per wakeup capped throughput at ~1 message per
      # SignalTimeoutRunningMs (~20/s) and made diagnostics/progress floods
      # lag by seconds, spuriously tripping request timeouts. Loop while a
      # completed frame is ready; processMessages re-arms outputFuture on
      # success and nils it on error/crash, so this terminates.
      if ctx.sharedState.loadState() == lwsRunning:
        try:
          while outputFuture != nil and outputFuture.finished:
            await processMessages()
        except CatchableError as e:
          sendError("Message processing error: " & e.msg)
          # Don't crash the worker, continue processing

      # Check for timed out requests
      if pendingRequests.len > 0:
        checkRequestTimeouts()

      # Wait for signal from main thread or timeout
      # Timeout ensures we check outputFuture periodically when LSP server is running
      try:
        if ctx.sharedState.loadState() == lwsRunning and outputFuture != nil:
          # When server is running, use short timeout to check for LSP messages
          discard
            await ctx.signal.wait().withTimeout(milliseconds(SignalTimeoutRunningMs))
        else:
          # When server is not running, wait longer for commands
          discard await ctx.signal.wait().withTimeout(milliseconds(SignalTimeoutIdleMs))
      except CatchableError:
        # Timeout or error - continue loop
        discard

  # Run the async main loop with top-level exception handling
  try:
    waitFor mainLoop()
  except CatchableError as e:
    # Fatal error - worker thread is about to exit
    var evt = LspEvent(kind: levError, errorMsg: "Worker thread fatal error: " & e.msg)
    ctx.eventQueue[].push(evt)
    ctx.sharedState.storeState(lwsCrashed)
    ctx.sharedState.storeRunning(false)
  finally:
    # Close the chronos dispatcher's selector (epoll fd) to prevent FD leak.
    # PDispatcher has no destructor, so we must close it explicitly.
    # Use finally to ensure cleanup even on Defect.
    try:
      let disp = getThreadDispatcher()
      disp.getIoHandler().close()
    except CancelledError:
      discard
    except Defect:
      discard

# Public API

proc initSharedState(): SharedState =
  result.running.store(false, moRelaxed)
  result.stateVal.store(lwsStopped.ord, moRelaxed)

proc newLspWorker*(languageId: string, rawJsonLog = false): Result[LspWorker, string] =
  ## Create a new LSP worker. Returns error if signal creation fails.
  ## rawJsonLog enables per-frame levRawJson debug events (off by default).
  let signalResult = ThreadSignalPtr.new()
  if signalResult.isErr:
    return err("Failed to create thread signal: " & signalResult.error)

  ok(
    LspWorker(
      commandQueue: initCommandQueue(),
      eventQueue: initEventQueue(),
      sharedState: initSharedState(),
      signal: signalResult.get,
      languageId: languageId,
      nextRequestId: 1,
      rawJsonLog: rawJsonLog,
    )
  )

proc start*(worker: LspWorker) =
  if worker.sharedState.running.load(moAcquire):
    return

  worker.sharedState.running.store(true, moRelease)
  worker.sharedState.stateVal.store(lwsStopped.ord, moRelease)

  let ctx = LspWorkerContext(
    commandQueue: addr worker.commandQueue,
    eventQueue: addr worker.eventQueue,
    sharedState: addr worker.sharedState,
    signal: worker.signal,
    tempDir: getTempDir(),
    rawJsonLog: worker.rawJsonLog,
  )

  createThread(worker.thread, workerThreadProc, ctx)
  worker.threadStarted = true

proc stop*(worker: LspWorker) =
  if worker.stopped:
    return

  if worker.sharedState.running.load(moAcquire):
    # Normal case: send shutdown command to gracefully stop
    worker.commandQueue.pushAndSignal(LspCommand(kind: lcmdShutdown), worker.signal)

  if worker.threadStarted:
    # Always join the thread if it was started, even if the worker has crashed.
    # Without joining, the old thread may still be accessing shared memory when
    # the LspWorker ref is freed, causing allocator corruption.
    joinThread(worker.thread)
    worker.threadStarted = false

  worker.sharedState.running.store(false, moRelease)

  # Clean up locks
  deinitLock(worker.commandQueue.lock)
  deinitLock(worker.eventQueue.lock)

  # Clean up signal
  discard worker.signal.close()

  worker.stopped = true

proc startServer*(
    worker: LspWorker,
    command: string,
    args: seq[string],
    workspaceRoot: string,
    initializationOptions: string = "",
) =
  let cmd = LspCommand(
    kind: lcmdStart,
    languageId: worker.languageId,
    command: command,
    args: args,
    workspaceRoot: workspaceRoot,
    initializationOptions: initializationOptions,
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc stopServer*(worker: LspWorker) =
  worker.commandQueue.pushAndSignal(LspCommand(kind: lcmdStop), worker.signal)

proc didOpen*(worker: LspWorker, uri, langId: string, version: int, text: string) =
  let cmd = LspCommand(
    kind: lcmdDidOpen,
    openUri: uri,
    openLangId: langId,
    openVersion: version,
    openText: text,
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc didClose*(worker: LspWorker, uri: string) =
  worker.commandQueue.pushAndSignal(
    LspCommand(kind: lcmdDidClose, closeUri: uri), worker.signal
  )

proc didChange*(worker: LspWorker, uri: string, version: int, text: string) =
  let cmd = LspCommand(
    kind: lcmdDidChange, changeUri: uri, changeVersion: version, changeText: text
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc didSave*(worker: LspWorker, uri: string, text: Option[string] = none(string)) =
  let cmd = LspCommand(kind: lcmdDidSave, saveUri: uri, saveText: text)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc pollEvents*(worker: LspWorker): seq[LspEvent] =
  ## Poll for events from the worker (non-blocking)
  result = worker.eventQueue.popAll()

proc state*(worker: LspWorker): LspWorkerState =
  ## Get the current worker state (thread-safe)
  LspWorkerState(worker.sharedState.stateVal.load(moAcquire))

proc isRunning*(worker: LspWorker): bool =
  ## Check if worker is running and LSP server is ready (thread-safe)
  worker.sharedState.running.load(moAcquire) and
    worker.sharedState.stateVal.load(moAcquire) == lwsRunning.ord

proc isStarting*(worker: LspWorker): bool =
  ## Check if worker is starting (thread-safe)
  worker.sharedState.running.load(moAcquire) and
    worker.sharedState.stateVal.load(moAcquire) == lwsStarting.ord

proc isStopped*(worker: LspWorker): bool =
  ## Check if worker is stopped (thread-safe)
  not worker.sharedState.running.load(moAcquire) or
    worker.sharedState.stateVal.load(moAcquire) == lwsStopped.ord

proc isThreadAlive*(worker: LspWorker): bool =
  ## Check if the worker thread itself is still running its main loop
  ## (thread-safe). The server process state is independent: a worker whose
  ## server crashed (lwsCrashed) keeps its thread alive and can be asked to
  ## start a new server without re-creating the thread.
  worker.threadStarted and not worker.stopped and
    worker.sharedState.running.load(moAcquire)

proc sendRequest*(worker: LspWorker, requestId: int, meth: string, params: JsonNode) =
  ## Send a request to the LSP server with a caller-provided request ID.
  ## Use pollEvents to get the response with matching requestId.
  ## The caller is responsible for ID uniqueness; LspService allocates IDs
  ## from a single counter shared by all workers so responses from different
  ## language servers can never collide in its tracking tables.
  ## The params are serialized here so no JsonNode ref crosses the thread
  ## boundary (non-atomic ORC refcounts).
  let cmd = LspCommand(
    kind: lcmdRequest, requestId: requestId, reqMethod: meth, reqParamsJson: $params
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc sendRequest*(worker: LspWorker, meth: string, params: JsonNode): int =
  ## Send a request to the LSP server and return the request ID
  ## Use pollEvents to get the response with matching requestId
  ## Note: IDs from this worker-local counter are only unique within this
  ## worker; cross-worker callers should allocate IDs themselves and use the
  ## explicit-ID overload.
  result = worker.nextRequestId
  worker.nextRequestId.inc
  worker.sendRequest(result, meth, params)

proc sendNotification*(worker: LspWorker, meth: string, params: JsonNode) =
  ## Send a notification to the LSP server (no response expected)
  let cmd =
    LspCommand(kind: lcmdNotification, notifyMethod: meth, notifyParamsJson: $params)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc cancelRequest*(worker: LspWorker, requestId: int) =
  ## Cancel a previously sent request identified by its tracking ID. The
  ## worker resolves the tracking ID to the server's JSON-RPC ID and sends
  ## $/cancelRequest; a plain notification cannot do this because the caller
  ## does not know the server-facing ID.
  let cmd = LspCommand(kind: lcmdCancel, cancelRequestId: requestId)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)
