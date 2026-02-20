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

import std/unittest

import ../src/moepkg/message_log

suite "message_log - Message Log":
  setup:
    clearMessageLog()
    clearLspMessageLog()

  test "addMessageLog single message":
    addMessageLog("hello")
    check messageLogLen() == 1
    check getMessageLog() == @["hello"]

  test "addMessageLog multiple messages one by one":
    addMessageLog("first")
    addMessageLog("second")
    addMessageLog("third")
    check messageLogLen() == 3
    check getMessageLog() == @["first", "second", "third"]

  test "addMessageLog seq overload":
    addMessageLog(@["a", "b", "c"])
    check messageLogLen() == 3
    check getMessageLog() == @["a", "b", "c"]

  test "clearMessageLog":
    addMessageLog("msg")
    check messageLogLen() == 1
    clearMessageLog()
    check messageLogLen() == 0
    check getMessageLog().len == 0

  test "messageLogLen on empty log":
    check messageLogLen() == 0

suite "message_log - LSP Message Log":
  setup:
    clearMessageLog()
    clearLspMessageLog()

  test "addLspMessageLog single message":
    addLspMessageLog("lsp msg")
    check lspMessageLogLen() == 1
    check getLspMessageLog() == @["lsp msg"]

  test "addLspMessageLog multiple messages one by one":
    addLspMessageLog("first")
    addLspMessageLog("second")
    check lspMessageLogLen() == 2
    check getLspMessageLog() == @["first", "second"]

  test "addLspMessageLog seq overload":
    addLspMessageLog(@["x", "y"])
    check lspMessageLogLen() == 2
    check getLspMessageLog() == @["x", "y"]

  test "clearLspMessageLog":
    addLspMessageLog("msg")
    clearLspMessageLog()
    check lspMessageLogLen() == 0
    check getLspMessageLog().len == 0

  test "lspMessageLogLen on empty log":
    check lspMessageLogLen() == 0

suite "message_log - Isolation":
  setup:
    clearMessageLog()
    clearLspMessageLog()

  test "message log and LSP log are independent":
    addMessageLog("editor msg")
    addLspMessageLog("lsp msg")

    check messageLogLen() == 1
    check lspMessageLogLen() == 1
    check getMessageLog() == @["editor msg"]
    check getLspMessageLog() == @["lsp msg"]

  test "clearing one log does not affect the other":
    addMessageLog("editor")
    addLspMessageLog("lsp")

    clearMessageLog()
    check messageLogLen() == 0
    check lspMessageLogLen() == 1

    clearLspMessageLog()
    check lspMessageLogLen() == 0
