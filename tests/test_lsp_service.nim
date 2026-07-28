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

import
  std/
    [unittest, json, options, os, times, strutils, importutils, tables, sets, monotimes]

import pkg/results

import ../src/moepkg/[lsp_service, logger]
import ../src/moepkg/lsp/protocol/types

suite "LspService - newLspService":
  privateAccess(LspService)

  test "creates service with default workspace root (current dir)":
    let svc = newLspService()
    check svc.enabled
    check svc.workspaceRoot == getCurrentDir()

  test "creates service with custom workspace root":
    let svc = newLspService("/tmp/test")
    check svc.workspaceRoot == "/tmp/test"

  test "creates service with empty workspace root uses current dir":
    let svc = newLspService("")
    check svc.workspaceRoot == getCurrentDir()

  test "has default language server configs":
    let svc = newLspService()

    let nimConfig = svc.getConfig("nim")
    check nimConfig.isSome
    check nimConfig.get.command == "nimlangserver"
    check nimConfig.get.enabled
    check "nim" in nimConfig.get.extensions

    let rustConfig = svc.getConfig("rust")
    check rustConfig.isSome
    check rustConfig.get.command == "rust-analyzer"
    check "rs" in rustConfig.get.extensions

    let pythonConfig = svc.getConfig("python")
    check pythonConfig.isSome
    check pythonConfig.get.command == "pylsp"
    check "py" in pythonConfig.get.extensions

    let goConfig = svc.getConfig("go")
    check goConfig.isSome
    check goConfig.get.command == "gopls"
    check "go" in goConfig.get.extensions

  test "default callbacks are not nil":
    let svc = newLspService()
    check not svc.onDiagnosticsUpdate.isNil
    check not svc.onLogMessage.isNil
    check not svc.onProgress.isNil
    check not svc.onStatusUpdate.isNil

suite "LspService - Config Management":
  test "setConfig adds new language config":
    let svc = newLspService()
    let config = LanguageServerConfig(
      command: "my-lsp", args: @["--stdio"], extensions: @["xyz"], enabled: true
    )
    svc.setConfig("xyz-lang", config)

    let retrieved = svc.getConfig("xyz-lang")
    check retrieved.isSome
    check retrieved.get.command == "my-lsp"
    check retrieved.get.args == @["--stdio"]
    check "xyz" in retrieved.get.extensions

  test "LanguageServerConfig traceLevel defaults to traceOff":
    let svc = newLspService()
    check svc.getConfig("nim").get.traceLevel == traceOff

  test "setConfig persists traceLevel":
    let svc = newLspService()
    var c = svc.getConfig("nim").get
    c.traceLevel = traceMessages
    svc.setConfig("nim", c)
    check svc.getConfig("nim").get.traceLevel == traceMessages

  test "setConfig updates existing config":
    let svc = newLspService()
    let newConfig = LanguageServerConfig(
      command: "custom-nimlangserver",
      args: @["--debug"],
      extensions: @["nim", "nims"],
      enabled: false,
    )
    svc.setConfig("nim", newConfig)

    let retrieved = svc.getConfig("nim")
    check retrieved.isSome
    check retrieved.get.command == "custom-nimlangserver"
    check retrieved.get.args == @["--debug"]
    check not retrieved.get.enabled

  test "getConfig returns none for unknown language":
    let svc = newLspService()
    check svc.getConfig("unknown-lang").isNone

suite "LspService - Language ID Detection":
  test "getLanguageIdFromPath detects nim files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("/home/test/foo.nim") == some("nim")
    check svc.getLanguageIdFromPath("test.nims") == some("nim")
    check svc.getLanguageIdFromPath("package.nimble") == some("nim")

  test "getLanguageIdFromPath detects rust files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("/home/test/main.rs") == some("rust")

  test "getLanguageIdFromPath detects python files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("script.py") == some("python")
    check svc.getLanguageIdFromPath("script.pyw") == some("python")

  test "getLanguageIdFromPath detects lua files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("init.lua") == some("lua")

  test "getLanguageIdFromPath detects go files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("main.go") == some("go")

  test "getLanguageIdFromPath detects c/cpp files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("main.c") == some("c")
    check svc.getLanguageIdFromPath("header.h") == some("c")
    check svc.getLanguageIdFromPath("main.cpp") == some("cpp")
    check svc.getLanguageIdFromPath("header.hpp") == some("cpp")

  test "getLanguageIdFromPath detects typescript/javascript files":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("app.ts") == some("typescript")
    check svc.getLanguageIdFromPath("component.tsx") == some("typescript")
    check svc.getLanguageIdFromPath("app.js") == some("javascript")
    check svc.getLanguageIdFromPath("component.jsx") == some("javascript")
    check svc.getLanguageIdFromPath("module.mjs") == some("javascript")

  test "getLanguageIdFromPath returns none for unknown extensions":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("file.xyz").isNone
    check svc.getLanguageIdFromPath("noextension").isNone
    check svc.getLanguageIdFromPath("").isNone

  test "getLanguageIdFromPath is case insensitive":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("FILE.NIM") == some("nim")
    check svc.getLanguageIdFromPath("Test.Py") == some("python")

  test "getLanguageIdFromPath respects disabled config":
    let svc = newLspService()
    var config = svc.getConfig("nim").get
    config.enabled = false
    svc.setConfig("nim", config)
    check svc.getLanguageIdFromPath("test.nim").isNone

  test "getLanguageIdFromExtension works with and without dot":
    let svc = newLspService()
    check svc.getLanguageIdFromExtension("nim") == some("nim")
    check svc.getLanguageIdFromExtension(".nim") == some("nim")
    check svc.getLanguageIdFromExtension("...nim") == some("nim")

  test "getLanguageIdFromExtension is case insensitive":
    let svc = newLspService()
    check svc.getLanguageIdFromExtension("NIM") == some("nim")
    check svc.getLanguageIdFromExtension("PY") == some("python")

  test "duplicate extension across configs resolves to alphabetically-first langId":
    let svc = newLspService()
    svc.setConfig(
      "zeta",
      LanguageServerConfig(command: "z", args: @[], extensions: @["xyz"], enabled: true),
    )
    svc.setConfig(
      "alpha",
      LanguageServerConfig(command: "a", args: @[], extensions: @["xyz"], enabled: true),
    )
    check svc.getLanguageIdFromPath("t.xyz") == some("alpha")
    check svc.getLanguageIdFromExtension("xyz") == some("alpha")

  test "setConfig overwriting a langId removes its old extensions from the index":
    let svc = newLspService()
    svc.setConfig(
      "nim",
      LanguageServerConfig(
        command: "nimlangserver", args: @[], extensions: @["nim"], enabled: true
      ),
    )
    check svc.getLanguageIdFromPath("pkg.nimble").isNone
    check svc.getLanguageIdFromPath("t.nim") == some("nim")

suite "LspService - URI Conversion":
  test "pathToUri converts absolute path":
    check pathToUri("/home/user/test.nim") == "file:///home/user/test.nim"

  test "pathToUri preserves existing file:// prefix":
    check pathToUri("file:///home/user/test.nim") == "file:///home/user/test.nim"

  test "pathToUri converts relative path to absolute":
    let result = pathToUri("test.nim")
    check result.startsWith("file://")
    check result.endsWith("test.nim")

  test "uriToPath converts file:// URI to path":
    check uriToPath("file:///home/user/test.nim") == "/home/user/test.nim"

  test "uriToPath returns non-file URI unchanged":
    check uriToPath("/home/user/test.nim") == "/home/user/test.nim"

  test "pathToUri percent-encodes spaces":
    check pathToUri("/home/user/my project/test.nim") ==
      "file:///home/user/my%20project/test.nim"

  test "pathToUri percent-encodes non-ASCII characters":
    # "テスト" in UTF-8: E3 83 86 E3 82 B9 E3 83 88
    check pathToUri("/home/user/テスト.nim") ==
      "file:///home/user/%E3%83%86%E3%82%B9%E3%83%88.nim"

  test "pathToUri does not encode path separators":
    check pathToUri("/a/b/c.nim") == "file:///a/b/c.nim"

  test "uriToPath percent-decodes":
    check uriToPath("file:///home/user/my%20project/test.nim") ==
      "/home/user/my project/test.nim"
    check uriToPath("file:///home/user/%E3%83%86%E3%82%B9%E3%83%88.nim") ==
      "/home/user/テスト.nim"

  test "uriToPath does not treat plus as space":
    check uriToPath("file:///home/user/a+b.nim") == "/home/user/a+b.nim"

  test "path/URI roundtrip":
    for p in [
      "/home/user/test.nim", "/home/user/my project/file.nim",
      "/home/user/日本語パス/ファイル.nim", "/tmp/a+b#c.nim",
    ]:
      check uriToPath(pathToUri(p)) == p

suite "LspService - Worker Management (without actual workers)":
  test "getWorker returns none when no workers started":
    let svc = newLspService()
    check svc.getWorker("nim").isNone

  test "isWorkerReady returns false when no workers":
    let svc = newLspService()
    check not svc.isWorkerReady("nim")
    check not svc.isWorkerReady("rust")

  test "getRunningLanguages returns empty when no workers":
    let svc = newLspService()
    check svc.getRunningLanguages().len == 0

  test "stopWorker succeeds even when no worker exists":
    let svc = newLspService()
    let result = svc.stopWorker("nim")
    check result.isOk

  test "stopAll works with no workers":
    let svc = newLspService()
    svc.stopAll()
    check svc.getRunningLanguages().len == 0

  test "startWorker fails when service is disabled":
    let svc = newLspService()
    svc.enabled = false
    let result = svc.startWorker("nim")
    check result.isErr
    check "disabled" in result.error

  test "startWorker fails for unknown language":
    let svc = newLspService()
    let result = svc.startWorker("unknown-lang")
    check result.isErr
    check "No LSP configuration" in result.error

  test "startWorker fails for disabled language":
    let svc = newLspService()
    var config = svc.getConfig("nim").get
    config.enabled = false
    svc.setConfig("nim", config)

    let result = svc.startWorker("nim")
    check result.isErr
    check "disabled" in result.error

  test "getWorkerForPath fails for unsupported file type":
    let svc = newLspService()
    let result = svc.getWorkerForPath("/home/test/file.xyz")
    check result.isErr
    check "No LSP support" in result.error

  test "startWorker returns existing worker without creating a new one":
    ## Regression test: startWorker must return an existing worker even when
    ## its state is lwsStopped (the period between start() and the worker
    ## thread processing lcmdStart). Previously, the state check
    ## (isRunning or isStarting) missed this intermediate state, causing a
    ## duplicate worker to be created and the original thread to be orphaned.
    let svc = newLspService()
    let result1 = svc.startWorker("nim")
    check result1.isOk
    let worker1 = result1.get

    # Worker is started but LSP server state is still lwsStopped
    # (lcmdStart hasn't been processed yet)
    check worker1.state == lwsStopped

    # Second call must return the same worker, not create a new one
    let result2 = svc.startWorker("nim")
    check result2.isOk
    let worker2 = result2.get
    check worker1 == worker2

    worker1.stop()

  test "startWorker restarts a crashed server (rate-limited)":
    proc waitForState(
        worker: LspWorker, expected: LspWorkerState, timeoutMs = 5000
    ): bool =
      let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
      while getMonoTime() < deadline:
        if worker.state == expected:
          return true
        sleep(10)
      false

    let svc = newLspService()
    # A "server" that exits immediately -> initialize fails -> lwsCrashed
    svc.setConfig(
      "crashlang",
      LanguageServerConfig(
        command: "true", args: @[], extensions: @["crashext"], enabled: true
      ),
    )

    let result1 = svc.startWorker("crashlang")
    check result1.isOk
    let worker = result1.get
    check worker.waitForState(lwsCrashed)

    # First call after the crash triggers a restart on the same thread
    let result2 = svc.startWorker("crashlang")
    check result2.isOk
    check result2.get == worker

    # The restarted server crashes again; an immediate further restart is
    # suppressed by the rate limit
    check worker.waitForState(lwsCrashed)
    let result3 = svc.startWorker("crashlang")
    check result3.isErr
    check result3.error.contains("restart suppressed")

    worker.stop()

suite "LspService - Pending Request Management":
  test "hasPendingRequests returns false initially":
    let svc = newLspService()
    check not svc.hasPendingRequests

  test "getPendingRequestCount returns 0 initially":
    let svc = newLspService()
    check svc.getPendingRequestCount == 0

  test "checkResponse reports unknown ids as timeout":
    # An unknown id means the request was already swept (or the response was
    # already consumed by an earlier checkResponse). Reporting it as timeout
    # lets pollers reset their pending id instead of looping on lrsPending —
    # otherwise the feature freezes until an unrelated invalidate clears it.
    let svc = newLspService()
    let (status, _, err) = svc.checkResponse(999)
    check status == lrsTimeout
    check err.isSome
    let (rawStatus, _, rawErr) = svc.checkResponseRaw(999)
    check rawStatus == lrsTimeout
    check rawErr.isSome

  test "checkResponse after sweep returns timeout for the dropped id":
    # Simulates the sweep-then-poll flow: an in-flight semantic tokens
    # request survives a buffer switch to a non-LSP buffer, times out on the
    # sweep, then the user switches back and the poller queries the id.
    let svc = newLspService()
    svc.activeRequests[42] =
      LspPendingRequest(requestId: 42, langId: "nim", startTime: 0.0, timeoutMs: 1)
    svc.cleanupTimedOutRequests()
    check 42 notin svc.activeRequests
    let (status, _, err) = svc.checkResponse(42)
    check status == lrsTimeout
    check err.isSome

  test "cleanupTimedOutRequests works with no requests":
    let svc = newLspService()
    svc.cleanupTimedOutRequests()
    check svc.getPendingRequestCount == 0

suite "LspService - Response Parsing":
  test "parseCompletionResponse parses array":
    let resp = $(%*[{"label": "item1", "kind": 1}, {"label": "item2", "kind": 2}])
    let (items, isIncomplete) = parseCompletionResponse(resp)
    check items.len == 2
    check items[0].label == "item1"
    check items[1].label == "item2"
    check items[0].kind == some(cikText)
    check not isIncomplete

  test "parseCompletionResponse parses object with items":
    let resp =
      $(%*{"isIncomplete": false, "items": [{"label": "item1"}, {"label": "item2"}]})
    let (items, isIncomplete) = parseCompletionResponse(resp)
    check items.len == 2
    check not isIncomplete

  test "parseCompletionResponse parses incomplete list":
    let resp = $(%*{"isIncomplete": true, "items": [{"label": "item1"}]})
    let (items, isIncomplete) = parseCompletionResponse(resp)
    check items.len == 1
    check isIncomplete

  test "parseCompletionResponse handles empty array":
    let resp = $(%*[])
    let (items, isIncomplete) = parseCompletionResponse(resp)
    check items.len == 0
    check not isIncomplete

  test "parseCompletionResponse handles null and out-of-range kind":
    let (items0, _) = parseCompletionResponse("null")
    check items0.len == 0
    # An out-of-range CompletionItemKind must not raise; it clamps to the
    # lowest valid member rather than crashing the typed parse.
    let resp = $(%*{"items": [{"label": "x", "kind": 999}]})
    let (items, _) = parseCompletionResponse(resp)
    check items.len == 1
    check items[0].kind == some(cikText)

  test "parseHoverResponse parses valid hover":
    let resp = %*{"contents": {"kind": "plaintext", "value": "hover text"}}
    let hover = parseHoverResponse(resp)
    check hover.isSome

  test "parseHoverResponse returns none for null":
    let resp = newJNull()
    let hover = parseHoverResponse(resp)
    check hover.isNone

  test "parseLocationsResponse parses array of locations":
    let resp = %*[
      {
        "uri": "file:///test.nim",
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}},
      },
      {
        "uri": "file:///test2.nim",
        "range":
          {"start": {"line": 5, "character": 2}, "end": {"line": 5, "character": 12}},
      },
    ]
    let locations = parseLocationsResponse(resp)
    check locations.len == 2
    check locations[0].uri == "file:///test.nim"
    check locations[1].uri == "file:///test2.nim"

  test "parseLocationsResponse handles single location":
    let resp = %*{
      "uri": "file:///test.nim",
      "range":
        {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}},
    }
    let locations = parseLocationsResponse(resp)
    check locations.len == 1

  test "parseSignatureHelpResponse parses valid signature":
    let resp = %*{"signatures": [{"label": "proc foo()"}]}
    let sigHelp = parseSignatureHelpResponse(resp)
    check sigHelp.isSome
    check sigHelp.get.signatures.len == 1

  test "parseSignatureHelpResponse returns none for null":
    let resp = newJNull()
    let sigHelp = parseSignatureHelpResponse(resp)
    check sigHelp.isNone

  test "parseDocumentHighlightResponse parses highlights":
    let resp = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}}
      },
      {
        "range":
          {"start": {"line": 2, "character": 3}, "end": {"line": 2, "character": 8}}
      },
    ]
    let highlights = parseDocumentHighlightResponse(resp)
    check highlights.len == 2

  test "parseDocumentHighlightResponse handles empty array":
    let resp = %*[]
    let highlights = parseDocumentHighlightResponse(resp)
    check highlights.len == 0

  test "parseCodeLensResponse parses code lenses":
    let resp = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}}
      }
    ]
    let lenses = parseCodeLensResponse(resp)
    check lenses.len == 1

  test "parseInlayHintResponse parses inlay hints":
    let resp = %*[
      {"position": {"line": 0, "character": 5}, "label": ": int", "kind": 1},
      {"position": {"line": 1, "character": 0}, "label": "arg: ", "kind": 2},
    ]
    let hints = parseInlayHintResponse(resp)
    check hints.len == 2
    check getInlayHintLabel(hints[0]) == ": int"

  test "parseInlayHintResponse returns empty for null/non-array":
    check parseInlayHintResponse(newJNull()).len == 0
    check parseInlayHintResponse(%*{"foo": "bar"}).len == 0

  test "parseInlayHintResponse drops invalid items":
    let resp = %*[
      {"position": {"line": 0, "character": 5}, "label": "ok"},
      {"label": "missing position"},
    ]
    let hints = parseInlayHintResponse(resp)
    check hints.len == 1
    check getInlayHintLabel(hints[0]) == "ok"

  test "parseCallHierarchyPrepareResponse parses items":
    let resp = %*[
      {
        "name": "testFunc",
        "kind": 12,
        "uri": "file:///test.nim",
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}},
        "selectionRange":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 8}},
      }
    ]
    let items = parseCallHierarchyPrepareResponse(resp)
    check items.len == 1
    check items[0].name == "testFunc"

  test "parseSelectionRangeResponse parses ranges":
    let resp = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}}
      }
    ]
    let ranges = parseSelectionRangeResponse(resp)
    check ranges.len == 1

  test "parseDocumentLinksResponse parses links":
    let resp = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 10}},
        "target": "https://example.com",
      }
    ]
    let links = parseDocumentLinksResponse(resp)
    check links.len == 1
    check links[0].target == some("https://example.com")

suite "LspService - Capability Checking (without workers)":
  test "capability checks return false when no workers":
    let svc = newLspService()
    check not svc.hasCompletionSupport("nim")
    check not svc.hasHoverSupport("nim")
    check not svc.hasDefinitionSupport("nim")
    check not svc.hasDeclarationSupport("nim")
    check not svc.hasReferencesSupport("nim")
    check not svc.hasTypeDefinitionSupport("nim")
    check not svc.hasImplementationSupport("nim")
    check not svc.hasDocumentHighlightSupport("nim")
    check not svc.hasSignatureHelpSupport("nim")
    check not svc.hasRenameSupport("nim")
    check not svc.hasFormattingSupport("nim")
    check not svc.hasRangeFormattingSupport("nim")
    check not svc.hasDocumentSymbolSupport("nim")
    check not svc.hasInlayHintSupport("nim")
    check not svc.hasSemanticTokensSupport("nim")
    check not svc.hasSemanticTokensFullSupport("nim")
    check not svc.hasSemanticTokensRangeSupport("nim")
    check not svc.hasSelectionRangeSupport("nim")
    check not svc.hasCodeLensSupport("nim")
    check not svc.hasCodeLensResolveSupport("nim")
    check not svc.hasCallHierarchySupport("nim")
    check not svc.hasFoldingRangeSupport("nim")
    check not svc.hasExecuteCommandSupport("nim")
    check not svc.hasDocumentLinkSupport("nim")
    check not svc.hasDocumentLinkResolveSupport("nim")

  test "explicit `false` capability is treated as unsupported":
    # A server may legitimately advertise `"xxxProvider": false` to disable a
    # feature. Storing the JsonNode and checking only `.isSome` would wrongly
    # report support and fire requests that hang until the timeout.
    let svc = newLspService()
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levCapabilities,
        capabilitiesJson: $(
          %*{
            "hoverProvider": false,
            "definitionProvider": false,
            "referencesProvider": false,
            # Options-typed capabilities: the parser must drop a literal `false`
            # so the gate does not fall back to a bare `isSome` check.
            "completionProvider": false,
            "signatureHelpProvider": false,
          }
        ),
      ),
    )
    check not svc.hasHoverSupport("nim")
    check not svc.hasDefinitionSupport("nim")
    check not svc.hasReferencesSupport("nim")
    check not svc.hasCompletionSupport("nim")
    check not svc.hasSignatureHelpSupport("nim")

  test "explicit `null` capability is treated as unsupported":
    # Some servers (notably Nim-based ones that serialise Option[T] fields
    # verbatim) emit `"xxxProvider": null` when a capability is not set. Both
    # capability paths — Option[JsonNode] (hover/definition/references/...)
    # and Option[Options] (completion/signatureHelp/executeCommand) — must
    # reject JNull the same way they reject literal `false`, otherwise every
    # gated request fires and hangs until the timeout.
    let svc = newLspService()
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levCapabilities,
        capabilitiesJson: $(
          %*{
            "hoverProvider": newJNull(),
            "definitionProvider": newJNull(),
            "referencesProvider": newJNull(),
            "completionProvider": newJNull(),
            "signatureHelpProvider": newJNull(),
            "executeCommandProvider": newJNull(),
          }
        ),
      ),
    )
    check not svc.hasHoverSupport("nim")
    check not svc.hasDefinitionSupport("nim")
    check not svc.hasReferencesSupport("nim")
    check not svc.hasCompletionSupport("nim")
    check not svc.hasSignatureHelpSupport("nim")
    check not svc.hasExecuteCommandSupport("nim")

  test "`true` and object capabilities are treated as supported":
    let svc = newLspService()
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levCapabilities,
        capabilitiesJson: $(
          %*{
            "hoverProvider": true,
            "definitionProvider": {"workDoneProgress": true},
            "completionProvider": {"triggerCharacters": ["."]},
            "signatureHelpProvider": {},
          }
        ),
      ),
    )
    check svc.hasHoverSupport("nim")
    check svc.hasDefinitionSupport("nim")
    check svc.hasCompletionSupport("nim")
    check svc.hasSignatureHelpSupport("nim")

  test "getServerInfo returns none when no workers":
    let svc = newLspService()
    check svc.getServerInfo("nim").isNone

  test "getSemanticTokensLegend returns none when no workers":
    let svc = newLspService()
    check svc.getSemanticTokensLegend("nim").isNone

suite "LspService - Dynamic Registration":
  test "hasDynamicRegistration returns false when no registrations":
    let svc = newLspService()
    check not svc.hasDynamicRegistration("nim", "textDocument/completion")

  test "getDynamicRegistration returns none when no registrations":
    let svc = newLspService()
    check svc.getDynamicRegistration("nim", "textDocument/completion").isNone

  test "getDynamicRegistrations returns empty when no registrations":
    let svc = newLspService()
    check svc.getDynamicRegistrations("nim").len == 0

  test "semantic tokens full/range honored via dynamic registration":
    privateAccess(LspService)
    let svc = newLspService()
    svc.dynamicRegistrations["nim"] = initTable[string, Registration]()
    svc.dynamicRegistrations["nim"]["reg-st"] = Registration(
      id: "reg-st",
      `method`: "textDocument/semanticTokens",
      registerOptions: some(%*{"full": {"delta": false}, "range": true}),
    )
    check svc.hasSemanticTokensSupport("nim")
    check svc.hasSemanticTokensFullSupport("nim")
    check svc.hasSemanticTokensRangeSupport("nim")

  test "semantic tokens dynamic registration with range disabled":
    privateAccess(LspService)
    let svc = newLspService()
    svc.dynamicRegistrations["nim"] = initTable[string, Registration]()
    svc.dynamicRegistrations["nim"]["reg-st"] = Registration(
      id: "reg-st",
      `method`: "textDocument/semanticTokens",
      registerOptions: some(%*{"full": true, "range": false}),
    )
    check svc.hasSemanticTokensFullSupport("nim")
    check not svc.hasSemanticTokensRangeSupport("nim")

  test "semantic tokens full served by separate method dynamic registration":
    privateAccess(LspService)
    let svc = newLspService()
    svc.dynamicRegistrations["nim"] = initTable[string, Registration]()
    svc.dynamicRegistrations["nim"]["reg-full"] =
      Registration(id: "reg-full", `method`: "textDocument/semanticTokens/full")
    check svc.hasSemanticTokensSupport("nim")
    check svc.hasSemanticTokensFullSupport("nim")
    check not svc.hasSemanticTokensRangeSupport("nim")

  test "semantic tokens range served by separate method dynamic registration":
    privateAccess(LspService)
    let svc = newLspService()
    svc.dynamicRegistrations["nim"] = initTable[string, Registration]()
    svc.dynamicRegistrations["nim"]["reg-range"] =
      Registration(id: "reg-range", `method`: "textDocument/semanticTokens/range")
    check svc.hasSemanticTokensRangeSupport("nim")

suite "LspService - Request Methods (error cases for unsupported files)":
  # Use unsupported file extension to avoid worker startup
  test "startCompletionRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startCompletionRequest("/tmp/test.xyz", 0, 0)
    check result.isErr
    check "No LSP support" in result.error

  test "startHoverRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startHoverRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startDefinitionRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startDefinitionRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startDeclarationRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startDeclarationRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startReferencesRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startReferencesRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startTypeDefinitionRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startTypeDefinitionRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startImplementationRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startImplementationRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startDocumentSymbolsRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startDocumentSymbolsRequest("/tmp/test.xyz")
    check result.isErr

  test "startSelectionRangeRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startSelectionRangeRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startSignatureHelpRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startSignatureHelpRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startDocumentHighlightRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startDocumentHighlightRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

  test "startCodeLensRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startCodeLensRequest("/tmp/test.xyz")
    check result.isErr

  test "startDocumentLinkRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startDocumentLinkRequest("/tmp/test.xyz")
    check result.isErr

  test "startSemanticTokensFullRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startSemanticTokensFullRequest("/tmp/test.xyz")
    check result.isErr

  test "startSemanticTokensRangeRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startSemanticTokensRangeRequest("/tmp/test.xyz", 0, 0, 10, 0)
    check result.isErr

  test "startCallHierarchyPrepareRequest fails for unsupported file":
    let svc = newLspService()
    let result = svc.startCallHierarchyPrepareRequest("/tmp/test.xyz", 0, 0)
    check result.isErr

suite "LspService - Document Notifications (error cases without workers)":
  test "notifyDocumentOpened fails for unsupported file":
    let svc = newLspService()
    let result = svc.notifyDocumentOpened("/tmp/test.xyz", "content")
    check result.isErr

  test "notifyDocumentChanged returns ok for unsupported file":
    let svc = newLspService()
    let result = svc.notifyDocumentChanged("/tmp/test.xyz", 1, "content")
    check result.isOk # Returns ok because no LSP for this file type

  test "notifyDocumentClosed returns ok for unsupported file":
    let svc = newLspService()
    let result = svc.notifyDocumentClosed("/tmp/test.xyz")
    check result.isOk

  test "notifyDocumentSaved returns ok for unsupported file":
    let svc = newLspService()
    let result = svc.notifyDocumentSaved("/tmp/test.xyz")
    check result.isOk

  test "notifyDocumentChanged returns ok when no worker started":
    let svc = newLspService()
    let result = svc.notifyDocumentChanged("/tmp/test.nim", 1, "content")
    check result.isOk # Returns ok because worker not started

  test "notifyDocumentClosed returns ok when no worker started":
    let svc = newLspService()
    let result = svc.notifyDocumentClosed("/tmp/test.nim")
    check result.isOk

  test "notifyDocumentSaved returns ok when no worker started":
    let svc = newLspService()
    let result = svc.notifyDocumentSaved("/tmp/test.nim")
    check result.isOk

suite "LspService - Poll":
  test "poll with no workers does nothing":
    let svc = newLspService()
    svc.poll() # Should not crash
    svc.poll(100) # With timeout

suite "LspService - processEvent (thread-boundary JSON parsing)":
  privateAccess(LspService)

  test "levResponse stores the raw result string verbatim":
    let svc = newLspService()
    svc.activeRequests[7] = LspPendingRequest(requestId: 7, langId: "nim")
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levResponse,
        requestId: 7,
        responseResultJson: some($(%*{"items": [1, 2]})),
        responseError: none(string),
      ),
    )
    check 7 in svc.pendingResponses
    let resp = svc.pendingResponses[7]
    check resp.result.isSome
    check resp.result.get == $(%*{"items": [1, 2]})
    check resp.error.isNone

  test "checkResponse surfaces a parse error for invalid JSON":
    # Parsing is deferred to consumption, so a malformed payload is stored as-is
    # and only fails when checkResponse tries to turn it into a JsonNode.
    let svc = newLspService()
    svc.activeRequests[8] = LspPendingRequest(requestId: 8, langId: "nim")
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levResponse,
        requestId: 8,
        responseResultJson: some("{invalid json"),
        responseError: none(string),
      ),
    )
    let (status, resultOpt, errorOpt) = svc.checkResponse(8)
    check status == lrsError
    check resultOpt.isNone
    check errorOpt.isSome
    check errorOpt.get.contains("Failed to parse response")

  test "levResponse for an unknown/timed-out request is dropped":
    # A response arriving after the request was timed out (no activeRequests
    # entry) must not be stored, or it would leak in pendingResponses forever.
    let svc = newLspService()
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levResponse,
        requestId: 99,
        responseResultJson: some($(%*{"ok": true})),
        responseError: none(string),
      ),
    )
    check 99 notin svc.pendingResponses
    check svc.pendingResponses.len == 0

  test "recordResponse stores only for active requests":
    let svc = newLspService()
    svc.activeRequests[1] = LspPendingRequest(requestId: 1, langId: "nim")
    svc.recordResponse(1, some($(%*{"a": 1})), none(string))
    svc.recordResponse(2, some($(%*{"b": 2})), none(string)) # not active -> dropped
    check 1 in svc.pendingResponses
    check 2 notin svc.pendingResponses

  test "late response after cleanupTimedOutRequests does not leak":
    let svc = newLspService()
    # An already-expired request
    svc.activeRequests[5] =
      LspPendingRequest(requestId: 5, langId: "nim", startTime: 0.0, timeoutMs: 1)
    svc.cleanupTimedOutRequests()
    check 5 notin svc.activeRequests
    # The worker's response arrives afterwards
    svc.recordResponse(5, some($(%*{"late": true})), none(string))
    check svc.pendingResponses.len == 0

  test "levDiagnostics is parsed and forwarded to the callback":
    let svc = newLspService()
    var gotUri = ""
    var gotDiags: seq[Diagnostic] = @[]
    svc.onDiagnosticsUpdate = proc(
        uri: string, diagnostics: seq[Diagnostic], version: Option[int]
    ) {.gcsafe.} =
      {.cast(gcsafe).}:
        gotUri = uri
        gotDiags = diagnostics
    let diagsJson = $(
      %*[
        {
          "range":
            {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 5}},
          "severity": 2,
          "message": "unused variable",
        }
      ]
    )
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levDiagnostics, diagUri: "file:///t.nim", diagnosticsJson: diagsJson
      ),
    )
    check gotUri == "file:///t.nim"
    check gotDiags.len == 1
    check gotDiags[0].message == "unused variable"

  test "levDiagnostics with invalid JSON does not invoke the callback":
    let svc = newLspService()
    var called = false
    svc.onDiagnosticsUpdate = proc(
        uri: string, diagnostics: seq[Diagnostic], version: Option[int]
    ) {.gcsafe.} =
      called = true
    svc.processEvent(
      "nim",
      LspEvent(kind: levDiagnostics, diagUri: "file:///t.nim", diagnosticsJson: "[oops"),
    )
    check not called

  test "levCapabilities is parsed and stored":
    let svc = newLspService()
    svc.processEvent(
      "nim",
      LspEvent(kind: levCapabilities, capabilitiesJson: $(%*{"hoverProvider": true})),
    )
    check "nim" in svc.capabilities

  test "levRawJson forwards pretty, timestamped lines to the viewer when verbose":
    let svc = newLspService()
    svc.setConfig("nim", LanguageServerConfig(enabled: true, traceLevel: traceVerbose))
    var logs: seq[string] = @[]
    svc.onLogMessage = proc(
        langId: string, msgType: MessageType, message: string
    ) {.gcsafe.} =
      {.cast(gcsafe).}:
        logs.add(message)
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levRawJson,
        jsonDirection: ljdSent,
        rawJson: """{"method":"initialize","id":1}""",
      ),
    )
    # Re-prettified on the main thread -> multiple lines, first one marked >>>.
    check logs.len >= 2
    let joined = logs.join("\n")
    check joined.contains(">>> ")
    check joined.contains("\"method\"")
    check joined.contains("initialize")

  test "levRawJson does not touch the viewer when trace is off":
    let svc = newLspService()
    svc.setConfig("nim", LanguageServerConfig(enabled: true, traceLevel: traceOff))
    var called = false
    svc.onLogMessage = proc(
        langId: string, msgType: MessageType, message: string
    ) {.gcsafe.} =
      {.cast(gcsafe).}:
        called = true
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levRawJson, jsonDirection: ljdReceived, rawJson: """{"result":null}"""
      ),
    )
    check not called

  test "levRawJson also forwards to the viewer when trace = messages":
    # Previously the viewer only fired for `verbose`; `messages` was silently
    # treated as `off`. Any non-off level must now reach the viewer.
    let svc = newLspService()
    svc.setConfig("nim", LanguageServerConfig(enabled: true, traceLevel: traceMessages))
    var called = false
    svc.onLogMessage = proc(
        langId: string, msgType: MessageType, message: string
    ) {.gcsafe.} =
      {.cast(gcsafe).}:
        called = true
    svc.processEvent(
      "nim",
      LspEvent(
        kind: levRawJson,
        jsonDirection: ljdSent,
        rawJson: """{"method":"initialize","id":1}""",
      ),
    )
    check called

  test "levRawJson mirrors a compact line to the debug log file when -d is on":
    # File logging is independent of the per-server trace level: only the
    # debug logger being enabled (-d) gates it.
    privateAccess(Logger)
    let svc = newLspService()
    svc.setConfig("nim", LanguageServerConfig(enabled: true, traceLevel: traceOff))
    let prev = getGlobalLogger()
    let logger = initLogger(enabled = true)
    setGlobalLogger(logger)
    try:
      # On a read-only CWD the logger disables itself; only assert when it opened.
      if logger.isEnabled:
        let payload = """{"method":"textDocument/hover","id":7}"""
        svc.processEvent(
          "nim", LspEvent(kind: levRawJson, jsonDirection: ljdSent, rawJson: payload)
        )
        logger.close()
        let content = readFile(logger.filePath)
        check content.contains("[lsp] nim >>> " & payload)
    finally:
      setGlobalLogger(prev)

  test "levDynamicRegister is parsed and stored":
    let svc = newLspService()
    let paramsJson =
      $(%*{"registrations": [{"id": "r1", "method": "textDocument/completion"}]})
    svc.processEvent(
      "nim", LspEvent(kind: levDynamicRegister, registrationsJson: paramsJson)
    )
    check "nim" in svc.dynamicRegistrations
    check "r1" in svc.dynamicRegistrations["nim"]

  test "levApplyEdit parses the edit and invokes onApplyWorkspaceEdit":
    let svc = newLspService()
    var gotEdit: WorkspaceEdit
    var called = false
    svc.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        called = true
        gotEdit = edit
      (applied: true, failureReason: none(string))
    let editJson = $(
      %*{
        "changes": {
          "file:///t.nim": [
            {
              "range": {
                "start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}
              },
              "newText": "x",
            }
          ]
        }
      }
    )
    svc.processEvent(
      "nim",
      LspEvent(kind: levApplyEdit, applyEditReqIdJson: "7", applyEditEditJson: editJson),
    )
    check called
    check gotEdit.changes.isSome
    check "file:///t.nim" in gotEdit.changes.get

  test "levApplyEdit with invalid JSON does not invoke onApplyWorkspaceEdit":
    let svc = newLspService()
    var called = false
    svc.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      called = true
      (applied: true, failureReason: none(string))
    svc.processEvent(
      "nim",
      LspEvent(kind: levApplyEdit, applyEditReqIdJson: "7", applyEditEditJson: "{oops"),
    )
    check not called

  test "levApplyEdit swallows a throwing apply callback (server still answerable)":
    # The server blocks on the ApplyWorkspaceEditResponse, so an exception raised
    # while applying the edit must NOT escape processEvent (it would otherwise
    # propagate out of poll() and tear the editor down via emergencySaveAndQuit,
    # while the server waits forever). processEvent must return normally.
    let svc = newLspService()
    var called = false
    svc.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        called = true
      raise newException(ValueError, "apply blew up")
    let editJson = $(%*{"changes": {"file:///t.nim": []}})
    # Must not raise.
    svc.processEvent(
      "nim",
      LspEvent(kind: levApplyEdit, applyEditReqIdJson: "7", applyEditEditJson: editJson),
    )
    check called

  test "first levInitialized records the language but does not fire onServerRestart":
    # Normal startup: the editor already sent didOpen at file-open time, so the
    # restart hook must stay silent.
    let svc = newLspService()
    var restarts: seq[string] = @[]
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        restarts.add(langId)
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check restarts.len == 0
    check "nim" in svc.initializedLangs

  test "repeat levInitialized fires onServerRestart (crash recovery)":
    # A second initialize for the same language means the server crashed and
    # restarted with no open documents: the editor must re-open them.
    let svc = newLspService()
    var restarts: seq[string] = @[]
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        restarts.add(langId)
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check restarts == @["nim"]

  test "onServerRestart is per-language":
    let svc = newLspService()
    var restarts: seq[string] = @[]
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        restarts.add(langId)
    # First init of two different languages: neither is a restart.
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    svc.processEvent("rust", LspEvent(kind: levInitialized))
    check restarts.len == 0
    # Only rust re-initializes.
    svc.processEvent("rust", LspEvent(kind: levInitialized))
    check restarts == @["rust"]

suite "LspService - crash recovery scenario":
  # The lifecycle at the service layer: a server initializes, crashes,
  # is auto-restarted, re-initializes, and the editor re-syncs its open
  # documents. The worker is not run as a real thread/process here; it is mocked
  # as the event stream the service observes (levInitialized on each (re)init),
  # and the editor's re-sync handler is modeled by a callback that repopulates
  # the set of documents the live server knows about. This drives the service's
  # state machine (initializedLangs + onServerRestart) end to end, asserting the
  # *ordering* of the transitions rather than each branch in isolation.
  privateAccess(LspService)

  test "initialize -> crash -> auto-restart -> document re-sync":
    let svc = newLspService()
    let uri = "file:///proj/main.nim"

    # `serverDocs` models the documents the *current* server process knows. A
    # crash drops them; the re-sync handler (mirroring renotifyOpenBuffers in
    # editor_lsp.nim) re-sends didOpen on restart, restoring them.
    var serverDocs = initHashSet[string]()
    var resyncCount = 0
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc resyncCount
        serverDocs.incl(uri) # editor re-sends didOpen for the open buffer

    # 1. Normal startup. The editor sends didOpen at file-open time; the worker
    #    queues it and flushes on initialize. The first initialize is NOT a
    #    crash recovery, so the re-sync hook must stay silent.
    serverDocs.incl(uri)
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check "nim" in svc.initializedLangs
    check resyncCount == 0
    check uri in serverDocs

    # 2. The server crashes (worker -> lwsCrashed). The respawned process starts
    #    with no open documents.
    serverDocs.clear()

    # 3. The auto-restart re-initializes. This second initialize for the same
    #    language is the crash-recovery signal: onServerRestart fires and the
    #    editor re-opens the buffer.
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check resyncCount == 1
    check uri in serverDocs # document re-synced to the restarted server
    check "nim" in svc.initializedLangs # recovery leaves the record intact

    # 4. Every subsequent crash+restart cycle re-syncs again.
    serverDocs.clear()
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check resyncCount == 2
    check uri in serverDocs

  test "re-sync is scoped to the crashed language only":
    # A crash in one language must not re-open another language's buffers.
    let svc = newLspService()
    var resynced: seq[string] = @[]
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        resynced.add(langId)

    # Both languages start up normally (first init each).
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    svc.processEvent("rust", LspEvent(kind: levInitialized))
    check resynced.len == 0

    # Only nim crashes and restarts.
    svc.processEvent("nim", LspEvent(kind: levInitialized))
    check resynced == @["nim"]
    check "rust" in svc.initializedLangs # rust untouched

  test "explicit restart (stopWorker) is a fresh start, not a crash recovery":
    # `:lspRestart` stops the worker then starts it again, re-opening buffers
    # itself. stopWorker clears initializedLangs so the next initialize is
    # treated as a first init, not a re-sync; otherwise every buffer would be
    # re-opened twice (once by the explicit restart, once by a bogus recovery).
    let svc = newLspService()
    var resyncCount = 0
    svc.onServerRestart = proc(langId: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc resyncCount

    # stopWorker only clears bookkeeping when a worker is present. Create one
    # without starting its thread: stop() skips the join when threadStarted is
    # false, so no real server/process is involved.
    svc.workers["nim"] = newLspWorker("nim").get

    svc.processEvent("nim", LspEvent(kind: levInitialized)) # first init
    check "nim" in svc.initializedLangs
    check resyncCount == 0

    check svc.stopWorker("nim").isOk # :lspRestart, step 1
    check "nim" notin svc.initializedLangs

    svc.processEvent("nim", LspEvent(kind: levInitialized)) # restart re-init
    check resyncCount == 0 # fresh start, NOT a crash recovery
    check "nim" in svc.initializedLangs

suite "LspService - LspResponseStatus enum":
  test "LspResponseStatus values":
    check lrsPending < lrsSuccess
    check lrsSuccess < lrsError
    check lrsError < lrsTimeout

suite "LspService - Callback Setup":
  test "can set custom onDiagnosticsUpdate callback":
    let svc = newLspService()
    var called = false
    svc.onDiagnosticsUpdate = proc(
        uri: string, diagnostics: seq[Diagnostic], version: Option[int]
    ) {.gcsafe.} =
      called = true
    svc.onDiagnosticsUpdate("test", @[], none(int))
    check called

  test "can set custom onLogMessage callback":
    let svc = newLspService()
    var called = false
    svc.onLogMessage = proc(
        langId: string, msgType: MessageType, message: string
    ) {.gcsafe.} =
      called = true
    svc.onLogMessage("nim", mtInfo, "test")
    check called

  test "can set custom onProgress callback":
    let svc = newLspService()
    var called = false
    svc.onProgress = proc(
        langId: string, token: string, progress: WorkDoneProgress
    ) {.gcsafe.} =
      called = true
    svc.onProgress("nim", "token", WorkDoneProgress())
    check called

  test "can set custom onStatusUpdate callback":
    let svc = newLspService()
    var called = false
    svc.onStatusUpdate = proc(
        langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
    ) {.gcsafe.} =
      called = true
    svc.onStatusUpdate("nim", shOk, true, none(string))
    check called

suite "LspService - Constants":
  test "DefaultRequestTimeoutMs matches worker RequestTimeoutSec":
    check DefaultRequestTimeoutMs == RequestTimeoutSec * 1000

suite "LspService - LanguageServerConfig":
  test "LanguageServerConfig has all expected fields":
    let config = LanguageServerConfig(
      command: "test-lsp",
      args: @["--arg1", "--arg2"],
      extensions: @["ext1", "ext2"],
      enabled: true,
    )
    check config.command == "test-lsp"
    check config.args == @["--arg1", "--arg2"]
    check config.extensions == @["ext1", "ext2"]
    check config.enabled

suite "LspService - LspPendingRequest":
  test "LspPendingRequest has all expected fields":
    let req = LspPendingRequest(
      requestId: 42,
      langId: "nim",
      methodName: "textDocument/completion",
      startTime: epochTime(),
      timeoutMs: 5000,
    )
    check req.requestId == 42
    check req.langId == "nim"
    check req.methodName == "textDocument/completion"
    check req.timeoutMs == 5000

suite "LspService - request timeout":
  test "defaults to DefaultRequestTimeoutMs":
    let svc = newLspService()
    check svc.requestTimeoutMs == DefaultRequestTimeoutMs

  test "setRequestTimeout applies a positive value":
    let svc = newLspService()
    svc.setRequestTimeout(12000)
    check svc.requestTimeoutMs == 12000

  test "setRequestTimeout ignores non-positive values":
    let svc = newLspService()
    svc.setRequestTimeout(8000)
    svc.setRequestTimeout(0)
    svc.setRequestTimeout(-1)
    check svc.requestTimeoutMs == 8000

suite "LspService - documentSyncKind":
  privateAccess(LspService)

  const NimPath = "/tmp/x.nim"

  proc withCaps(caps: JsonNode): LspService =
    result = newLspService()
    result.processEvent("nim", LspEvent(kind: levCapabilities, capabilitiesJson: $caps))

  test "defaults to Full when no capabilities received":
    # Deliberate divergence from the LSP spec (default None) to avoid a
    # regression for servers that under-advertise capabilities.
    let svc = newLspService()
    check svc.documentSyncKind(NimPath) == tdskFull

  test "static int form: 0/1/2":
    check withCaps(%*{"textDocumentSync": 0}).documentSyncKind(NimPath) == tdskNone
    check withCaps(%*{"textDocumentSync": 1}).documentSyncKind(NimPath) == tdskFull
    check withCaps(%*{"textDocumentSync": 2}).documentSyncKind(NimPath) ==
      tdskIncremental

  test "static object form: change present":
    check withCaps(%*{"textDocumentSync": {"change": 2}}).documentSyncKind(NimPath) ==
      tdskIncremental
    check withCaps(%*{"textDocumentSync": {"change": 0}}).documentSyncKind(NimPath) ==
      tdskNone

  test "static object without change -> Full":
    # An object that omits `change` defaults to Full (don't under-advertise),
    # not None; only an explicit `change: 0` opts the server out of didChange.
    check withCaps(%*{"textDocumentSync": {"openClose": true}}).documentSyncKind(
      NimPath
    ) == tdskFull

  test "malformed value falls back to Full":
    check withCaps(%*{"textDocumentSync": 9}).documentSyncKind(NimPath) == tdskFull
    check withCaps(%*{"textDocumentSync": {"change": 9}}).documentSyncKind(NimPath) ==
      tdskFull

  test "dynamic registration syncKind overrides static":
    let svc = withCaps(%*{"textDocumentSync": 0})
    svc.dynamicRegistrations["nim"] = initTable[string, Registration]()
    svc.dynamicRegistrations["nim"]["reg-dc"] = Registration(
      id: "reg-dc",
      `method`: "textDocument/didChange",
      registerOptions: some(%*{"syncKind": 2}),
    )
    check svc.documentSyncKind(NimPath) == tdskIncremental

  test "unknown file type -> Full":
    let svc = newLspService()
    check svc.documentSyncKind("/tmp/x.unknownext") == tdskFull

  test "crash restart clears stale capabilities but keeps initializedLangs":
    proc waitForState(
        worker: LspWorker, expected: LspWorkerState, timeoutMs = 5000
    ): bool =
      let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
      while getMonoTime() < deadline:
        if worker.state == expected:
          return true
        sleep(10)
      false

    let svc = newLspService()
    # A "server" that exits immediately -> initialize fails -> lwsCrashed.
    svc.setConfig(
      "crashlang",
      LanguageServerConfig(
        command: "true", args: @[], extensions: @["crashext"], enabled: true
      ),
    )
    const Path = "/tmp/x.crashext"

    let started = svc.startWorker("crashlang")
    check started.isOk
    let worker = started.get
    check worker.waitForState(lwsCrashed)

    # Simulate the now-crashed server having advertised incremental sync while
    # it was alive (capabilities + a completed initialize).
    svc.processEvent(
      "crashlang",
      LspEvent(kind: levCapabilities, capabilitiesJson: $(%*{"textDocumentSync": 2})),
    )
    svc.processEvent("crashlang", LspEvent(kind: levInitialized))
    check svc.documentSyncKind(Path) == tdskIncremental
    check "crashlang" in svc.initializedLangs

    # Restarting drops the stale capabilities (-> conservative Full during the
    # window) but keeps initializedLangs so onServerRestart still re-opens
    # buffers after the next initialize.
    check svc.startWorker("crashlang").isOk
    check "crashlang" notin svc.capabilities
    check svc.documentSyncKind(Path) == tdskFull
    check "crashlang" in svc.initializedLangs

    worker.stop()

suite "LspService - isWorkerRunningForPath":
  privateAccess(LspService)

  const NimPath = "/tmp/x.nim"

  test "no worker and no override -> false":
    let svc = newLspService()
    check not svc.isWorkerRunningForPath(NimPath)

  test "liveWorkerOverride true without runningWorkerOverride -> true (fallback)":
    let svc = newLspService()
    svc.liveWorkerOverride = proc(path: string): bool =
      true
    check svc.isWorkerRunningForPath(NimPath)

  test "runningWorkerOverride false overrides liveWorkerOverride true":
    let svc = newLspService()
    svc.liveWorkerOverride = proc(path: string): bool =
      true
    svc.runningWorkerOverride = proc(path: string): bool =
      false
    check not svc.isWorkerRunningForPath(NimPath)

  test "runningWorkerOverride true without a real worker -> true":
    let svc = newLspService()
    svc.runningWorkerOverride = proc(path: string): bool =
      true
    check svc.isWorkerRunningForPath(NimPath)
