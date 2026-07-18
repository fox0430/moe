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

## End-to-end tests that drive LspService against a real LSP process.
##
## The counterpart server is `lasm` (fox0430/lasm), a scriptable mock LSP that
## answers per a JSON scenario. Each test spins up a fresh service+worker
## against the same shared scenario file, then exercises a single LSP feature.
##
## The whole suite auto-skips when `lasm` is not on PATH so contributors and
## CI jobs without it stay green.

import std/[unittest, json, options, os, osproc, strutils, tables, times]

import pkg/[chronos, results]

import ../src/moepkg/lsp_service
import ../src/moepkg/lsp/protocol/[types, enums]

const
  LasmBin = "lasm"
  LangId = "dummy"
  Ext = "dummy"
  ReadyTimeoutMs = 10_000
  RequestTimeoutMs = 5_000
  DiagnosticsWaitMs = 3_000
  SampleText = "abc\ndef\nghi\n"

proc lasmAvailable(): bool =
  findExe(LasmBin).len > 0

proc scenarioJson(): string =
  # A single scenario that enables every feature the suite exercises. lasm
  # returns configured payloads verbatim, so callers just need to know the
  # shape below to write assertions.
  """
{
  "currentScenario": "moe-e2e",
  "scenarios": {
    "moe-e2e": {
      "name": "moe e2e all features",
      "hover": {
        "enabled": true,
        "contents": [
          {
            "kind": "plaintext",
            "message": "hello from lasm",
            "position": { "line": 0, "character": 0 }
          }
        ]
      },
      "completion": {
        "enabled": true,
        "isIncomplete": false,
        "items": [
          {
            "label": "println",
            "kind": 3,
            "detail": "func println(message: string)",
            "insertText": "println(${1:message})"
          },
          {
            "label": "variable",
            "kind": 6,
            "detail": "var variable: int",
            "insertText": "variable"
          }
        ]
      },
      "definition": {
        "enabled": true,
        "location": {
          "uri": "file:///path/to/definition.dummy",
          "range": {
            "start": { "line": 25, "character": 2 },
            "end":   { "line": 25, "character": 12 }
          }
        }
      },
      "references": {
        "enabled": true,
        "includeDeclaration": true,
        "locations": [
          {
            "uri": "file:///path/to/reference1.dummy",
            "range": {
              "start": { "line": 15, "character": 8 },
              "end":   { "line": 15, "character": 18 }
            }
          },
          {
            "uri": "file:///path/to/reference2.dummy",
            "range": {
              "start": { "line": 42, "character": 12 },
              "end":   { "line": 42, "character": 22 }
            }
          }
        ]
      },
      "documentHighlight": {
        "enabled": true,
        "highlights": [
          {
            "range": {
              "start": { "line": 10, "character": 5 },
              "end":   { "line": 10, "character": 15 }
            },
            "kind": 1
          },
          {
            "range": {
              "start": { "line": 20, "character": 8 },
              "end":   { "line": 20, "character": 18 }
            },
            "kind": 2
          }
        ]
      },
      "rename": {
        "enabled": true,
        "workspaceEdit": {
          "changes": [
            {
              "uri": "file:///path/to/file.dummy",
              "edits": [
                {
                  "range": {
                    "start": { "line": 5, "character": 10 },
                    "end":   { "line": 5, "character": 18 }
                  },
                  "newText": "${newName}"
                }
              ]
            }
          ]
        }
      },
      "diagnostics": {
        "enabled": true,
        "diagnostics": [
          {
            "range": {
              "start": { "line": 2, "character": 10 },
              "end":   { "line": 2, "character": 20 }
            },
            "severity": 1,
            "code": "E001",
            "source": "lasm",
            "message": "Undefined variable 'testVar'"
          },
          {
            "range": {
              "start": { "line": 5, "character": 0 },
              "end":   { "line": 5, "character": 5 }
            },
            "severity": 2,
            "code": "W001",
            "source": "lasm",
            "message": "Function 'oldFunc' is deprecated"
          }
        ]
      },
      "declaration": {
        "enabled": true,
        "location": {
          "uri": "file:///path/to/declaration.dummy",
          "range": {
            "start": { "line": 10, "character": 5 },
            "end":   { "line": 10, "character": 15 }
          }
        }
      },
      "typeDefinition": {
        "enabled": true,
        "location": {
          "uri": "file:///path/to/type.dummy",
          "range": {
            "start": { "line": 8, "character": 0 },
            "end":   { "line": 8, "character": 10 }
          }
        }
      },
      "implementation": {
        "enabled": true,
        "location": {
          "uri": "file:///path/to/implementation.dummy",
          "range": {
            "start": { "line": 30, "character": 0 },
            "end":   { "line": 30, "character": 20 }
          }
        }
      },
      "inlayHint": {
        "enabled": true,
        "hints": [
          {
            "position": { "line": 1, "character": 20 },
            "label": ": string",
            "kind": 1,
            "paddingLeft": false,
            "paddingRight": false
          },
          {
            "position": { "line": 3, "character": 15 },
            "label": " -> void",
            "kind": 1,
            "paddingLeft": true,
            "paddingRight": false
          }
        ]
      },
      "semanticTokens": {
        "enabled": true,
        "tokens": [
          0, 0, 8, 14, 0,
          0, 9, 4, 12, 1,
          1, 2, 3, 6, 0,
          0, 4, 4, 15, 0
        ]
      },
      "prepareCallHierarchy": {
        "enabled": true,
        "items": [
          {
            "name": "myFunction",
            "kind": 12,
            "detail": "proc myFunction()",
            "uri": "file:///path/to/file.dummy",
            "range": {
              "start": { "line": 10, "character": 5 },
              "end":   { "line": 10, "character": 15 }
            },
            "selectionRange": {
              "start": { "line": 10, "character": 5 },
              "end":   { "line": 10, "character": 15 }
            }
          }
        ]
      },
      "callHierarchyIncoming": {
        "enabled": true,
        "calls": [
          {
            "from": {
              "name": "callerFunction",
              "kind": 12,
              "uri": "file:///path/to/caller.dummy",
              "range": {
                "start": { "line": 5, "character": 0 },
                "end":   { "line": 8, "character": 1 }
              },
              "selectionRange": {
                "start": { "line": 5, "character": 5 },
                "end":   { "line": 5, "character": 19 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 6, "character": 2 },
                "end":   { "line": 6, "character": 12 }
              }
            ]
          }
        ]
      },
      "callHierarchyOutgoing": {
        "enabled": true,
        "calls": [
          {
            "to": {
              "name": "calleeFunction",
              "kind": 12,
              "uri": "file:///path/to/callee.dummy",
              "range": {
                "start": { "line": 20, "character": 0 },
                "end":   { "line": 23, "character": 1 }
              },
              "selectionRange": {
                "start": { "line": 20, "character": 5 },
                "end":   { "line": 20, "character": 19 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 11, "character": 2 },
                "end":   { "line": 11, "character": 16 }
              }
            ]
          }
        ]
      },
      "formatting": {
        "enabled": true,
        "edits": [
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end":   { "line": 1, "character": 20 }
            },
            "newText": "formatted line 1"
          },
          {
            "range": {
              "start": { "line": 5, "character": 2 },
              "end":   { "line": 5, "character": 10 }
            },
            "newText": "    return;"
          }
        ]
      }
    }
  }
}
"""

type LasmHandle = object
  svc*: LspService
  filePath*: string
  workspace*: string
  cfgPath*: string

proc waitUntilReady(svc: LspService, langId: string, timeoutMs: int): bool =
  let deadline = epochTime() + timeoutMs.float / 1000.0
  while epochTime() < deadline:
    svc.poll()
    if svc.isWorkerReady(langId):
      return true
    sleep(20)
  return false

proc startLasmWith(cfg: string, text: string = SampleText): LasmHandle =
  let workspace = getTempDir() / "moe-lasm-e2e"
  createDir(workspace)
  let cfgPath = workspace / "lasm.json"
  let filePath = workspace / ("sample." & Ext)
  writeFile(cfgPath, cfg)
  writeFile(filePath, text)

  let svc = newLspService(workspace)
  svc.setConfig(
    LangId,
    LanguageServerConfig(
      command: LasmBin, args: @["--config", cfgPath], extensions: @[Ext], enabled: true
    ),
  )

  doAssert svc.startWorker(LangId).isOk
  doAssert waitUntilReady(svc, LangId, ReadyTimeoutMs), "lasm did not become ready"
  doAssert svc.notifyDocumentOpened(filePath, text).isOk

  LasmHandle(svc: svc, filePath: filePath, workspace: workspace, cfgPath: cfgPath)

proc startLasm(): LasmHandle =
  startLasmWith(scenarioJson())

proc slowHoverScenario(delayMs: int): string =
  ## Same shape as scenarioJson but only wires hover, with an injected
  ## per-request delay so the caller can drive the timeout path deterministically.
  """
{
  "currentScenario": "slow",
  "scenarios": {
    "slow": {
      "name": "slow hover",
      "hover": {
        "enabled": true,
        "contents": [
          {
            "kind": "plaintext",
            "message": "slow reply",
            "position": { "line": 0, "character": 0 }
          }
        ]
      },
      "delays": {
        "hover": """ &
    $delayMs & """
      }
    }
  }
}
"""

proc twoHoverScenariosJson(): string =
  ## Two scenarios that differ only in the hover payload. The test switches
  ## between them via `workspace/executeCommand` (lasm's `lsptest.switchScenario`).
  """
{
  "currentScenario": "s1",
  "scenarios": {
    "s1": {
      "name": "s1",
      "hover": {
        "enabled": true,
        "contents": [
          {
            "kind": "plaintext",
            "message": "reply from s1",
            "position": { "line": 0, "character": 0 }
          }
        ]
      }
    },
    "s2": {
      "name": "s2",
      "hover": {
        "enabled": true,
        "contents": [
          {
            "kind": "plaintext",
            "message": "reply from s2",
            "position": { "line": 0, "character": 0 }
          }
        ]
      }
    }
  }
}
"""

proc simpleHoverScenario(msg: string): string =
  ## Minimal scenario used by the reload test. Built via `%*` so `msg` is JSON
  ## escaped automatically.
  let node = %*{
    "currentScenario": "s",
    "scenarios": {
      "s": {
        "name": "s",
        "hover": {
          "enabled": true,
          "contents": [
            {
              "kind": "plaintext",
              "message": msg,
              "position": {"line": 0, "character": 0},
            }
          ],
        },
      }
    },
  }
  $node

proc errorInjectedHoverScenario(): string =
  ## Enables hover but registers an errors.hover override so the server raises
  ## an LSP error response instead of returning payload.
  """
{
  "currentScenario": "err",
  "scenarios": {
    "err": {
      "name": "hover error",
      "hover": {
        "enabled": true,
        "contents": [
          {
            "kind": "plaintext",
            "message": "never returned",
            "position": { "line": 0, "character": 0 }
          }
        ]
      },
      "errors": {
        "hover": { "code": -32603, "message": "Injected failure" }
      }
    }
  }
}
"""

proc awaitExecuteCommand(
    svc: LspService, path, command: string, arguments: seq[JsonNode]
): Result[JsonNode, string] =
  proc runner(): Future[Result[JsonNode, string]] {.async.} =
    return await svc.requestExecuteCommand(path, command, arguments)

  waitFor runner()

proc stopLasm(h: LasmHandle) =
  discard h.svc.stopWorker(LangId)

proc awaitResponse(
    svc: LspService, id: int, timeoutMs: int = RequestTimeoutMs
): Result[JsonNode, string] =
  proc runner(): Future[Result[JsonNode, string]] {.async.} =
    return await svc.waitForResponse(id, timeoutMs)

  waitFor runner()

proc awaitResponseRaw(
    svc: LspService, id: int, timeoutMs: int = RequestTimeoutMs
): Result[string, string] =
  proc runner(): Future[Result[string, string]] {.async.} =
    return await svc.waitForResponseRaw(id, timeoutMs)

  waitFor runner()

var
  # Written by the onDiagnosticsUpdate callback in the diagnostics test.
  # Kept at module scope because unittest's `test` macro turns test-local
  # `var`s into effective globals, so an in-test closure would fail the
  # gc-safety check on capture.
  diagReceived {.threadvar.}: seq[Diagnostic]
  diagUri {.threadvar.}: string
  # Written by the onLogMessage callback in the showMessage test.
  logMessages {.threadvar.}: seq[string]

proc awaitRename(
    svc: LspService, path: string, newName: string
): Result[Option[WorkspaceEdit], string] =
  proc runner(): Future[Result[Option[WorkspaceEdit], string]] {.async.} =
    return await svc.requestRename(path, 0, 0, newName)

  waitFor runner()

proc awaitFormatting(svc: LspService, path: string): Result[seq[TextEdit], string] =
  proc runner(): Future[Result[seq[TextEdit], string]] {.async.} =
    return await svc.requestFormatting(path)

  waitFor runner()

suite "e2e: LspService driven by lasm":
  setup:
    if not lasmAvailable():
      skip()

  test "initialize -> didOpen -> hover -> shutdown":
    let h = startLasm()
    try:
      let idRes = h.svc.startHoverRequest(h.filePath, 0, 0)
      check idRes.isOk

      let resp = awaitResponse(h.svc, idRes.get)
      check resp.isOk
      check ($resp.get).contains("hello from lasm")

      let hover = parseHoverResponse(resp.get)
      check hover.isSome
    finally:
      stopLasm(h)

  test "completion returns scenario items":
    let h = startLasm()
    try:
      let idRes = h.svc.startCompletionRequest(h.filePath, 0, 0)
      check idRes.isOk

      let respRes = awaitResponseRaw(h.svc, idRes.get)
      check respRes.isOk

      let (items, isIncomplete) = parseCompletionResponse(respRes.get)
      check not isIncomplete
      check items.len == 2
      check items[0].label == "println"
      check items[1].label == "variable"
    finally:
      stopLasm(h)

  test "definition returns the configured single location":
    let h = startLasm()
    try:
      let idRes = h.svc.startDefinitionRequest(h.filePath, 0, 0)
      check idRes.isOk

      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk

      let locs = parseLocationsResponse(respRes.get)
      check locs.len == 1
      check locs[0].uri == "file:///path/to/definition.dummy"
      check locs[0].range.start.line == 25
    finally:
      stopLasm(h)

  test "references returns both configured locations":
    let h = startLasm()
    try:
      let idRes = h.svc.startReferencesRequest(h.filePath, 0, 0, true)
      check idRes.isOk

      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk

      # lasm may prepend a synthetic declaration entry when includeDeclaration
      # is on, so assert the configured URIs are present rather than pinning
      # the exact count.
      let locs = parseLocationsResponse(respRes.get)
      var uris: seq[string] = @[]
      for loc in locs:
        uris.add(loc.uri)
      check "file:///path/to/reference1.dummy" in uris
      check "file:///path/to/reference2.dummy" in uris
    finally:
      stopLasm(h)

  test "documentHighlight returns both configured highlights":
    let h = startLasm()
    try:
      let idRes = h.svc.startDocumentHighlightRequest(h.filePath, 0, 0)
      check idRes.isOk

      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk

      let highlights = parseDocumentHighlightResponse(respRes.get)
      check highlights.len == 2
      check highlights[0].kind.isSome
      check highlights[0].kind.get == DocumentHighlightKind.dhkText
    finally:
      stopLasm(h)

  test "rename substitutes ${newName} in workspaceEdit":
    let h = startLasm()
    try:
      let respRes = awaitRename(h.svc, h.filePath, "renamed")
      check respRes.isOk
      check respRes.get.isSome

      let edit = respRes.get.get
      check edit.changes.isSome
      let changes = edit.changes.get
      # The scenario has a single change entry: file:///path/to/file.dummy.
      check "file:///path/to/file.dummy" in changes
      let edits = changes["file:///path/to/file.dummy"]
      check edits.len == 1
      check edits[0].newText == "renamed"
    finally:
      stopLasm(h)

  test "declaration returns the configured location":
    let h = startLasm()
    try:
      let idRes = h.svc.startDeclarationRequest(h.filePath, 0, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      let locs = parseLocationsResponse(respRes.get)
      check locs.len == 1
      check locs[0].uri == "file:///path/to/declaration.dummy"
    finally:
      stopLasm(h)

  test "typeDefinition returns the configured location":
    let h = startLasm()
    try:
      let idRes = h.svc.startTypeDefinitionRequest(h.filePath, 0, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      let locs = parseLocationsResponse(respRes.get)
      check locs.len == 1
      check locs[0].uri == "file:///path/to/type.dummy"
    finally:
      stopLasm(h)

  test "implementation returns the configured location":
    let h = startLasm()
    try:
      let idRes = h.svc.startImplementationRequest(h.filePath, 0, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      let locs = parseLocationsResponse(respRes.get)
      check locs.len == 1
      check locs[0].uri == "file:///path/to/implementation.dummy"
    finally:
      stopLasm(h)

  test "inlayHint returns hints for the requested range":
    let h = startLasm()
    try:
      let idRes = h.svc.startInlayHintRequest(h.filePath, 0, 0, 100, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      let hints = parseInlayHintResponse(respRes.get)
      check hints.len == 2
      check hints[0].position.line == 1
      check hints[1].position.line == 3
    finally:
      stopLasm(h)

  test "semanticTokens/full returns the configured data array":
    let h = startLasm()
    try:
      let idRes = h.svc.startSemanticTokensFullRequest(h.filePath)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      # The response envelope is `{ "data": [...] }`; verify the array is the
      # 20-element token stream from the scenario without wiring a full parser.
      let node = respRes.get
      check node.kind == JObject
      check node.hasKey("data")
      check node["data"].kind == JArray
      check node["data"].len == 20
      check node["data"][0].getInt == 0
      check node["data"][3].getInt == 14
    finally:
      stopLasm(h)

  test "callHierarchy prepare -> incoming -> outgoing chain":
    let h = startLasm()
    try:
      let prepIdRes = h.svc.startCallHierarchyPrepareRequest(h.filePath, 0, 0)
      check prepIdRes.isOk
      let prepResp = awaitResponse(h.svc, prepIdRes.get)
      check prepResp.isOk
      let items = parseCallHierarchyPrepareResponse(prepResp.get)
      check items.len == 1
      check items[0].name == "myFunction"

      let incIdRes = h.svc.startCallHierarchyIncomingCallsRequest(h.filePath, items[0])
      check incIdRes.isOk
      let incResp = awaitResponse(h.svc, incIdRes.get)
      check incResp.isOk
      let incoming = parseCallHierarchyIncomingCallsResponse(incResp.get)
      check incoming.len == 1
      check incoming[0].`from`.name == "callerFunction"

      let outIdRes = h.svc.startCallHierarchyOutgoingCallsRequest(h.filePath, items[0])
      check outIdRes.isOk
      let outResp = awaitResponse(h.svc, outIdRes.get)
      check outResp.isOk
      let outgoing = parseCallHierarchyOutgoingCallsResponse(outResp.get)
      check outgoing.len == 1
      check outgoing[0].to.name == "calleeFunction"
    finally:
      stopLasm(h)

  test "formatting returns the configured text edits":
    let h = startLasm()
    try:
      let respRes = awaitFormatting(h.svc, h.filePath)
      check respRes.isOk
      let edits = respRes.get
      check edits.len == 2
      check edits[0].newText == "formatted line 1"
      check edits[1].newText.contains("return")
    finally:
      stopLasm(h)

  test "semanticTokens/range returns the configured data array":
    let h = startLasm()
    try:
      let idRes = h.svc.startSemanticTokensRangeRequest(h.filePath, 0, 0, 10, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isOk
      let node = respRes.get
      check node.kind == JObject
      check node.hasKey("data")
      check node["data"].kind == JArray
      # lasm mirrors the same token stream for full and range requests.
      check node["data"].len == 20
    finally:
      stopLasm(h)

  test "hover request times out when scenario injects a delay":
    # Inject a 1500ms server-side delay; drop the consumer-side timeout to
    # 200ms so waitForResponse surfaces "Request timed out" before lasm ever
    # answers.
    let h = startLasmWith(slowHoverScenario(1500))
    try:
      let idRes = h.svc.startHoverRequest(h.filePath, 0, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get, timeoutMs = 200)
      check respRes.isErr
      check respRes.error.toLowerAscii.contains("timed out")
    finally:
      stopLasm(h)

  test "workspace/executeCommand switches scenarios mid-session":
    let h = startLasmWith(twoHoverScenariosJson())
    try:
      # First hover uses the s1 payload.
      let id1 = h.svc.startHoverRequest(h.filePath, 0, 0)
      check id1.isOk
      let resp1 = awaitResponse(h.svc, id1.get)
      check resp1.isOk
      check ($resp1.get).contains("reply from s1")

      # Ask lasm to swap to s2 via its bespoke executeCommand hook.
      let switch =
        awaitExecuteCommand(h.svc, h.filePath, "lsptest.switchScenario", @[%"s2"])
      check switch.isOk

      # Now hover should return the s2 payload.
      let id2 = h.svc.startHoverRequest(h.filePath, 0, 0)
      check id2.isOk
      let resp2 = awaitResponse(h.svc, id2.get)
      check resp2.isOk
      check ($resp2.get).contains("reply from s2")
    finally:
      stopLasm(h)

  test "lsptest.listScenarios returns the configured scenarios":
    let h = startLasm()
    try:
      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listScenarios", @[])
      check resp.isOk
      let arr = resp.get
      check arr.kind == JArray
      check arr.len >= 1
      # Each entry is {name, description}. lasm reports the scenarios map key
      # as the name, not the scenario body's "name" field, so we look for the
      # key we authored.
      var names: seq[string] = @[]
      for entry in arr:
        names.add(entry{"name"}.getStr(""))
      check "moe-e2e" in names
    finally:
      stopLasm(h)

  test "lsptest.listOpenFiles reports the file opened during startup":
    let h = startLasm()
    try:
      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      let arr = resp.get
      check arr.kind == JArray
      check arr.len == 1
      check arr[0]{"fileName"}.getStr == "sample." & Ext
      check arr[0]{"version"}.getInt == 1
    finally:
      stopLasm(h)

  test "errors.hover surfaces an LSP error response":
    let h = startLasmWith(errorInjectedHoverScenario())
    try:
      let idRes = h.svc.startHoverRequest(h.filePath, 0, 0)
      check idRes.isOk
      let respRes = awaitResponse(h.svc, idRes.get)
      check respRes.isErr
      check respRes.error.contains("Injected failure")
    finally:
      stopLasm(h)

  test "multiple language workers coexist against separate lasm processes":
    let h = startLasm()
    try:
      # Register a second language mapped to the same lasm binary and config,
      # then spin up its worker independently. Both workers should end up
      # alive at the same time, and both files should serve hover payload.
      const Ext2 = "dummy2"
      const LangId2 = "dummy2"
      h.svc.setConfig(
        LangId2,
        LanguageServerConfig(
          command: LasmBin,
          args: @["--config", h.cfgPath],
          extensions: @[Ext2],
          enabled: true,
        ),
      )
      let secondPath = h.workspace / ("second." & Ext2)
      writeFile(secondPath, SampleText)

      check h.svc.startWorker(LangId2).isOk
      check waitUntilReady(h.svc, LangId2, ReadyTimeoutMs)
      check h.svc.notifyDocumentOpened(secondPath, SampleText).isOk

      let live = h.svc.liveWorkerLangIds()
      check LangId in live
      check LangId2 in live

      let id1 = h.svc.startHoverRequest(h.filePath, 0, 0)
      let id2 = h.svc.startHoverRequest(secondPath, 0, 0)
      check id1.isOk
      check id2.isOk

      let r1 = awaitResponse(h.svc, id1.get)
      let r2 = awaitResponse(h.svc, id2.get)
      check r1.isOk
      check r2.isOk
      check ($r1.get).contains("hello from lasm")
      check ($r2.get).contains("hello from lasm")

      discard h.svc.stopWorker(LangId2)
    finally:
      stopLasm(h)

  test "lsptest.reloadConfig picks up edits to the config file":
    let h = startLasmWith(simpleHoverScenario("before reload"))
    try:
      # Before reload: the "before" payload.
      let id1 = h.svc.startHoverRequest(h.filePath, 0, 0)
      check id1.isOk
      let r1 = awaitResponse(h.svc, id1.get)
      check r1.isOk
      check ($r1.get).contains("before reload")

      # Overwrite the on-disk config, then ask the server to reload it.
      writeFile(h.cfgPath, simpleHoverScenario("after reload"))
      let reload = awaitExecuteCommand(h.svc, h.filePath, "lsptest.reloadConfig", @[])
      check reload.isOk
      check reload.get{"success"}.getBool

      # After reload: the "after" payload.
      let id2 = h.svc.startHoverRequest(h.filePath, 0, 0)
      check id2.isOk
      let r2 = awaitResponse(h.svc, id2.get)
      check r2.isOk
      check ($r2.get).contains("after reload")
    finally:
      stopLasm(h)

  test "onLogMessage captures window/showMessage from switchScenario":
    logMessages = @[]
    let h = startLasmWith(twoHoverScenariosJson())
    try:
      h.svc.onLogMessage = proc(
          langId: string, msgType: MessageType, message: string
      ) {.gcsafe.} =
        logMessages.add(message)

      let switch =
        awaitExecuteCommand(h.svc, h.filePath, "lsptest.switchScenario", @[%"s2"])
      check switch.isOk

      # Drain a few more polls so the notification, which may arrive strictly
      # after the response, still lands before we assert.
      let deadline = epochTime() + 1.0
      while epochTime() < deadline:
        var found = false
        for m in logMessages:
          if m.contains("Switched to scenario: s2"):
            found = true
            break
        if found:
          break
        h.svc.poll()
        sleep(20)

      var switchedSeen = false
      for m in logMessages:
        if m.contains("Switched to scenario: s2"):
          switchedSeen = true
          break
      check switchedSeen
    finally:
      stopLasm(h)

  test "didChange (full sync) updates version and contentLength on the server":
    let h = startLasm()
    try:
      # Baseline: after startup the doc is version 1 with SampleText's length.
      let before = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check before.isOk
      check before.get.kind == JArray
      check before.get.len == 1
      check before.get[0]{"version"}.getInt == 1
      check before.get[0]{"contentLength"}.getInt == SampleText.len

      # Send a full didChange with new text and bumped version.
      const NewText = "hello world\n"
      check h.svc.notifyDocumentChanged(h.filePath, 2, NewText).isOk

      let after = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check after.isOk
      check after.get.len == 1
      check after.get[0]{"version"}.getInt == 2
      check after.get[0]{"contentLength"}.getInt == NewText.len
    finally:
      stopLasm(h)

  test "didChange (incremental) splices range with new text on the server":
    let h = startLasm()
    try:
      # SampleText is "abc\ndef\nghi\n" (12 bytes). Replace "abc"
      # (range (0,0)-(0,3)) with "HELLO"; expected result
      # "HELLO\ndef\nghi\n" (14 bytes). lasm's initialize advertises
      # textDocumentSync.change = 2 (Incremental) and applies ranges via
      # applyContentChange (splice), so this exercises moe's incremental
      # encoder against a compliant receiver.
      let contentChanges = %*[
        {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}},
          "text": "HELLO",
        }
      ]
      check h.svc.notifyDocumentChangedIncremental(h.filePath, 2, $contentChanges).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.len == 1
      check resp.get[0]{"version"}.getInt == 2
      check resp.get[0]{"contentLength"}.getInt == "HELLO\ndef\nghi\n".len
    finally:
      stopLasm(h)

  test "didChange (incremental) handles multi-line ranges":
    let h = startLasm()
    try:
      # SampleText = "abc\ndef\nghi\n". Splice range (0,1)-(1,2) (which
      # covers "bc\nde" — five bytes crossing the first newline) with "X".
      # Expected: "a" + "X" + "f\nghi\n" = "aXf\nghi\n" (8 bytes).
      let contentChanges = %*[
        {
          "range":
            {"start": {"line": 0, "character": 1}, "end": {"line": 1, "character": 2}},
          "text": "X",
        }
      ]
      check h.svc.notifyDocumentChangedIncremental(h.filePath, 2, $contentChanges).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.len == 1
      check resp.get[0]{"contentLength"}.getInt == "aXf\nghi\n".len
    finally:
      stopLasm(h)

  test "didChange (incremental) applies multi-edit contentChanges in order":
    let h = startLasm()
    try:
      # Two edits, applied sequentially per LSP spec (each edit computed
      # against the state produced by the previous one):
      #   1. (0,0)-(0,3) "abc" -> "AA"        -> "AA\ndef\nghi\n"
      #   2. (1,0)-(1,3) "def" -> "BBBB"      -> "AA\nBBBB\nghi\n" (13 bytes)
      let contentChanges = %*[
        {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}},
          "text": "AA",
        },
        {
          "range":
            {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 3}},
          "text": "BBBB",
        },
      ]
      check h.svc.notifyDocumentChangedIncremental(h.filePath, 2, $contentChanges).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.len == 1
      check resp.get[0]{"contentLength"}.getInt == "AA\nBBBB\nghi\n".len
    finally:
      stopLasm(h)

  test "switchScenario with an unknown name surfaces an error response":
    let h = startLasmWith(twoHoverScenariosJson())
    try:
      let resp = awaitExecuteCommand(
        h.svc, h.filePath, "lsptest.switchScenario", @[%"does-not-exist"]
      )
      check resp.isErr
      # lasm raises `LSPError("Unknown scenario: <name>")`, which is
      # forwarded as the JSON-RPC error message.
      check resp.error.contains("Unknown scenario") or
        resp.error.contains("does-not-exist")
    finally:
      stopLasm(h)

  test "didChange (incremental) respects UTF-16 character positions":
    # Content: "こんにちは\nworld\n"
    #   - 5 Japanese chars, each 3 bytes in UTF-8 and 1 UTF-16 code unit
    #   - Total UTF-8 bytes = 5*3 + 1 + 5 + 1 = 22
    # Splice UTF-16 range (0,2)-(0,4) — covering "にち" — with "XX":
    #   Result "こんXXは\nworld\n" = 6 + 2 + 3 + 1 + 5 + 1 = 18 bytes
    const InitialText = "こんにちは\nworld\n"
    const Expected = "こんXXは\nworld\n"
    let h = startLasmWith(scenarioJson(), InitialText)
    try:
      let contentChanges = %*[
        {
          "range":
            {"start": {"line": 0, "character": 2}, "end": {"line": 0, "character": 4}},
          "text": "XX",
        }
      ]
      check h.svc.notifyDocumentChangedIncremental(h.filePath, 2, $contentChanges).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.len == 1
      check resp.get[0]{"contentLength"}.getInt == Expected.len
    finally:
      stopLasm(h)

  test "listOpenFiles reflects multiple files opened via the same worker":
    let h = startLasm()
    try:
      # Open a second file on the same language/worker. lasm keeps a
      # documents table keyed by URI so both entries should be listed.
      let secondPath = h.workspace / ("second." & Ext)
      writeFile(secondPath, "another payload\n")
      check h.svc.notifyDocumentOpened(secondPath, "another payload\n").isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.kind == JArray
      check resp.get.len == 2

      var names: seq[string] = @[]
      for entry in resp.get:
        names.add(entry{"fileName"}.getStr(""))
      check "sample." & Ext in names
      check "second." & Ext in names
    finally:
      stopLasm(h)

  test "has*Support covers the remaining capabilities lasm advertises":
    let h = startLasm()
    try:
      # All of these are set to `some(true)` (or equivalent) in lasm's
      # initialize handler, so moe should surface support for each.
      check h.svc.hasTypeDefinitionSupport(LangId)
      check h.svc.hasImplementationSupport(LangId)
      check h.svc.hasDocumentHighlightSupport(LangId)
      check h.svc.hasRenameSupport(LangId)
      check h.svc.hasFormattingSupport(LangId)
      check h.svc.hasInlayHintSupport(LangId)
      check h.svc.hasSemanticTokensSupport(LangId)
      check h.svc.hasCallHierarchySupport(LangId)
      # lasm does not advertise these capabilities. It serialises absent
      # Option fields as `"xxxProvider": null` in the initialize result, so
      # this branch also guards `isCapabilityEnabled` against treating JNull
      # as enabled — a regression would silently reintroduce timeout-hangs
      # on servers that emit null.
      check not h.svc.hasDocumentLinkSupport(LangId)
      check not h.svc.hasSignatureHelpSupport(LangId)
      check not h.svc.hasCodeLensSupport(LangId)
    finally:
      stopLasm(h)

  test "didSave with text overwrites the server-side content":
    let h = startLasm()
    try:
      const SavedText = "saved payload"
      check h.svc.notifyDocumentSaved(h.filePath, some(SavedText)).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.len == 1
      check resp.get[0]{"contentLength"}.getInt == SavedText.len
    finally:
      stopLasm(h)

  test "didClose drops the document from listOpenFiles":
    let h = startLasm()
    try:
      check h.svc.notifyDocumentClosed(h.filePath).isOk

      let resp = awaitExecuteCommand(h.svc, h.filePath, "lsptest.listOpenFiles", @[])
      check resp.isOk
      check resp.get.kind == JArray
      check resp.get.len == 0
    finally:
      stopLasm(h)

  test "getServerInfo exposes lasm's initialize response":
    let h = startLasm()
    try:
      let info = h.svc.getServerInfo(LangId)
      check info.isSome
      check info.get.name == "LSP Test Server"
      check info.get.version.isSome
      check info.get.version.get == "0.1.0"
    finally:
      stopLasm(h)

  test "publishDiagnostics is re-sent (empty) after didClose":
    # Reset the module-level captures used by the diagnostics callback.
    diagReceived = @[]
    diagUri = ""
    let h = startLasm()
    try:
      h.svc.onDiagnosticsUpdate = proc(
          uri: string, diagnostics: seq[Diagnostic]
      ) {.gcsafe.} =
        diagUri = uri
        diagReceived = diagnostics

      # First: the initial batch from didOpen surfaces 2 entries.
      let d1 = epochTime() + 3.0
      while epochTime() < d1 and diagReceived.len == 0:
        h.svc.poll()
        sleep(20)
      check diagReceived.len == 2

      check h.svc.notifyDocumentClosed(h.filePath).isOk

      # Then: didClose provokes an empty publishDiagnostics for the same URI.
      let d2 = epochTime() + 3.0
      while epochTime() < d2 and diagReceived.len != 0:
        h.svc.poll()
        sleep(20)
      check diagReceived.len == 0
      check diagUri.endsWith("sample." & Ext)
    finally:
      stopLasm(h)

  test "worker restarts after the lasm process is killed":
    let h = startLasm()
    try:
      # Find the running lasm subprocess by its unique config path so we don't
      # collide with lasm processes owned by parallel test files.
      let pattern = "lasm --config " & h.cfgPath
      let (raw, _) = execCmdEx("pgrep -f " & quoteShell(pattern))
      let firstLine = raw.strip.splitLines()[0]
      check firstLine.len > 0
      let pid = parseInt(firstLine)
      check pid > 0

      # SIGKILL and wait for the worker to notice the pipe closed.
      check execCmd("kill -9 " & $pid) == 0
      let crashDeadline = epochTime() + 5.0
      while epochTime() < crashDeadline and h.svc.isWorkerReady(LangId):
        h.svc.poll()
        sleep(30)
      check not h.svc.isWorkerReady(LangId)

      # First restart attempt after a crash is not rate-limited (empty
      # lastRestartTimes entry), so it should spin up a fresh lasm.
      let restart = h.svc.startWorker(LangId)
      check restart.isOk
      check waitUntilReady(h.svc, LangId, ReadyTimeoutMs)

      # The new server doesn't know about the previously opened doc, but
      # lasm's hover payload isn't doc-scoped, so a hover round-trip
      # confirms the restart is fully wired up.
      let idRes = h.svc.startHoverRequest(h.filePath, 0, 0)
      check idRes.isOk
      let resp = awaitResponse(h.svc, idRes.get)
      check resp.isOk
      check ($resp.get).contains("hello from lasm")
    finally:
      stopLasm(h)

  test "server capabilities from initialize propagate to has*Support queries":
    let h = startLasm()
    try:
      # lasm advertises hover/completion/definition/rename/references/
      # documentHighlight/formatting/callHierarchy in its initialize result.
      check h.svc.hasHoverSupport(LangId)
      check h.svc.hasCompletionSupport(LangId)
      check h.svc.hasDefinitionSupport(LangId)
      check h.svc.hasReferencesSupport(LangId)
    finally:
      stopLasm(h)

  test "cancelRequest drops a pending request from the tracking table":
    # Use a slow hover so we can cancel it in-flight; a short wait afterwards
    # keeps the test snappy while still proving the cleanup happened.
    let h = startLasmWith(slowHoverScenario(2000))
    try:
      let idRes = h.svc.startHoverRequest(h.filePath, 0, 0)
      check idRes.isOk
      check h.svc.getPendingRequestCount == 1

      h.svc.cancelRequest(idRes.get)
      check h.svc.getPendingRequestCount == 0
      check not h.svc.hasPendingRequests
    finally:
      stopLasm(h)

  test "diagnostics arrive via publishDiagnostics after didOpen":
    diagReceived = @[]
    diagUri = ""
    let h = startLasm()
    try:
      h.svc.onDiagnosticsUpdate = proc(
          uri: string, diagnostics: seq[Diagnostic]
      ) {.gcsafe.} =
        diagUri = uri
        diagReceived = diagnostics

      let deadline = epochTime() + DiagnosticsWaitMs.float / 1000.0
      while epochTime() < deadline and diagReceived.len == 0:
        h.svc.poll()
        sleep(20)

      check diagReceived.len == 2
      check diagUri.endsWith("sample." & Ext)
      check diagReceived[0].message.contains("testVar")
      check diagReceived[0].severity.isSome
      check diagReceived[0].severity.get == DiagnosticSeverity.dsError
      check diagReceived[1].severity.get == DiagnosticSeverity.dsWarning
    finally:
      stopLasm(h)
