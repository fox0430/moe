#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import moepkg/lsp/protocol/[enums, types]
import moepkg/[independentutils, unicodeext]

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
      "id": 0,
      "method": "workspace/didChangeConfiguration",
      "params": nil
    }).get

  test "textDocument/didOpen":
    check LspMethod.textDocumentDidOpen == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/didOpen",
      "params": nil
    }).get

  test "textDocument/didChange":
    check LspMethod.textDocumentDidChange == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/didChange",
      "params": nil
    }).get

  test "textDocument/didSave":
    check LspMethod.textDocumentDidSave == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/didSave",
      "params": nil
    }).get

  test "textDocument/didClose":
    check LspMethod.textDocumentDidClose == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "textDocument/didClose",
      "params": nil
    }).get

  test "window/publishDiagnostics":
    check LspMethod.textDocumentPublishDiagnostics == lspMethod(%*{
      "jsonrpc": "2.0",
      "id": 0,
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

suite "lsp: parseLspMessageType":
  test "Invalid":
    check parseLspMessageType(-1).isErr
    check parseLspMessageType(0).isErr
    check parseLspMessageType(6).isErr

  test "Error":
    check LspMessageType.error == parseLspMessageType(1).get

  test "Warning":
    check LspMessageType.warn == parseLspMessageType(2).get

  test "Info":
    check LspMessageType.info == parseLspMessageType(3).get

  test "Log":
    check LspMessageType.log == parseLspMessageType(4).get

  test "Debug":
    check LspMessageType.debug == parseLspMessageType(5).get

suite "lsp: parseWindowShowMessageNotify":
  test "Invalid":
    check parseWindowShowMessageNotify(%*{"jsonrpc": "2.0", "result": nil}).isErr

  test "Basic":
    check ServerMessage(
      messageType: LspMessageType.info,
      message: "Nimsuggest initialized for test.nim") == parseWindowShowMessageNotify(%*{
        "jsonrpc": "2.0",
        "method": "window/showMessage",
        "params": {
          "type": 3,
          "message": "Nimsuggest initialized for test.nim"
        }
      }).get

suite "lsp: parseWindowLogMessageNotify":
  test "Invalid":
    check parseWindowShowMessageNotify(%*{"jsonrpc": "2.0", "result": nil}).isErr

  test "Basic":
    check ServerMessage(
      messageType: LspMessageType.info,
      message: "Log message") == parseWindowShowMessageNotify(%*{
        "jsonrpc": "2.0",
        "method": "window/logMessage",
        "params": {
          "type": 3,
          "message": "Log message"
        }
      }).get

suite "lsp: parseTextDocumentHoverResponse":
  test "Invalid":
    let res = %*{"jsonrpc": "2.0", "params": nil}
    check parseTextDocumentHoverResponse(res).isErr

  test "Not found":
    let res = %*{"jsonrpc": "2.0", "id": 0, "result": nil}
    check parseTextDocumentHoverResponse(res).get.isNone

  test "Basic":
    let res = %*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "contents": {
          "language": "nim",
          "value": "editorstatus.LastCursorPosition"},
          "range":{
            "start": {
              "line":33,
              "character":12
            },
            "end":{"line":33,"character":30}
          }
       }
     }

    check %*parseTextDocumentHoverResponse(res).get == %*{
      "contents": {
        "language": "nim",
        "value": "editorstatus.LastCursorPosition"
      },
      "range": {
        "start": {
          "line": 33,
          "character": 12},
        "end": {
          "line": 33,
          "character": 30
        }
      }
    }

  test "Without range":
    let res = %*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "contents": {
          "language": "nim",
          "value": "editorstatus.LastCursorPosition"},
          "range": nil
       }
     }

    check %*parseTextDocumentHoverResponse(res).get == %*{
      "contents": {
        "language": "nim",
        "value": "editorstatus.LastCursorPosition"
      },
      "range": nil
    }

  test "Array contents":
    let res = %*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "contents": [
          {
            "language": "nim",
            "value": "system.echo: proc (x: varargs[typed]){.gcsafe.}"
          },
          {
            "language": "",
            "value": "description"
          }
        ],
        "range": {
          "start": {
            "line": 0,
            "character": 0
          },
          "end": {
            "line": 0,
            "character": 4
          }
        }
      }
    }

    check %*parseTextDocumentHoverResponse(res).get == %*{
      "contents": [
        {
          "language": "nim",
          "value": "system.echo: proc (x: varargs[typed]){.gcsafe.}"
        },
        {
          "language": "",
          "value":"description"
        }
      ],
      "range": {
        "start": {
          "line": 0,
          "character": 0
        },
        "end": {
          "line": 0,
          "character": 4
        }
      }
    }

suite "lsp: parseTextDocumentPublishDiagnosticsNotify":
  test "Invalid":
    let res = %*{"jsonrpc": "2.0", "params": nil}
    check parseTextDocumentPublishDiagnosticsNotify(res).isErr

  test "Basic":
    check %*parseTextDocumentPublishDiagnosticsNotify(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/publishDiagnostics",
      "params": {
        "uri": "file:///tmp/test.nim",
        "diagnostics": [
          {
            "range": {
              "start": {
                "line": 0,
                "character": 0
              },
              "end": {
                "line": 0,
                "character": 2
              }
            },
            "severity": 1,
            "code": "nimsuggest chk",
            "source": "nim",
            "message": "undeclared identifier: 'cho'",
            "relatedInformation": nil
          }
        ]
      }
    }).get.get == %*{
      "path": "/tmp/test.nim",
      "diagnostics": [
        {
          "range": {
            "start": {
              "line": 0,
              "character": 0
            },
            "end": {
              "line": 0,
              "character": 2
            }
          },
          "severity": 1,
          "code": "nimsuggest chk",
          "source": "nim",
          "message": "undeclared identifier: 'cho'",
          "relatedInformation": nil
        }
      ]
    }

suite "lsp: toHoverContent":
  test "Basic":
    let hoverJson = %* {
      "contents": [
        {"language": "nim", "value": "title"},
        {"language": "", "value": "line1\nline2"}
      ],
      "range": {
        "start": {"line": 1, "character": 2},
        "end": {"line": 3, "character": 4}
      }
    }

    check toHoverContent(hoverJson.to(Hover)) == HoverContent(
      title: ru"title",
      description: @[ru"line1", ru"line2"],
      range: BufferRange(
        first: BufferPosition(line: 1, column: 2),
        last: BufferPosition(line: 3, column: 4)))

  test "Only description":
    let hoverJson = %* {
      "contents": {"language": "nim", "value": "description"},
      "range": {
        "start": {"line": 1, "character": 2},
        "end": {"line": 3, "character": 4}
      }
    }

    check toHoverContent(hoverJson.to(Hover)) == HoverContent(
      title: ru"",
      description: @[ru"description"],
      range: BufferRange(
        first: BufferPosition(line: 1, column: 2),
        last: BufferPosition(line: 3, column: 4)))
