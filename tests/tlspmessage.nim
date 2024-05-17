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

import moepkg/lsp/message {.all.}

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
