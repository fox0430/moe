#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, importutils, os, osproc, options, tables, json]
import pkg/results
import moepkg/independentutils
import moepkg/lsp/protocol/[enums, types]
import moepkg/lsp/utils

import utils

import moepkg/settings {.all.}
import moepkg/lsp/client {.all.}

suite "lsp: setCapabilities":
  var client: LspClient

  setup:
    client = LspClient()

  test "Enable Completion":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          completionProvider: some(CompletionOptions())))

      s = LspFeatureSettings(
        completion: LspCompletionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.completion.isSome

  test "Disable Completion 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          completionProvider: none(CompletionOptions)))

      s = LspFeatureSettings(
        completion: LspCompletionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.completion.isNone

  test "Disable Completion 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          completionProvider: some(CompletionOptions())))

      s = LspFeatureSettings(
        completion: LspCompletionSettings(
          enable: false))

    client.setCapabilities(r, s)

    check client.capabilities.get.completion.isNone

  test "Enable Definition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(true)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.definition

  test "Disable Definition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(false)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.definition

  test "Disable Definition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(true)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.definition

  test "Enable TypeDefinition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(true)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.typeDefinition

  test "Disable TypeDefinition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(false)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.typeDefinition

  test "Disable TypeDefinition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(true)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.typeDefinition

  test "Enable Diagnostic 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          diagnosticProvider: some(%*{
            "identifier": none(string),
            "interFileDependencies": false,
            "workspaceDiagnostics": false
          })))

      s = LspFeatureSettings(
        diagnostics: LspDiagnosticsSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.diagnostics

  test "Enable Diagnostic 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          diagnosticProvider: some(%*{
            "identifier": none(string),
            "interFileDependencies": false,
            "workspaceDiagnostics": false,
            "id": none(string)
          })))

      s = LspFeatureSettings(
        diagnostics: LspDiagnosticsSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.diagnostics

  test "Disable Diagnostic 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          diagnosticProvider: none(JsonNode)))

      s = LspFeatureSettings(
        diagnostics: LspDiagnosticsSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.diagnostics

  test "Disable Diagnostic 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          diagnosticProvider: some(%*{
            "identifier": none(string),
            "interFileDependencies": false,
            "workspaceDiagnostics": false,
            "id": none(string)
          })))

      s = LspFeatureSettings(
        diagnostics: LspDiagnosticsSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.diagnostics

  test "Enable Hover":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(true)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.hover

  test "Disable Hover 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(false)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.hover

  test "Disable Hover 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(true)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.hover

  test "Enable SemanticTokens":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          semanticTokensProvider: some(%*{
            "legend": {
              "tokenTypes": @[""],
              "tokenModifiers": @[""]
            }
          })))

      s = LspFeatureSettings(
        semanticTokens: LspSemanticTokesnSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.semanticTokens.isSome

  test "Disable SemanticTokens 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          semanticTokensProvider: none(JsonNode)))

      s = LspFeatureSettings(
        semanticTokens: LspSemanticTokesnSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.semanticTokens.isNone

  test "Disable SemanticTokens 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          semanticTokensProvider: some(%*{
            "legend": {
              "tokenTypes": @[""],
              "tokenModifiers": @[""]
            }
          })))

      s = LspFeatureSettings(
        semanticTokens: LspSemanticTokesnSettings(
          enable: false))

    client.setCapabilities(r, s)

    check client.capabilities.get.semanticTokens.isNone

  test "Enable InlayHint":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: some(InlayHintOptions())))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.inlayHint

  test "Disable InlayHint 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: none(InlayHintOptions)))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlayHint

  test "Disable InlayHint 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: some(InlayHintOptions())))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlayHint

  test "Enable Rename":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          renameProvider: some(%*{"prepareProvider": true})))

      s = LspFeatureSettings(
        rename: LspRenameSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.rename

  test "Disable Rename":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          renameProvider: none(JsonNode)))

      s = LspFeatureSettings(
        rename: LspRenameSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.rename

  test "Disable Rename 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: some(InlayHintOptions())))

      s = LspFeatureSettings(
        rename: LspRenameSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.rename

suite "lsp: Send requests":
  privateAccess(LspClient)

  const
    Command = "nimlangserver"
    Trace = TraceValue.verbose
    Timeout = 5000

  let rootDir = getCurrentDir() / "lspTestDir"

  var client: LspClient

  setup:
    if isNimlangserverAvailable():
      client = initLspClient(Command).get
      createDir(rootDir)

  teardown:
    if dirExists(rootDir):
      removeDir(rootDir)

  test "Send initialize":
    if not isNimlangserverAvailable():
      skip()
    else:
      const BufferId = 1
      let params = initInitializeParams(rootDir, Trace)

      check client.initialize(BufferId, params).isOk
      check client.waitingResponses[1].lspMethod == LspMethod.initialize

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["id"].getInt == 1
      check client.initCapacities(initLspFeatureSettings(), res).isOk

  test "Send textDocument/didOpen":
    if not isNimlangserverAvailable():
      skip()
    else:
      const BufferId = 1

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(BufferId, params).isOk

        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(
            initLspFeatureSettings(),
            initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

      const LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      check client.textDocumentDidOpen(path, LanguageId, text).isOk

  template prepareLsp(bufferId: int, langId: LanguageId, path, text: string) =
    block:
      let params = initInitializeParams(rootDir, Trace)
      assert client.initialize(BufferId, params).isOk

    assert client.readable(Timeout).isOk
    let initializeRes = client.read.get
    assert client.initCapacities(initLspFeatureSettings(), initializeRes).isOk

    assert client.initialized.isOk

    assert client.workspaceDidChangeConfiguration.isOk

    check client.textDocumentDidOpen(path, langId, text).isOk

    while client.readable(Timeout).get:
      let res = client.read.get
      if res.contains("id") and res["id"].getInt > client.lastId:
        client.lastId = res["id"].getInt

  test "Send $/cancelRequest":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "let a: int = 0"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      let requestId = client.lastId + 1

      # Send hover request and cancel
      block:
        let position = BufferPosition(line: 0, column: 7)
        check client.textDocumentHover(BufferId, path, position).isOk
        check client.waitingResponses[requestId].lspMethod == LspMethod.textDocumentHover

      check client.cancelRequest(BufferId, requestId).isOk

  test "Send shutdown":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1

      block:
        # Initialize

        let params = initInitializeParams(rootDir, Trace)

        check client.initialize(BufferId, params).isOk
        check client.waitingResponses[1].lspMethod == LspMethod.initialize

        assert client.readable(Timeout).get
        let res = client.read.get
        check res["id"].getInt == 1
        check client.initCapacities(initLspFeatureSettings(), res).isOk

      let requestId = client.lastId + 1

      check client.shutdown(BufferId).isOk

      assert client.readable(Timeout).get
      check client.waitingResponses[requestId].lspMethod == LspMethod.shutdown

      let res = client.read.get
      check res["id"].getInt == requestId
      check res["result"].kind == JNull

  test "Send workspace/didChangeConfiguration":
    if not isNimlangserverAvailable():
      skip()
    else:
      block:
        # Initialize LSP client

        const BufferId = 1
        let rootPath = getCurrentDir()

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(BufferId, params).isOk

        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(
            initLspFeatureSettings(),
            initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

      check client.workspaceDidChangeConfiguration.isOk

  test "Send textDocument/didChange":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "echo 0"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      const
        SecondVersion = 2
        ChangedText = "echo 1"
      check client.textDocumentDidChange(SecondVersion, path, ChangedText).isOk

  test "Send textDocument/didSave":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "echo 0"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      const Version = 1
      check client.textDocumentDidSave(Version, path, Text).isOk

  test "Send textDocument/didClose":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "echo 0"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      check client.textDocumentDidClose(path).isOk

  test "Send textDocument/hover":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "let a: int = 0"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      let position = BufferPosition(line: 0, column: 7)
      var requestId = client.lastId + 1

      check client.textDocumentHover(BufferId, path, position).isOk
      check client.waitingResponses[requestId].lspMethod == LspMethod.textDocumentHover

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"]["contents"][0]["value"].getStr == "system.int: int"

  test "Send textDocument/completion":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "echo 1\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      block:
        const SecondVersion = 2
        let changedText = "echo 1\ne"
        check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

      var requestId = client.lastId + 1

      let position = BufferPosition(line: 1, column: 0)
      const IsIncompleteTrigger = false
      check client.textDocumentCompletion(
        BufferId,
        path,
        position,
        IsIncompleteTrigger,
        "e").isOk
      check client.waitingResponses[requestId].lspMethod == LspMethod.textDocumentCompletion

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"][0].len > 0

  test "Send textDocument/inlayHint":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "let a = 0\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      var requestId = client.lastId + 1

      check client.textDocumentInlayHint(
        BufferId,
        path,
        BufferRange(
          first: BufferPosition(line: 0, column: 0),
          last: BufferPosition(line: 0, column: Text.high))).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentInlayHint

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"][0]["position"]["line"].getInt == 0
      check res["result"][0]["position"]["character"].getInt == 5

  test "Send textDocument/definition":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = """
type number = int
var num: number
        """

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentDefinition(
        BufferId,
        path,
        BufferPosition(line: 1, column: 9)).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentDefinition

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"] == %* [
        {
          "uri": "file://" & getCurrentDir() & "/lspTestDir/test.nim",
          "range": {
            "start": {
              "line": 0,
              "character":5
            },"end": {
              "line":0,
              "character":11
            }}
        }
      ]

  test "Send textDocument/typeDefinition":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = """
type number = int
var num: number
        """

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentTypeDefinition(
        BufferId,
        path,
        BufferPosition(line: 1, column: 9)).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentTypeDefinition

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"] == %* [
        {
          "uri": "file://" & getCurrentDir() & "/lspTestDir/test.nim",
          "range": {
            "start": {
              "line": 0,
              "character": 5},
            "end": {
              "line": 0,
              "character":11
            }
          }
        }
      ]

  test "Send textDocument/rename":
    if not isNimlangserverAvailable():
      skip()
    else:
      block:
        const Text = """
type Obj* = object
  n*: int
"""

        let path = rootDir / "test1.nim"
        writeFile(path, Text)

      const
        BufferId = 1
        LanguageId = "nim"
        Text = """
import test1
let o = Obj()
echo Ojb(n: 1)
        """

      let path = rootDir / "test2.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentRename(
        BufferId,
        path,
        BufferPosition(line: 1, column: 8),
        "newName").isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentRename

      assert client.readable(Timeout).get
      let res = client.read.get
      check res["result"] == %* {
        "changes": {
          "file://" & getCurrentDir() & "/lspTestDir/test2.nim": [
            {
              "range": {
                "start": {
                  "line": 1,
                  "character": 8
                },
                "end": {
                  "line": 1,
                  "character": 11
                }
              },
              "newText" :"newName"
            }
          ],
          "file://" & getCurrentDir() & "/lspTestDir/test1.nim": [
            {
              "range": {
                "start": {
                  "line": 0,
                  "character": 5
                },
                "end": {
                  "line": 0,
                  "character": 8
                }
              },
              "newText": "newName"
            }
          ]
        },
        "documentChanges": nil
      }
