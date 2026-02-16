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

import std/[unittest, json, options, os, tables]

import ../src/moepkg/lsp/client
import ../src/moepkg/lsp/protocol/types

suite "LspClient - newLspClient":
  test "creates client with default values":
    let client = newLspClient("nim", "lasm")
    check client.state == lssStopped
    check client.languageId == "nim"
    check client.serverCommand == "lasm"
    check client.serverArgs.len == 0
    check client.workspaceRoot == getCurrentDir()
    check client.capabilities.isNone
    check client.serverInfo.isNone
    check client.waitingResponses.len == 0
    check not client.needsSendInitialized
    check client.initError == ""

  test "creates client with custom args":
    let client = newLspClient("nim", "lasm", @["--stdio", "--debug"])
    check client.serverArgs == @["--stdio", "--debug"]

  test "creates client with custom workspace root":
    let client = newLspClient("nim", "lasm", @[], "/tmp/test")
    check client.workspaceRoot == "/tmp/test"

  test "creates client with empty workspace root uses current dir":
    let client = newLspClient("nim", "lasm", @[], "")
    check client.workspaceRoot == getCurrentDir()

suite "LspClient - State Checks":
  test "isStopped returns true for stopped client":
    let client = newLspClient("nim", "lasm")
    check client.isStopped
    check client.state == lssStopped

  test "isStopped returns false for non-stopped client":
    let client = newLspClient("nim", "lasm")
    client.state = lssRunning
    check not client.isStopped

  test "isStarting returns true for starting client":
    let client = newLspClient("nim", "lasm")
    client.state = lssStarting
    check client.isStarting

  test "isStarting returns false for non-starting client":
    let client = newLspClient("nim", "lasm")
    check not client.isStarting

  test "isInitialized returns true when capabilities set":
    let client = newLspClient("nim", "lasm")
    client.capabilities = some(ServerCapabilities())
    check client.isInitialized

  test "isInitialized returns false when no capabilities":
    let client = newLspClient("nim", "lasm")
    check not client.isInitialized

  test "running returns false when serverProcess is nil":
    let client = newLspClient("nim", "lasm")
    check not client.running

  test "isRunning returns false when stopped":
    let client = newLspClient("nim", "lasm")
    check not client.isRunning

  test "isReady returns false when not fully initialized":
    let client = newLspClient("nim", "lasm")
    check not client.isReady

  test "canSend returns false when stopped":
    let client = newLspClient("nim", "lasm")
    check not client.canSend

  test "readable returns false when outputStreamFuture is nil":
    let client = newLspClient("nim", "lasm")
    let r = client.readable()
    check r.isOk
    check r.get == false

suite "LspClient - Waiting Response Management":
  test "getWaitingResponse returns none for unknown id":
    let client = newLspClient("nim", "lasm")
    let result = client.getWaitingResponse(999)
    check result.isNone

  test "getWaitingResponse returns response after adding":
    let client = newLspClient("nim", "lasm")
    let id = 1
    client.waitingResponses[id] =
      WaitingResponse(id: id, methodName: "textDocument/completion")
    let result = client.getWaitingResponse(id)
    check result.isSome
    check result.get.id == id
    check result.get.methodName == "textDocument/completion"

  test "deleteWaitingResponse removes existing response":
    let client = newLspClient("nim", "lasm")
    let id = 1
    client.waitingResponses[id] = WaitingResponse(id: id, methodName: "test")
    check client.waitingResponses.len == 1
    client.deleteWaitingResponse(id)
    check client.waitingResponses.len == 0

  test "deleteWaitingResponse handles non-existent id":
    let client = newLspClient("nim", "lasm")
    client.deleteWaitingResponse(999)
    check client.waitingResponses.len == 0

  test "multiple waiting responses tracked separately":
    let client = newLspClient("nim", "lasm")
    client.waitingResponses[1] = WaitingResponse(id: 1, methodName: "method1")
    client.waitingResponses[2] = WaitingResponse(id: 2, methodName: "method2")
    client.waitingResponses[3] = WaitingResponse(id: 3, methodName: "method3")
    check client.waitingResponses.len == 3

    client.deleteWaitingResponse(2)
    check client.waitingResponses.len == 2
    check client.getWaitingResponse(1).isSome
    check client.getWaitingResponse(2).isNone
    check client.getWaitingResponse(3).isSome

suite "LspClient - handleNotification":
  test "handles publishDiagnostics with callback":
    let client = newLspClient("nim", "lasm")
    var receivedUri: string
    var receivedDiagnostics: seq[Diagnostic]

    client.onDiagnostics = proc(
        uri: string, diagnostics: seq[Diagnostic]
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedUri = uri
        receivedDiagnostics = diagnostics

    let params = %*{
      "uri": "file:///test.nim",
      "diagnostics": [
        {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
          "severity": 1,
          "message": "Error message",
        }
      ],
    }

    client.handleNotification("textDocument/publishDiagnostics", params)
    check receivedUri == "file:///test.nim"
    check receivedDiagnostics.len == 1
    check receivedDiagnostics[0].message == "Error message"

  test "handles publishDiagnostics without diagnostics key":
    let client = newLspClient("nim", "lasm")
    var receivedDiagnostics: seq[Diagnostic]

    client.onDiagnostics = proc(
        uri: string, diagnostics: seq[Diagnostic]
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedDiagnostics = diagnostics

    let params = %*{"uri": "file:///test.nim"}

    client.handleNotification("textDocument/publishDiagnostics", params)
    check receivedDiagnostics.len == 0

  test "handles publishDiagnostics without callback (no crash)":
    let client = newLspClient("nim", "lasm")
    let params = %*{"uri": "file:///test.nim", "diagnostics": []}
    # Should not crash
    client.handleNotification("textDocument/publishDiagnostics", params)

  test "handles window/logMessage with callback":
    let client = newLspClient("nim", "lasm")
    var receivedType: MessageType
    var receivedMessage: string

    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedType = msgType
        receivedMessage = message

    let params = %*{"type": 3, "message": "Info message"}

    client.handleNotification("window/logMessage", params)
    check receivedType == mtInfo
    check receivedMessage == "Info message"

  test "handles window/showMessage with callback":
    let client = newLspClient("nim", "lasm")
    var receivedType: MessageType
    var receivedMessage: string

    client.onShowMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedType = msgType
        receivedMessage = message

    let params = %*{"type": 1, "message": "Error message"}

    client.handleNotification("window/showMessage", params)
    check receivedType == mtError
    check receivedMessage == "Error message"

  test "handles $/logTrace with callback":
    let client = newLspClient("nim", "lasm")
    var receivedMessage: string

    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedMessage = message

    let params = %*{"message": "Trace message"}

    client.handleNotification("$/logTrace", params)
    check receivedMessage == "Trace message"

  test "handles $/logTrace with verbose":
    let client = newLspClient("nim", "lasm")
    var receivedMessage: string

    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedMessage = message

    let params = %*{"message": "Trace message", "verbose": "Verbose details"}

    client.handleNotification("$/logTrace", params)
    check receivedMessage == "Trace message\nVerbose details"

  test "unknown notification does not crash":
    let client = newLspClient("nim", "lasm")
    let params = %*{"key": "value"}
    # Should not crash
    client.handleNotification("unknown/notification", params)

  test "handles malformed publishDiagnostics gracefully":
    let client = newLspClient("nim", "lasm")
    # Missing "uri" key
    let params = %*{"diagnostics": []}
    # Should not crash
    client.handleNotification("textDocument/publishDiagnostics", params)

  test "handles malformed logMessage gracefully":
    let client = newLspClient("nim", "lasm")
    var callbackCalled = false
    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        callbackCalled = true

    # Missing "type" and "message" keys
    let params = %*{"invalid": "data"}
    # Should not crash
    client.handleNotification("window/logMessage", params)
    check not callbackCalled # Callback not called due to error

  test "handles malformed showMessage gracefully":
    let client = newLspClient("nim", "lasm")
    # Missing required keys
    let params = %*{}
    # Should not crash
    client.handleNotification("window/showMessage", params)

  test "handles malformed diagnostics in array gracefully":
    let client = newLspClient("nim", "lasm")
    var receivedDiagnostics: seq[Diagnostic]
    client.onDiagnostics = proc(
        uri: string, diagnostics: seq[Diagnostic]
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedDiagnostics = diagnostics

    # Malformed diagnostic entry (missing range)
    let params = %*{"uri": "file:///test.nim", "diagnostics": [{"message": "Error"}]}
    # Should not crash
    client.handleNotification("textDocument/publishDiagnostics", params)

suite "LspClient - processResponse":
  test "processes response and returns request id":
    let client = newLspClient("nim", "lasm")
    client.waitingResponses[1] = WaitingResponse(id: 1, methodName: "test")

    let response = %*{"jsonrpc": "2.0", "id": 1, "result": {"key": "value"}}

    let result = client.processResponse(response)
    check result.isSome
    check result.get == 1
    check client.waitingResponses.len == 0

  test "processes notification and returns none":
    let client = newLspClient("nim", "lasm")
    var notificationReceived = false

    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        notificationReceived = true

    let notification = %*{
      "jsonrpc": "2.0",
      "method": "window/logMessage",
      "params": {"type": 3, "message": "test"},
    }

    let result = client.processResponse(notification)
    check result.isNone
    check notificationReceived

  test "processes request (notification with id) and returns none":
    let client = newLspClient("nim", "lasm")

    # A request has both "id" and "method" fields
    let request = %*{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "window/showMessageRequest",
      "params": {"type": 1, "message": "test"},
    }

    # processResponse should treat this as a notification (has method)
    let result = client.processResponse(request)
    check result.isNone

  test "processes response with unknown id":
    let client = newLspClient("nim", "lasm")
    # No waiting response registered for id 999
    let response = %*{"jsonrpc": "2.0", "id": 999, "result": {"key": "value"}}

    let result = client.processResponse(response)
    check result.isSome
    check result.get == 999

  test "processes error response":
    let client = newLspClient("nim", "lasm")
    client.waitingResponses[1] = WaitingResponse(id: 1, methodName: "test")

    let response = %*{
      "jsonrpc": "2.0", "id": 1, "error": {"code": -32600, "message": "Invalid Request"}
    }

    # Error responses are still processed as responses (have id, no method)
    let result = client.processResponse(response)
    check result.isSome
    check result.get == 1
    check client.waitingResponses.len == 0

  test "processes notification without params":
    let client = newLspClient("nim", "lasm")
    var callbackCalled = false
    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        callbackCalled = true

    # Notification without params key
    let notification = %*{"jsonrpc": "2.0", "method": "window/logMessage"}

    let result = client.processResponse(notification)
    check result.isNone
    # Callback may or may not be called depending on params handling

suite "LspClient - checkInitComplete":
  test "returns true when not in starting state":
    let client = newLspClient("nim", "lasm")
    client.state = lssRunning
    check client.checkInitComplete

  test "returns true when no pending init request (stopped state)":
    let client = newLspClient("nim", "lasm")
    # In stopped state, there's no pending init request
    check client.checkInitComplete

suite "LspClient - LspServerState enum":
  test "state enum values":
    check lssStopped < lssStarting
    check lssStarting < lssRunning
    check lssRunning < lssShuttingDown
    check lssShuttingDown < lssCrashed

suite "LspClient - checkInitComplete extended":
  test "returns false when starting with pending request but nil future":
    let client = newLspClient("nim", "lasm")
    client.state = lssStarting
    client.pendingInitRequest = some(1)
    # outputStreamFuture is nil
    check not client.checkInitComplete

  test "returns true when starting but no pending request":
    let client = newLspClient("nim", "lasm")
    client.state = lssStarting
    client.pendingInitRequest = none(int)
    check client.checkInitComplete

  test "returns true for crashed state":
    let client = newLspClient("nim", "lasm")
    client.state = lssCrashed
    check client.checkInitComplete

  test "returns true for shutting down state":
    let client = newLspClient("nim", "lasm")
    client.state = lssShuttingDown
    check client.checkInitComplete

suite "LspClient - State Combinations":
  test "isRunning requires both running state and process":
    let client = newLspClient("nim", "lasm")
    # State is running but no process
    client.state = lssRunning
    check not client.isRunning # False because running() returns false

  test "isReady requires running state, process, and capabilities":
    let client = newLspClient("nim", "lasm")
    # Only state is running
    client.state = lssRunning
    check not client.isReady

    # State is running and has capabilities, but no process
    client.capabilities = some(ServerCapabilities())
    check not client.isReady

  test "canSend works for starting state":
    let client = newLspClient("nim", "lasm")
    client.state = lssStarting
    # Still false because running() returns false (no process)
    check not client.canSend

  test "canSend returns false for shutting down":
    let client = newLspClient("nim", "lasm")
    client.state = lssShuttingDown
    check not client.canSend

  test "canSend returns false for crashed":
    let client = newLspClient("nim", "lasm")
    client.state = lssCrashed
    check not client.canSend

suite "LspClient - State Transitions":
  test "initial state is stopped":
    let client = newLspClient("nim", "lasm")
    check client.state == lssStopped
    check client.isStopped
    check not client.isStarting
    check not client.isRunning
    check not client.isReady

  test "starting state flags":
    let client = newLspClient("nim", "lasm")
    client.state = lssStarting
    check not client.isStopped
    check client.isStarting
    check not client.isRunning
    check not client.isReady

  test "running state without capabilities":
    let client = newLspClient("nim", "lasm")
    client.state = lssRunning
    check not client.isStopped
    check not client.isStarting
    check not client.isInitialized
    check not client.isReady

  test "running state with capabilities":
    let client = newLspClient("nim", "lasm")
    client.state = lssRunning
    client.capabilities = some(ServerCapabilities())
    check client.isInitialized
    # isReady still false because running() returns false (no process)
    check not client.isReady

  test "crashed state":
    let client = newLspClient("nim", "lasm")
    client.state = lssCrashed
    check not client.isStopped
    check not client.isStarting
    check not client.isRunning
    check not client.isReady

  test "shutting down state":
    let client = newLspClient("nim", "lasm")
    client.state = lssShuttingDown
    check not client.isStopped
    check not client.isStarting
    check not client.isRunning
    check not client.isReady

suite "LspClient - Error Flags":
  test "initError is empty initially":
    let client = newLspClient("nim", "lasm")
    check client.initError == ""

  test "initError can be set":
    let client = newLspClient("nim", "lasm")
    client.initError = "Failed to start server"
    check client.initError == "Failed to start server"

  test "needsSendInitialized is false initially":
    let client = newLspClient("nim", "lasm")
    check not client.needsSendInitialized

  test "needsSendInitialized can be set":
    let client = newLspClient("nim", "lasm")
    client.needsSendInitialized = true
    check client.needsSendInitialized

suite "LspClient - Callback Registration":
  test "callbacks are nil initially":
    let client = newLspClient("nim", "lasm")
    check client.onDiagnostics.isNil
    check client.onLogMessage.isNil
    check client.onShowMessage.isNil

  test "can set onDiagnostics callback":
    let client = newLspClient("nim", "lasm")
    var called = false
    client.onDiagnostics = proc(
        uri: string, diagnostics: seq[Diagnostic]
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        called = true
    check not client.onDiagnostics.isNil

  test "can set onLogMessage callback":
    let client = newLspClient("nim", "lasm")
    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      discard
    check not client.onLogMessage.isNil

  test "can set onShowMessage callback":
    let client = newLspClient("nim", "lasm")
    client.onShowMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      discard
    check not client.onShowMessage.isNil

suite "LspClient - ServerInfo and Capabilities":
  test "serverInfo is none initially":
    let client = newLspClient("nim", "lasm")
    check client.serverInfo.isNone

  test "can set serverInfo":
    let client = newLspClient("nim", "lasm")
    client.serverInfo = some(ServerInfo(name: "test-server", version: some("1.0.0")))
    check client.serverInfo.isSome
    check client.serverInfo.get.name == "test-server"
    check client.serverInfo.get.version.get == "1.0.0"

  test "capabilities is none initially":
    let client = newLspClient("nim", "lasm")
    check client.capabilities.isNone
    check not client.isInitialized

  test "setting capabilities marks client as initialized":
    let client = newLspClient("nim", "lasm")
    client.capabilities = some(ServerCapabilities())
    check client.capabilities.isSome
    check client.isInitialized

suite "LspClient - MessageType enum":
  test "MessageType values":
    check mtError.int == 1
    check mtWarning.int == 2
    check mtInfo.int == 3
    check mtLog.int == 4

  test "handleNotification parses MessageType correctly":
    let client = newLspClient("nim", "lasm")
    var receivedTypes: seq[MessageType]

    client.onLogMessage = proc(
        msgType: MessageType, message: string
    ) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        receivedTypes.add(msgType)

    # Test each message type
    for typeVal in [1, 2, 3, 4]:
      let params = %*{"type": typeVal, "message": "test"}
      client.handleNotification("window/logMessage", params)

    check receivedTypes.len == 4
    check receivedTypes[0] == mtError
    check receivedTypes[1] == mtWarning
    check receivedTypes[2] == mtInfo
    check receivedTypes[3] == mtLog
