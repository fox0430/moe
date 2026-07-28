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

import std/[algorithm, tables, sets, options, os, strutils, json, times, uri]

import pkg/[results, chronos, jsony]

import lsp/worker
import lsp/protocol/types
import logger

export worker, types

const
  DefaultRequestTimeoutMs* = RequestTimeoutSec * 1000
    ## Matches worker's RequestTimeoutSec; a shorter default would drop
    ## responses that arrive between the two deadlines (see recordResponse).
  PollIntervalMs = 5 ## Polling interval for async response waiting
  RestartSuppressionSec* = 5.0
    ## Minimum interval between automatic server restarts per language.
    ## Prevents a crash-looping server from being respawned on every
    ## request that funnels through getOrStartWorker.

type
  LanguageServerConfig* = object ## Configuration for a language server
    command*: string
    args*: seq[string]
    extensions*: seq[string]
    enabled*: bool
    traceLevel*: LspTrace
      ## LSP trace level; forwarded to `initialize` and
      ## gates raw JSON-RPC events (any non-off level enables them).
    initializationOptions*: string
      ## Serialized JSON for the server's `initializationOptions` ("" = none).
      ## Stored as a string because JsonNode refs cannot cross the worker
      ## thread boundary under --mm:orc.
    settings*: string
      ## Serialized JSON for workspace/didChangeConfiguration and
      ## workspace/configuration responses ("" = none).

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

  ApplyWorkspaceEditResult* = tuple[applied: bool, failureReason: Option[string]]
    ## Outcome of applying a server-initiated workspace/applyEdit on the main
    ## thread, reported back to the worker so it can answer the blocking server.

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
    extToLangId: Table[string, string] # lowercase ext -> langId (reverse index)
    capabilities: Table[string, ServerCapabilities] # languageId -> capabilities
    serverInfo: Table[string, tuple[name: string, version: Option[string]]]
      # languageId -> server info
    # Dynamic registrations: languageId -> (registrationId -> Registration)
    dynamicRegistrations: Table[string, Table[string, Registration]]
    workspaceRoot: string
    enabled*: bool
    # Consumer-side per-request timeout (ms), from `config.lsp.timeout`.
    # Setting this below worker's RequestTimeoutSec drops late replies
    # (recordResponse discards ids no longer in activeRequests).
    requestTimeoutMs*: int
    # Pending request responses (requestId -> response).
    # The result is kept as the raw JSON string exactly as it crossed the
    # worker thread boundary; it is parsed lazily by the consumer (parseJson for
    # the JsonNode-based getters, jsony fromJson for the typed ones). This avoids
    # eagerly building a JsonNode tree for large payloads (e.g. completion lists)
    # that a typed consumer would rather parse directly.
    pendingResponses: Table[int, tuple[result: Option[string], error: Option[string]]]
    # Active pending requests for timeout tracking
    activeRequests*: Table[int, LspPendingRequest]
    # Single request-ID counter shared by all workers. Both tables above are
    # keyed by the bare ID, so letting each worker allocate its own IDs
    # (starting at 1) would collide as soon as two language servers run
    # concurrently and responses could be attributed to the wrong request.
    nextRequestId: int
    # Last automatic restart attempt per language (epochTime), for
    # crash-loop suppression
    lastRestartTimes: Table[string, float]
    # Languages whose worker has completed `initialize` at least once. A second
    # (or later) initialization for a language means the server (re)started
    # after a crash, so the open documents it knew about were lost and must be
    # re-opened. stopWorker clears the entry so an explicit restart, which
    # re-opens buffers itself, is not double-counted as a crash recovery.
    initializedLangs: HashSet[string]
    # Global callbacks (forwarded from individual workers)
    onDiagnosticsUpdate*:
      proc(uri: string, diagnostics: seq[Diagnostic], version: Option[int]) {.gcsafe.}
    onLogMessage*:
      proc(langId: string, msgType: MessageType, message: string) {.gcsafe.}
    onProgress*:
      proc(langId: string, token: string, progress: WorkDoneProgress) {.gcsafe.}
    onStatusUpdate*: proc(
      langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
    ) {.gcsafe.}
    # Invoked when a language server re-initializes after a crash. The editor
    # uses this to re-send didOpen for every open buffer of that language, since
    # the restarted server starts with no open documents (see initializedLangs).
    onServerRestart*: proc(langId: string) {.gcsafe.}
    # Apply a server-initiated workspace/applyEdit on the main thread (it
    # mutates buffers). Returns whether the edit was applied so the worker can
    # answer the server's blocking request.
    onApplyWorkspaceEdit*:
      proc(edit: WorkspaceEdit): ApplyWorkspaceEditResult {.gcsafe.}
    # Test seam: when set, overrides hasLiveWorkerForPath so the document-sync
    # tests can exercise the "a worker would receive this" path without spawning
    # a real server. nil in production.
    liveWorkerOverride*: proc(path: string): bool {.gcsafe.}
    # Test seam: when set, overrides isWorkerRunningForPath. Falls back to
    # liveWorkerOverride when nil so existing tests that only set the latter
    # still treat the fake worker as running. nil in production.
    runningWorkerOverride*: proc(path: string): bool {.gcsafe.}
    # Test seam: when set, overrides liveWorkerLangIds so tests can exercise
    # the "config changed for a running worker" branch without spawning a real
    # server. nil in production.
    liveWorkerLangIdsOverride*: proc(): seq[string] {.gcsafe.}

proc defaultLanguageServerConfigs*(): Table[string, LanguageServerConfig] =
  ## Built-in default LSP server registrations.
  ## Extracted so `applyLspServerConfigs` can rebuild the config table from
  ## scratch on live reload, letting removed [Lsp.<lang>] user sections revert
  ## to defaults instead of leaving stale overrides in place.
  result = initTable[string, LanguageServerConfig]()

  result["nim"] = LanguageServerConfig(
    command: "nimlangserver",
    args: @[],
    extensions: @["nim", "nims", "nimble"],
    enabled: true,
  )

  result["rust"] = LanguageServerConfig(
    command: "rust-analyzer", args: @[], extensions: @["rs"], enabled: true
  )

  result["python"] = LanguageServerConfig(
    command: "pylsp", args: @[], extensions: @["py", "pyw"], enabled: true
  )

  result["typescript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["ts", "tsx"],
    enabled: true,
  )

  result["javascript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["js", "jsx", "mjs"],
    enabled: true,
  )

  result["lua"] = LanguageServerConfig(
    command: "lua-language-server",
    args: @[],
    extensions: @["lua", "luau", "rockspec"],
    enabled: true,
  )

  result["go"] = LanguageServerConfig(
    command: "gopls", args: @[], extensions: @["go"], enabled: true
  )

  result["c"] = LanguageServerConfig(
    command: "clangd", args: @[], extensions: @["c", "h"], enabled: true
  )

  result["cpp"] = LanguageServerConfig(
    command: "clangd",
    args: @[],
    extensions: @["cpp", "hpp", "cc", "hh", "cxx", "hxx"],
    enabled: true,
  )

proc rebuildExtIndex(svc: LspService) =
  ## On duplicate extensions the alphabetically-first langId wins for stability.
  svc.extToLangId.clear()
  var langIds: seq[string]
  for langId in svc.configs.keys:
    langIds.add(langId)
  langIds.sort()
  for langId in langIds:
    let config = svc.configs[langId]
    if not config.enabled:
      continue
    for ext in config.extensions:
      let key = ext.toLowerAscii()
      if key.len == 0:
        continue
      if key in svc.extToLangId:
        logWarn(
          "lsp",
          "duplicate extension '." & key & "' registered for '" & langId & "'; keeping '" &
            svc.extToLangId[key] & "'",
        )
        continue
      svc.extToLangId[key] = langId

proc newLspService*(workspaceRoot: string = ""): LspService =
  ## Create a new LSP service
  result = LspService(
    workers: initTable[string, LspWorker](),
    configs: initTable[string, LanguageServerConfig](),
    extToLangId: initTable[string, string](),
    capabilities: initTable[string, ServerCapabilities](),
    serverInfo: initTable[string, tuple[name: string, version: Option[string]]](),
    dynamicRegistrations: initTable[string, Table[string, Registration]](),
    workspaceRoot:
      if workspaceRoot.len > 0:
        workspaceRoot
      else:
        getCurrentDir(),
    enabled: true,
    requestTimeoutMs: DefaultRequestTimeoutMs,
    pendingResponses:
      initTable[int, tuple[result: Option[string], error: Option[string]]](),
    activeRequests: initTable[int, LspPendingRequest](),
    nextRequestId: 1,
    lastRestartTimes: initTable[string, float](),
    initializedLangs: initHashSet[string](),
    # Default no-op callbacks to avoid nil checks throughout the code
    onDiagnosticsUpdate: proc(
        uri: string, diagnostics: seq[Diagnostic], version: Option[int]
    ) {.gcsafe.} =
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
    onServerRestart: proc(langId: string) {.gcsafe.} =
      discard,
    onApplyWorkspaceEdit: proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      (applied: false, failureReason: some("applyEdit not handled")),
  )

  result.configs = defaultLanguageServerConfigs()
  result.rebuildExtIndex()

proc resetConfigsToDefaults*(svc: LspService) =
  ## Replace the configs table with a fresh copy of the built-in defaults.
  ## Used by live reload so removed [Lsp.<lang>] sections and cleared fields
  ## revert to defaults instead of retaining stale merged state.
  ## Already-running workers keep their old command until they restart.
  svc.configs = defaultLanguageServerConfigs()
  svc.rebuildExtIndex()

proc setRequestTimeout*(svc: LspService, timeoutMs: int) =
  ## Set the per-request timeout (ms). Non-positive values are ignored.
  if timeoutMs > 0:
    svc.requestTimeoutMs = timeoutMs

proc setConfig*(svc: LspService, langId: string, config: LanguageServerConfig) =
  ## Set configuration for a language server
  svc.configs[langId] = config
  svc.rebuildExtIndex()

proc getConfig*(svc: LspService, langId: string): Option[LanguageServerConfig] =
  ## Get configuration for a language server
  if langId in svc.configs:
    return some(svc.configs[langId])
  return none(LanguageServerConfig)

proc liveWorkerLangIds*(svc: LspService): seq[string] =
  ## Language IDs whose worker is running or starting.
  if svc.liveWorkerLangIdsOverride != nil:
    return svc.liveWorkerLangIdsOverride()
  for langId, worker in svc.workers:
    if worker.isRunning or worker.isStarting:
      result.add(langId)

proc getLanguageIdFromPath*(svc: LspService, path: string): Option[string] =
  ## Determine language ID from file path extension
  let ext = path.splitFile().ext.strip(chars = {'.'}).toLowerAscii()
  if ext.len == 0:
    return none(string)
  if ext in svc.extToLangId:
    return some(svc.extToLangId[ext])
  return none(string)

proc getLanguageIdFromExtension*(svc: LspService, ext: string): Option[string] =
  ## Determine language ID from file extension
  let cleanExt = ext.strip(chars = {'.'}).toLowerAscii()
  if cleanExt in svc.extToLangId:
    return some(svc.extToLangId[cleanExt])
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
  ## Start a worker for a language (or return existing one). If the
  ## language's server crashed or stopped, attempt a rate-limited restart.
  if not svc.enabled:
    return err("LSP service is disabled")

  # Get config
  if langId notin svc.configs:
    return err("No LSP configuration for language: " & langId)

  let config = svc.configs[langId]
  if not config.enabled:
    return err("LSP disabled for language: " & langId)

  if langId in svc.workers:
    let worker = svc.workers[langId]
    if worker.state != lwsCrashed:
      # Running, starting, or the lcmdStart is still queued (lwsStopped
      # right after creation) — return the existing worker. Only a crashed
      # server warrants a restart; re-sending lcmdStart in other states
      # would spawn a duplicate server process.
      return ok(worker)

    # The server crashed. Restart it, rate-limited so a crash-looping
    # server isn't respawned by every request.
    let now = epochTime()
    if now - svc.lastRestartTimes.getOrDefault(langId, 0.0) < RestartSuppressionSec:
      return err("LSP server for " & langId & " crashed recently; restart suppressed")
    svc.lastRestartTimes[langId] = now

    # Drop the crashed server's stale capabilities so documentSyncKind is
    # conservatively Full during the restart window. Otherwise a didChange sent
    # before the new server re-initializes could be a ranged (incremental) change
    # for a document the fresh server has not yet been told about. initializedLangs
    # is intentionally kept so the next initialize is recognized as a restart and
    # onServerRestart re-opens the buffers.
    svc.capabilities.del(langId)
    svc.serverInfo.del(langId)
    svc.dynamicRegistrations.del(langId)

    if worker.isThreadAlive:
      # The worker thread survived (only the server process died); ask it to
      # spawn a new server on the same thread.
      worker.startServer(
        config.command, config.args, svc.workspaceRoot, config.initializationOptions,
        config.settings,
      )
      svc.onLogMessage(langId, mtInfo, "Restarting language server: " & config.command)
      return ok(worker)

    # The thread itself died (fatal error): join it and fall through to
    # create a fresh worker.
    worker.stop()
    svc.workers.del(langId)

  # Create new worker
  let workerResult = newLspWorker(langId, config.traceLevel)
  if workerResult.isErr:
    return err("Failed to create worker: " & workerResult.error)
  let worker = workerResult.get

  # Start worker thread
  worker.start()

  # Start the LSP server
  worker.startServer(
    config.command, config.args, svc.workspaceRoot, config.initializationOptions,
    config.settings,
  )

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

proc workerForExistingPath(svc: LspService, path: string): Option[LspWorker] =
  ## Resolve the already running/starting worker for `path` WITHOUT starting one
  ## (unlike getWorkerForPath). Shared by the notifyDocument* notifications and
  ## hasLiveWorkerForPath so they agree on what "deliverable" means.
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return none(LspWorker)
  svc.getWorker(langIdOpt.get)

proc hasLiveWorkerForPath*(svc: LspService, path: string): bool =
  ## Whether a notification for `path` would actually be handed to a worker.
  ## Mirrors notifyDocument*'s getWorker check: true when the worker is running
  ## (sends now) or starting (coalesces into the pending didOpen); false when
  ## the file has no LSP or the worker is absent/crashed, so a change would be
  ## silently dropped.
  if svc.liveWorkerOverride != nil:
    return svc.liveWorkerOverride(path)
  svc.workerForExistingPath(path).isSome

proc isWorkerRunningForPath*(svc: LspService, path: string): bool =
  ## Whether the worker for `path` is actually running (lwsRunning), as opposed
  ## to merely starting/crashed/stopped. The integration layer uses this to
  ## decide whether incremental didChange can be sent safely: a starting worker
  ## must receive full sync so the change can coalesce into the pending didOpen.
  if svc.runningWorkerOverride != nil:
    return svc.runningWorkerOverride(path)
  if svc.liveWorkerOverride != nil:
    return svc.liveWorkerOverride(path)
  let workerOpt = svc.workerForExistingPath(path)
  if workerOpt.isNone:
    return false
  return workerOpt.get.isRunning

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
  # Forget the initialization so a fresh start is treated as a first init, not
  # a crash recovery. restartLspServer stops then starts and re-opens buffers
  # itself; without this the next initialize would also fire onServerRestart and
  # re-open everything a second time.
  svc.initializedLangs.excl(langId)

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
  svc.initializedLangs.clear()

proc recordResponse*(
    svc: LspService, requestId: int, res: Option[string], error: Option[string]
) =
  ## Store a response for a request that is still awaiting one. Responses
  ## that arrive after the request was already timed out or cancelled (no
  ## activeRequests entry) are dropped: otherwise they would sit in
  ## pendingResponses forever, since cleanupTimedOutRequests and checkResponse
  ## only ever look at requestIds present in activeRequests.
  if requestId in svc.activeRequests:
    svc.pendingResponses[requestId] = (result: res, error: error)

proc processEvent*(svc: LspService, langId: string, evt: LspEvent) =
  ## Process a single worker event on the main thread. JSON payloads cross
  ## the thread boundary as serialized strings (JsonNode refs are unsafe to
  ## share under non-atomic ORC refcounting) and are parsed here, on the
  ## owning thread. Exposed for tests.
  case evt.kind
  of levInitialized:
    svc.onLogMessage(langId, mtInfo, "Language server initialized")
    # A repeat initialization means the server crashed and was restarted: the
    # new process has no open documents, so ask the editor to re-send didOpen
    # for every open buffer of this language. The first initialization is the
    # normal startup path, where the editor already sent didOpen at file-open
    # time (queued in the worker and flushed on initialize).
    if langId in svc.initializedLangs:
      svc.onServerRestart(langId)
    else:
      svc.initializedLangs.incl(langId)
  of levError:
    svc.onLogMessage(langId, mtError, evt.errorMsg)
  of levDiagnostics:
    var diagnostics: seq[Diagnostic] = @[]
    try:
      for d in parseJson(evt.diagnosticsJson):
        diagnostics.add(parseDiagnostic(d))
    except CatchableError as e:
      svc.onLogMessage(langId, mtWarning, "Failed to parse diagnostics: " & e.msg)
      return
    svc.onDiagnosticsUpdate(evt.diagUri, diagnostics, evt.diagVersion)
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
    try:
      svc.capabilities[langId] =
        parseServerCapabilities(parseJson(evt.capabilitiesJson))
    except CatchableError as e:
      svc.onLogMessage(langId, mtWarning, "Failed to parse capabilities: " & e.msg)
  of levResponse:
    # Store the raw result string as-is; parsing is deferred to the consumer
    # (see checkResponse / waitForResponse / *Raw). Malformed JSON therefore
    # surfaces as a parse error at consumption time rather than here.
    svc.recordResponse(evt.requestId, evt.responseResultJson, evt.responseError)
  of levRawJson:
    # Debug log file: one compact line per frame whenever `-d` is on,
    # independent of the per-server verbose setting. logDebug no-ops when the
    # logger is disabled; the isEnabled guard skips building the line then.
    if getGlobalLogger().isEnabled:
      logDebug("lsp", formatRawJsonLogLine(langId, evt.jsonDirection, evt.rawJson))

    # In-memory :lspLog viewer: pretty-printed and timestamped, but only for
    # servers that opted into raw-JSON logging (any non-off trace level).
    if langId in svc.configs and svc.configs[langId].traceLevel != traceOff:
      let timestamp = now().format("HH:mm:ss'.'fff")
      let direction = if evt.jsonDirection == ljdSent: ">>> " else: "<<< "
      let pretty =
        try:
          parseJson(evt.rawJson).pretty
        except CatchableError:
          evt.rawJson
      # Split multi-line JSON into separate log entries
      let lines = pretty.splitLines()
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
    var registrations: seq[Registration]
    try:
      registrations =
        parseRegistrationParams(parseJson(evt.registrationsJson)).registrations
    except CatchableError as e:
      svc.onLogMessage(langId, mtWarning, "Failed to parse registrations: " & e.msg)
      return
    if langId notin svc.dynamicRegistrations:
      svc.dynamicRegistrations[langId] = initTable[string, Registration]()
    for reg in registrations:
      svc.dynamicRegistrations[langId][reg.id] = reg
      svc.onLogMessage(
        langId,
        mtInfo,
        "Dynamic registration: " & reg.`method` & " (id: " & reg.id & ")",
      )
  of levDynamicUnregister:
    # Dynamic capability unregistration
    var unregistrations: seq[Unregistration]
    try:
      unregistrations =
        parseUnregistrationParams(parseJson(evt.unregistrationsJson)).unregisterations
    except CatchableError as e:
      svc.onLogMessage(langId, mtWarning, "Failed to parse unregistrations: " & e.msg)
      return
    if langId in svc.dynamicRegistrations:
      for unreg in unregistrations:
        if unreg.id in svc.dynamicRegistrations[langId]:
          svc.dynamicRegistrations[langId].del(unreg.id)
          svc.onLogMessage(
            langId,
            mtInfo,
            "Dynamic unregistration: " & unreg.`method` & " (id: " & unreg.id & ")",
          )
  of levStatusUpdate:
    svc.onStatusUpdate(langId, evt.statusHealth, evt.statusQuiescent, evt.statusMessage)
  of levApplyEdit:
    # A server-initiated workspace/applyEdit. Apply it on the main thread, then
    # answer the worker so it can unblock the server's request. The server is
    # blocking on the ApplyWorkspaceEditResponse, so EVERY path must answer:
    # both the parse and the apply run inside the try, and any CatchableError
    # becomes a negative response instead of escaping poll() (where it would
    # strand the server and reach emergencySaveAndQuit). A Defect is deliberately
    # NOT caught here: the apply path reports errors via Result rather than
    # raising, so a Defect signals a real bug and stays fatal, as elsewhere.
    var applied = false
    var failureReason = ""
    try:
      let edit = parseWorkspaceEdit(parseJson(evt.applyEditEditJson))
      let res = svc.onApplyWorkspaceEdit(edit)
      applied = res.applied
      failureReason = res.failureReason.get("")
    except CatchableError as e:
      svc.onLogMessage(langId, mtWarning, "Failed to apply applyEdit: " & e.msg)
      failureReason = "applyEdit failed: " & e.msg
    let workerOpt = svc.getWorker(langId)
    if workerOpt.isSome:
      workerOpt.get.sendApplyEditResponse(
        evt.applyEditReqIdJson, applied, failureReason, evt.applyEditGeneration
      )

proc poll*(svc: LspService, timeoutMs: int = 0) =
  ## Poll all workers - process events from worker threads
  ## This is non-blocking - it only processes events that have been queued

  # Skip if no workers
  if svc.workers.len == 0:
    return

  # Snapshot the worker set before processing events. processEvent can re-enter
  # the service — the applyEdit callback runs onBufferChange, which may
  # notifyDocumentOpened -> startWorker and insert/replace entries in
  # svc.workers. Mutating the table while its `pairs` iterator is live raises
  # "the length of the table changed while iterating" (a Defect), so iterate a
  # copy of the (langId, worker) pairs instead.
  var snapshot: seq[(string, LspWorker)] = @[]
  for langId, worker in svc.workers:
    snapshot.add((langId, worker))

  for (langId, worker) in snapshot:
    # Get all pending events from this worker
    for evt in worker.pollEvents():
      svc.processEvent(langId, evt)

# Non-blocking response checking
proc checkResponse*(
    svc: LspService, requestId: int
): tuple[status: LspResponseStatus, result: Option[JsonNode], error: Option[string]] =
  ## Non-blocking check if a response has arrived
  ## Returns (lrsPending, none, none) if not yet received
  ## Returns (lrsSuccess, some(result), none) on success
  ## Returns (lrsError, none, some(error)) on error
  ## Returns (lrsTimeout, none, some("timeout")) if timed out, or if the id is
  ## unknown to the service (already swept by cleanupTimedOutRequests, or
  ## consumed by an earlier checkResponse). Reporting unknown ids as timeout
  ## lets pollers reset their pending state instead of looping on lrsPending.

  # Check if response has arrived
  if requestId in svc.pendingResponses:
    let resp = svc.pendingResponses[requestId]
    svc.pendingResponses.del(requestId)
    svc.activeRequests.del(requestId)

    if resp.error.isSome:
      return (lrsError, none(JsonNode), resp.error)
    elif resp.result.isSome:
      try:
        return (lrsSuccess, some(parseJson(resp.result.get)), none(string))
      except CatchableError as e:
        return (lrsError, none(JsonNode), some("Failed to parse response: " & e.msg))
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

  # Unknown id: treat as timeout so the poller drops its pending state. This
  # is the sweep-then-poll case — cleanupTimedOutRequests already dropped the
  # activeRequests entry, and returning lrsPending here would freeze the
  # feature until an unrelated invalidate (e.g. a buffer edit) cleared the id.
  return (lrsTimeout, none(JsonNode), some("Request timed out"))

proc checkResponseRaw*(
    svc: LspService, requestId: int
): tuple[status: LspResponseStatus, raw: Option[string], error: Option[string]] =
  ## Like checkResponse but returns the unparsed result JSON string, letting a
  ## typed consumer parse it directly (jsony fromJson) without the intermediate
  ## JsonNode. `raw` is none when the server returned no result (or null).
  if requestId in svc.pendingResponses:
    let resp = svc.pendingResponses[requestId]
    svc.pendingResponses.del(requestId)
    svc.activeRequests.del(requestId)

    if resp.error.isSome:
      return (lrsError, none(string), resp.error)
    else:
      return (lrsSuccess, resp.result, none(string))

  if requestId in svc.activeRequests:
    let req = svc.activeRequests[requestId]
    let elapsed = (epochTime() - req.startTime) * 1000.0
    if elapsed > req.timeoutMs.float:
      svc.activeRequests.del(requestId)
      return (lrsTimeout, none(string), some("Request timed out"))
    return (lrsPending, none(string), none(string))

  # Unknown id — see checkResponse for the sweep-then-poll rationale.
  return (lrsTimeout, none(string), some("Request timed out"))

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
    # Ask the worker to cancel. It maps this tracking id to the server's
    # JSON-RPC id before sending $/cancelRequest — sending the tracking id
    # directly (as before) targets the wrong id and never cancels anything.
    if req.langId in svc.workers:
      let worker = svc.workers[req.langId]
      if worker.isRunning:
        worker.cancelRequest(requestId)
    svc.activeRequests.del(requestId)
  svc.pendingResponses.del(requestId)

# Request-response helper (async, non-blocking)
proc waitForResponse*(
    svc: LspService, requestId: int, timeoutMs: int = 0
): Future[Result[JsonNode, string]] {.async: (raises: [CancelledError]).} =
  ## Wait for response asynchronously. timeoutMs <= 0 uses the service default.
  let startTime = epochTime()
  let effectiveMs = if timeoutMs > 0: timeoutMs else: svc.requestTimeoutMs
  let timeoutSec = effectiveMs.float / 1000.0

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
          try:
            return ok(parseJson(resp.result.get))
          except CatchableError as e:
            return err("Failed to parse response: " & e.msg)
        else:
          return ok(newJNull())

    # Check timeout
    if epochTime() - startTime > timeoutSec:
      {.cast(raises: []).}:
        svc.activeRequests.del(requestId)
      return err("Request timed out")

    # Async sleep to yield to other tasks
    await sleepAsync(timer.milliseconds(PollIntervalMs))

proc waitForResponseRaw*(
    svc: LspService, requestId: int, timeoutMs: int = 0
): Future[Result[string, string]] {.async: (raises: [CancelledError]).} =
  ## Like waitForResponse but yields the unparsed result JSON string so a typed
  ## consumer can jsony fromJson it directly. A server result of null (or none)
  ## is returned as the literal "null".
  let startTime = epochTime()
  let effectiveMs = if timeoutMs > 0: timeoutMs else: svc.requestTimeoutMs
  let timeoutSec = effectiveMs.float / 1000.0

  while true:
    {.cast(raises: []).}:
      try:
        svc.poll()
      except CatchableError as e:
        svc.onLogMessage("", mtError, "Unexpected error in poll: " & e.msg)
      except Defect as e:
        svc.onLogMessage("", mtError, "Defect in poll: " & e.msg)
        raise

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
          return ok("null")

    if epochTime() - startTime > timeoutSec:
      {.cast(raises: []).}:
        svc.activeRequests.del(requestId)
      return err("Request timed out")

    await sleepAsync(timer.milliseconds(PollIntervalMs))

# Helper to start a tracked request
proc startTrackedRequest(
    svc: LspService,
    worker: LspWorker,
    methodName: string,
    params: JsonNode,
    timeoutMs: int = 0,
): int =
  ## Start a request and track it for timeout checking.
  ## timeoutMs <= 0 uses the service default.
  ## IDs are allocated from the service-wide counter so requests to
  ## different workers never share an ID in the tracking tables.
  let requestId = svc.nextRequestId
  inc svc.nextRequestId
  # Serialize once here; the worker splices the string into the request envelope
  # rather than parsing it back into a JsonNode.
  worker.sendRequest(requestId, methodName, $params)
  svc.activeRequests[requestId] = LspPendingRequest(
    requestId: requestId,
    langId: worker.languageId,
    methodName: methodName,
    startTime: epochTime(),
    timeoutMs: if timeoutMs > 0: timeoutMs else: svc.requestTimeoutMs,
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
  let workerOpt = svc.workerForExistingPath(path)
  if workerOpt.isNone:
    return ok() # No LSP for this file type, or worker not started

  workerOpt.get.didChangeFull(pathToUri(path), version, text)
  return ok()

proc notifyDocumentChangedIncremental*(
    svc: LspService, path: string, version: int, contentChangesJson: string
): Result[void, string] =
  ## Incremental variant of notifyDocumentChanged: sends a serialized
  ## contentChanges array instead of the full text (non-blocking).
  let workerOpt = svc.workerForExistingPath(path)
  if workerOpt.isNone:
    return ok() # No LSP for this file type, or worker not started

  workerOpt.get.didChangeIncremental(pathToUri(path), version, contentChangesJson)
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

proc startInlayHintRequest*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[int, string] =
  ## Start a textDocument/inlayHint request (non-blocking). Returns request ID.
  ## InlayHintParams requires a range; hints are requested for the visible
  ## viewport only.
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

  ok(svc.startTrackedRequest(worker, "textDocument/inlayHint", params))

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

  let params = %*{"item": item.toJson}

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

  let params = %*{"item": item.toJson}

  let requestId = svc.startTrackedRequest(worker, "callHierarchy/outgoingCalls", params)
  return ok(requestId)

# Response parsing helpers for async requests
proc parseCompletionResponse*(
    raw: string
): tuple[items: seq[CompletionItem], isIncomplete: bool] =
  ## Parse a completion response (the `result` of textDocument/completion)
  ## straight from its raw JSON string with jsony, skipping the intermediate
  ## JsonNode. The result may be a CompletionList object, a bare CompletionItem
  ## array, or null. Malformed payloads degrade to an empty list rather than
  ## raising.
  var k = 0
  while k < raw.len and raw[k] in Whitespace:
    inc k
  if k >= raw.len or raw[k] == 'n': # empty or null
    return (@[], false)
  try:
    if raw[k] == '[':
      return (raw.fromJson(seq[CompletionItem]), false)
    else:
      let cl = raw.fromJson(CompletionList)
      return (cl.items, cl.isIncomplete)
  except CatchableError:
    return (@[], false)

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

proc parseInlayHintResponse*(resp: JsonNode): seq[InlayHint] =
  ## Parse a textDocument/inlayHint response (array of InlayHint | null).
  ## Uses parseInlayHint (handles the label string | LabelPart[] union);
  ## invalid items are silently dropped.
  result = @[]
  if resp.isNil or resp.kind != JArray:
    return
  for item in resp:
    let hint = parseInlayHint(item)
    if hint.isSome:
      result.add hint.get

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

template isCapabilityEnabled(cap: Option[JsonNode]): bool =
  ## A `boolean | Options` server capability counts as supported only when it is
  ## present and not literally `false` or `null`. A server may legitimately
  ## advertise `"xxxProvider": false` (or `null`, which some servers emit via
  ## Option-field serialisation) to disable a feature; treating either as
  ## enabled fires useless requests that hang until the request timeout. An
  ## object (Options) always means enabled.
  cap.isSome and cap.get.kind != JNull and (cap.get.kind != JBool or cap.get.getBool)

template isCapabilityEnabled[T](cap: Option[T]): bool =
  ## Capabilities typed as `Options` (e.g. CompletionOptions) carry no boolean,
  ## so presence means supported. `parseServerCapabilities` is responsible for
  ## leaving the field `none` when a server advertises a literal `false`.
  cap.isSome

# Template for standard capability checks (dynamic registration + static capability)
template hasCapabilitySupport(
    svc: LspService, langId: string, methodName: string, capability: untyped
): bool =
  if svc.hasDynamicRegistration(langId, methodName):
    true
  elif langId notin svc.capabilities:
    false
  else:
    isCapabilityEnabled(svc.capabilities[langId].capability)

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

proc dynamicSemanticTokensOption(svc: LspService, langId, key: string): bool =
  ## Check a `full`/`range` flag inside a dynamically-registered semantic
  ## tokens registration. The option is present (and not literally false)
  ## when supported; it may be `true` or an object such as {"delta": ...}.
  let reg = svc.getDynamicRegistration(langId, "textDocument/semanticTokens")
  if reg.isNone or reg.get.registerOptions.isNone:
    return false
  let opts = reg.get.registerOptions.get
  if opts.kind != JObject or not opts.hasKey(key):
    return false
  let node = opts[key]
  return node.kind != JBool or node.getBool

proc hasSemanticTokensFullSupport*(svc: LspService, langId: string): bool =
  ## Check if full semantic tokens is supported for a language
  ## (static capability or dynamic registration)
  if svc.dynamicSemanticTokensOption(langId, "full"):
    return true
  if svc.hasDynamicRegistration(langId, "textDocument/semanticTokens/full"):
    return true
  if langId notin svc.capabilities:
    return false
  let provider = svc.capabilities[langId].semanticTokensProvider
  if provider.isNone:
    return false
  return provider.get.full.isSome

proc hasSemanticTokensRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if range semantic tokens is supported for a language
  ## (static capability or dynamic registration)
  if svc.dynamicSemanticTokensOption(langId, "range"):
    return true
  if svc.hasDynamicRegistration(langId, "textDocument/semanticTokens/range"):
    return true
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

proc documentSyncKind*(svc: LspService, path: string): TextDocumentSyncKind =
  ## Resolution order: dynamic registration > static textDocumentSync > Full.
  ## The default is Full rather than the spec's None to avoid a regression:
  ## servers that under-advertise capabilities would otherwise stop receiving
  ## didChange (breaking diagnostics, etc.).
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return tdskFull
  let langId = langIdOpt.get

  let reg = svc.getDynamicRegistration(langId, "textDocument/didChange")
  if reg.isSome:
    # A dynamic didChange registration is authoritative: the server explicitly
    # opted into didChange, so resolve its syncKind here. Fall back to Full (not
    # the static caps, which could be None) when the options are absent/malformed
    # so an explicit opt-in is never turned into a silent opt-out.
    if reg.get.registerOptions.isSome:
      let opts = reg.get.registerOptions.get
      if opts.kind == JObject and opts.hasKey("syncKind") and
          opts["syncKind"].kind == JInt:
        return toEnumOr(opts["syncKind"].getInt, tdskFull)
    return tdskFull

  if langId notin svc.capabilities:
    return tdskFull
  let tds = svc.capabilities[langId].textDocumentSync
  if tds.isNone:
    return tdskFull
  let node = tds.get
  case node.kind
  of JInt:
    return toEnumOr(node.getInt, tdskFull)
  of JObject:
    if node.hasKey("change") and node["change"].kind == JInt:
      return toEnumOr(node["change"].getInt, tdskFull)
    # Object without an explicit `change`: default to Full rather than None,
    # consistent with the "don't under-advertise" default. An explicit
    # `change: 0` above still opts the server out.
    return tdskFull
  else:
    return tdskFull

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
    let respResult = await svc.waitForResponseRaw(requestId)

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
