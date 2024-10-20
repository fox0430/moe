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

import std/[unittest, os, oids, options]

import pkg/results

import moepkg/[editorstatus, cmdlineoption, bufferstatus, unicodeext, gapbuffer,
               windownode, settings]

import moepkg/init {.all.}

suite "init: addBufferStatus":
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
    let
      path = $genOid()
      parsedList = CmdParsedList(path: @[path])

    status.addBufferStatus(parsedList)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == path.toRunes
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
    check currentBufStatus.filerStatusIndex.get == 0

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
    check currentMainWindowNode.parent.splitType == SplitType.horizontal

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

  test "Open an unreadable file":
    # Create an unreadable file for the test.
    let path = $genOid()
    writeFile(path, "hello")
    const Permissions = {fpUserWrite}
    setFilePermissions(path, Permissions)

    var status = initEditorStatus()
    let parsedList = CmdParsedList(path: @[path])

    status.addBufferStatus(parsedList)

    if fileExists(path): removeFile(path)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == ru""
    check currentBufStatus.mode == Mode.normal

    check currentMainWindowNode.bufferIndex == 0

  test "Open an unreadable dir":
    # Create an unreadable dir for the test.
    let path = $genOid()
    createDir(path)
    const Permissions = {fpUserWrite}
    setFilePermissions(path, Permissions)

    var status = initEditorStatus()
    let parsedList = CmdParsedList(path: @[path])

    status.addBufferStatus(parsedList)

    if dirExists(path): removeDir(path)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == ru""
    check currentBufStatus.mode == Mode.normal

    check currentMainWindowNode.bufferIndex == 0

  test "Read only mode":
    var status = initEditorStatus()
    const ParsedList = CmdParsedList(isReadonly: true)

    status.isReadonly = true

    status.addBufferStatus(ParsedList)

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentBufStatus.path == ru""
    check currentBufStatus.mode == Mode.normal
    check currentBufStatus.isReadonly

    check mainWindowNode.getAllWindowNode.len == 1

suite "init: checkNcurses":
  test "Basic":
    check checkNcurses().isOk
