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

suite "lsp: initInitializeParams":
  const Trace = TraceValue.verbose

  test "Disable experimental":
    const
      ServerName = "rust-analyzer"
      WorkspaceRoot = "/"

    let r = initInitializeParams(
      ServerName,
      WorkspaceRoot,
      Trace)

    check r.capabilities.experimental.isNone

  test "Enable rust-analyzer.runSingle":
    const
      ServerName = "rust-analyzer"
      WorkspaceRoot = "/"
    let experimental = %* {
        "commands": {
          "commands": [
            "rust-analyzer.runSingle"
          ]
        }
      }

    let r = initInitializeParams(
      ServerName,
      WorkspaceRoot,
      Trace,
      some(experimental))

    check r.capabilities.experimental.get == experimental

  test "Enable rust-analyzer.debugSingle":
    const
      ServerName = "rust-analyzer"
      WorkspaceRoot = "/"
    let experimental = %* {
        "commands": {
          "commands": [
            "rust-analyzer.debugSingle"
          ]
        }
      }

    let r = initInitializeParams(
      ServerName,
      WorkspaceRoot,
      Trace,
      some(experimental))

    check r.capabilities.experimental.get == experimental

suite "lsp: restart":
  privateAccess(LspClient)

  const
    ServerName = "nimlangserver"
    Command = "nimlangserver"
    Trace = TraceValue.verbose

  var client: LspClient

  setup:
    if isNimlangserverAvailable():
      client = initLspClient(Command).get

  test "Basic 1":
    if not isNimlangserverAvailable():
      skip()
    else:
      const BufferId = 1
      let params = initInitializeParams(ServerName, "/", Trace)
      check client.initialize(BufferId, params).isOk

      let
        beforePid = client.serverProcessId
        beforeLogLen = client.log.len

      check client.running

      check client.restart.isOk

      check beforePid != client.serverProcessId
      check client.log.len == beforeLogLen

  test "Basic 2":
    if not isNimlangserverAvailable():
      skip()
    else:
      const BufferId = 1
      let params = initInitializeParams(ServerName, "/", Trace)
      check client.initialize(BufferId, params).isOk

      let
        beforePid = client.serverProcessId
        beforeLogLen = client.log.len

      client.serverProcess.kill

      check client.restart.isOk

      check beforePid != client.serverProcessId
      check client.log.len == beforeLogLen

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

  test "Enable Declaration":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          declarationProvider: some(%*true)))

      s = LspFeatureSettings(
        declaration: LspDeclarationSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.declaration

  test "Disable Declaration":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          declarationProvider: none(JsonNode)))

      s = LspFeatureSettings(
        declaration: LspDeclarationSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.declaration

  test "Disable Declaration 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          declarationProvider: some(%*true)))

      s = LspFeatureSettings(
        declaration: LspDeclarationSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.declaration

  test "Enable Definition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(%*true)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.definition

  test "Enable Definition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(%*{"workDoneProgress": true})))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.definition

  test "Disable Definition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(%*false)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.definition

  test "Disable Definition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          definitionProvider: some(%*true)))

      s = LspFeatureSettings(
        definition: LspDefinitionSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.definition

  test "Enable TypeDefinition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(%*true)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.typeDefinition

  test "Enable TypeDefinition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(%*{"workDoneProgress": true})))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.typeDefinition

  test "Disable TypeDefinition":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(%*false)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.typeDefinition

  test "Disable TypeDefinition 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          typeDefinitionProvider: some(%*true)))

      s = LspFeatureSettings(
        typeDefinition: LspTypeDefinitionSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.typeDefinition

  test "Enable Implementation":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          implementationProvider: some(%*true)))

      s = LspFeatureSettings(
        implementation: LspImplementationSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.implementation

  test "Disable Implementation":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          implementationProvider: none(JsonNode)))

      s = LspFeatureSettings(
        implementation: LspImplementationSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.implementation

  test "Disable Implementation 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          implementationProvider: some(%*true)))

      s = LspFeatureSettings(
        implementation: LspImplementationSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.implementation

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
          hoverProvider: some(%*true)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.hover

  test "Enable Hover 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(%*{"workDoneProgress": true})))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.hover

  test "Disable Hover 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(%*false)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.hover

  test "Disable Hover 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          hoverProvider: some(%*true)))

      s = LspFeatureSettings(
        hover: LspHoverSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.hover

  test "Enable References":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          referencesProvider: some(%*true)))

      s = LspFeatureSettings(
        references: LspReferencesSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.references

  test "Enable References 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          referencesProvider: some(%*{"workDoneProgress": true})))

      s = LspFeatureSettings(
        references: LspReferencesSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.references

  test "Disable References":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          referencesProvider: none(JsonNode)))

      s = LspFeatureSettings(
        references: LspReferencesSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.references

  test "Disable References 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          referencesProvider: some(%*true)))

      s = LspFeatureSettings(
        references: LspReferencesSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.references

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
          inlayHintProvider: some(%*InlayHintOptions())))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.inlayHint

  test "Disable InlayHint 1":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: none(JsonNode)))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlayHint

  test "Disable InlayHint 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlayHintProvider: some(%*InlayHintOptions())))

      s = LspFeatureSettings(
        inlayHint: LspInlayHintSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlayHint

  test "Enable CallHierarchy":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          callHierarchyProvider: some(%*{"callHierarchyProvider": true})))

      s = LspFeatureSettings(
        callHierarchy: LspCallHierarchySettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.callHierarchy

  test "Disable CallHierarchy":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          callHierarchyProvider: none(JsonNode)))

      s = LspFeatureSettings(
        callHierarchy: LspCallHierarchySettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.callHierarchy

  test "Disable CallHierarchy 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          callHierarchyProvider: some(%*{"callHierarchyProvider": true})))

      s = LspFeatureSettings(
        callHierarchy: LspCallHierarchySettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.callHierarchy

  test "Enable DocumentHighlight":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentHighlightProvider: some(%*true)))

      s = LspFeatureSettings(
        documentHighlight: LspDocumentHighlightSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.documentHighlight

  test "Disable DocumentHighlight":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentHighlightProvider: some(%*false)))

      s = LspFeatureSettings(
        documentHighlight: LspDocumentHighlightSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentHighlight

  test "Disable DocumentHighlight 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentHighlightProvider: some(%*true)))

      s = LspFeatureSettings(
        documentHighlight: LspDocumentHighlightSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentHighlight

  test "Enable DocumentLink":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentLinkProvider: some(DocumentLinkOptions())))

      s = LspFeatureSettings(
        documentlink: LspDocumentLinkSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.documentLink

  test "Disable DocumentLink":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentLinkProvider: none(DocumentLinkOptions)))

      s = LspFeatureSettings(
        documentlink: LspDocumentLinkSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentLink

  test "Disable DocumentLink 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentLinkProvider: some(DocumentLinkOptions())))

      s = LspFeatureSettings(
        documentlink: LspDocumentLinkSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentLink

  test "Enable CodeLens":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          codeLensProvider: some(CodeLensOptions())))

      s = LspFeatureSettings(
        codeLens: LspCodeLensSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.codeLens

  test "Disable CodeLens":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          codeLensProvider: none(CodeLensOptions)))

      s = LspFeatureSettings(
        codeLens: LspCodeLensSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.codeLens

  test "Disable CodeLens 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          codeLensProvider: some(CodeLensOptions())))

      s = LspFeatureSettings(
        codeLens: LspCodeLensSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.codeLens

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
          renameProvider: some(%*{"prepareProvider": true})))

      s = LspFeatureSettings(
        rename: LspRenameSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.rename

  test "Enable ExecuteCommand":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          executeCommandProvider: some(ExecuteCommandOptions())))

      s = LspFeatureSettings(
        executeCommand: LspExecuteCommandSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.executeCommand.isSome

  test "Disable ExecuteCommand":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          executeCommandProvider: none(ExecuteCommandOptions)))

      s = LspFeatureSettings(
        executeCommand: LspExecuteCommandSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.executeCommand.isNone

  test "Disable ExecuteCommand 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          executeCommandProvider: some(ExecuteCommandOptions())))

      s = LspFeatureSettings(
        executeCommand: LspExecuteCommandSettings(
          enable: false))

    client.setCapabilities(r, s)

    check client.capabilities.get.executeCommand.isNone

  test "Enable Folding Range":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          foldingRangeProvider: some(%*true)))

      s = LspFeatureSettings(
        foldingRange: LspFoldingRangeSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.foldingRange

  test "Disable Folding Range":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          foldingRangeProvider: none(JsonNode)))

      s = LspFeatureSettings(
        foldingRange: LspFoldingRangeSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.foldingRange

  test "Disable Folding Range 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          foldingRangeProvider: some(%*true)))

      s = LspFeatureSettings(
        foldingRange: LspFoldingRangeSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.foldingRange

  test "Enable Selection Range":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          selectionRangeProvider: some(%*true)))

      s = LspFeatureSettings(
        selectionRange: LspSelectionRangeSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.selectionRange

  test "Disable Selection Range":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          selectionRangeProvider: none(JsonNode)))

      s = LspFeatureSettings(
        selectionRange: LspSelectionRangeSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.selectionRange

  test "Disable Selection Range 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          selectionRangeProvider: some(%*true)))

      s = LspFeatureSettings(
        selectionRange: LspSelectionRangeSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.selectionRange

  test "Enable Document Symbol":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentSymbolProvider: some(%*true)))

      s = LspFeatureSettings(
        documentSymbol: LspDocumentSymbolSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.documentSymbol

  test "Disable Document Symbol":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentSymbolProvider: none(JsonNode)))

      s = LspFeatureSettings(
        documentSymbol: LspDocumentSymbolSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentSymbol

  test "Disable Document Symbol 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentSymbolProvider: some(%*true)))

      s = LspFeatureSettings(
        documentSymbol: LspDocumentSymbolSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.documentSymbol

  test "Enable Inline Value":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlineValueProvider: some(%*true)))

      s = LspFeatureSettings(
        inlineValue: LspInlineValueSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.inlineValue

  test "Disable Inline Value":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlineValueProvider: none(JsonNode)))

      s = LspFeatureSettings(
        inlineValue: LspInlineValueSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlineValue

  test "Disable Inline Value 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          inlineValueProvider: some(%*true)))

      s = LspFeatureSettings(
        inlineValue: LspInlineValueSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.inlineValue

  test "Enable Signature Help":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          signatureHelpProvider: some(SignatureHelpOptions())))

      s = LspFeatureSettings(
        signatureHelp: LspSignatureHelpSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.signatureHelp.isSome

  test "Disable Signature Help":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          signatureHelpProvider: none(SignatureHelpOptions)))

      s = LspFeatureSettings(
        signatureHelp: LspSignatureHelpSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.signatureHelp.isNone

  test "Disable Signature Help 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          signatureHelpProvider: some(SignatureHelpOptions())))

      s = LspFeatureSettings(
        signatureHelp: LspSignatureHelpSettings(
          enable: false))

    client.setCapabilities(r, s)

    check client.capabilities.get.signatureHelp.isNone

  test "Enable Document Formatting":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentFormattingProvider: some(%*true)))

      s = LspFeatureSettings(
        formatting: LspDocumentFormattingSettings(
          enable: true))

    client.setCapabilities(r, s)

    check client.capabilities.get.formatting

  test "Disable Document Formatting":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentFormattingProvider: none(JsonNode)))

      s = LspFeatureSettings(
        formatting: LspDocumentFormattingSettings(
          enable: true))

    client.setCapabilities(r, s)

    check not client.capabilities.get.formatting

  test "Disable Document Formatting 2":
    let
      r = InitializeResult(
        capabilities: ServerCapabilities(
          documentFormattingProvider: some(%*true)))

      s = LspFeatureSettings(
        formatting: LspDocumentFormattingSettings(
          enable: false))

    client.setCapabilities(r, s)

    check not client.capabilities.get.formatting

suite "lsp: Send requests":
  privateAccess(LspClient)

  const
    ServerName = "nimlangserver"
    Command = "nimlangserver"
    Trace = TraceValue.verbose
    Timeout = 1000

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
      let params = initInitializeParams(ServerName, rootDir, Trace)

      check client.initialize(BufferId, params).isOk
      check client.waitingResponses[1].lspMethod == LspMethod.initialize

      for _ in 0 .. 20:
        assert client.readable(Timeout).get
        let res = client.read.get
        if res.contains("id"):
          check res["id"].getInt == 1
          check client.initCapacities(initLspFeatureSettings(), res).isOk
          break

  proc lspInitialize(
    c: var LspClient,
    bufferId: int,
    params: InitializeParams): Result[(), string] =

      block:
        let err = c.initialize(bufferId, params)
        if err.isErr:
          return Result[(), string].err err.error

      for _ in 0 .. 30:
        assert c.readable(Timeout).isOk
        let res = c.read.get
        if res.contains("id"):
          if res["id"].getInt != 1:
            return Result[(), string].err "Invalid id"

          block:
            let err = c.initCapacities(initLspFeatureSettings(), res)
            if err.isErr:
              return Result[(), string].err err.error

          block:
            if not c.isInitialized:
              return Result[(), string].err "Not initialized"

          return Result[(), string].ok ()

#  test "Send textDocument/didOpen":
#    if not isNimlangserverAvailable():
#      skip()
#    else:
#      const BufferId = 1
#
#      block:
#        let
#          rootPath = getCurrentDir()
#          params = initInitializeParams(ServerName, rootPath, Trace)
#        assert client.lspInitialize(BufferId, params).isOk
#
#        # workspace/didChangeConfiguration notification
#        assert client.workspaceDidChangeConfiguration.isOk
#
#      const LanguageId = "nim"
#      let
#        path = getCurrentDir() / "src/moe.nim"
#        text = readFile(path)
#
#      check client.textDocumentDidOpen(path, LanguageId, text).isOk

  template prepareLsp(bufferId: int, langId: LanguageId, rootDir, path, text: string) =
    block:
      let params = initInitializeParams(ServerName, rootDir, Trace)
      assert client.lspInitialize(bufferId, params).isOk

    assert client.workspaceDidChangeConfiguration.isOk

    check client.textDocumentDidOpen(path, langId, text).isOk

    while true:
      # Read messages/logs
      const Timeout = 100
      if not client.readable(Timeout).get:
        break
      else:
        discard client.read.get

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

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
        const
          BufferId = 1
          LanguageId = "nim"
          Text = "echo 0\n"

        let path = rootDir / "test.nim"
        writeFile(path, Text)

        prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.shutdown(BufferId).isOk
      check client.waitingResponses[requestId].lspMethod == LspMethod.shutdown

      var isTimeout= true
      for _ in 0 .. 5:
        assert client.readable(Timeout).get
        let res = client.read.get
        if res.contains("id"):
          check res["id"].getInt == requestId
          check res["result"].kind == JNull
          isTimeout = false
          break

      check not isTimeout

  test "Send workspace/didChangeConfiguration":
    if not isNimlangserverAvailable():
      skip()
    else:
      block:
        # Initialize
        const
          BufferId = 1
          LanguageId = "nim"
          Text = "echo 0\n"

        let path = rootDir / "test.nim"
        writeFile(path, Text)

        prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      check client.workspaceDidChangeConfiguration.isOk

  test "Send textDocument/didChange":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "echo 0\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

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
        Text = "echo 0\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      const Version = 1
      check client.textDocumentDidSave(Version, path, Text).isOk

  test "Send textDocument/didClose":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = """
  echo 0
"""

      let path = rootDir / "test.nim"

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      check client.textDocumentDidClose(path).isOk

  test "Send textDocument/hover":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "let a: int = 0\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let position = BufferPosition(line: 0, column: 7)
      var requestId = client.lastId + 1

      check client.textDocumentHover(BufferId, path, position).isOk
      check client.waitingResponses[requestId].lspMethod == LspMethod.textDocumentHover

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
            check res["result"]["contents"][0]["value"].getStr == "system.int: int"
            isTimeout = false
            break

      check not isTimeout

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

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

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
            check res["result"][0].len > 0
            isTimeout = false
            break

      check not isTimeout

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      var requestId = client.lastId + 1

      check client.textDocumentInlayHint(
        BufferId,
        path,
        BufferRange(
          first: BufferPosition(line: 0, column: 0),
          last: BufferPosition(line: 1, column: 0))).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentInlayHint

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
            check res["result"][0]["position"]["line"].getInt == 0
            check res["result"][0]["position"]["character"].getInt == 5
            isTimeout = false
            break

      check not isTimeout

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentDefinition(
        BufferId,
        path,
        BufferPosition(line: 1, column: 9)).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentDefinition

      assert client.readable(Timeout).get
      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
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
            isTimeout = false
            break

      check not isTimeout

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentTypeDefinition(
        BufferId,
        path,
        BufferPosition(line: 1, column: 9)).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentTypeDefinition

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
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
            isTimeout = false
            break

      check not isTimeout

  test "Send textDocument/documentHighlight":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = """
let a = 0
let b = a + 1
echo a
       """

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentDocumentHighlight(
        BufferId,
        path,
        BufferPosition(line: 0, column: 4)
      ).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentDocumentHighlight

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
            check res == %*{
              "jsonrpc": "2.0",
              "id": requestId,
              "result": [
                {
                  "range": {
                    "start": {
                      "line": 0,
                      "character": 4
                    },
                    "end": {
                      "line": 0,
                      "character": 5
                    }
                  },
                  "kind": nil
                },
                {
                  "range": {
                    "start": {
                      "line": 0,
                      "character": 4
                    },
                    "end": {
                      "line": 0,
                      "character": 5
                    }
                  },
                  "kind": nil
                },
                {
                  "range": {
                    "start": {
                      "line": 1,
                      "character": 8
                    },
                    "end": {
                      "line": 1,
                      "character": 9
                    }
                  },
                  "kind": nil
                },
                {
                  "range": {
                    "start": {
                      "line": 2,
                      "character": 5
                    },
                    "end": {
                      "line": 2,
                      "character": 6
                    }
                  },
                  "kind": nil
                }
              ]
            }
            isTimeout = false
            break

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

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentRename(
        BufferId,
        path,
        BufferPosition(line: 1, column: 8),
        "newName").isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentRename

      var isTimeout = true
      for _ in 0 .. 20:
        if client.readable(Timeout).get:
          let res = client.read.get
          if res.contains("id"):
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
            isTimeout = false
            break

      check not isTimeout

  test "Send textDocument/documentFormatting":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        BufferId = 1
        LanguageId = "nim"
        Text = "  echo 0\n"

      let path = rootDir / "test.nim"
      writeFile(path, Text)

      prepareLsp(BufferId, LanguageId, rootDir, path, Text)

      let requestId = client.lastId + 1

      check client.textDocumentDocumentFormatting(
        BufferId,
        path).isOk
      check client.waitingResponses[requestId].lspMethod ==
        LspMethod.textDocumentDocumentFormatting

      # TODO: Add response check
