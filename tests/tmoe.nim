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

import std/[unittest, os]
import moepkg/[editorstatus, cmdlineoption, bufferstatus, unicodeext, gapbuffer,
               windownode, settings]

import moe {.all.}

suite "moe: addBufferStatus":
  test "No args":
    var status = initEditorStatus()
    const ParsedList = CmdParsedList()

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == ru""
    check currentBufStatus.mode == Mode.normal

    check mainWindowNode.getAllWindowNode.len == 1

  test "1 file":
    var status = initEditorStatus()
    const ParsedList = CmdParsedList(path: @["test.nim"])

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == ru"test.nim"
    check currentBufStatus.mode == Mode.normal

    check mainWindowNode.getAllWindowNode.len == 1

  test "1 dir":
    var status = initEditorStatus()
    const ParsedList = CmdParsedList(path: @["./"])

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes.len > 0
    check currentBufStatus.path == getCurrentDir().toRunes & ru"/"
    check currentBufStatus.mode == Mode.filer

    check mainWindowNode.getAllWindowNode.len == 1

  test "2 files and auto vertical split":
    var status = initEditorStatus()
    const ParsedList = CmdParsedList(path: @["test1.nim", "test2.nim"])

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 2

    check status.bufStatus[0].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[0].path == ru"test1.nim"
    check status.bufStatus[0].mode == Mode.normal

    check status.bufStatus[1].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[1].path == ru"test2.nim"
    check status.bufStatus[1].mode == Mode.normal

    check mainWindowNode.getAllWindowNode.len == 2
    check currentMainWindowNode.bufferIndex == 1
    check currentMainWindowNode.parent.splitType == SplitType.vertical

  test "2 files and auto horizontal split":
    var status = initEditorStatus()
    status.settings.startUp.fileOpen.splitType = WindowSplitType.horizontal
    const ParsedList = CmdParsedList(path: @["test1.nim", "test2.nim"])

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 2

    check status.bufStatus[0].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[0].path == ru"test1.nim"
    check status.bufStatus[0].mode == Mode.normal

    check status.bufStatus[1].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[1].path == ru"test2.nim"
    check status.bufStatus[1].mode == Mode.normal

    check mainWindowNode.getAllWindowNode.len == 2
    check currentMainWindowNode.bufferIndex == 1
    check currentMainWindowNode.parent.splitType == SplitType.horaizontal

  test "2 files and startUp.fileOpen.autoSplit = false":
    var status = initEditorStatus()
    status.settings.startUp.fileOpen.autoSplit = false
    const ParsedList = CmdParsedList(path: @["test1.nim", "test2.nim"])

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 2

    check status.bufStatus[0].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[0].path == ru"test1.nim"
    check status.bufStatus[0].mode == Mode.normal

    check status.bufStatus[1].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[1].path == ru"test2.nim"
    check status.bufStatus[1].mode == Mode.normal

    check mainWindowNode.getAllWindowNode.len == 1
    check currentMainWindowNode.bufferIndex == 1
