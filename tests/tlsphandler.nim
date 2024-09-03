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

import std/[unittest, oids, options, os, osproc, json, tables, strformat,
            sequtils]

import pkg/results

import moepkg/lsp/protocol/types
import moepkg/lsp/[client, utils, hover, progress]
import moepkg/[bufferstatus, commandline,  unicodeext, gapbuffer, windownode,
               independentutils, popupwindow, syntaxcheck, completion, folding]

import utils

import moepkg/editorstatus {.all.}
import moepkg/lsp/handler {.all.}

suite "lsp: lspInitialized":
  const Buffer = "echo 1"
  let
    testDir = getCurrentDir() / "lspInitTestDir"
    testFilePath = testDir / "test.nim"

  setup:
    createDir(testDir)
    writeFile(testFilePath, Buffer)

    var status = initEditorStatus()
    status.settings.lsp.enable = true

  teardown:
    removeDir(testDir)

  test "Basic":
    if not isNimlangserverAvailable():
      skip()
    else:
      assert status.addNewBufferInCurrentWin(testFilePath).isOk
      assert currentBufStatus.buffer.toSeqRunes == @["echo 1"].toSeqRunes

      let workspaceRoot = testDir
      const LangId = "nim"

      assert status.lspInitialize(workspaceRoot, LangId).isOk

      const Timeout = 5000
      assert lspClient.readable(Timeout).get

      let resJson = lspClient.read.get
      check status.lspInitialized(resJson).isOk

      check lspClient.isInitialized

      check status.statusLine[0].message == ru"nimlangserver"

suite "lsp: initHoverWindow":
  test "Basic":
    var node = initWindowNode()
    node.resize(independentutils.Position(y: 0, x: 0), Size(h: 100, w: 100))

    let hoverContent = HoverContent(
      title: ru"title",
      description: @["1", "2"].toSeqRunes)

    var hoverWin = initHoverWindow(node, hoverContent)

    check hoverWin.buffer == @[" title ", "", " 1 ", " 2 "].toSeqRunes
    check hoverWin.size == Size(h: 4, w: 7)

suite "lsp showLspServerLog":
  setup:
    var cli = initCommandLine()

  test "Invalid":
    check cli.showLspServerLog(%*{"jsonrpc": "2.0", "result": nil}).isErr

  test "Error":
    check cli.showLspServerLog(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 1,
        "message": "error message"
      }
    }).isOk
    check cli.buffer == ru"ERR: lsp: error message"

  test "Warning":
    check cli.showLspServerLog(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 2,
        "message": "warning message"
      }
    }).isOk
    check cli.buffer == ru"WARN: lsp: warning message"

  test "Info":
    check cli.showLspServerLog(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 3,
        "message": "info message"
      }
    }).isOk
    check cli.buffer == ru"INFO: lsp: info message"

  test "Log":
    check cli.showLspServerLog(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 4,
        "message": "log message"
      }
    }).isOk
    check cli.buffer == ru"LOG: lsp: log message"

  test "Debug":
    check cli.showLspServerLog(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 5,
        "message": "debug message"
      }
    }).isOk
    check cli.buffer == ru"DEBUG: lsp: debug message"

suite "lsp: lspDiagnostics":
  const FilePath = "/tmp/test.nim"

  test "Invalid":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin(FilePath).isOk

    check status.bufStatus.lspDiagnostics(%*{
      "jsonrpc": "2.0",
      "result": nil}).isErr

  test "Basic":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin(FilePath).isOk

    check status.bufStatus.lspDiagnostics(%*{
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
    }).isOk

    check currentBufStatus.syntaxCheckResults == @[
      SyntaxError(
        position: BufferPosition(line: 0, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "undeclared identifier: 'cho'".toRunes)
    ]

  test "2 errors":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin(FilePath).isOk

    check status.bufStatus.lspDiagnostics(%*{
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
          },
          {
            "range": {
              "start": {
                "line": 2,
                "character": 0
              },
              "end": {
                "line": 2,
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
    }).isOk

    check currentBufStatus.syntaxCheckResults == @[
      SyntaxError(
        position: BufferPosition(line: 0, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "undeclared identifier: 'cho'".toRunes),
      SyntaxError(
        position: BufferPosition(line: 2, column: 0),
        messageType: SyntaxCheckMessageType.error,
        message: "undeclared identifier: 'cho'".toRunes)

    ]

  test "Unopened file results":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin(FilePath).isOk

    check status.bufStatus.lspDiagnostics(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/publishDiagnostics",
      "params": {
        "uri": "file:///tmp/otherfile.nim",
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
    }).isOk

    check currentBufStatus.syntaxCheckResults.len == 0

suite "lsp: lspWorkDoneProgressCreate":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "",
      state: ProgressState.create)

  test "Invalid":
    check lspClient.lspProgressCreate(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).isErr

  test "Basic":
    check lspClient.lspProgressCreate(%*{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "window/workDoneProgress/create",
      "params": {
        "token": "token"
      }
    }).isOk

    check lspClient.progress["token"].state == ProgressState.create

suite "lsp: lspProgress":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()

  test "begin":
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "",
      state: ProgressState.create)

    check status.lspProgress(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind": "begin",
          "title": "begin",
          "cancellable": false
        }
      }
    }).isOk

    check ProgressState.begin == status.lspClients["nim"].progress["token"].state
    check "begin" == status.lspClients["nim"].progress["token"].title
    check "" == status.lspClients["nim"].progress["token"].message
    check none(Natural) == status.lspClients["nim"].progress["token"].percentage

    check ru"lsp: progress: begin" == status.commandLine.buffer

  test "begin with message":
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "",
      state: ProgressState.create)

    check status.lspProgress(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind": "begin",
          "title": "begin",
          "message": "message",
          "cancellable": false
        }
      }
    }).isOk

    check ProgressState.begin == status.lspClients["nim"].progress["token"].state
    check "begin" == status.lspClients["nim"].progress["token"].title
    check "message" == status.lspClients["nim"].progress["token"].message
    check none(Natural) == status.lspClients["nim"].progress["token"].percentage

    check ru"lsp: progress: begin: message" == status.commandLine.buffer

  test "report":
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "report",
      state: ProgressState.begin)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"report",
          "cancellable": false,
          "message": "report"
        }
      }
    }).isOk

    check ProgressState.report == status.lspClients["nim"].progress["token"].state
    check "report" == status.lspClients["nim"].progress["token"].title
    check "report" == status.lspClients["nim"].progress["token"].message
    check none(Natural) == status.lspClients["nim"].progress["token"].percentage

    check ru"lsp: progress: report: report" == status.commandLine.buffer

  test "report with percentage":
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "report",
      state: ProgressState.begin)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"report",
          "cancellable": false,
          "message": "report",
          "percentage": 50
        }
      }
    }).isOk

    check ProgressState.report == status.lspClients["nim"].progress["token"].state
    check "report" == status.lspClients["nim"].progress["token"].title
    check "report" == status.lspClients["nim"].progress["token"].message
    check some(Natural(50)) == status.lspClients["nim"].progress["token"].percentage

    check ru"lsp: progress: report: 50%: report" == status.commandLine.buffer

  test "end":
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "end",
      state: ProgressState.report)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"end",
          "message": "end"
        }
      }
    }).isOk

    check ProgressState.`end` == status.lspClients["nim"].progress["token"].state
    check "end" == status.lspClients["nim"].progress["token"].title
    check "end" == status.lspClients["nim"].progress["token"].message
    check none(Natural) == status.lspClients["nim"].progress["token"].percentage

    check ru"lsp: progress: end: end" == status.commandLine.buffer

suite "lsp: lspCompletion":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()

  test "Basic":
    check status.lspCompletion(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "label": "a",
          "kind": 3,
          "detail": "detail1",
          "documentation": "documentation1",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": "a1",
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        },
        {
          "label": "b",
          "kind": 3,
          "detail": "detail2",
          "documentation": "documentation2",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": "b1",
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        }
      ]
    }).isOk

    check currentBufStatus.lspCompletionList.items == @[
      completion.CompletionItem(label: ru"a", insertText: ru"a1"),
      completion.CompletionItem(label: ru"b", insertText: ru"b1"),
    ]

  test "Without insertText":
    check status.lspCompletion(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "label": "a",
          "kind": 3,
          "detail": "detail1",
          "documentation": "documentation1",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": nil,
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        },
        {
          "label": "b",
          "kind": 3,
          "detail": "detail2",
          "documentation": "documentation2",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": nil,
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        }
      ]
    }).isOk

    check currentBufStatus.lspCompletionList.items == @[
      completion.CompletionItem(label: ru"a", insertText: ru"a"),
      completion.CompletionItem(label: ru"b", insertText: ru"b"),
    ]

suite "lsp: lspInlayHint":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()

  test "Empty":
    currentBufStatus.inlayHints.range = independentutils.Range(
      first: 0,
      last: 0)

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentInlayHint)

    check status.lspInlayHint(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isOk

    check currentBufStatus.inlayHints.range == independentutils.Range(
      first: 0,
      last: 0)

    check currentBufStatus.inlayHints.hints.len == 0

  test "Basic":
    currentBufStatus.inlayHints.range = independentutils.Range(
      first: 0,
      last: 0)

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentInlayHint)

    check status.lspInlayHint(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "position": {
            "line": 4,
            "character": 5
          },
          "label": ": int",
          "kind": 1,
          "textEdits": [
            {
              "range": {
                "start":{
                  "line": 4,
                  "character": 5
                },
                "end": {
                  "line": 4,
                  "character": 5}
                },
                "newText": ": int"
              }
          ],
          "tooltip": "",
          "paddingLeft": false,
          "paddingRight": false
        }
      ]
    }).isOk

    check currentBufStatus.inlayHints.range == independentutils.Range(
      first: 0,
      last: 0)

    let hints = currentBufStatus.inlayHints.hints
    check hints.len == 1
    check hints[0].textEdits.get.len == 1
    check hints[0].textEdits.get[0].range.start[] == types.Position(
      line: 4,
      character: 5)[]
    check hints[0].textEdits.get[0].range.`end`[] == types.Position(
      line: 4,
      character: 5)[]
    check hints[0].textEdits.get[0].newText == ": int"
    check hints[0].tooltip.get == ""
    check hints[0].paddingLeft.get == false
    check hints[0].paddingRight.get == false

suite "lsp: lspDeclaration":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk
    currentBufStatus.buffer = @[
      "type number = int",
      "var a: number"
    ]
    .toSeqRunes
    .toGapBuffer

    status.lspClients["nim"] = LspClient()

  test "Not found":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentDeclaration)

    check status.lspDeclaration(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentDeclaration)

    check status.lspDeclaration(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri": pathToUri($currentBufStatus.absolutePath),
          "range": {
            "start": {
              "line": 0,
              "character": 5,
            },
            "end": {
              "line": 0,
              "character": 5,
            }
          }
        }
      ]
    }).isOk

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

suite "lsp: lspDefinition":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk
    currentBufStatus.buffer = @[
      "type number = int",
      "var a: number"
    ]
    .toSeqRunes
    .toGapBuffer

    status.lspClients["nim"] = LspClient()

  test "Not found":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentDefinition)

    check status.lspDefinition(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentDefinition)

    check status.lspDefinition(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri": pathToUri($currentBufStatus.absolutePath),
          "range": {
            "start": {
              "line": 0,
              "character": 5,
            },
            "end": {
              "line": 0,
              "character": 5,
            }
          }
        }
      ]
    }).isOk

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

suite "lsp: lspTypeDefinition":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk
    currentBufStatus.buffer = @[
      "type number = int",
      "var a: number"
    ]
    .toSeqRunes
    .toGapBuffer

    status.lspClients["nim"] = LspClient()

  test "Not found":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentTypeDefinition)

    check status.lspTypeDefinition(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentTypeDefinition)

    check status.lspTypeDefinition(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri": pathToUri($currentBufStatus.absolutePath),
          "range": {
            "start": {
              "line": 0,
              "character": 5,
            },
            "end": {
              "line": 0,
              "character": 5,
            }
          }
        }
      ]
    }).isOk

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

suite "lsp: lspReferences":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()

  test "Not found":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentReferences)

    check status.lspReferences(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Same buffer":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentReferences)

    check status.lspReferences(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri": pathToUri($currentBufStatus.absolutePath),
          "range": {
            "start": {
              "line": 0,
              "character": 0,
            },
            "end": {
              "line": 0,
              "character": 0,
            }
          }
        },
        {
          "uri": pathToUri($currentBufStatus.absolutePath),
          "range": {
            "start": {
              "line": 1,
              "character": 0,
            },
            "end": {
              "line": 1,
              "character": 0,
            }
          }
        }
      ]
    }).isOk

    let nodes = mainWindowNode.getAllWindowNode

    check nodes.len == 2
    check (nodes[0].bufferIndex == 0 and nodes[1].bufferIndex == 1) or
          (nodes[0].bufferIndex == 1 and nodes[1].bufferIndex == 0)

    check currentMainWindowNode.bufferIndex == 1

    check status.bufStatus.len == 2
    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[1].mode == Mode.references

    check status.bufStatus[1].buffer.toSeqRunes == @[
      fmt"{$status.bufStatus[0].absolutePath} 0 Line 0 Col",
      fmt"{$status.bufStatus[0].absolutePath} 1 Line 0 Col",
    ]
    .toSeqRunes

  test "Other buffer":
    let destFilePath = getCurrentDir() / $genOid() & ".nim"

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentReferences)

    check status.lspReferences(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri": pathToUri(destFilePath),
          "range": {
            "start": {
              "line": 0,
              "character": 0,
            },
            "end": {
              "line": 0,
              "character": 0,
            }
          }
        },
        {
          "uri": pathToUri(destFilePath),
          "range": {
            "start": {
              "line": 1,
              "character": 0,
            },
            "end": {
              "line": 1,
              "character": 0,
            }
          }
        }
      ]
    }).isOk

    let nodes = mainWindowNode.getAllWindowNode

    check nodes.len == 2
    check nodes[0].bufferIndex == 0 or nodes[0].bufferIndex == 1
    check nodes[1].bufferIndex == 0 or nodes[1].bufferIndex == 1

    check currentMainWindowNode.bufferIndex == 1

    check status.bufStatus.len == 2
    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[1].mode == Mode.references

    check status.bufStatus[1].buffer.toSeqRunes == @[
      fmt"{destFilePath} 0 Line 0 Col",
      fmt"{destFilePath} 1 Line 0 Col",
    ]
    .toSeqRunes

suite "lsp: lspRename":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()
    status.settings.lsp.enable = true

    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()

  test "Not found":
    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentRename)

    check status.lspReferences(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    let filePath = getCurrentDir() / filename

    const Buffer = @[
      "type Obj = object",
      "  n: int",
      "let n = Obj()",
    ]

    currentBufStatus.buffer = Buffer.toSeqRunes.toGapBuffer

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentRename)

    check status.lspRename(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "changes": {
          filePath.pathToUri: [
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
            },
            {
              "range": {
                "start": {
                  "line": 2,
                  "character": 8
                },
                "end": {
                  "line": 2,
                  "character": 11
                }
              },
              "newText": "newName"
            }
          ]
        },
        "documentChanges": nil
      }
    }).isOk

    check currentBufStatus.buffer.toSeqRunes == @[
      "type newName = object",
      "  n: int",
      "let n = newName()",
    ].toSeqRunes

suite "lsp: lspFoldingRange":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()

    let filename = $genOid()
    assert status.addNewBufferInCurrentWin(filename).isOk

  test "Not found":
    check status.lspFoldingRange(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    currentBufStatus.buffer = toSeq(0..5).mapIt(it.toRunes & ru" ").toGapBuffer
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    currentBufStatus.langId = "dummy"
    status.lspClients["dummy"] = LspClient()

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentFoldingRange)

    check status.lspFoldingRange(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "startLine": 0,
          "startCharacter": 0,
          "endLine": 1,
          "endCharacter": 0
        },
        {
          "startLine": 3,
          "startCharacter": 0,
          "endLine": 4,
          "endCharacter": 0
        }
      ]
    }).isOk

    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

    check currentMainWindowNode.view.foldingRanges == @[
      folding.FoldingRange(first: 0, last: 1),
      folding.FoldingRange(first: 3, last: 4)
    ]

suite "lsp: Selection Range":
  var status = initEditorStatus()

  setup:
    status = initEditorStatus()

    let filename = $genOid()
    assert status.addNewBufferInCurrentWin(filename).isOk

  test "Not found":
    check status.lspFoldingRange(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).isErr

  test "Basic":
    currentBufStatus.buffer = toSeq(0..10)
      .mapIt(" ".repeat(10).toRunes)
      .toGapBuffer

    status.resize(100, 100)
    status.update

    currentBufStatus.langId = "dummy"
    status.lspClients["dummy"] = LspClient()

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentSelectionRange)

    let res = %*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "range": {
            "start": {
              "line": 0,
              "character": 0
            },
            "end": {
              "line": 0,
              "character": 0
            }
          },
          "parent": {
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
            "parent": {
              "range": {
                "start": {
                  "line": 0,
                  "character": 0
                },
                "end": {
                  "line": 2,
                  "character": 1
                }
              },
              "parent": {
                "range": {
                  "start": {
                    "line": 0,
                    "character": 0
                  },
                  "end": {
                    "line": 9,
                    "character": 0
                  }
                }
              }
            }
          }
        }
      ]
    }

    check status.lspSelectionRange(res).isOk

    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

    check currentBufStatus.selectionRanges.len == 1

    var r = currentBufStatus.selectionRanges[0]
    check r.range.start[] == LspPosition(line: 0, character: 0)[]
    check r.range.`end`[] == LspPosition(line: 2, character: 1)[]

    r = r.parent.get
    check r.range.start[] == LspPosition(line: 0, character: 0)[]
    check r.range.`end`[] == LspPosition(line: 9, character: 0)[]

    check r.parent.isNone

  test "Over buffer len":
    currentBufStatus.buffer = toSeq(0..2)
      .mapIt(" ".repeat(10).toRunes)
      .toGapBuffer

    status.resize(100, 100)
    status.update

    currentBufStatus.langId = "dummy"
    status.lspClients["dummy"] = LspClient()

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentSelectionRange)

    check status.lspSelectionRange(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "range": {
            "start": {
              "line": 0,
              "character": 0
            },
            "end": {
              "line": 3,
              "character": 0
            }
          }
        }
      ]
    })
    .isOk

    status.update

    # Generally, the last line is ignored since it's only a newline.
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Over line len":
    currentBufStatus.buffer = toSeq(0..2)
      .mapIt(" ".repeat(10).toRunes)
      .toGapBuffer

    status.resize(100, 100)
    status.update

    currentBufStatus.langId = "dummy"
    status.lspClients["dummy"] = LspClient()

    lspClient.waitingResponses[0] = WaitLspResponse(
      bufferId: currentBufStatus.id,
      requestId: 0,
      lspMethod: LspMethod.textDocumentSelectionRange)

    check status.lspSelectionRange(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "range": {
            "start": {
              "line": 0,
              "character": 0
            },
            "end": {
              "line": 0,
              "character": 10
            }
          }
        }
      ]
    })
    .isOk

    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 9

suite "lsp: handleLspServerNotify":
  setup:
    var status = initEditorStatus()
    status.settings.lsp.enable = true

  test "Invalid":
    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "result": nil
    }).isErr

  test "window/showMessage":
    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "window/showMessage",
      "params": {
        "type": 3,
        "message": "Nimsuggest initialized for test.nim"
      }
    }).isOk

  test "window/logMessage":
    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "window/logMessage",
      "params": {
        "type": 3,
        "message": "Log message"
      }
    }).isOk

  test "window/logMessage":
    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "window/logMessage",
      "params": {
        "type": 3,
        "message": "Log message"
      }
    }).isOk

  test "workspace/configuration":
    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "workspace/configuration",
      "params": {
        "items": [
          {"section": "test"}
        ]
      }
    }).isOk

  test "window/workDoneProgress/create":
    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk
    status.lspClients["nim"] = LspClient()

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "window/workDoneProgress/create",
      "params": {
        "token":"token"
      }
    }).isOk

  test "$/progress (begin)":
    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "",
      state: ProgressState.create)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind": "begin",
          "title": "begin",
          "cancellable": false
        }
      }
    }).isOk

  test "$/progress (report)":
    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "report",
      state: ProgressState.create)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"report",
          "cancellable": false,
          "message": "report"
        }
      }
    }).isOk

    check ru"lsp: progress: report: report" == status.commandLine.buffer

  test "$/progress (report with percentage)":
    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "report",
      state: ProgressState.create)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"report",
          "cancellable": false,
          "message": "report",
          "percentage": 50
        }
      }
    }).isOk

  test "$/progress (end)":
    let filename = $genOid() & ".nim"
    assert status.addNewBufferInCurrentWin(filename).isOk

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].progress["token"] = ProgressReport(
      title: "end",
      state: ProgressState.create)

    check status.handleLspServerNotify(%*{
      "jsonrpc": "2.0",
      "method": "$/progress",
      "params": {
        "token": "token",
        "value": {
          "kind":"end",
          "message": "end"
        }
      }
    }).isOk

  test "textDocument/publishDiagnostics":
    check status.handleLspServerNotify(%*{
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
    }).isOk

suite "lsp: handleLspResponse":
  setup:
    var status = initEditorStatus()
    status.settings.lsp.enable = true

  test "Initialize response":
    if not isNimlangserverAvailable():
      skip()
    else:
      # Open a new file.
      let filename = $genOid() & ".nim"
      assert status.addNewBufferInCurrentWin(filename).isOk

      let workspaceRoot = getCurrentDir()
      const LangId = "nim"
      assert status.lspInitialize(workspaceRoot, LangId).isOk


      const Timeout = 5000
      assert lspClient.readable(Timeout).get

      status.handleLspResponse

      check lspClient.isInitialized
