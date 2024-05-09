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

suite "lsp: Send requests":
  privateAccess(LspClient)

  const
    Command = "nimlangserver"
    Trace = TraceValue.verbose

  var client: LspClient

  setup:
    if isNimlangserverAvailable():
      client = initLspClient(Command).get

  test "Send initialize":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        RootPath = ""
      let params = initInitializeParams(RootPath, Trace)

      check client.initialize(Id, params).isOk
      check client.waitingResponses[1].lspMethod == LspMethod.initialize

  test "Send shutdown":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        RootPath = ""

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(RootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

      check client.shutdown(Id).isOk

  test "Send workspace/didChangeConfiguration":
    if not isNimlangserverAvailable():
      skip()
    else:
      block:
        # Initialize LSP client

        const Id = 1
        let rootPath = getCurrentDir()

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

  test "Send textDocument/didOpen":
    if not isNimlangserverAvailable():
      skip()
    else:
      const Id = 1

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

  test "Send textDocument/didChange":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      block:
        const SecondVersion = 2
        let changedText = "echo 1"

        check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

  test "Send textDocument/didSave":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      block:
        const Version = 1
        check client.textDocumentDidSave(Version, path, text).isOk

  test "Send textDocument/didClose":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      check client.textDocumentDidClose(path).isOk

  test "Send textDocument/hover":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"
        Text = "echo 1" # Use simple text for the test.

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

      let position = BufferPosition(line: 0, column: 0)

      check client.textDocumentHover(Id, path, position).isOk
      check client.waitingResponses[2].lspMethod == LspMethod.textDocumentHover

  test "Send textDocument/completion":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"
        Text = "echo 1\n" # Use simple text for the test.

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

      block:
        const SecondVersion = 2
        let changedText = "echo 1\ne"
        check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

      let position = BufferPosition(line: 1, column: 0)
      const IsIncompleteTrigger = false
      check client.textDocumentCompletion(
        Id,
        path,
        position,
        IsIncompleteTrigger,
        "e").isOk
      check client.waitingResponses[2].lspMethod == LspMethod.textDocumentCompletion

  test "Send textDocument/inlayHint":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"
        Text = "let a = 0\n" # Use simple text for the test.

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

        check client.textDocumentInlayHint(
          Id,
          path,
          BufferRange(
            first: BufferPosition(line: 0, column: 0),
            last: BufferPosition(line: 0, column: Text.high))).isOk

  test "Send textDocument/definition":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"

        # Use simple text for the test.
        Text = """
type number = int
var num: number
        """

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
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

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

        block:
          check client.textDocumentDefinition(
            Id,
            path,
            BufferPosition(line: 1, column: 9)).isOk
