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

## LSP Worker Thread
## Runs chronos event loop in a separate thread to avoid blocking the UI

import std/[json, options, os, strutils, strtabs, locks, tables, atomics, deques]

import pkg/[results, chronos]
import pkg/chronos/[asyncproc, threadsync]

import jsonrpc
import protocol/types

export types

const
  # Signal wait timeouts
  SignalTimeoutRunningMs* = 50 # Short timeout when LSP server is running
  SignalTimeoutIdleMs* = 500 # Longer timeout when idle

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

  LspCommand* = object
    case kind*: LspCommandKind
    of lcmdStart:
      languageId*: string
      command*: string
      args*: seq[string]
      workspaceRoot*: string
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
      reqParams*: JsonNode

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

  LspEvent* = object
    case kind*: LspEventKind
    of levInitialized:
      discard
    of levError:
      errorMsg*: string
    of levDiagnostics:
      diagUri*: string
      diagnostics*: seq[Diagnostic]
    of levLogMessage, levShowMessage:
      msgType*: MessageType
      message*: string
    of levServerInfo:
      serverName*: string
      serverVersion*: Option[string]
    of levCapabilities:
      capabilities*: ServerCapabilities
    of levResponse:
      requestId*: int
      responseResult*: Option[JsonNode]
      responseError*: Option[string]

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

  LspWorker* = ref object
    thread: Thread[LspWorkerContext]
    commandQueue: CommandQueue
    eventQueue: EventQueue
    sharedState: SharedState
    signal: ThreadSignalPtr # Signal for event-driven wakeup
    languageId*: string
    nextRequestId: int # For generating unique request IDs

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
    "workspace": {"applyEdit": true, "workspaceFolders": true, "configuration": false},
  }

# Worker thread main loop
proc workerThreadProc(ctx: LspWorkerContext) {.thread.} =
  var
    serverProcess: AsyncProcessRef = nil
    serverStreams: Streams = nil
    outputFuture: Future[JsonRpcResponseResult] = nil
    lastId = 0
    # Pending document notifications to send after initialization
    pendingDidOpen: seq[LspCommand] = @[]
    # Map LSP request ID to our request ID for response tracking
    pendingRequests: Table[int, int]

  proc sendEvent(kind: LspEventKind) =
    var evt = LspEvent(kind: kind)
    ctx.eventQueue[].push(evt)

  proc sendError(msg: string) =
    var evt = LspEvent(kind: levError, errorMsg: msg)
    ctx.eventQueue[].push(evt)

  proc sendLogMessage(msgType: MessageType, msg: string) =
    var evt = LspEvent(kind: levLogMessage, msgType: msgType, message: msg)
    ctx.eventQueue[].push(evt)

  proc sendDiagnostics(uri: string, diags: seq[Diagnostic]) =
    var evt = LspEvent(kind: levDiagnostics, diagUri: uri, diagnostics: diags)
    ctx.eventQueue[].push(evt)

  proc sendCapabilities(caps: ServerCapabilities) =
    var evt = LspEvent(kind: levCapabilities, capabilities: caps)
    ctx.eventQueue[].push(evt)

  proc sendServerInfo(name: string, version: Option[string]) =
    var evt = LspEvent(kind: levServerInfo, serverName: name, serverVersion: version)
    ctx.eventQueue[].push(evt)

  proc sendResponse(reqId: int, result: Option[JsonNode], error: Option[string]) =
    var evt = LspEvent(
      kind: levResponse, requestId: reqId, responseResult: result, responseError: error
    )
    ctx.eventQueue[].push(evt)

  proc handleNotification(meth: string, params: JsonNode) =
    case meth
    of "textDocument/publishDiagnostics":
      let uri = params["uri"].getStr
      var diagnostics: seq[Diagnostic] = @[]
      if params.hasKey("diagnostics"):
        for d in params["diagnostics"]:
          diagnostics.add(parseDiagnostic(d))
      sendDiagnostics(uri, diagnostics)
    of "window/logMessage":
      var evt = LspEvent(
        kind: levLogMessage,
        msgType: MessageType(params["type"].getInt),
        message: params["message"].getStr,
      )
      ctx.eventQueue[].push(evt)
    of "window/showMessage":
      var evt = LspEvent(
        kind: levShowMessage,
        msgType: MessageType(params["type"].getInt),
        message: params["message"].getStr,
      )
      ctx.eventQueue[].push(evt)
    else:
      discard

  proc sendRequest(
      meth: string, params: JsonNode
  ): Future[Result[int, string]] {.async.} =
    if serverStreams.isNil:
      return Result[int, string].err("Server not running")

    lastId.inc
    let req = %*{"jsonrpc": "2.0", "id": lastId, "method": meth, "params": params}
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
    return await serverStreams.input.sendNotify(notify)

  proc sendNotificationLog(meth: string, params: JsonNode): Future[void] {.async.} =
    ## Send notification and log any errors (non-critical)
    let sendResult = await sendNotification(meth, params)
    if sendResult.isErr:
      sendLogMessage(mtWarning, "Failed to send " & meth & ": " & sendResult.error)

  proc startServer(cmd: LspCommand): Future[void] {.async.} =
    ctx.sharedState.storeState(lwsStarting)

    let commandParts = cmd.command.split(' ')
    let command = commandParts[0]
    var args = cmd.args
    if commandParts.len > 1:
      args = commandParts[1 ..^ 1] & args

    # Use /tmp as working directory to prevent nimlangserver from
    # detecting a project based on moe's current working directory
    let workingDir = "/tmp"
    let env: StringTableRef = nil
    let opts: set[AsyncProcessOption] = {UsePath, StdErrToStdOut}

    try:
      serverProcess = await startProcess(
        command,
        workingDir,
        args,
        env,
        opts,
        stdoutHandle = AsyncProcess.Pipe,
        stdinHandle = AsyncProcess.Pipe,
      )
    except CatchableError as e:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to start LSP server: " & e.msg)
      return

    serverStreams = Streams(
      input: InputStream(stream: serverProcess.stdinStream),
      output: OutputStream(stream: serverProcess.stdoutStream),
    )

    outputFuture = serverStreams.output.read()

    # Send initialize request
    # Use null rootUri/rootPath to let server determine project per-file
    let initParams =
      %*{
        "processId": getCurrentProcessId(),
        "clientInfo": {"name": "moe", "version": "0.3.0"},
        "rootUri": newJNull(),
        "rootPath": newJNull(),
        "workspaceFolders": newJNull(),
        "capabilities": buildClientCapabilities(),
        "trace": "verbose",
      }

    let reqResult = await sendRequest("initialize", initParams)
    if reqResult.isErr:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to send initialize: " & reqResult.error)
      return

    # Wait for initialize response
    while true:
      let respResult = await outputFuture
      outputFuture = serverStreams.output.read()

      if respResult.isErr:
        ctx.sharedState.storeState(lwsCrashed)
        sendError("Failed to read initialize response: " & respResult.error)
        return

      let response = respResult.get

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

      # Check for error
      if response.hasKey("error"):
        ctx.sharedState.storeState(lwsCrashed)
        sendError(
          "Initialize error: " & response["error"]["message"].getStr("Unknown error")
        )
        return

      # Parse capabilities
      if response.hasKey("result"):
        let resultNode = response["result"]
        if resultNode.hasKey("capabilities"):
          sendCapabilities(parseServerCapabilities(resultNode["capabilities"]))
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
      return

    # Send workspace/didChangeConfiguration (some servers need this)
    await sendNotificationLog("workspace/didChangeConfiguration", %*{"settings": {}})

    ctx.sharedState.storeState(lwsRunning)
    sendEvent(levInitialized)

    # Send all pending didOpen notifications now that server is running
    for cmd in pendingDidOpen:
      let params =
        %*{
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

    # Send shutdown request with timeout
    try:
      discard await sendRequest("shutdown", newJNull())
      await sleepAsync(milliseconds(100))
      # Send exit notification
      await sendNotificationLog("exit", %*{})
    except CatchableError as e:
      sendLogMessage(mtWarning, "Error during graceful shutdown: " & e.msg)

    # Kill process if still exists
    try:
      if serverProcess != nil:
        discard serverProcess.kill()
    except CatchableError as e:
      sendLogMessage(mtWarning, "Failed to kill LSP server process: " & e.msg)

    serverProcess = nil
    serverStreams = nil
    outputFuture = nil
    pendingRequests.clear()
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
        let params =
          %*{
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
        let params =
          %*{
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
          # No pending didOpen for this URI, can't do much without langId
          discard
    of lcmdDidSave:
      if ctx.sharedState.loadState() == lwsRunning:
        var params = %*{"textDocument": {"uri": cmd.saveUri}}
        if cmd.saveText.isSome:
          params["text"] = %cmd.saveText.get
        await sendNotificationLog("textDocument/didSave", params)
    of lcmdRequest:
      if ctx.sharedState.loadState() == lwsRunning:
        let lspIdResult = await sendRequest(cmd.reqMethod, cmd.reqParams)
        if lspIdResult.isOk:
          # Track mapping from LSP request ID to our request ID
          pendingRequests[lspIdResult.get] = cmd.requestId
        else:
          # Send error response immediately
          sendResponse(cmd.requestId, none(JsonNode), some(lspIdResult.error))
      else:
        sendResponse(cmd.requestId, none(JsonNode), some("Server not running"))

  proc processMessages(): Future[void] {.async.} =
    if outputFuture.isNil:
      return

    if not outputFuture.finished:
      return

    let respResult = outputFuture.read()
    outputFuture = serverStreams.output.read()

    if respResult.isErr:
      sendError("Read error: " & respResult.error)
      return

    let response = respResult.get

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

    # Check if this is a response (has "id", no "method")
    if response.hasKey("id") and not response.hasKey("method"):
      let lspId = response["id"].getInt
      if lspId in pendingRequests:
        let ourId = pendingRequests[lspId]
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

      # Process any available messages from server
      if ctx.sharedState.loadState() == lwsRunning and outputFuture != nil:
        try:
          await processMessages()
        except CatchableError as e:
          sendError("Message processing error: " & e.msg)
          # Don't crash the worker, continue processing

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

# Public API

proc initSharedState(): SharedState =
  result.running.store(false, moRelaxed)
  result.stateVal.store(lwsStopped.ord, moRelaxed)

proc newLspWorker*(languageId: string): Result[LspWorker, string] =
  ## Create a new LSP worker. Returns error if signal creation fails.
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
  )

  createThread(worker.thread, workerThreadProc, ctx)

proc stop*(worker: LspWorker) =
  if not worker.sharedState.running.load(moAcquire):
    return

  # Push shutdown command and signal worker to wake up
  worker.commandQueue.pushAndSignal(LspCommand(kind: lcmdShutdown), worker.signal)
  joinThread(worker.thread)
  worker.sharedState.running.store(false, moRelease)

  # Clean up signal
  discard worker.signal.close()

proc startServer*(
    worker: LspWorker, command: string, args: seq[string], workspaceRoot: string
) =
  let cmd = LspCommand(
    kind: lcmdStart,
    languageId: worker.languageId,
    command: command,
    args: args,
    workspaceRoot: workspaceRoot,
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

proc sendRequest*(worker: LspWorker, meth: string, params: JsonNode): int =
  ## Send a request to the LSP server and return the request ID
  ## Use pollEvents to get the response with matching requestId
  result = worker.nextRequestId
  worker.nextRequestId.inc

  let cmd =
    LspCommand(kind: lcmdRequest, requestId: result, reqMethod: meth, reqParams: params)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)
