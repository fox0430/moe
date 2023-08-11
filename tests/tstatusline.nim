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

import std/[unittest, os, strutils, strformat, importutils]
import moepkg/[bufferstatus, unicodeext, editorstatus, ui, gapbuffer, git, color]

import moepkg/statusline {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "statusline: displayPath":
  test "Empty":
    const Path = ""
    let bufStatus = initBufferStatus(Path)

    check ru"No name" == displayPath(bufStatus)

  test "Absolute path":
    const Path = "/path/to/file"
    let bufStatus = initBufferStatus(Path)

    check Path.toRunes == displayPath(bufStatus)

  test "Relative path":
    const Path = "./file"
    let bufStatus = initBufferStatus(Path)

    check Path.toRunes == displayPath(bufStatus)

  test "In the home dir":
    let path = getHomeDir() / "file"
    let bufStatus = initBufferStatus(path)

    check ru"~/file" == displayPath(bufStatus)

suite "statusline: getFileType":
  test "Nim and Normal mode":
    const Path = "test.nim"
    let bufStatus = initBufferStatus(Path)

    check ru"Nim" == bufStatus.getFileType

  test "Plain and Normal mode":
    const Path = "test.txt"
    let bufStatus = initBufferStatus(Path)

    check ru"Plain" == bufStatus.getFileType

suite "statusline: statusLineInfoBuffer":
  test "Default setting with Nim":
    var status = initEditorStatus()

    const Path = "test.nim"
    status.addNewBufferInCurrentWin(Path)

    status.resize(100, 100)
    status.update

    const SetupText =
      ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"

    check ru"1/1 1/0 UTF-8 Nim " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

  test "Nim 2":
    var status = initEditorStatus()

    const Path = "test.nim"
    status.addNewBufferInCurrentWin(Path)

    for i in 0 ..< 9:
      currentBufStatus.buffer.add ' '.repeat(10).toRunes

    currentMainWindowNode.currentLine = 9
    currentMainWindowNode.currentColumn = 9

    status.resize(100, 100)
    status.update

    const SetupText =
      ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType} {fileTypeIcon}"

    check ru"10/10 10/10 UTF-8 Nim 👑 " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

  test "Plain":
    var status = initEditorStatus()

    const Path = "test.txt"
    status.addNewBufferInCurrentWin(Path)

    status.resize(100, 100)
    status.update

    const SetupText =
      ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType} {fileTypeIcon}"

    check ru"1/1 1/0 UTF-8 Plain 📝 " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

  test "Empty":
    var status = initEditorStatus()

    const Path = "test.txt"
    status.addNewBufferInCurrentWin(Path)

    status.resize(100, 100)
    status.update

    const SetupText = ru""

    check ru"" == currentBufStatus.statusLineInfoBuffer(
      currentMainWindowNode,
      SetupText)

  test "Wihtout items":
    var status = initEditorStatus()

    const Path = "test.txt"
    status.addNewBufferInCurrentWin(Path)

    status.resize(100, 100)
    status.update

    # This is the invalid item.
    const SetupText = ru"lineNumber"

    check ru"lineNumber " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

suite "statusline: addFilerModeInfo":
  # "../", dummy1 and dummy2
  const NumOfFiles = 3

  let path = getCurrentDir() / "statusline_test_dir"

  setup:
    createDir(path)
    writeFile(path / "dummy1", "")
    writeFile(path / "dummy2", "")

  teardown:
    removeDir(path)

  test "Active window":
    var status = initEditorStatus()

    status.addNewBufferInCurrentWin(path, Mode.filer)

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addFilerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check startsWith($status.statusLine[0].buffer, fmt" FILER  {path}")
    check endsWith($status.statusLine[0].buffer, fmt"1/{NumOfFiles} ")
    for i in fmt" FILER  {path}".len .. fmt"1/{NumOfFiles} ".len:
      check " " == $status.statusLine[0].buffer[i]

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(first: 0, last: 6, color: EditorColorPairIndex.statusLineModeFilerMode),
      StatusLineColorSegment(first: 7, last: 99, color: EditorColorPairIndex.statusLineFilerMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    status.addNewBufferInCurrentWin(path, Mode.filer)

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addFilerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check startsWith($status.statusLine[0].buffer, fmt"   {path}")
    check endsWith($status.statusLine[0].buffer, fmt"1/{NumOfFiles} ")
    for i in fmt"   {path}".len .. fmt"1/{NumOfFiles} ".len:
      check " " == $status.statusLine[0].buffer[i]

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(first: 0, last: 1, color: EditorColorPairIndex.statusLineModeFilerMode),
      StatusLineColorSegment(first: 2, last: 99, color: EditorColorPairIndex.statusLineFilerModeInactive)
    ]

suite "statusline: gitBranchNameBuffer":
  test "With changedLines":
    const
      BranchName = ru"branch-name"
      WithGitChangedLine = true
    check ru" branch-name " == gitBranchNameBuffer(
      BranchName,
      WithGitChangedLine)

  test "Without changedLines":
    const
      BranchName = ru"branch-name"
      WithGitChangedLine = false
    check ru"  branch-name " == gitBranchNameBuffer(
      BranchName,
      WithGitChangedLine)

suite "statusline: changedLinesBuffer":
  test "Added line":
    check ru" +1 ~0 -0" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)])

  test "Changed line":
    check ru" +0 ~1 -0" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0)])

  test "Deleted line":
    check ru" +0 ~0 -1" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0)])

  test "Changed and deleted line":
    check ru" +0 ~1 -1" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)])

  test "Mixed":
    check ru" +1 ~2 -2" ==
      changedLinesBuffer(@[
        Diff(operation: OperationType.added, firstLine: 0, lastLine: 0),
        Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0),
        Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0),
        Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)
      ])
