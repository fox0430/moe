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

## Integration tests for LSP client using lasm (LSP mock server)
## These tests require lasm to be installed: https://github.com/fox0430/lasm

import std/[unittest, json, options, os, osproc, strutils]

import pkg/chronos

import ../src/moepkg/lsp/client
import ../src/moepkg/lsp/protocol/types

const
  LasmCommand = "lasm"
  TestTimeout = 5.seconds
  # Path to lasm test config (relative to source file)
  TestConfigPath = currentSourcePath().parentDir / "lasm_test_config.json"

# Cache lasm availability check
var lasmAvailableCache: Option[bool] = none(bool)

proc lasmAvailable(): bool =
  if lasmAvailableCache.isNone:
    let (output, exitCode) = execCmdEx("which " & LasmCommand)
    lasmAvailableCache = some(exitCode == 0 and output.strip.len > 0)
  result = lasmAvailableCache.get

proc waitForInit(client: LspClient): Future[bool] {.async.} =
  ## Wait for client initialization to complete
  let deadline = Moment.now() + TestTimeout
  while Moment.now() < deadline:
    if client.checkInitComplete():
      return client.state == lssRunning
    await sleepAsync(10.milliseconds)
  return false

proc waitForReady(client: LspClient): Future[bool] {.async.} =
  ## Wait for client to be fully ready
  let deadline = Moment.now() + TestTimeout
  while Moment.now() < deadline:
    if client.isReady:
      return true
    if client.state == lssCrashed:
      return false
    if client.checkInitComplete():
      if client.needsSendInitialized:
        let r = await client.sendNotification("initialized", %*{})
        if r.isOk:
          client.needsSendInitialized = false
    await sleepAsync(10.milliseconds)
  return false

# Helper to run async tests
template asyncTest(name: string, body: untyped) =
  test name:
    proc asyncBody() {.async: (raises: [Exception]).} =
      body

    waitFor asyncBody()

suite "LspClient Integration - Server Lifecycle":
  asyncTest "start and stop server":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()

      # Wait for initialization
      let initOk = await waitForInit(client)
      check initOk
      check client.state == lssRunning

      # Send initialized notification
      if client.needsSendInitialized:
        let r = await client.sendNotification("initialized", %*{})
        check r.isOk
        client.needsSendInitialized = false

      # Stop the server
      let stopResult = await client.stop()
      check stopResult.isOk
      check client.state == lssStopped

  asyncTest "startInBackground initializes correctly":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      client.startInBackground()

      # Wait for initialization
      let initOk = await waitForInit(client)
      check initOk
      check client.state == lssRunning

      # Cleanup
      discard await client.stop()

  asyncTest "kill forcefully terminates server":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let initOk = await waitForInit(client)
      check initOk

      # Kill the server
      client.kill()
      check client.state == lssStopped
      check not client.running

  asyncTest "server info is populated after init":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let initOk = await waitForInit(client)
      check initOk
      check client.capabilities.isSome

      # Cleanup
      client.kill()

  asyncTest "starting already started client sets error":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let initOk = await waitForInit(client)
      check initOk

      # Try to start again
      await client.startAsync()
      check client.initError == "Client already started"

      # Cleanup
      client.kill()

suite "LspClient Integration - Document Synchronization":
  asyncTest "didOpen notification":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      let r = await client.didOpen("file:///test.nim", "nim", 1, "echo \"Hello\"")
      check r.isOk

      client.kill()

  asyncTest "didClose notification":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      # Open first
      discard await client.didOpen("file:///test.nim", "nim", 1, "echo \"Hello\"")

      # Then close
      let r = await client.didClose("file:///test.nim")
      check r.isOk

      client.kill()

  asyncTest "didChange notification":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      # Open first
      discard await client.didOpen("file:///test.nim", "nim", 1, "echo \"Hello\"")

      # Then change
      let r = await client.didChange("file:///test.nim", 2, "echo \"World\"")
      check r.isOk

      client.kill()

  asyncTest "didSave notification":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      # Open first
      discard await client.didOpen("file:///test.nim", "nim", 1, "echo \"Hello\"")

      # Then save
      let r = await client.didSave("file:///test.nim")
      check r.isOk

      client.kill()

  asyncTest "didSave with text":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      # Open first
      discard await client.didOpen("file:///test.nim", "nim", 1, "echo \"Hello\"")

      # Save with text
      let r = await client.didSave("file:///test.nim", some("echo \"Hello\""))
      check r.isOk

      client.kill()

suite "LspClient Integration - LSP Features":
  asyncTest "completion request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      # Open a document first
      discard await client.didOpen("file:///test.nim", "nim", 1, "echo test")

      # Request completion
      let r = await client.completion("file:///test.nim", 0, 5)
      check r.isOk
      let items = r.get
      check items.len >= 1
      check items[0].label == "testFunc"

      client.kill()

  asyncTest "hover request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      let r = await client.hover("file:///test.nim", 0, 0)
      check r.isOk
      let hover = r.get
      check hover.isSome

      client.kill()

  asyncTest "gotoDefinition request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "proc test()")

      let r = await client.gotoDefinition("file:///test.nim", 0, 5)
      check r.isOk
      let locations = r.get
      check locations.len >= 1
      check locations[0].uri == "file:///test/definition.nim"

      client.kill()

  asyncTest "gotoDeclaration request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "proc test()")

      let r = await client.gotoDeclaration("file:///test.nim", 0, 5)
      check r.isOk
      let locations = r.get
      check locations.len >= 1
      check locations[0].uri == "file:///test/declaration.nim"

      client.kill()

  asyncTest "references request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      let r = await client.references("file:///test.nim", 0, 4)
      check r.isOk
      let locations = r.get
      check locations.len >= 2

      client.kill()

  asyncTest "documentHighlight request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      let r = await client.documentHighlight("file:///test.nim", 0, 4)
      check r.isOk
      let highlights = r.get
      check highlights.len >= 1

      client.kill()

  asyncTest "formatting request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "echo   test")

      let r = await client.formatting("file:///test.nim")
      check r.isOk
      let edits = r.get
      check edits.len >= 1

      client.kill()

  asyncTest "inlayHints request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      let r = await client.inlayHints("file:///test.nim", 0, 0, 10, 0)
      check r.isOk
      # lasm config has inlayHint enabled with hints
      let hints = r.get
      check hints.len >= 1

      client.kill()

  asyncTest "semanticTokensFull request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "proc test()")

      let r = await client.semanticTokensFull("file:///test.nim")
      check r.isOk
      # lasm config has semanticTokens enabled with tokens
      let tokens = r.get
      check tokens.isSome

      client.kill()

suite "LspClient Integration - Notifications":
  asyncTest "diagnostics notification callback":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      client.onDiagnostics = proc(
          uri: string, diagnostics: seq[Diagnostic]
      ) {.gcsafe, raises: [].} =
        discard

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready
      check not client.onDiagnostics.isNil

      # Open a document to trigger diagnostics
      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      # Wait a bit for diagnostics to arrive and poll
      await sleepAsync(500.milliseconds)
      await client.poll()

      client.kill()

  asyncTest "log message notification callback":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      client.onLogMessage = proc(
          msgType: MessageType, message: string
      ) {.gcsafe, raises: [].} =
        discard

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready
      check not client.onLogMessage.isNil

      client.kill()

suite "LspClient Integration - Error Handling":
  asyncTest "invalid command fails gracefully":
    let client = newLspClient("nim", "nonexistent-lsp-server-command-xyz", @[], "/tmp")

    await client.startAsync()

    # Should fail to start
    check client.state == lssCrashed
    check client.initError.len > 0

  asyncTest "request on stopped client returns error":
    # No lasm needed - testing client behavior without server
    let client = newLspClient("nim", "dummy-server", @[], "/tmp")

    # Try to send request without starting
    let r = await client.sendRequest("test", %*{})
    check r.isErr
    check r.error == "Client not running"

  asyncTest "notification on stopped client returns error":
    # No lasm needed - testing client behavior without server
    let client = newLspClient("nim", "dummy-server", @[], "/tmp")

    # Try to send notification without starting
    let r = await client.sendNotification("test", %*{})
    check r.isErr
    check r.error == "Client not running"

  asyncTest "didOpen on uninitialized client returns error":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      # Don't wait for init to complete

      # capabilities not set yet
      let r = await client.didOpen("file:///test.nim", "nim", 1, "test")
      check r.isErr
      check r.error == "Client not initialized"

      client.kill()

suite "LspClient Integration - sendAndWait":
  asyncTest "sendAndWait on stopped client returns error":
    # No lasm needed - testing client behavior without server
    let client = newLspClient("nim", "dummy-server", @[], "/tmp")

    let r = await client.sendAndWait("test/method", %*{})
    check r.isErr
    check r.error == "Client not running"

  asyncTest "sendAndWait returns result for valid request":
    if not lasmAvailable():
      skip()
    else:
      let client =
        newLspClient("nim", LasmCommand, @["--config", TestConfigPath], "/tmp")

      await client.startAsync()
      let ready = await waitForReady(client)
      check ready

      discard await client.didOpen("file:///test.nim", "nim", 1, "let x = 1")

      # Use completion as a test for sendAndWait
      let r = await client.sendAndWait(
        "textDocument/completion",
        %*{
          "textDocument": {"uri": "file:///test.nim"},
          "position": {"line": 0, "character": 5},
        },
      )
      check r.isOk

      client.kill()
