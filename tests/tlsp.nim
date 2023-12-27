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

import std/[unittest, oids, options, os, osproc, json]

import pkg/results

import moepkg/lsp/[client, utils]
import moepkg/[independentutils, unicodeext, gapbuffer, bufferstatus,
               windownode, popupwindow, commandline]

import utils

import moepkg/editorstatus {.all.}
import moepkg/lsp {.all.}

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
    if not isNimlspAvailable():
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

suite "lsp: initHoverWindow":
  test "Basic":
    var node = initWindowNode()
    node.resize(Position(y: 0, x: 0), Size(h: 100, w: 100))

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

suite "lsp: handleLspResponse":
  setup:
    var status = initEditorStatus()
    status.settings.lsp.enable = true

  test "Initialize response":
    if not isNimlspAvailable():
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
