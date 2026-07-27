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

when defined(posix):
  from std/posix import nil

import pkg/[results, chronos, jsony]
import pkg/chronos/[asyncproc, threadsync, selectors2]

import jsonrpc
import protocol/types
import ../logger

export types

type
  LspTrace* = enum ## LSP `initialize` trace level (client → server).
    traceOff = "off"
    traceMessages = "messages"
    traceVerbose = "verbose"

  # Typed params for the notifications the worker builds itself. Serialized with
  # jsony toJson, so they carry exactly these fields (no Option/null noise) and
  # match the previous %* output byte-for-byte.
  DidOpenParams = object
    textDocument: TextDocumentItem

  DidCloseParams = object
    textDocument: TextDocumentIdentifier

  FullContentChange = object
    text: string

  DidChangeParams = object
    textDocument: VersionedTextDocumentIdentifier
    contentChanges: seq[FullContentChange]

proc didOpenParamsJson(uri, langId: string, version: int, text: string): string =
  DidOpenParams(
    textDocument:
      TextDocumentItem(uri: uri, languageId: langId, version: version, text: text)
  ).toJson

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
  # Cap on undispatched inbound frames held by the read pump. The pump must
  # never block (that would re-introduce the very pipe deadlock it prevents),
  # so on overflow we treat the server as runaway and let the service restart
  # it instead of growing memory without bound. Far above any real burst.
  MaxInboundFrames* = 10_000

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
    serverPid: Atomic[int]
      # OS pid of the live server process (spawned as its own group leader);
      # 0 when no server is running. Read by the main thread at shutdown to
      # SIGKILL a worker that is wedged in a blocking write (pipe deadlock).

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
    lcmdApplyEditResponse # Answer to a server-initiated workspace/applyEdit

  LspDidChangeMode* = enum
    lcdmFull # Full document text (changeText)
    lcdmIncremental # Serialized contentChanges array (changeContentChangesJson)

  LspCommand* = object
    case kind*: LspCommandKind
    of lcmdStart:
      languageId*: string
      command*: string
      args*: seq[string]
      workspaceRoot*: string
      initializationOptions*: string # Serialized JSON ("" = none)
      settings*: string # Serialized JSON ("" = none)
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
      case changeMode*: LspDidChangeMode
      of lcdmFull:
        changeText*: string # Full document text (also used by coalescing)
      of lcdmIncremental:
        changeContentChangesJson*: string # Serialized contentChanges array
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
    of lcmdApplyEditResponse:
      # The main thread applied (or refused) a server-initiated
      # workspace/applyEdit; the worker turns this into the ApplyWorkspaceEdit
      # response the server is still blocking on.
      applyEditReqIdJson*: string # Serialized server JSON-RPC id (int or string)
      applyEditApplied*: bool
      applyEditFailureReason*: string # Empty when applied, or no reason given
      applyEditGeneration*: int
        # Server generation the request belonged to. The worker drops the
        # response if the server has since crashed and been replaced (the new
        # process never issued this id), see levApplyEdit.

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
    levApplyEdit # Server-initiated workspace/applyEdit (answered by main thread)

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
      diagVersion*: Option[int] # LSP optional, used to drop stale publishes
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
    of levApplyEdit:
      # The worker defers the response: the WorkspaceEdit is applied on the
      # main thread, which then sends back an lcmdApplyEditResponse carrying
      # the same id and generation.
      applyEditReqIdJson*: string # Serialized server JSON-RPC id for the response
      applyEditEditJson*: string # Serialized WorkspaceEdit (the request's `edit`)
      applyEditGeneration*: int
        # Server generation that issued this request. Echoed back in the
        # response command so the worker can drop it if the server crashed and
        # was replaced in the meantime (the replacement never issued this id).

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
    traceLevel: LspTrace
      # Both drives the `trace` value sent in `initialize` and gates whether
      # per-frame levRawJson events are emitted (any non-off level enables them).
    debugLog: bool # Also emit them so req/res reach the debug log file (-d)

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
    traceLevel: LspTrace # Forwarded to the worker context on start()

# Atomic state accessors
proc loadRunning(s: ptr SharedState): bool =
  s[].running.load(moAcquire)

proc storeRunning(s: ptr SharedState, val: bool) =
  s[].running.store(val, moRelease)

proc loadState(s: ptr SharedState): LspWorkerState =
  LspWorkerState(s[].stateVal.load(moAcquire))

proc storeState(s: ptr SharedState, val: LspWorkerState) =
  s[].stateVal.store(val.ord, moRelease)

proc storeServerPid(s: ptr SharedState, val: int) =
  s[].serverPid.store(val, moRelease)

proc killServerProcessGroup(pid: int) =
  ## SIGKILL the server's whole process group. The server is spawned as a group
  ## leader (AsyncProcessOption.ProcessGroup), so the negative-pid kill also
  ## reaps grandchildren (e.g. nimsuggest spawned by nimlangserver). Harmless if
  ## the process has already exited (ESRCH is ignored).
  if pid <= 0:
    return
  when defined(posix):
    discard posix.kill(posix.Pid(-pid), posix.SIGKILL)
  else:
    discard

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
    "workspace": {
      "applyEdit": true,
      "workspaceFolders": true,
      "configuration": true,
      "didChangeConfiguration": {"dynamicRegistration": true},
    },
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

proc buildApplyEditResponse*(
    reqIdJson: string, applied: bool, failureReason: string
): JsonNode =
  ## Build the JSON-RPC response to a server-initiated workspace/applyEdit.
  ## `reqIdJson` is the server's id serialized as JSON (`$reqId`): parse it back
  ## so both integer (`7`) and string (`"abc"`) ids round-trip with their
  ## original type. A `failureReason` is only attached when the edit was refused.
  var idNode: JsonNode
  try:
    idNode = parseJson(reqIdJson)
  except CatchableError:
    idNode = newJNull()
  var resultObj = %*{"applied": applied}
  if not applied and failureReason.len > 0:
    resultObj["failureReason"] = %failureReason
  %*{"jsonrpc": "2.0", "id": idNode, "result": resultObj}

proc lookupSettingsSection*(settings: JsonNode, section: string): JsonNode =
  if section.len == 0:
    return settings
  if not settings.isNil and settings.kind == JObject and settings.hasKey(section):
    return settings[section]
  let keys = section.split('.')
  var current = settings
  for key in keys:
    if current.isNil or current.kind != JObject or not current.hasKey(key):
      return newJNull()
    current = current[key]
  return current

proc buildWorkspaceConfigurationResponse*(
    params: JsonNode, settings: JsonNode
): JsonNode =
  result = newJArray()
  let reqItems = params{"items"}
  if not reqItems.isNil and reqItems.kind == JArray:
    for item in reqItems:
      let section = item{"section"}
      if not section.isNil and section.kind == JString:
        result.add(lookupSettingsSection(settings, section.getStr))
      else:
        result.add(settings)

proc dropPendingDidOpen*(pending: var seq[LspCommand], uri: string) =
  ## Remove any queued lcmdDidOpen for `uri` from `pending`. Used when a
  ## didClose arrives before the server reaches lwsRunning so the flush
  ## doesn't emit a didOpen for an already-closed buffer.
  var i = 0
  while i < pending.len:
    if pending[i].openUri == uri:
      pending.delete(i)
    else:
      inc i

proc formatRawJsonLogLine*(
    languageId: string, direction: LspJsonDirection, json: string
): string =
  ## Build a one-line debug-log entry for a raw JSON-RPC frame. `json` is the
  ## already-serialized (compact) payload, kept on a single greppable line and
  ## tagged with the server's language id and a direction marker
  ## (`>>>` sent / `<<<` received).
  let arrow = if direction == ljdSent: ">>>" else: "<<<"
  languageId & " " & arrow & " " & json

proc extractErrorMessage*(errorNode: JsonNode, fallback = "Unknown error"): string =
  ## Non-conformant servers occasionally send a non-object `error`; the `[]`
  ## operator would assert-crash the worker, so route everything through here.
  if errorNode.isNil or errorNode.kind != JObject:
    return fallback
  errorNode{"message"}.getStr(fallback)

proc notificationToEvents*(meth: string, params: JsonNode): LspEvent =
  ## Convert a server notification (method + params) into the LspEvent to
  ## enqueue. Pure - no I/O, no queue access, no raising. Malformed frames
  ## (missing or wrong-typed fields) resolve to a warning levLogMessage so a
  ## bad frame never unwinds the caller and drops adjacent frames from the
  ## same drain.
  case meth
  of "textDocument/publishDiagnostics":
    let uri = params.getOrDefault("uri").getStr
    if uri.len == 0:
      return LspEvent(
        kind: levLogMessage,
        msgType: mtWarning,
        message: "publishDiagnostics missing/invalid uri; dropping frame",
      )
    # Serialize the raw diagnostics array; the main thread parses it
    # (Diagnostic carries JsonNode fields that must not cross threads)
    let diagsJson =
      if params.hasKey("diagnostics"):
        $params["diagnostics"]
      else:
        "[]"
    # PublishDiagnosticsParams.version is optional; accept only well-formed int.
    let version =
      if params.hasKey("version") and params["version"].kind == JInt:
        some(params["version"].getInt)
      else:
        none(int)
    return LspEvent(
      kind: levDiagnostics,
      diagUri: uri,
      diagnosticsJson: diagsJson,
      diagVersion: version,
    )
  of "window/logMessage":
    return LspEvent(
      kind: levLogMessage,
      msgType:
        toEnumOr[MessageType](params.getOrDefault("type").getInt(mtLog.ord), mtLog),
      message: params.getOrDefault("message").getStr,
    )
  of "window/showMessage":
    return LspEvent(
      kind: levShowMessage,
      msgType:
        toEnumOr[MessageType](params.getOrDefault("type").getInt(mtLog.ord), mtLog),
      message: params.getOrDefault("message").getStr,
    )
  of "$/logTrace":
    var message = params.getOrDefault("message").getStr
    let verbose = params.getOrDefault("verbose").getStr
    if verbose.len > 0:
      message &= "\n" & verbose
    return LspEvent(kind: levLogMessage, msgType: mtInfo, message: message)
  of "$/progress":
    try:
      let progressParams = parseWorkDoneProgressParams(params)
      return LspEvent(
        kind: levProgress,
        progressToken: getProgressToken(progressParams),
        progress: progressParams.value,
      )
    except CatchableError as e:
      return LspEvent(
        kind: levLogMessage,
        msgType: mtWarning,
        message: "Failed to parse $/progress: " & e.msg,
      )
  of "experimental/serverStatus":
    # rust-analyzer style status notification
    try:
      let health =
        case params.getOrDefault("health").getStr
        of "warning": shWarning
        of "error": shError
        else: shOk
      let quiescent = params.getOrDefault("quiescent").getBool(true)
      let msgNode = params.getOrDefault("message")
      let message =
        if not msgNode.isNil and msgNode.kind == JString:
          some(msgNode.getStr)
        else:
          none(string)
      return LspEvent(
        kind: levStatusUpdate,
        statusHealth: health,
        statusQuiescent: quiescent,
        statusMessage: message,
      )
    except CatchableError as e:
      return LspEvent(
        kind: levLogMessage,
        msgType: mtWarning,
        message: "Failed to parse experimental/serverStatus: " & e.msg,
      )
  of "extension/statusUpdate":
    # nimlangserver style status notification
    try:
      let projectErrors = params.getOrDefault("projectErrors")
      let hasErrors =
        not projectErrors.isNil and projectErrors.kind == JArray and
        projectErrors.len > 0
      let health = if hasErrors: shWarning else: shOk
      let pending = params.getOrDefault("pendingRequests")
      let quiescent =
        if not pending.isNil and pending.kind == JArray:
          pending.len == 0
        else:
          true
      var message = none(string)
      if hasErrors:
        for err in projectErrors:
          if err.kind == JString:
            message = some(err.getStr)
            break
      return LspEvent(
        kind: levStatusUpdate,
        statusHealth: health,
        statusQuiescent: quiescent,
        statusMessage: message,
      )
    except CatchableError as e:
      return LspEvent(
        kind: levLogMessage,
        msgType: mtWarning,
        message: "Failed to parse extension/statusUpdate: " & e.msg,
      )
  else:
    return LspEvent(
      kind: levLogMessage, msgType: mtInfo, message: "Unknown LSP notification: " & meth
    )

# Worker thread main loop
proc workerThreadProc(ctx: LspWorkerContext) {.thread.} =
  var
    serverProcess: AsyncProcessRef = nil
    serverStreams: Streams = nil
    outputFuture: Future[JsonRpcResponseResult] = nil
    # Drains the server's stderr pipe so it never blocks the child and its
    # output never corrupts the JSON-RPC stdout stream
    stderrDrainFut: Future[void] = nil
    # Steady-state stdout drain. readPump keeps one read outstanding at all
    # times and parks frames here for mainLoop to dispatch, so a blocked write
    # in the command path can never stall reads and deadlock both pipes (the
    # stdout analog of stderrDrainFut). Started after the init handshake.
    readPumpFut: Future[void] = nil
    inboundFrames = initDeque[JsonNode]()
    readPumpStopped = false # set by readPump when stdout closed/errored
    readPumpOverflow = false # set by readPump when inboundFrames hit the cap
    readPumpError = "" # last stdout read error, surfaced as a crash event
    lastId = 0
    # Bumped on every (re)start of the server process. A deferred
    # workspace/applyEdit response is tagged with the generation that issued it
    # and dropped if the generation has moved on — i.e. the server crashed and
    # was replaced on this same thread, so the old request id means nothing to
    # the new process.
    serverGeneration = 0
    # Pending document notifications to send after initialization
    pendingDidOpen: seq[LspCommand] = @[]
    # Map LSP request ID to (our request ID, timestamp) for response tracking
    pendingRequests: Table[int, tuple[requestId: int, timestamp: Time]]
    # Parsed server settings for workspace/configuration responses
    currentSettings: JsonNode = newJNull()

  proc sendEvent(kind: LspEventKind) =
    var evt = LspEvent(kind: kind)
    ctx.eventQueue[].push(evt)

  proc sendError(msg: string) =
    var evt = LspEvent(kind: levError, errorMsg: msg)
    ctx.eventQueue[].push(evt)

  proc sendLogMessage(msgType: MessageType, msg: string) =
    var evt = LspEvent(kind: levLogMessage, msgType: msgType, message: msg)
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
    # Capture the frame only if a sink wants it: the in-memory :lspLog viewer
    # (any non-off trace level) or the debug log file (-d). Both sinks live on
    # the main thread, so just serialize compactly and hand the frame off via
    # the event queue; processEvent decides routing (the viewer re-prettifies,
    # the file logs the line as-is).
    if ctx.traceLevel == traceOff and not ctx.debugLog:
      return
    var evt = LspEvent(kind: levRawJson, jsonDirection: direction, rawJson: $node)
    ctx.eventQueue[].push(evt)

  proc sendRawJsonStr(direction: LspJsonDirection, frame: string) =
    ## Like sendRawJson but for an already-serialized frame string.
    if ctx.traceLevel == traceOff and not ctx.debugLog:
      return
    ctx.eventQueue[].push(
      LspEvent(kind: levRawJson, jsonDirection: direction, rawJson: frame)
    )

  proc sendDynamicRegister(paramsJson: string) =
    var evt = LspEvent(kind: levDynamicRegister, registrationsJson: paramsJson)
    ctx.eventQueue[].push(evt)

  proc sendDynamicUnregister(paramsJson: string) =
    var evt = LspEvent(kind: levDynamicUnregister, unregistrationsJson: paramsJson)
    ctx.eventQueue[].push(evt)

  proc sendShowMessage(msgType: MessageType, msg: string) =
    var evt = LspEvent(kind: levShowMessage, msgType: msgType, message: msg)
    ctx.eventQueue[].push(evt)

  proc sendApplyEdit(reqIdJson, editJson: string) =
    var evt = LspEvent(
      kind: levApplyEdit,
      applyEditReqIdJson: reqIdJson,
      applyEditEditJson: editJson,
      applyEditGeneration: serverGeneration,
    )
    ctx.eventQueue[].push(evt)

  proc handleServerRequest(
      meth: string, reqId: JsonNode, params: JsonNode
  ): Future[Option[JsonNode]] {.async.} =
    ## Handle server-initiated requests. Returns the response to send, or
    ## `none` when the response is deferred — workspace/applyEdit is answered
    ## later, once the main thread has applied the edit, via
    ## lcmdApplyEditResponse.
    case meth
    of "window/workDoneProgress/create":
      # Accept the progress token creation (respond with null/empty result)
      return some(%*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()})
    of "client/registerCapability":
      # Dynamic capability registration. Validate here so a malformed
      # request is rejected to the server; the main thread re-parses the
      # serialized params when it processes the event.
      try:
        discard parseRegistrationParams(params)
        sendDynamicRegister($params)
        return some(%*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()})
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse registerCapability: " & e.msg)
        return some(
          %*{
            "jsonrpc": "2.0",
            "id": reqId,
            "error": {"code": -32602, "message": "Invalid params: " & e.msg},
          }
        )
    of "client/unregisterCapability":
      # Dynamic capability unregistration (validated as above)
      try:
        discard parseUnregistrationParams(params)
        sendDynamicUnregister($params)
        return some(%*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()})
      except CatchableError as e:
        sendLogMessage(mtWarning, "Failed to parse unregisterCapability: " & e.msg)
        return some(
          %*{
            "jsonrpc": "2.0",
            "id": reqId,
            "error": {"code": -32602, "message": "Invalid params: " & e.msg},
          }
        )
    of "workspace/applyEdit":
      # Servers (e.g. rust-analyzer) push edits from executeCommand-based
      # refactors through this request and block on the
      # ApplyWorkspaceEditResponse. The edit must be applied on the main thread
      # (it mutates TextBuffers), so forward the `edit` and defer the response;
      # the main thread answers via lcmdApplyEditResponse once it is applied.
      #
      # `params{"edit"}` is nil-safe: it returns nil when params is not a JObject
      # (e.g. a non-conforming `"params": null`, which would otherwise crash the
      # worker thread on `hasKey`'s `assert(kind == JObject)`) or when the key is
      # absent. Reject a null edit value too, rather than forwarding a no-op edit
      # the main thread would "apply" and report back as success.
      let editNode = params{"edit"}
      if editNode.isNil or editNode.kind == JNull:
        return some(
          %*{
            "jsonrpc": "2.0",
            "id": reqId,
            "error": {"code": -32602, "message": "applyEdit: missing 'edit' param"},
          }
        )
      sendApplyEdit($reqId, $editNode)
      return none(JsonNode)
    of "window/showMessageRequest":
      # We have no UI to present the action buttons, so surface the message in
      # the LSP log and answer null (= no action selected). That is
      # spec-compliant and far friendlier to the server than -32601. Append the
      # offered action titles to the surfaced text so the user at least sees
      # that the server asked something with choices (we just can't answer it).
      let msgType =
        toEnumOr[MessageType](params.getOrDefault("type").getInt(mtInfo.ord), mtInfo)
      var msg = params.getOrDefault("message").getStr("")
      let actions = params.getOrDefault("actions")
      if not actions.isNil and actions.kind == JArray and actions.len > 0:
        var titles: seq[string] = @[]
        for a in actions:
          let title = a.getOrDefault("title").getStr("")
          if title.len > 0:
            titles.add(title)
        if titles.len > 0:
          msg = msg & " [actions: " & titles.join(", ") & "]"
      sendShowMessage(msgType, msg)
      return some(%*{"jsonrpc": "2.0", "id": reqId, "result": newJNull()})
    of "workspace/configuration":
      return some(
        %*{
          "jsonrpc": "2.0",
          "id": reqId,
          "result": buildWorkspaceConfigurationResponse(params, currentSettings),
        }
      )
    else:
      # Unknown server request - respond with method not found error
      sendLogMessage(mtInfo, "Unknown server request: " & meth)
      return some(
        %*{
          "jsonrpc": "2.0",
          "id": reqId,
          "error": {"code": -32601, "message": "Method not found: " & meth},
        }
      )

  proc handleNotification(meth: string, params: JsonNode) =
    ctx.eventQueue[].push(notificationToEvents(meth, params))

  proc sendRequest(
      meth: string, paramsJson: string
  ): Future[Result[int, string]] {.async.} =
    ## paramsJson is the already-serialized params object. The envelope is built
    ## by splicing it in, avoiding a JsonNode round-trip on the request path.
    if serverStreams.isNil:
      return Result[int, string].err("Server not running")

    lastId.inc
    let frame =
      "{\"jsonrpc\":\"2.0\",\"id\":" & $lastId & ",\"method\":" & escapeJson(meth) &
      ",\"params\":" & paramsJson & "}"
    sendRawJsonStr(ljdSent, frame)
    let sendResult = await serverStreams.input.sendFrame(frame)
    if sendResult.isErr:
      return Result[int, string].err(sendResult.error)
    return Result[int, string].ok(lastId)

  proc sendNotification(
      meth: string, paramsJson: string
  ): Future[Result[void, string]] {.async.} =
    if serverStreams.isNil:
      return Result[void, string].err("Server not running")

    let frame =
      "{\"jsonrpc\":\"2.0\",\"method\":" & escapeJson(meth) & ",\"params\":" & paramsJson &
      "}"
    sendRawJsonStr(ljdSent, frame)
    return await serverStreams.input.sendFrame(frame)

  proc sendNotificationLog(meth: string, paramsJson: string): Future[void] {.async.} =
    ## Send notification and log any errors (non-critical)
    let sendResult = await sendNotification(meth, paramsJson)
    if sendResult.isErr:
      sendLogMessage(mtWarning, "Failed to send " & meth & ": " & sendResult.error)

  let lspWorkingDir = ctx.tempDir

  proc cleanupProcess(): Future[void] {.async.} =
    ## Kill the server process, release its handles, and fail any requests
    ## still waiting on it. Does not change the worker state; callers set
    ## lwsStopped/lwsCrashed as appropriate.
    # Drop the shared pid first so the main-thread shutdown backstop won't also
    # try to kill it. Then SIGKILL the whole process group (reaps grandchildren
    # like nimsuggest that chronos's single-process kill would orphan).
    let pid = if serverProcess != nil: serverProcess.pid else: 0
    ctx.sharedState.storeServerPid(0)
    killServerProcessGroup(pid)
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

    # Stop the stdout read pump before closing its pipe
    if not readPumpFut.isNil and not readPumpFut.finished:
      try:
        await readPumpFut.cancelAndWait()
      except CatchableError:
        discard
    readPumpFut = nil

    if serverProcess != nil:
      # Close process pipe FDs and streams (must be called explicitly)
      try:
        await serverProcess.closeWait()
      except CatchableError:
        discard

    serverProcess = nil
    serverStreams = nil
    outputFuture = nil
    inboundFrames.clear()
    # Fail pending requests instead of leaving the main thread to hit its
    # own response timeout for each of them
    for lspId, (ourId, _) in pendingRequests.pairs:
      sendResponse(ourId, none(JsonNode), some("LSP server stopped"))
    pendingRequests.clear()

  proc readPump() {.async.} =
    ## Continuously drain the server's stdout, parking parsed frames in
    ## inboundFrames for mainLoop to dispatch. Runs as an independent task so a
    ## blocked write in the command path can never stall reads. If reads stall,
    ## the server's stdout pipe fills, the server blocks writing it, then stops
    ## reading its stdin, and our next write blocks too: a two-way deadlock.
    ## Keeping one read always outstanding here breaks that cycle.
    while true:
      # On the first pass adopt the read already armed by the init handshake;
      # afterwards keep exactly one read outstanding.
      let fut =
        if outputFuture != nil:
          outputFuture
        else:
          serverStreams.output.read()
      outputFuture = nil

      var respResult: JsonRpcResponseResult
      try:
        respResult = await fut
      except CancelledError:
        # Cancelled by cleanupProcess; just stop draining.
        break
      except CatchableError as e:
        readPumpError = e.msg
        readPumpStopped = true
        break

      if respResult.isErr:
        # stdout closed or broke: server crashed/exited. mainLoop turns this
        # into the crash/restart path once it has drained queued frames.
        readPumpError = respResult.error
        readPumpStopped = true
        break

      inboundFrames.addLast(respResult.get)
      if inboundFrames.len > MaxInboundFrames:
        readPumpOverflow = true
        readPumpStopped = true
        break

  proc startServer(cmd: LspCommand): Future[void] {.async.} =
    ctx.sharedState.storeState(lwsStarting)
    # New server instance: invalidate any deferred applyEdit response still in
    # flight for the previous one.
    inc serverGeneration
    # Reset read-pump state for the fresh process.
    readPumpStopped = false
    readPumpOverflow = false
    readPumpError = ""
    inboundFrames.clear()

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
    # ProcessGroup makes the server its own process-group leader, so a single
    # kill(-pid) at shutdown/crash reaps any children it spawned (e.g.
    # nimsuggest under nimlangserver) instead of orphaning them.
    let opts: set[AsyncProcessOption] = {UsePath, ProcessGroup}

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

    # Publish the pid so the main thread can SIGKILL the group at shutdown if
    # the worker is wedged in a blocking write and can't process lcmdShutdown.
    ctx.sharedState.storeServerPid(serverProcess.pid)

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
      # Forward the configured trace level verbatim (LSP spec: off/messages/verbose).
      # An off level tells the server not to send $/logTrace at all.
      "trace": $ctx.traceLevel,
    }

    # Forward server-specific initializationOptions (e.g. rust-analyzer lens
    # config). Carried as a serialized string across the thread boundary.
    if cmd.initializationOptions.len > 0:
      try:
        initParams["initializationOptions"] = parseJson(cmd.initializationOptions)
      except JsonParsingError:
        discard

    if cmd.settings.len > 0:
      try:
        currentSettings = parseJson(cmd.settings)
      except JsonParsingError:
        currentSettings = newJNull()
    else:
      currentSettings = newJNull()

    let reqResult = await sendRequest("initialize", $initParams)
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
        let respOpt = await handleServerRequest(meth, reqId, params)
        if respOpt.isSome:
          sendRawJson(ljdSent, respOpt.get)
          discard await serverStreams.input.sendRequest(respOpt.get)
        # else: response deferred (workspace/applyEdit), sent later by the
        # main thread via lcmdApplyEditResponse
        continue

      # Check for error
      if response.hasKey("error"):
        ctx.sharedState.storeState(lwsCrashed)
        sendError("Initialize error: " & extractErrorMessage(response["error"]))
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
    let initedResult = await sendNotification("initialized", "{}")
    if initedResult.isErr:
      ctx.sharedState.storeState(lwsCrashed)
      sendError("Failed to send initialized: " & initedResult.error)
      await cleanupProcess()
      return

    if currentSettings.kind != JNull:
      await sendNotificationLog(
        "workspace/didChangeConfiguration", "{\"settings\":" & $currentSettings & "}"
      )

    ctx.sharedState.storeState(lwsRunning)
    sendEvent(levInitialized)

    # Start the steady-state stdout drain now that the handshake is done. It
    # adopts the read already in flight and must be running before the didOpen
    # flood below (full file bodies) so those writes can't deadlock the pipes.
    readPumpFut = readPump()

    # Send all pending didOpen notifications now that server is running
    for cmd in pendingDidOpen:
      await sendNotificationLog(
        "textDocument/didOpen",
        didOpenParamsJson(cmd.openUri, cmd.openLangId, cmd.openVersion, cmd.openText),
      )
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
        await sendNotificationLog(
          "textDocument/didOpen",
          didOpenParamsJson(cmd.openUri, cmd.openLangId, cmd.openVersion, cmd.openText),
        )
      else:
        let currentState = ctx.sharedState.loadState()
        if currentState == lwsStarting or currentState == lwsStopped:
          # Queue didOpen to send after initialization completes
          # Also handle lwsStopped because lcmdStart may still be pending in queue
          pendingDidOpen.add(cmd)
    of lcmdDidClose:
      if ctx.sharedState.loadState() == lwsRunning:
        let params =
          DidCloseParams(textDocument: TextDocumentIdentifier(uri: cmd.closeUri)).toJson
        await sendNotificationLog("textDocument/didClose", params)
      else:
        dropPendingDidOpen(pendingDidOpen, cmd.closeUri)
    of lcmdDidChange:
      let changeState = ctx.sharedState.loadState()
      if changeState == lwsRunning:
        let params =
          case cmd.changeMode
          of lcdmIncremental:
            # contentChanges was already serialized to JSON by the integration
            # layer; splice it straight into the envelope rather than parsing it
            # back into a JsonNode only to re-serialize it.
            "{\"textDocument\":{\"uri\":" & escapeJson(cmd.changeUri) & ",\"version\":" &
              $cmd.changeVersion & "},\"contentChanges\":" & cmd.changeContentChangesJson &
              "}"
          of lcdmFull:
            DidChangeParams(
              textDocument: VersionedTextDocumentIdentifier(
                uri: cmd.changeUri, version: cmd.changeVersion
              ),
              contentChanges: @[FullContentChange(text: cmd.changeText)],
            ).toJson
        await sendNotificationLog("textDocument/didChange", params)
      elif changeState == lwsStarting or changeState == lwsStopped:
        # Before the server is running, fold the change into the pending didOpen
        # so it opens with the latest content (handle lwsStopped too because
        # lcmdStart may still be queued). Incremental sends only happen after
        # lwsRunning, so an incremental command here has no full text to coalesce
        # and is dropped rather than corrupting the pending didOpen.
        case cmd.changeMode
        of lcdmFull:
          var found = false
          for i in 0 ..< pendingDidOpen.len:
            if pendingDidOpen[i].openUri == cmd.changeUri:
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
            # No pending didOpen for this URI: can't send didChange without one.
            sendLogMessage(
              mtWarning,
              "didChange received for URI without prior didOpen: " & cmd.changeUri,
            )
        of lcdmIncremental:
          sendLogMessage(
            mtWarning,
            "incremental didChange before server running, dropped: " & cmd.changeUri,
          )
      else:
        # lwsCrashed / lwsShuttingDown: no running server to send to and no
        # pending didOpen to coalesce into. Log rather than drop silently. The
        # integration shadow has already advanced, so this relies on re-sync at
        # the next initialize: a crash AFTER a prior successful init fires
        # onServerRestart, which re-opens the buffer and re-seeds the shadow. A
        # crash DURING the first init does NOT (the lang never entered
        # initializedLangs), so that buffer stays unsynced until the file is
        # reopened or the server is restarted manually.
        sendLogMessage(
          mtWarning,
          "didChange dropped; worker not running (" & $changeState & "): " &
            cmd.changeUri,
        )
    of lcmdDidSave:
      if ctx.sharedState.loadState() == lwsRunning:
        var params = "{\"textDocument\":{\"uri\":" & escapeJson(cmd.saveUri) & "}"
        if cmd.saveText.isSome:
          params &= ",\"text\":" & escapeJson(cmd.saveText.get)
        params &= "}"
        await sendNotificationLog("textDocument/didSave", params)
    of lcmdRequest:
      if ctx.sharedState.loadState() == lwsRunning:
        # reqParamsJson was serialized by the integration layer; pass it through
        # to be spliced into the envelope without a JsonNode round-trip.
        let lspIdResult = await sendRequest(cmd.reqMethod, cmd.reqParamsJson)
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
        await sendNotificationLog(cmd.notifyMethod, cmd.notifyParamsJson)
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
          await sendNotificationLog("$/cancelRequest", "{\"id\":" & $lspId & "}")
    of lcmdApplyEditResponse:
      # Deliver the deferred response to a server-initiated workspace/applyEdit.
      # Drop it if the server is gone (no one to answer) or if it crashed and was
      # replaced since the request (generation moved on) — sending the old id to
      # the new process would be protocol garbage it never asked for.
      if ctx.sharedState.loadState() == lwsRunning and not serverStreams.isNil and
          cmd.applyEditGeneration == serverGeneration:
        let resp = buildApplyEditResponse(
          cmd.applyEditReqIdJson, cmd.applyEditApplied, cmd.applyEditFailureReason
        )
        sendRawJson(ljdSent, resp)
        discard await serverStreams.input.sendRequest(resp)

  proc dispatchFrame(response: JsonNode): Future[void] {.async.} =
    ## Dispatch one frame the read pump drained from the server. The pump owns
    ## reading/re-arming; this only routes a parsed frame to its handler.
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

      let respOpt = await handleServerRequest(meth, reqId, params)
      if respOpt.isSome:
        sendRawJson(ljdSent, respOpt.get)
        discard await serverStreams.input.sendRequest(respOpt.get)
      # else: response deferred (workspace/applyEdit), sent later by the main
      # thread via lcmdApplyEditResponse
      return

    # Check if this is a response (has "id", no "method")
    if response.hasKey("id") and not response.hasKey("method"):
      # JSON-RPC 2.0 allows id to be Number, String, or null. moe emits integer
      # ids, but accept string ids from lenient servers to keep correlation.
      let idNode = response["id"]
      var lspId: int
      case idNode.kind
      of JInt:
        lspId = idNode.getInt
      of JString:
        try:
          lspId = parseInt(idNode.getStr)
        except ValueError:
          sendLogMessage(
            mtWarning,
            "Dropped LSP response with non-numeric string id: " & idNode.getStr,
          )
          return
      else:
        let errText =
          if response.hasKey("error"):
            extractErrorMessage(response["error"], "unknown error")
          else:
            "no error field"
        sendLogMessage(
          mtWarning,
          "Dropped LSP response with unhandled id kind (" & $idNode.kind & "): " &
            errText,
        )
        return

      if lspId in pendingRequests:
        let (ourId, _) = pendingRequests[lspId]
        pendingRequests.del(lspId)

        # Check for error
        if response.hasKey("error"):
          sendResponse(
            ourId, none(JsonNode), some(extractErrorMessage(response["error"]))
          )
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

      # Dispatch every frame the read pump has drained from the server. The
      # pump keeps reading independently, so this never blocks on the wire; it
      # just routes already-received frames. Drain fully each wakeup so
      # diagnostics/progress floods don't lag.
      if ctx.sharedState.loadState() == lwsRunning:
        try:
          while inboundFrames.len > 0:
            await dispatchFrame(inboundFrames.popFirst())
        except CatchableError as e:
          sendError("Message processing error: " & e.msg)
          # Don't crash the worker, continue processing

        # The pump stopped: stdout closed (crash/exit) or the inbound queue
        # overflowed (runaway server). Surface it as a crash so the service
        # restarts, after the queued frames above have been dispatched.
        if readPumpStopped:
          ctx.sharedState.storeState(lwsCrashed)
          if readPumpOverflow:
            sendError(
              "LSP server inbound queue overflow (>" & $MaxInboundFrames &
                " frames); treating as crashed"
            )
          else:
            sendError("LSP server connection lost: " & readPumpError)
          await cleanupProcess()

      # Check for timed out requests
      if pendingRequests.len > 0:
        checkRequestTimeouts()

      # Wait for signal from main thread or timeout. The timeout also bounds how
      # long pump-queued frames sit before the next drain above.
      try:
        if ctx.sharedState.loadState() == lwsRunning:
          # When server is running, use short timeout to drain LSP messages
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

proc newLspWorker*(
    languageId: string, traceLevel: LspTrace = traceOff
): Result[LspWorker, string] =
  ## Create a new LSP worker. Returns error if signal creation fails.
  ## traceLevel is forwarded to `initialize` and gates per-frame levRawJson
  ## events (any non-off level enables them).
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
      traceLevel: traceLevel,
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
    traceLevel: worker.traceLevel,
    # Read once here on the main thread; the worker only emits events, the
    # actual file write happens in processEvent (also on the main thread).
    debugLog: getGlobalLogger().isEnabled,
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
    # The worker may be wedged in a blocking write to a server that has stopped
    # reading its stdin (pipe-full deadlock), so it would never observe the
    # queued lcmdShutdown and joinThread would block forever. Killing the
    # server's process group from here closes the pipes, which fails that write
    # and lets the worker reach the shutdown path. Harmless if already gone, or
    # if the read pump already cleared the pid on a clean stop.
    let pid = worker.sharedState.serverPid.load(moAcquire)
    if pid > 0:
      killServerProcessGroup(pid)

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
    settings: string = "",
) =
  let cmd = LspCommand(
    kind: lcmdStart,
    languageId: worker.languageId,
    command: command,
    args: args,
    workspaceRoot: workspaceRoot,
    initializationOptions: initializationOptions,
    settings: settings,
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

proc didChangeFull*(worker: LspWorker, uri: string, version: int, text: string) =
  ## Queue a full-document didChange (contentChanges = [{text}]).
  let cmd = LspCommand(
    kind: lcmdDidChange,
    changeUri: uri,
    changeVersion: version,
    changeMode: lcdmFull,
    changeText: text,
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc didChangeIncremental*(
    worker: LspWorker, uri: string, version: int, contentChangesJson: string
) =
  ## Queue an incremental didChange carrying a serialized contentChanges array.
  let cmd = LspCommand(
    kind: lcmdDidChange,
    changeUri: uri,
    changeVersion: version,
    changeMode: lcdmIncremental,
    changeContentChangesJson: contentChangesJson,
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

proc hasPendingCommands*(worker: LspWorker): bool =
  ## True if the command queue has commands waiting to be processed
  ## (thread-safe). Intended for tests that need to confirm a queued command
  ## was dequeued before asserting on the worker's subsequent behavior.
  withLock(worker.commandQueue.lock):
    result = worker.commandQueue.queue.len > 0

proc isThreadAlive*(worker: LspWorker): bool =
  ## Check if the worker thread itself is still running its main loop
  ## (thread-safe). The server process state is independent: a worker whose
  ## server crashed (lwsCrashed) keeps its thread alive and can be asked to
  ## start a new server without re-creating the thread.
  worker.threadStarted and not worker.stopped and
    worker.sharedState.running.load(moAcquire)

proc sendRequest*(worker: LspWorker, requestId: int, meth: string, paramsJson: string) =
  ## Send a request to the LSP server with a caller-provided request ID.
  ## Use pollEvents to get the response with matching requestId.
  ## The caller is responsible for ID uniqueness; LspService allocates IDs
  ## from a single counter shared by all workers so responses from different
  ## language servers can never collide in its tracking tables.
  ## `paramsJson` is the already-serialized params object: only strings cross
  ## the thread boundary (no JsonNode ref under non-atomic ORC refcounts), and
  ## the worker splices it into the request envelope without re-parsing.
  let cmd = LspCommand(
    kind: lcmdRequest, requestId: requestId, reqMethod: meth, reqParamsJson: paramsJson
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc sendRequest*(worker: LspWorker, meth: string, paramsJson: string): int =
  ## Send a request to the LSP server and return the request ID
  ## Use pollEvents to get the response with matching requestId
  ## Note: IDs from this worker-local counter are only unique within this
  ## worker; cross-worker callers should allocate IDs themselves and use the
  ## explicit-ID overload.
  result = worker.nextRequestId
  worker.nextRequestId.inc
  worker.sendRequest(result, meth, paramsJson)

proc sendNotification*(worker: LspWorker, meth: string, paramsJson: string) =
  ## Send a notification to the LSP server (no response expected).
  ## `paramsJson` is the already-serialized params object (see sendRequest).
  let cmd =
    LspCommand(kind: lcmdNotification, notifyMethod: meth, notifyParamsJson: paramsJson)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc cancelRequest*(worker: LspWorker, requestId: int) =
  ## Cancel a previously sent request identified by its tracking ID. The
  ## worker resolves the tracking ID to the server's JSON-RPC ID and sends
  ## $/cancelRequest; a plain notification cannot do this because the caller
  ## does not know the server-facing ID.
  let cmd = LspCommand(kind: lcmdCancel, cancelRequestId: requestId)
  worker.commandQueue.pushAndSignal(cmd, worker.signal)

proc sendApplyEditResponse*(
    worker: LspWorker,
    reqIdJson: string,
    applied: bool,
    failureReason: string = "",
    generation: int = 0,
) =
  ## Answer a server-initiated workspace/applyEdit. `reqIdJson` is the
  ## serialized JSON-RPC id captured from the levApplyEdit event; the worker
  ## turns it back into the response the server is blocking on. `generation` is
  ## the levApplyEdit's `applyEditGeneration`: the worker drops the response if
  ## the server was replaced since the request was issued.
  let cmd = LspCommand(
    kind: lcmdApplyEditResponse,
    applyEditReqIdJson: reqIdJson,
    applyEditApplied: applied,
    applyEditFailureReason: failureReason,
    applyEditGeneration: generation,
  )
  worker.commandQueue.pushAndSignal(cmd, worker.signal)
