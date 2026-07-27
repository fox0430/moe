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

import std/[unittest, json, options, os, monotimes, times, strutils]

import pkg/results

import ../src/moepkg/lsp/worker

suite "LspWorker - pathToFileUri":
  test "plain absolute path":
    check pathToFileUri("/home/user/project") == "file:///home/user/project"

  test "percent-encodes spaces":
    check pathToFileUri("/home/user/my project") == "file:///home/user/my%20project"

  test "percent-encodes non-ASCII":
    check pathToFileUri("/home/user/プロジェクト") ==
      "file:///home/user/%E3%83%97%E3%83%AD%E3%82%B8%E3%82%A7%E3%82%AF%E3%83%88"

  test "keeps path separators":
    check pathToFileUri("/a/b/c") == "file:///a/b/c"

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

suite "LspWorker - formatRawJsonLogLine":
  test "sent frames use the >>> marker":
    let line = formatRawJsonLogLine(
      "nim", ljdSent, """{"jsonrpc":"2.0","method":"initialize"}"""
    )
    check line == """nim >>> {"jsonrpc":"2.0","method":"initialize"}"""

  test "received frames use the <<< marker":
    let line = formatRawJsonLogLine("rust", ljdReceived, """{"id":1,"result":null}""")
    check line == """rust <<< {"id":1,"result":null}"""

  test "language id prefixes the line":
    let line = formatRawJsonLogLine("python", ljdSent, "{}")
    check line.startsWith("python >>> ")

  test "the payload is passed through verbatim on a single line":
    # Compactness is the caller's responsibility ($node); the formatter must
    # not reflow the payload, so a single-line input stays single-line.
    let payload = """{"a":1,"b":{"c":2}}"""
    let line = formatRawJsonLogLine("nim", ljdSent, payload)
    check not line.contains("\n")
    check line.endsWith(payload)

  test "empty language id still produces a well-formed line":
    let line = formatRawJsonLogLine("", ljdReceived, """{"x":1}""")
    check line == """ <<< {"x":1}"""

suite "LspWorker - extractErrorMessage":
  test "returns message from a well-formed error object":
    let err = %*{"code": -32603, "message": "boom"}
    check extractErrorMessage(err) == "boom"

  test "falls back when message field is absent":
    let err = %*{"code": -32603}
    check extractErrorMessage(err) == "Unknown error"

  test "custom fallback is honored":
    let err = %*{"code": -32603}
    check extractErrorMessage(err, "unknown error") == "unknown error"

  # Regression: non-object `error` (JNull / JString) used to hit `[]`'s
  # `assert kind == JObject` and crash the worker with AssertionDefect.
  test "non-object error node does not raise":
    check extractErrorMessage(newJNull()) == "Unknown error"
    check extractErrorMessage(newJString("oops")) == "Unknown error"
    check extractErrorMessage(newJInt(42)) == "Unknown error"
    check extractErrorMessage(newJArray()) == "Unknown error"

  test "nil node does not raise":
    check extractErrorMessage(nil) == "Unknown error"

  test "non-string message field falls back":
    let err = %*{"message": 123}
    check extractErrorMessage(err) == "Unknown error"

suite "LspWorker - dropPendingDidOpen":
  # Regression: a didClose that arrives before the server reaches lwsRunning
  # must remove the queued didOpen for the same URI. Otherwise the post-init
  # flush emits a didOpen for a buffer the user already closed, and a later
  # reopen sends a second didOpen without an intervening didClose - a
  # protocol violation.
  proc openCmd(uri: string, version = 1): LspCommand =
    LspCommand(
      kind: lcmdDidOpen,
      openUri: uri,
      openLangId: "nim",
      openVersion: version,
      openText: "x",
    )

  test "removes the sole matching entry":
    var pending = @[openCmd("file:///a.nim")]
    dropPendingDidOpen(pending, "file:///a.nim")
    check pending.len == 0

  test "leaves non-matching URIs untouched":
    var pending = @[openCmd("file:///a.nim"), openCmd("file:///b.nim")]
    dropPendingDidOpen(pending, "file:///b.nim")
    check pending.len == 1
    check pending[0].openUri == "file:///a.nim"

  test "removes every duplicate for the same URI":
    var pending = @[
      openCmd("file:///a.nim", 1), openCmd("file:///a.nim", 2), openCmd("file:///b.nim")
    ]
    dropPendingDidOpen(pending, "file:///a.nim")
    check pending.len == 1
    check pending[0].openUri == "file:///b.nim"

  test "is a no-op when the URI is not queued":
    var pending = @[openCmd("file:///a.nim")]
    dropPendingDidOpen(pending, "file:///missing.nim")
    check pending.len == 1
    check pending[0].openUri == "file:///a.nim"

  test "is a no-op on an empty queue":
    var pending: seq[LspCommand] = @[]
    dropPendingDidOpen(pending, "file:///a.nim")
    check pending.len == 0

  test "preserves the relative order of surviving entries":
    var pending = @[
      openCmd("file:///a.nim"),
      openCmd("file:///b.nim"),
      openCmd("file:///c.nim"),
      openCmd("file:///b.nim"),
      openCmd("file:///d.nim"),
    ]
    dropPendingDidOpen(pending, "file:///b.nim")
    check pending.len == 3
    check pending[0].openUri == "file:///a.nim"
    check pending[1].openUri == "file:///c.nim"
    check pending[2].openUri == "file:///d.nim"

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

  test "LspCommand lcmdDidChange full variant":
    let cmd = LspCommand(
      kind: lcmdDidChange,
      changeUri: "file:///test.nim",
      changeVersion: 2,
      changeMode: lcdmFull,
      changeText: "echo \"updated\"",
    )
    check cmd.kind == lcmdDidChange
    check cmd.changeMode == lcdmFull
    check cmd.changeUri == "file:///test.nim"
    check cmd.changeVersion == 2
    check cmd.changeText == "echo \"updated\""

  test "LspCommand lcmdDidChange incremental variant":
    let changes = $(%*[{"range": {"start": {"line": 0, "character": 0}}, "text": "x"}])
    let cmd = LspCommand(
      kind: lcmdDidChange,
      changeUri: "file:///test.nim",
      changeVersion: 3,
      changeMode: lcdmIncremental,
      changeContentChangesJson: changes,
    )
    check cmd.changeMode == lcdmIncremental
    check cmd.changeContentChangesJson == changes

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

  test "LspCommand lcmdCancel variant":
    let cmd = LspCommand(kind: lcmdCancel, cancelRequestId: 7)
    check cmd.kind == lcmdCancel
    check cmd.cancelRequestId == 7

  test "LspCommand lcmdApplyEditResponse variant":
    let cmd = LspCommand(
      kind: lcmdApplyEditResponse,
      applyEditReqIdJson: "7",
      applyEditApplied: false,
      applyEditFailureReason: "buffer changed",
    )
    check cmd.kind == lcmdApplyEditResponse
    check cmd.applyEditReqIdJson == "7"
    check not cmd.applyEditApplied
    check cmd.applyEditFailureReason == "buffer changed"

  test "sendApplyEditResponse is safe without a running server":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    # Nothing is running; this only enqueues a command and must not crash.
    worker.sendApplyEditResponse("7", true)

  test "cancelRequest is safe without a running server":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get
    worker.cancelRequest(123) # Should not crash; nothing is pending

suite "LspWorker - buildApplyEditResponse":
  test "integer id round-trips as an integer":
    let resp = buildApplyEditResponse("7", true, "")
    check resp["jsonrpc"].getStr == "2.0"
    check resp["id"].kind == JInt
    check resp["id"].getInt == 7
    check resp["result"]["applied"].getBool
    # No failureReason when applied.
    check not resp["result"].hasKey("failureReason")

  test "string id round-trips as a string":
    # The server id is captured as `$reqId`, so a string id arrives quoted.
    let resp = buildApplyEditResponse("\"abc\"", true, "")
    check resp["id"].kind == JString
    check resp["id"].getStr == "abc"

  test "refusal carries the failureReason":
    let resp = buildApplyEditResponse("7", false, "buffer changed")
    check not resp["result"]["applied"].getBool
    check resp["result"]["failureReason"].getStr == "buffer changed"

  test "refusal without a reason omits failureReason":
    let resp = buildApplyEditResponse("7", false, "")
    check not resp["result"]["applied"].getBool
    check not resp["result"].hasKey("failureReason")

  test "an unparseable id falls back to null rather than raising":
    let resp = buildApplyEditResponse("{not json", true, "")
    check resp["id"].kind == JNull
    check resp["result"]["applied"].getBool

suite "LspWorker - buildWorkspaceConfigurationResponse":
  test "returns one null per item when settings is null":
    let params = %*{"items": [{"section": "foo"}, {"section": "bar"}]}
    let result = buildWorkspaceConfigurationResponse(params, newJNull())
    check result.kind == JArray
    check result.len == 2
    check result[0].kind == JNull
    check result[1].kind == JNull

  test "returns empty array when items is empty":
    let params = %*{"items": []}
    let result = buildWorkspaceConfigurationResponse(params, newJNull())
    check result.kind == JArray
    check result.len == 0

  test "returns empty array when items is missing":
    let params = %*{}
    let result = buildWorkspaceConfigurationResponse(params, newJNull())
    check result.kind == JArray
    check result.len == 0

  test "returns empty array when items is not an array":
    let params = %*{"items": "not-an-array"}
    let result = buildWorkspaceConfigurationResponse(params, newJNull())
    check result.kind == JArray
    check result.len == 0

  test "returns empty array when params is null":
    let result = buildWorkspaceConfigurationResponse(newJNull(), newJNull())
    check result.kind == JArray
    check result.len == 0

  test "returns settings for item without section":
    let settings = %*{"foo": "bar"}
    let params = %*{"items": [{}]}
    let result = buildWorkspaceConfigurationResponse(params, settings)
    check result.kind == JArray
    check result.len == 1
    check result[0] == settings

  test "returns section lookup for item with section":
    let settings = %*{"rust": {"analyzer": {"enable": true}}}
    let params = %*{"items": [{"section": "rust.analyzer"}]}
    let result = buildWorkspaceConfigurationResponse(params, settings)
    check result.kind == JArray
    check result.len == 1
    check result[0] == %*{"enable": true}

  test "returns null for missing section":
    let settings = %*{"foo": "bar"}
    let params = %*{"items": [{"section": "baz"}]}
    let result = buildWorkspaceConfigurationResponse(params, settings)
    check result.kind == JArray
    check result.len == 1
    check result[0].kind == JNull

  test "returns full settings for empty section":
    let settings = %*{"foo": "bar"}
    let params = %*{"items": [{"section": ""}]}
    let result = buildWorkspaceConfigurationResponse(params, settings)
    check result.kind == JArray
    check result.len == 1
    check result[0] == settings

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

  test "LspEvent levApplyEdit variant":
    let editJson = $(%*{"changes": {"file:///t.nim": []}})
    let evt =
      LspEvent(kind: levApplyEdit, applyEditReqIdJson: "7", applyEditEditJson: editJson)
    check evt.kind == levApplyEdit
    check evt.applyEditReqIdJson == "7"
    check parseJson(evt.applyEditEditJson).hasKey("changes")

suite "LspWorker - notificationToEvents":
  # Regression: a malformed publishDiagnostics frame used to raise KeyError on
  # the raw `params["uri"]` access, unwinding the drain loop and stranding
  # adjacent frames until the next mainLoop tick. It must now resolve to a
  # warning event instead.
  test "publishDiagnostics with valid uri returns a diagnostics event":
    let params = %*{"uri": "file:///t.nim", "diagnostics": [{"message": "x"}]}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levDiagnostics
    check evt.diagUri == "file:///t.nim"
    # Serialized array preserves the diagnostics content
    check parseJson(evt.diagnosticsJson).kind == JArray
    check parseJson(evt.diagnosticsJson).len == 1

  test "publishDiagnostics with missing uri returns a warning, not a raise":
    let params = %*{"diagnostics": []}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levLogMessage
    check evt.msgType == mtWarning
    check "dropping frame" in evt.message

  test "publishDiagnostics with non-string uri returns a warning":
    # A JNumber where a string was expected: getStr defaults to "" and we drop.
    let params = %*{"uri": 42, "diagnostics": []}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levLogMessage
    check evt.msgType == mtWarning

  test "publishDiagnostics without diagnostics field defaults to empty array":
    let params = %*{"uri": "file:///t.nim"}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levDiagnostics
    check evt.diagnosticsJson == "[]"

  test "publishDiagnostics without version leaves diagVersion none":
    let params = %*{"uri": "file:///t.nim", "diagnostics": []}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levDiagnostics
    check evt.diagVersion.isNone

  test "publishDiagnostics with integer version populates diagVersion":
    let params = %*{"uri": "file:///t.nim", "diagnostics": [], "version": 7}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levDiagnostics
    check evt.diagVersion == some(7)

  test "publishDiagnostics with non-integer version is treated as absent":
    # Servers occasionally send an unexpected type; refuse to guess.
    let params = %*{"uri": "file:///t.nim", "diagnostics": [], "version": "3"}
    let evt = notificationToEvents("textDocument/publishDiagnostics", params)
    check evt.kind == levDiagnostics
    check evt.diagVersion.isNone

  test "window/logMessage with missing type defaults to mtLog":
    let params = %*{"message": "hello"}
    let evt = notificationToEvents("window/logMessage", params)
    check evt.kind == levLogMessage
    check evt.msgType == mtLog
    check evt.message == "hello"

  test "window/logMessage with missing message returns empty string":
    let params = %*{"type": 1}
    let evt = notificationToEvents("window/logMessage", params)
    check evt.kind == levLogMessage
    check evt.message == ""

  test "window/showMessage with empty params does not raise":
    let evt = notificationToEvents("window/showMessage", newJObject())
    check evt.kind == levShowMessage
    check evt.message == ""

  test "$/logTrace with only message":
    let params = %*{"message": "trace line"}
    let evt = notificationToEvents("$/logTrace", params)
    check evt.kind == levLogMessage
    check evt.msgType == mtInfo
    check evt.message == "trace line"

  test "$/logTrace with message and verbose concatenates":
    let params = %*{"message": "head", "verbose": "detail"}
    let evt = notificationToEvents("$/logTrace", params)
    check evt.message == "head\ndetail"

  test "$/logTrace without message returns empty message":
    let evt = notificationToEvents("$/logTrace", newJObject())
    check evt.kind == levLogMessage
    check evt.message == ""

  test "experimental/serverStatus with missing health defaults to shOk":
    let evt = notificationToEvents("experimental/serverStatus", newJObject())
    check evt.kind == levStatusUpdate
    check evt.statusHealth == shOk
    check evt.statusQuiescent
    check evt.statusMessage.isNone

  test "experimental/serverStatus maps warning/error strings":
    let warn = notificationToEvents(
      "experimental/serverStatus", %*{"health": "warning", "quiescent": false}
    )
    check warn.statusHealth == shWarning
    check not warn.statusQuiescent
    let err = notificationToEvents(
      "experimental/serverStatus", %*{"health": "error", "message": "boom"}
    )
    check err.statusHealth == shError
    check err.statusMessage == some("boom")

  test "extension/statusUpdate reports warning when projectErrors are present":
    let params = %*{"projectErrors": ["cannot resolve foo"], "pendingRequests": []}
    let evt = notificationToEvents("extension/statusUpdate", params)
    check evt.kind == levStatusUpdate
    check evt.statusHealth == shWarning
    check evt.statusQuiescent
    check evt.statusMessage == some("cannot resolve foo")

  test "extension/statusUpdate with no projectErrors is healthy":
    let params = %*{"projectErrors": [], "pendingRequests": ["req1"]}
    let evt = notificationToEvents("extension/statusUpdate", params)
    check evt.statusHealth == shOk
    check not evt.statusQuiescent
    check evt.statusMessage.isNone

  test "unknown notification method returns an info log event":
    let evt = notificationToEvents("some/unknown", newJObject())
    check evt.kind == levLogMessage
    check evt.msgType == mtInfo
    check "Unknown LSP notification" in evt.message
    check "some/unknown" in evt.message

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

suite "LspWorker - traceLevel construction":
  test "newLspWorker defaults traceLevel to traceOff":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk

  test "newLspWorker accepts traceLevel argument":
    check newLspWorker("nim", traceLevel = traceMessages).isOk
    check newLspWorker("nim", traceLevel = traceVerbose).isOk

  test "LspTrace string values match the LSP `initialize` trace spec":
    # The `initialize` request forwards `$ctx.traceLevel` verbatim to the
    # server, so a rename of the enum variants would silently violate the
    # protocol (which mandates exactly "off" | "messages" | "verbose").
    check $traceOff == "off"
    check $traceMessages == "messages"
    check $traceVerbose == "verbose"

suite "LspWorker - sendRequest (without starting worker)":
  test "sendRequest returns incrementing request ids":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    let id1 = worker.sendRequest("textDocument/completion", "{}")
    let id2 = worker.sendRequest("textDocument/hover", "{}")
    let id3 = worker.sendRequest("textDocument/definition", "{}")

    check id1 == 1
    check id2 == 2
    check id3 == 3

  test "sendRequest with different methods":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    discard worker.sendRequest(
      "textDocument/completion", """{"position":{"line":0,"character":5}}"""
    )
    discard worker.sendRequest(
      "textDocument/hover", """{"textDocument":{"uri":"file:///test.nim"}}"""
    )

  test "sendRequest with explicit caller-provided id":
    # The service allocates IDs from a shared counter so different workers'
    # requests never collide; the worker must use the given ID as-is.
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.sendRequest(42, "textDocument/hover", "{}")
    # The internal counter is unaffected by explicit IDs
    let autoId = worker.sendRequest("textDocument/completion", "{}")
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

  test "isThreadAlive reflects thread state":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    check not worker.isThreadAlive
    worker.start()
    check worker.isThreadAlive
    worker.stop()
    check not worker.isThreadAlive

suite "LspWorker - Server Crash Handling":
  proc waitForState(
      worker: LspWorker, expected: LspWorkerState, timeoutMs = 5000
  ): bool =
    ## Poll until the worker reaches `expected` state or the timeout expires
    let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
    while getMonoTime() < deadline:
      if worker.state == expected:
        return true
      sleep(10)
    false

  test "nonexistent command transitions to lwsCrashed":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.startServer("moe-test-no-such-lsp-server-binary", @[], "/tmp")
    check worker.waitForState(lwsCrashed)
    # Thread survives the server crash and can be asked to start again
    check worker.isThreadAlive
    worker.stop()

  test "server that exits immediately crashes without error spam":
    # `true` exits right away: the initialize read fails once and the worker
    # must transition to lwsCrashed instead of re-arming the read and
    # emitting an error event every tick.
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.startServer("true", @[], "/tmp")
    check worker.waitForState(lwsCrashed)

    # Drain events, then confirm no further errors accumulate
    discard worker.pollEvents()
    sleep(300)
    var lateErrors = 0
    for evt in worker.pollEvents():
      if evt.kind == levError:
        inc lateErrors
    check lateErrors == 0
    worker.stop()

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

  test "didChangeFull queues command":
    let workerResult = newLspWorker("nim")
    check workerResult.isOk
    let worker = workerResult.get

    worker.start()
    worker.didChangeFull("file:///test.nim", 2, "echo \"updated\"")
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
