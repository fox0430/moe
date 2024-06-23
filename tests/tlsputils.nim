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

import std/[unittest, json, options]

import pkg/results

import moepkg/lsp/protocol/enums
import moepkg/independentutils

import moepkg/lsp/utils {.all.}

suite "lsp: toLspPosition":
  test "toLspPosition 1":
    check BufferPosition(line: 1, column: 2).toLspPosition[] ==
      LspPosition(line: 1, character: 2)[]

suite "lsp: parseTraceValue":
  test "off":
    check parseTraceValue("off").get == TraceValue.off
  test "messages":
    check parseTraceValue("messages").get == TraceValue.messages
  test "off":
    check parseTraceValue("verbose").get == TraceValue.verbose
  test "Invalid value":
    check parseTraceValue("a").isErr

suite "lsp: lspMetod":
  test "Invalid":
    check lspMethod(%*{"jsonrpc": "2.0", "result": nil}).isErr

  test "initialize":
    check LspMethod.cancelRequest == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "$/cancelRequest",
      "params": nil
    }).get

    check LspMethod.initialize == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "initialize",
      "params": nil
    }).get

  test "initialized":
    check LspMethod.initialized == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "initialized",
      "params": nil
    }).get

  test "shutdown":
    check LspMethod.shutdown == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "shutdown",
      "params": nil
    }).get

  test "window/showMessage":
    check LspMethod.windowShowMessage == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "window/showMessage",
      "params": nil
    }).get

  test "window/logMessage":
    check LspMethod.windowLogMessage == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "window/logMessage",
      "params": nil
    }).get

  test "workspace/didChangeConfiguration":
    check LspMethod.workspaceDidChangeConfiguration == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "workspace/didChangeConfiguration",
      "params": nil
    }).get

  test "textDocument/didOpen":
    check LspMethod.textDocumentDidOpen == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/didOpen",
      "params": nil
    }).get

  test "textDocument/didChange":
    check LspMethod.textDocumentDidChange == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/didChange",
      "params": nil
    }).get

  test "textDocument/didSave":
    check LspMethod.textDocumentDidSave == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/didSave",
      "params": nil
    }).get

  test "textDocument/didClose":
    check LspMethod.textDocumentDidClose == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/didClose",
      "params": nil
    }).get

  test "workspace/configuration":
    check LspMethod.workspaceConfiguration == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "workspace/configuration",
      "params": nil
    }).get

  test "window/workDoneProgress/create":
    check LspMethod.windowWorkDnoneProgressCreate == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "window/workDoneProgress/create",
      "params": nil
    }).get

  test "$/progress":
    check LspMethod.progress == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "$/progress",
      "params": nil
    }).get

  test "window/publishDiagnostics":
    check LspMethod.textDocumentPublishDiagnostics == lspMethod(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/publishDiagnostics",
      "params": nil
    }).get

  test "textDocument/hover":
    check LspMethod.textDocumentHover == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/hover",
      "params": nil
    }).get

  test "textDocument/completion":
    check LspMethod.textDocumentCompletion == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/completion",
      "params": nil
    }).get

  test "textDocument/semanticTokens/full":
    check LspMethod.textDocumentSemanticTokensFull == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/semanticTokens/full",
      "params": nil
    }).get

  test "textDocument/semanticTokens/delta":
    check LspMethod.textDocumentSemanticTokensDelta == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/semanticTokens/delta",
      "params": nil
    }).get

  test "textDocument/inlayHint":
    check LspMethod.textDocumentInlayHint == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/inlayHint",
      "params": nil
    }).get

  test "textDocument/references":
    check LspMethod.textDocumentReferences == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/references",
      "params": nil
    }).get

  test "textDocument/definition":
    check LspMethod.textDocumentDefinition == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/definition",
      "params": nil
    }).get

  test "textDocument/typeDefinition":
    check LspMethod.textDocumentTypeDefinition == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/typeDefinition",
      "params": nil
    }).get

  test "textDocument/implementation":
    check LspMethod.textDocumentImplementation == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/implementation",
      "params": nil
    }).get

  test "textDocument/prepareCallHierarchy":
    check LspMethod.textDocumentPrepareCallHierarchy == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/prepareCallHierarchy",
      "params": nil
    }).get

  test "callHierarchy/incomingCalls":
    check LspMethod.callHierarchyIncomingCalls == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "callHierarchy/incomingCalls",
      "params": nil
    }).get

  test "callHierarchy/outgoingCalls":
    check LspMethod.callHierarchyOutgoingCalls == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "callHierarchy/outgoingCalls",
      "params": nil
    }).get
