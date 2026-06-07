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

import std/[unittest, json, options]

import pkg/results

import ../src/moepkg/lsp/worker

suite "LspWorker - Constants":
  test "SignalTimeoutRunningMs is defined":
    check SignalTimeoutRunningMs == 50

  test "SignalTimeoutIdleMs is defined":
    check SignalTimeoutIdleMs == 500

  test "RequestTimeoutSec is defined":
    check RequestTimeoutSec == 30

suite "LspWorker - LspWorkerState enum":
  test "LspWorkerState values are ordered":
    check lwsStopped.ord == 0
    check lwsStarting.ord == 1
    check lwsRunning.ord == 2
    check lwsShuttingDown.ord == 3
    check lwsCrashed.ord == 4

  test "LspWorkerState enum has all expected values":
    check lwsStopped < lwsStarting
    check lwsStarting < lwsRunning
    check lwsRunning < lwsShuttingDown
    check lwsShuttingDown < lwsCrashed

suite "LspWorker - LspCommandKind enum":
  test "LspCommandKind has all expected values":
    check lcmdStart in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdStop in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdShutdown in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdDidOpen in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdDidClose in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdDidChange in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdDidSave in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }
    check lcmdRequest in {
      lcmdStart, lcmdStop, lcmdShutdown, lcmdDidOpen, lcmdDidClose, lcmdDidChange,
      lcmdDidSave, lcmdRequest,
    }

suite "LspWorker - LspEventKind enum":
  test "LspEventKind has all expected values":
    check levInitialized in {
      levInitialized, levError, levDiagnostics, levLogMessage, levShowMessage,
      levServerInfo, levCapabilities, levResponse, levRawJson, levProgress,
      levDynamicRegister, levDynamicUnregister, levStatusUpdate,
    }
    check levError in {
      levInitialized, levError, levDiagnostics, levLogMessage, levShowMessage,
      levServerInfo, levCapabilities, levResponse, levRawJson, levProgress,
      levDynamicRegister, levDynamicUnregister, levStatusUpdate,
    }

suite "LspWorker - ServerHealth enum":
  test "ServerHealth string values":
    check $shOk == "ok"
    check $shWarning == "warning"
    check $shError == "error"

suite "LspWorker - LspJsonDirection enum":
  test "LspJsonDirection has expected values":
    check ljdSent in {ljdSent, ljdReceived}
    check ljdReceived in {ljdSent, ljdReceived}

suite "LspWorker - LspCommand object":
  test "LspCommand lcmdStart variant":
    let cmd = LspCommand(
      kind: lcmdStart,
      languageId: "nim",
      command: "nimlangserver",
      args: @["--stdio"],
      workspaceRoot: "/home/test/project",
    )
    check cmd.kind == lcmdStart
    check cmd.languageId == "nim"
    check cmd.command == "nimlangserver"
    check cmd.args == @["--stdio"]
    check cmd.workspaceRoot == "/home/test/project"

  test "LspCommand lcmdStop variant":
    let cmd = LspCommand(kind: lcmdStop)
    check cmd.kind == lcmdStop

  test "LspCommand lcmdShutdown variant":
    let cmd = LspCommand(kind: lcmdShutdown)
    check cmd.kind == lcmdShutdown

  test "LspCommand lcmdDidOpen variant":
    let cmd = LspCommand(
      kind: lcmdDidOpen,
      openUri: "file:///test.nim",
      openLangId: "nim",
      openVersion: 1,
      openText: "echo \"hello\"",
    )
    check cmd.kind == lcmdDidOpen
    check cmd.openUri == "file:///test.nim"
    check cmd.openLangId == "nim"
    check cmd.openVersion == 1
    check cmd.openText == "echo \"hello\""

  test "LspCommand lcmdDidClose variant":
    let cmd = LspCommand(kind: lcmdDidClose, closeUri: "file:///test.nim")
    check cmd.kind == lcmdDidClose
    check cmd.closeUri == "file:///test.nim"

  test "LspCommand lcmdDidChange variant":
    let cmd = LspCommand(
      kind: lcmdDidChange,
      changeUri: "file:///test.nim",
      changeVersion: 2,
      changeText: "echo \"updated\"",
    )
    check cmd.kind == lcmdDidChange
    check cmd.changeUri == "file:///test.nim"
    check cmd.changeVersion == 2
    check cmd.changeText == "echo \"updated\""

  test "LspCommand lcmdDidSave variant with text":
    let cmd = LspCommand(
      kind: lcmdDidSave, saveUri: "file:///test.nim", saveText: some("echo \"saved\"")
    )
    check cmd.kind == lcmdDidSave
    check cmd.saveUri == "file:///test.nim"
    check cmd.saveText.isSome
    check cmd.saveText.get == "echo \"saved\""

  test "LspCommand lcmdDidSave variant without text":
    let cmd =
      LspCommand(kind: lcmdDidSave, saveUri: "file:///test.nim", saveText: none(string))
    check cmd.kind == lcmdDidSave
    check cmd.saveUri == "file:///test.nim"
    check cmd.saveText.isNone

  test "LspCommand lcmdRequest variant":
    let cmd = LspCommand(
      kind: lcmdRequest,
      requestId: 42,
      reqMethod: "textDocument/completion",
      reqParamsJson: $(%*{"textDocument": {"uri": "file:///test.nim"}}),
    )
    check cmd.kind == lcmdRequest
    check cmd.requestId == 42
    check cmd.reqMethod == "textDocument/completion"
    check parseJson(cmd.reqParamsJson).hasKey("textDocument")

suite "LspWorker - LspEvent object":
  test "LspEvent levInitialized variant":
    let evt = LspEvent(kind: levInitialized)
    check evt.kind == levInitialized

  test "LspEvent levError variant":
    let evt = LspEvent(kind: levError, errorMsg: "Connection failed")
    check evt.kind == levError
    check evt.errorMsg == "Connection failed"

  test "LspEvent levDiagnostics variant":
    # Diagnostics cross the thread boundary serialized as a JSON array
    let diagsJson = $(
      %*[
        {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
          "severity": 1,
          "message": "Error message",
        }
      ]
    )
    let evt = LspEvent(
      kind: levDiagnostics, diagUri: "file:///test.nim", diagnosticsJson: diagsJson
    )
    check evt.kind == levDiagnostics
    check evt.diagUri == "file:///test.nim"
    let parsed = parseJson(evt.diagnosticsJson)
    check parsed.len == 1
    check parseDiagnostic(parsed[0]).message == "Error message"

  test "LspEvent levLogMessage variant":
    let evt = LspEvent(kind: levLogMessage, msgType: mtInfo, message: "Log message")
    check evt.kind == levLogMessage
    check evt.msgType == mtInfo
    check evt.message == "Log message"

  test "LspEvent levShowMessage variant":
    let evt = LspEvent(kind: levShowMessage, msgType: mtWarning, message: "Warning!")
    check evt.kind == levShowMessage
    check evt.msgType == mtWarning
    check evt.message == "Warning!"

  test "LspEvent levServerInfo variant":
    let evt = LspEvent(
      kind: levServerInfo, serverName: "nimlangserver", serverVersion: some("1.0.0")
    )
    check evt.kind == levServerInfo
    check evt.serverName == "nimlangserver"
    check evt.serverVersion.isSome
    check evt.serverVersion.get == "1.0.0"

  test "LspEvent levServerInfo variant without version":
    let evt = LspEvent(
      kind: levServerInfo, serverName: "test-server", serverVersion: none(string)
    )
    check evt.kind == levServerInfo
    check evt.serverName == "test-server"
    check evt.serverVersion.isNone

  test "LspEvent levCapabilities variant":
    let evt = LspEvent(kind: levCapabilities, capabilitiesJson: "{}")
    check evt.kind == levCapabilities

  test "LspEvent levResponse variant with result":
    let evt = LspEvent(
      kind: levResponse,
      requestId: 42,
      responseResultJson: some($(%*{"items": []})),
      responseError: none(string),
    )
    check evt.kind == levResponse
    check evt.requestId == 42
    check evt.responseResultJson.isSome
    check parseJson(evt.responseResultJson.get).hasKey("items")
    check evt.responseError.isNone

  test "LspEvent levResponse variant with error":
    let evt = LspEvent(
      kind: levResponse,
      requestId: 42,
      responseResultJson: none(string),
      responseError: some("Request failed"),
    )
    check evt.kind == levResponse
    check evt.requestId == 42
    check evt.responseResultJson.isNone
    check evt.responseError.isSome
    check evt.responseError.get == "Request failed"

  test "LspEvent levRawJson variant sent":
    let evt = LspEvent(
      kind: levRawJson, jsonDirection: ljdSent, rawJson: "{\"jsonrpc\":\"2.0\"}"
    )
    check evt.kind == levRawJson
    check evt.jsonDirection == ljdSent
    check evt.rawJson == "{\"jsonrpc\":\"2.0\"}"

  test "LspEvent levRawJson variant received":
    let evt = LspEvent(
      kind: levRawJson, jsonDirection: ljdReceived, rawJson: "{\"result\":null}"
    )
    check evt.kind == levRawJson
    check evt.jsonDirection == ljdReceived

  test "LspEvent levProgress variant":
    let beginData = WorkDoneProgressBegin(title: "Indexing")
    let progress = WorkDoneProgress(kind: wdpkBegin, begin: beginData)
    let evt =
      LspEvent(kind: levProgress, progressToken: "token-123", progress: progress)
    check evt.kind == levProgress
    check evt.progressToken == "token-123"
    check evt.progress.kind == wdpkBegin
    check evt.progress.begin.title == "Indexing"

  test "LspEvent levDynamicRegister variant":
    # RegistrationParams cross the boundary serialized
    let paramsJson =
      $(%*{"registrations": [{"id": "reg-1", "method": "textDocument/completion"}]})
    let evt = LspEvent(kind: levDynamicRegister, registrationsJson: paramsJson)
    check evt.kind == levDynamicRegister
    let regs = parseRegistrationParams(parseJson(evt.registrationsJson)).registrations
    check regs.len == 1
    check regs[0].id == "reg-1"
    check regs[0].`method` == "textDocument/completion"

  test "LspEvent levDynamicUnregister variant":
    let paramsJson =
      $(%*{"unregisterations": [{"id": "reg-1", "method": "textDocument/completion"}]})
    let evt = LspEvent(kind: levDynamicUnregister, unregistrationsJson: paramsJson)
    check evt.kind == levDynamicUnregister
    let unregs =
      parseUnregistrationParams(parseJson(evt.unregistrationsJson)).unregisterations
    check unregs.len == 1
    check unregs[0].id == "reg-1"

  test "LspEvent levStatusUpdate variant":
    let evt = LspEvent(
      kind: levStatusUpdate,
      statusHealth: shOk,
      statusQuiescent: true,
      statusMessage: some("Ready"),
    )
    check evt.kind == levStatusUpdate
    check evt.statusHealth == shOk
    check evt.statusQuiescent
    check evt.statusMessage.isSome
    check evt.statusMessage.get == "Ready"

  test "LspEvent levStatusUpdate variant without message":
    let evt = LspEvent(
      kind: levStatusUpdate,
      statusHealth: shWarning,
      statusQuiescent: false,
      statusMessage: none(string),
    )
    check evt.kind == levStatusUpdate
    check evt.statusHealth == shWarning
    check not evt.statusQuiescent
    check evt.statusMessage.isNone

suite "LspWorker - newLspWorker":
  test "creates worker with language id":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check worker.languageId == "nim"

  test "creates worker with different language ids":
    let nimWorker = newLspWorker("nim")
    check nimWorker.isOk
    check nimWorker.get.languageId == "nim"

    let rustWorker = newLspWorker("rust")
    check rustWorker.isOk
    check rustWorker.get.languageId == "rust"

    let pythonWorker = newLspWorker("python")
    check pythonWorker.isOk
    check pythonWorker.get.languageId == "python"

suite "LspWorker - State Checks (without starting worker)":
  test "initial state is stopped":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check worker.state == lwsStopped

  test "isStopped returns true initially":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check worker.isStopped

  test "isRunning returns false initially":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check not worker.isRunning

  test "isStarting returns false initially":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check not worker.isStarting

suite "LspWorker - pollEvents (without starting worker)":
  test "pollEvents returns empty seq when no events":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    let events = worker.pollEvents()
    check events.len == 0

  test "pollEvents can be called multiple times":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    check worker.pollEvents().len == 0
    check worker.pollEvents().len == 0
    check worker.pollEvents().len == 0

suite "LspWorker - sendRequest (without starting worker)":
  test "sendRequest returns incrementing request ids":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    let id1 = worker.sendRequest("textDocument/completion", %*{})
    let id2 = worker.sendRequest("textDocument/hover", %*{})
    let id3 = worker.sendRequest("textDocument/definition", %*{})

    check id1 == 1
    check id2 == 2
    check id3 == 3

  test "sendRequest with different methods":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    discard worker.sendRequest(
      "textDocument/completion", %*{"position": {"line": 0, "character": 5}}
    )
    discard worker.sendRequest(
      "textDocument/hover", %*{"textDocument": {"uri": "file:///test.nim"}}
    )

  test "sendRequest with explicit caller-provided id":
    # The service allocates IDs from a shared counter so different workers'
    # requests never collide; the worker must use the given ID as-is.
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.sendRequest(42, "textDocument/hover", %*{})
    # The internal counter is unaffected by explicit IDs
    let autoId = worker.sendRequest("textDocument/completion", %*{})
    check autoId == 1

suite "LspWorker - Worker Thread Lifecycle":
  test "start and stop worker thread":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    check worker.isStopped
    check worker.state == lwsStopped

    worker.start()
    # Worker thread is started but LSP server is not running yet
    # isStopped returns true because stateVal is still lwsStopped (no server started)
    # This is expected behavior - isStopped checks if LSP server state is stopped
    check worker.state == lwsStopped
    check not worker.isRunning # No LSP server started

    worker.stop()
    check worker.isStopped
    check worker.state == lwsStopped

  test "stop is safe to call on stopped worker":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    check worker.isStopped
    worker.stop() # Should not crash
    check worker.isStopped

  test "start is safe to call on already started worker":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.start() # Should not crash or create duplicate threads
    worker.stop()
    check worker.isStopped

  test "double stop after start does not crash":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.stop()
    worker.stop() # Second stop should be safe (no double deinitLock/close)
    check worker.isStopped

  test "double stop without start does not crash":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.stop()
    worker.stop() # Second stop should be safe
    check worker.isStopped

suite "LspWorker - Document Notification Commands":
  test "didOpen queues command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didOpen("file:///test.nim", "nim", 1, "echo \"hello\"")
    worker.stop()

  test "didClose queues command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didClose("file:///test.nim")
    worker.stop()

  test "didChange queues command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didChange("file:///test.nim", 2, "echo \"updated\"")
    worker.stop()

  test "didSave queues command with text":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didSave("file:///test.nim", some("echo \"saved\""))
    worker.stop()

  test "didSave queues command without text":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didSave("file:///test.nim")
    worker.stop()

suite "LspWorker - Server Commands":
  test "startServer queues start command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.startServer("nimlangserver", @["--stdio"], "/home/test/project")
    worker.stop()

  test "stopServer queues stop command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.stopServer()
    worker.stop()

suite "LspWorker - MessageType enum":
  test "MessageType values":
    check mtError.int == 1
    check mtWarning.int == 2
    check mtInfo.int == 3
    check mtLog.int == 4

suite "LspWorker - DiagnosticSeverity enum":
  test "DiagnosticSeverity values":
    check dsError.int == 1
    check dsWarning.int == 2
    check dsInformation.int == 3
    check dsHint.int == 4

suite "LspWorker - WorkDoneProgressKind enum":
  test "WorkDoneProgressKind values":
    check wdpkBegin in {wdpkBegin, wdpkReport, wdpkEnd}
    check wdpkReport in {wdpkBegin, wdpkReport, wdpkEnd}
    check wdpkEnd in {wdpkBegin, wdpkReport, wdpkEnd}

suite "LspWorker - Range and Position types":
  test "Position creation":
    let pos = Position(line: 10, character: 5)
    check pos.line == 10
    check pos.character == 5

  test "Range creation":
    let r = Range(
      start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 10)
    )
    check r.start.line == 0
    check r.start.character == 0
    check r.`end`.line == 0
    check r.`end`.character == 10

suite "LspWorker - Diagnostic type":
  test "Diagnostic creation with all fields":
    let diag = Diagnostic(
      `range`: Range(
        start: Position(line: 5, character: 0), `end`: Position(line: 5, character: 20)
      ),
      severity: some(dsWarning),
      code: some(%"W001"),
      codeDescription: none(JsonNode),
      source: some("compiler"),
      message: "Unused variable",
      tags: some(@[dtUnnecessary]),
      relatedInformation: none(seq[DiagnosticRelatedInformation]),
      data: none(JsonNode),
    )
    check diag.`range`.start.line == 5
    check diag.severity.get == dsWarning
    check diag.code.get.getStr == "W001"
    check diag.source.get == "compiler"
    check diag.message == "Unused variable"
    check diag.tags.isSome
    check dtUnnecessary in diag.tags.get

  test "Diagnostic creation with minimal fields":
    let diag = Diagnostic(
      `range`: Range(
        start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
      ),
      message: "Error",
    )
    check diag.message == "Error"
    check diag.severity.isNone
    check diag.code.isNone
    check diag.source.isNone

suite "LspWorker - Registration and Unregistration types":
  test "Registration creation":
    let reg = Registration(
      id: "registration-123",
      `method`: "textDocument/completion",
      registerOptions: some(%*{"triggerCharacters": ["."]}),
    )
    check reg.id == "registration-123"
    check reg.`method` == "textDocument/completion"
    check reg.registerOptions.isSome

  test "Registration creation without options":
    let reg = Registration(id: "reg-1", `method`: "textDocument/hover")
    check reg.id == "reg-1"
    check reg.`method` == "textDocument/hover"
    check reg.registerOptions.isNone

  test "Unregistration creation":
    let unreg =
      Unregistration(id: "registration-123", `method`: "textDocument/completion")
    check unreg.id == "registration-123"
    check unreg.`method` == "textDocument/completion"

suite "LspWorker - WorkDoneProgress type":
  test "WorkDoneProgress begin":
    let beginData = WorkDoneProgressBegin(
      title: "Indexing",
      cancellable: some(true),
      message: some("Starting..."),
      percentage: some(0),
    )
    let progress = WorkDoneProgress(kind: wdpkBegin, begin: beginData)
    check progress.kind == wdpkBegin
    check progress.begin.title == "Indexing"
    check progress.begin.cancellable.get == true
    check progress.begin.message.get == "Starting..."
    check progress.begin.percentage.get == 0

  test "WorkDoneProgress report":
    let reportData = WorkDoneProgressReport(
      cancellable: some(false),
      message: some("Processing file 5 of 10"),
      percentage: some(50),
    )
    let progress = WorkDoneProgress(kind: wdpkReport, report: reportData)
    check progress.kind == wdpkReport
    check progress.report.message.get == "Processing file 5 of 10"
    check progress.report.percentage.get == 50

  test "WorkDoneProgress end":
    let endData = WorkDoneProgressEnd(message: some("Done"))
    let progress = WorkDoneProgress(kind: wdpkEnd, `end`: endData)
    check progress.kind == wdpkEnd
    check progress.`end`.message.get == "Done"

suite "LspWorker - ServerCapabilities type":
  test "ServerCapabilities default values":
    let caps = ServerCapabilities()
    check caps.completionProvider.isNone
    check caps.hoverProvider.isNone
    check caps.definitionProvider.isNone

suite "LspWorker - Multiple workers":
  test "multiple workers can be created":
    let worker1Result = newLspWorker("nim")
    let worker2Result = newLspWorker("rust")
    let worker3Result = newLspWorker("python")

    check worker1Result.isOk
    check worker2Result.isOk
    check worker3Result.isOk

    check worker1Result.get.languageId == "nim"
    check worker2Result.get.languageId == "rust"
    check worker3Result.get.languageId == "python"

  test "multiple workers can be started and stopped independently":
    let worker1Result = newLspWorker("nim")
    let worker2Result = newLspWorker("rust")

    check worker1Result.isOk
    check worker2Result.isOk

    let worker1 = worker1Result.get
    let worker2 = worker2Result.get

    # Both workers start in stopped state
    check worker1.state == lwsStopped
    check worker2.state == lwsStopped

    worker1.start()
    # Worker thread started, but LSP server state is still stopped
    check worker1.state == lwsStopped
    check worker2.state == lwsStopped

    worker2.start()
    check worker1.state == lwsStopped
    check worker2.state == lwsStopped

    worker1.stop()
    check worker1.state == lwsStopped

    worker2.stop()
    check worker1.state == lwsStopped
    check worker2.state == lwsStopped
