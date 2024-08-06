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

import std/[unittest, times, json, strformat]

import moepkg/lsp/utils
import moepkg/[unicodeext, messagelog]

import moepkg/logviewerutils {.all.}

suite "logviewerutils: countLogLine":
  test "Basic":
    check @[
      "line1",
      "",
      "line2",
      "",
      "line3"
    ]
    .countLogLine == 3

suite "logviewerutils: initEditorLogViewrBuffer":
  setup:
    clearMessageLog()

  test "Empty":
    check initEditorLogViewrBuffer() == @[""].toSeqRunes

  test "Basic":
    addMessageLog "line1"
    addMessageLog "line2"

    check initEditorLogViewrBuffer() == @[
      "line1",
      "",
      "line2"
    ]
    .toSeqRunes

  test "With new line":
    addMessageLog "line1.0\nline1.1"
    addMessageLog "line2.0\nline2.1"

    check initEditorLogViewrBuffer() == @[
      "line1.0",
      "line1.1",
      "",
      "line2.0",
      "line2.1"
    ]
    .toSeqRunes

suite "logviewerutils: initLspLogViewrBuffer":
  setup:
    clearMessageLog()

  test "Empty":
    var log: LspLog

    let time1 = now()
    log.add LspMessage(
      timestamp: time1,
      kind: LspMessageKind.request,
      message: %*{"message1": "val1"})

    let time2 = now()
    log.add LspMessage(
      timestamp: time2,
      kind: LspMessageKind.response,
      message: %*{"message2": "val2"})

    check initLspLogViewrBuffer(log) == @[
      fmt"{$time1} -- request",
      "{",
      """  "message1": "val1"""",
      "}",
      "",
      fmt"{$time2} -- response",
      "{",
      """  "message2": "val2"""",
      "}"
    ]
    .toSeqRunes

suite "logviewerutils: isUpdateEditorLogViwer":
  setup:
    clearMessageLog()

  test "Expect true":
    var buffer = @[""]
    addMessageLog "line1"

    check isUpdateEditorLogViwer(buffer)

  test "Expect true 2":
    addMessageLog "line1"
    var buffer = @["line1"]
    addMessageLog "line2"

    check isUpdateEditorLogViwer(buffer)

  test "Expect false":
    addMessageLog "line1"
    var buffer = @["line1"]

    check not isUpdateEditorLogViwer(buffer)

suite "logviewerutils: isUpdateLspLogViwer":
  setup:
    clearMessageLog()

  test "Expect true":
    var buffer = @[""]

    var log: LspLog
    log.add LspMessage(
      timestamp: now(),
      kind: LspMessageKind.request,
      message: %*{"message1": "val1"})

    check isUpdateLspLogViwer(buffer, log)

  test "Expect true 2":
    var log: LspLog

    log.add LspMessage(
      timestamp: now(),
      kind: LspMessageKind.request,
      message: %*{"message1": "val1"})

    var buffer = @[
      fmt"{$now()} -- request",
      "{",
      """  "message1": "val1"""",
      "}"
    ]

    log.add LspMessage(
      timestamp: now(),
      kind: LspMessageKind.request,
      message: %*{"message2": "val2"})

    check isUpdateLspLogViwer(buffer, log)

  test "Expect false":
    var log: LspLog
    log.add LspMessage(
      timestamp: now(),
      kind: LspMessageKind.request,
      message: %*{"message1": "val1"})

    var buffer = @[
      fmt"{$now()} -- request",
      "{",
      """  "message1": "val1"""",
      "}"
    ]

    check not isUpdateLspLogViwer(buffer, log)
