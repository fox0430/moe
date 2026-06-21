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

import std/[unittest, json, options, strutils]

import pkg/results

import ../src/moepkg/lsp/jsonrpc
import ../src/moepkg/lsp/protocol/[types, enums]
import ../src/moepkg/lsp_service
import ../src/moepkg/lsp_integration

suite "LSP JSON-RPC":
  test "encodeRequest":
    let msg = encodeRequest(1, "test/method", %*{"key": "value"})
    check msg.contains("Content-Length:")
    check msg.contains("jsonrpc")
    check msg.contains("\"id\":1")
    check msg.contains("test/method")

  test "encodeNotification":
    let msg = encodeNotification("test/notify", %*{})
    check msg.contains("Content-Length:")
    check msg.contains("jsonrpc")
    check not msg.contains("\"id\"")
    check msg.contains("test/notify")

  test "parseJsonRpcMessage response":
    let body = """{"jsonrpc":"2.0","id":1,"result":{"key":"value"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    let msg = result.get
    check msg.kind == jrmkResponse
    check msg.respId == 1

  test "parseJsonRpcMessage notification":
    let body = """{"jsonrpc":"2.0","method":"test/notify","params":{}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    let msg = result.get
    check msg.kind == jrmkNotification
    check msg.notifyMethod == "test/notify"

  test "parseJsonRpcMessage error":
    let body =
      """{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    let msg = result.get
    check msg.kind == jrmkError
    check msg.error.code == -32600

  test "JsonRpcState nextId":
    let state = newJsonRpcState()
    check state.getNextId() == 1
    check state.getNextId() == 2
    check state.getNextId() == 3

  test "JsonRpcState pending":
    let state = newJsonRpcState()
    state.addPending(1, "test/method")
    check state.hasPending(1)
    check not state.hasPending(2)

    let removed = state.removePending(1)
    check removed.isSome
    check removed.get.methodName == "test/method"
    check not state.hasPending(1)

suite "LSP Protocol Types":
  test "Position":
    let pos = newPosition(10, 5)
    check pos.line == 10
    check pos.character == 5

    let json = pos.toJson
    check json["line"].getInt == 10
    check json["character"].getInt == 5

  test "Range":
    let r = newRange(1, 0, 1, 10)
    check r.start.line == 1
    check r.start.character == 0
    check r.`end`.line == 1
    check r.`end`.character == 10

  test "parsePosition":
    let json = %*{"line": 5, "character": 3}
    let pos = parsePosition(json)
    check pos.line == 5
    check pos.character == 3

  test "parseRange":
    let json =
      %*{"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 10}}
    let r = parseRange(json)
    check r.start.line == 1
    check r.`end`.character == 10

  test "parseDiagnostic":
    let json = %*{
      "range":
        {"start": {"line": 5, "character": 0}, "end": {"line": 5, "character": 10}},
      "severity": 1,
      "message": "Test error",
    }
    let diag = parseDiagnostic(json)
    check diag.range.start.line == 5
    check diag.severity.isSome
    check diag.severity.get == dsError
    check diag.message == "Test error"

  test "parseCompletionItem":
    let json = %*{
      "label": "testFunc",
      "kind": 3,
      "detail": "func testFunc()",
      "insertText": "testFunc()",
    }
    let item = parseCompletionItem(json)
    check item.label == "testFunc"
    check item.kind.isSome
    check item.kind.get == cikFunction
    check item.detail.isSome
    check item.insertText.isSome

  test "DiagnosticSeverity values":
    check ord(dsError) == 1
    check ord(dsWarning) == 2
    check ord(dsInformation) == 3
    check ord(dsHint) == 4

  test "CompletionItemKind values":
    check ord(cikText) == 1
    check ord(cikMethod) == 2
    check ord(cikFunction) == 3
    check ord(cikVariable) == 6
    check ord(cikKeyword) == 14

suite "LspService":
  test "newLspService":
    let svc = newLspService("/tmp")
    check svc.enabled
    check svc.getConfig("nim").isSome
    check svc.getConfig("rust").isSome
    check svc.getConfig("unknown").isNone

  test "getLanguageIdFromPath nim":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("test.nim") == some("nim")
    check svc.getLanguageIdFromPath("test.nims") == some("nim")
    check svc.getLanguageIdFromPath("/path/to/file.nim") == some("nim")

  test "getLanguageIdFromPath rust":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("main.rs") == some("rust")

  test "getLanguageIdFromPath python":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("script.py") == some("python")

  test "getLanguageIdFromPath typescript":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("app.ts") == some("typescript")
    check svc.getLanguageIdFromPath("component.tsx") == some("typescript")

  test "getLanguageIdFromPath javascript":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("app.js") == some("javascript")
    check svc.getLanguageIdFromPath("module.mjs") == some("javascript")

  test "getLanguageIdFromPath unknown":
    let svc = newLspService()
    check svc.getLanguageIdFromPath("data.xyz").isNone
    check svc.getLanguageIdFromPath("noext").isNone

  test "pathToUri":
    check pathToUri("/home/user/test.nim").startsWith("file://")
    check pathToUri("file:///already/uri") == "file:///already/uri"

  test "uriToPath":
    check uriToPath("file:///home/user/test.nim") == "/home/user/test.nim"
    check uriToPath("/plain/path") == "/plain/path"

  test "setConfig":
    let svc = newLspService()
    svc.setConfig(
      "custom",
      LanguageServerConfig(
        command: "custom-lsp", args: @["--arg"], extensions: @["cust"], enabled: true
      ),
    )
    let config = svc.getConfig("custom")
    check config.isSome
    check config.get.command == "custom-lsp"
    check config.get.extensions == @["cust"]

suite "LspIntegration":
  test "newLspIntegration":
    let lsp = newLspIntegration("/tmp")
    check lsp.isEnabled()

  test "setEnabled":
    let lsp = newLspIntegration()
    check lsp.isEnabled()
    lsp.setEnabled(false)
    check not lsp.isEnabled()
    lsp.setEnabled(true)
    check lsp.isEnabled()

  test "hasServerForPath":
    let lsp = newLspIntegration()
    check lsp.hasServerForPath("test.nim")
    check lsp.hasServerForPath("main.rs")
    check not lsp.hasServerForPath("unknown.xyz")

  test "getHoverText string":
    let hover = Hover(contents: %"Simple text")
    check getHoverText(hover) == "Simple text"

  test "getHoverText MarkupContent":
    let hover = Hover(contents: %*{"kind": "markdown", "value": "# Header"})
    check getHoverText(hover) == "# Header"

  test "getHoverText array":
    let hover = Hover(contents: %*["Line 1", "Line 2"])
    let text = getHoverText(hover)
    check text.contains("Line 1")
    check text.contains("Line 2")

suite "SignatureHelp":
  test "parseSignatureHelp empty":
    let node = %*{"signatures": []}
    let sh = parseSignatureHelp(node)
    check sh.signatures.len == 0

  test "parseSignatureHelp single signature":
    let node = %*{
      "signatures": [
        {
          "label": "func(a: int, b: string)",
          "parameters": [{"label": "a: int"}, {"label": "b: string"}],
        }
      ],
      "activeSignature": 0,
      "activeParameter": 1,
    }
    let sh = parseSignatureHelp(node)
    check sh.signatures.len == 1
    check sh.signatures[0].label == "func(a: int, b: string)"
    check sh.signatures[0].parameters.isSome
    check sh.signatures[0].parameters.get.len == 2
    check sh.activeSignature == some(0)
    check sh.activeParameter == some(1)

  test "getSignatureHelpText":
    let sh = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "myFunc(x: int, y: float): string",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    check getSignatureHelpText(sh) == "myFunc(x: int, y: float): string"

  test "getSignatureHelpText with documentation":
    let sh = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "foo()",
          documentation: some(%"This is foo function"),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    let text = getSignatureHelpText(sh)
    check text.contains("foo()")
    check text.contains("This is foo function")

  test "getActiveParameterIndex":
    let sh = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "f(a, b)",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(1),
    )
    check getActiveParameterIndex(sh) == 1

  test "getParameterInfo":
    let sh = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "func(first: int, second: string)",
          documentation: none(JsonNode),
          parameters: some(
            @[
              ParameterInformation(label: "first: int", documentation: none(JsonNode)),
              ParameterInformation(
                label: "second: string", documentation: none(JsonNode)
              ),
            ]
          ),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(0),
    )
    let info = getParameterInfo(sh)
    check info.label == "func(first: int, second: string)"
    check info.start == 5 # Position of "first"
    check info.stop == 15 # End of "first: int"
