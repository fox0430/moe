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

import std/[unittest, os, strutils, strformat, importutils]

import pkg/results

import moepkg/[bufferstatus, unicodeext, editorstatus, gapbuffer, git, color,
               messagelog]

import utils

import moepkg/statusline {.all.}

suite "statusline: displayPath":
  test "Empty":
    const Path = ""
    let bufStatus = initBufferStatus(Path).get

    check ru"No name" == displayPath(bufStatus)

  test "Absolute path":
    const Path = "/path/to/file"
    let bufStatus = initBufferStatus(Path).get

    check Path.toRunes == displayPath(bufStatus)

  test "Relative path":
    const Path = "./file"
    let bufStatus = initBufferStatus(Path).get

    check Path.toRunes == displayPath(bufStatus)

  test "In the home dir":
    let path = getHomeDir() / "file"
    let bufStatus = initBufferStatus(path).get

    check ru"~/file" == displayPath(bufStatus)

suite "statusline: getFileType":
  test "Nim and Normal mode":
    const Path = "test.nim"
    let bufStatus = initBufferStatus(Path).get

    check ru"Nim" == bufStatus.getFileType

  test "Plain and Normal mode":
    const Path = "test.txt"
    let bufStatus = initBufferStatus(Path).get

    check ru"Plain" == bufStatus.getFileType

suite "statusline: statusLineInfoBuffer":
  test "Default setting with Nim":
    var status = initEditorStatus()

    const Path = "test.nim"
    discard status.addNewBufferInCurrentWin(Path).get

    status.resize(100, 100)
    status.update

    const SetupText =
      ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"

    check ru"1/1 1/0 UTF-8 Nim " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

  test "Nim 2":
    var status = initEditorStatus()

    const Path = "test.nim"
    discard status.addNewBufferInCurrentWin(Path).get

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
    discard status.addNewBufferInCurrentWin(Path).get

    status.resize(100, 100)
    status.update

    const SetupText =
      ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType} {fileTypeIcon}"

    check ru"1/1 1/0 UTF-8 Plain 📝 " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

  test "Empty":
    var status = initEditorStatus()

    const Path = "test.txt"
    discard status.addNewBufferInCurrentWin(Path).get

    status.resize(100, 100)
    status.update

    const SetupText = ru""

    check ru"" == currentBufStatus.statusLineInfoBuffer(
      currentMainWindowNode,
      SetupText)

  test "Without items":
    var status = initEditorStatus()

    const Path = "test.txt"
    discard status.addNewBufferInCurrentWin(Path).get

    status.resize(100, 100)
    status.update

    # This is the invalid item.
    const SetupText = ru"lineNumber"

    check ru"lineNumber " ==
      currentBufStatus.statusLineInfoBuffer(currentMainWindowNode, SetupText)

suite "statusline: statusLineFilerInfoBuffer":
  let path = getCurrentDir() / "statusline_test_dir"

  setup:
    createDir(path)

  teardown:
    removeDir(path)

  test "1 digit":
    # Create a file for the test.
    writeFile(path / "dummy", "")

    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

    status.resize(100, 100)
    status.update

    check statusLineFilerInfoBuffer(currentBufStatus, currentMainWindowNode) ==
      fmt"1/2 ".toRunes

  test "1 digit 2":
    # Create a file for the test.
    writeFile(path / "dummy", "")

    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    check statusLineFilerInfoBuffer(currentBufStatus, currentMainWindowNode) ==
      fmt"2/2 ".toRunes

  test "2 digit":
    # Create files for the test.
    for i in 0 ..< 9:
      writeFile(path / "dummy" & $i, "")

    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

    status.resize(100, 100)
    status.update

    check statusLineFilerInfoBuffer(currentBufStatus, currentMainWindowNode) ==
      fmt"1/10 ".toRunes

  test "2 digit 2":
    # Create files for the test.
    for i in 0 ..< 9:
      writeFile(path / "dummy" & $i, "")

    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

    currentMainWindowNode.currentLine = 9

    status.resize(100, 100)
    status.update

    check statusLineFilerInfoBuffer(currentBufStatus, currentMainWindowNode) ==
      fmt"10/10 ".toRunes

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

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

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
      StatusLineColorSegment(
        first: 0,
        last: 6,
        color: EditorColorPairIndex.statusLineFilerModeLabel),
      StatusLineColorSegment(
        first: 7,
        last: 99,
        color: EditorColorPairIndex.statusLineFilerMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin(path, Mode.filer).get

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
    check startsWith($status.statusLine[0].buffer, fmt" {path}")
    check endsWith($status.statusLine[0].buffer, fmt"1/{NumOfFiles} ")
    for i in fmt"   {path}".len .. fmt"1/{NumOfFiles} ".len:
      check " " == $status.statusLine[0].buffer[i]

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineFilerModeInactive)
    ]

  test "With message":
    var status = initEditorStatus()

    assert status.addNewBufferInCurrentWin(path, Mode.filer).isOk

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].message = ru"message"

    status.statusLine[0].addFilerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check startsWith($status.statusLine[0].buffer, fmt" FILER  {path} message")
    check endsWith($status.statusLine[0].buffer, fmt"1/{NumOfFiles} ")
    for i in fmt" FILER  {path}".len .. fmt"1/{NumOfFiles} ".len:
      check " " == $status.statusLine[0].buffer[i]

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 6,
        color: EditorColorPairIndex.statusLineFilerModeLabel),
      StatusLineColorSegment(
        first: 7,
        last: 99,
        color: EditorColorPairIndex.statusLineFilerMode)
    ]

suite "statusline: addBufManagerModeInfo":
  test "Active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.bufManager).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addBufManagerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " BUFFER                                                                                         1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 7,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 8,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.bufManager).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addBufManagerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      "                                                                                                1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalModeInactive)
    ]

  test "With message":
    var status = initEditorStatus()

    const Path = ""
    assert status.addNewBufferInCurrentWin(Path, Mode.bufManager).isOk

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].message = ru"message"

    status.statusLine[0].addBufManagerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " BUFFER  message                                                                                1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 7,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 8,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]



suite "statusline: addLogViewerModeInfo":
  setup:
    clearMessageLog()

  test "Active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.logViewer).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addLogViewerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " LOG                                                                                            1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 4,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 5,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.logViewer).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addLogViewerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      "                                                                                                1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalModeInactive)
    ]

  test "With message":
    var status = initEditorStatus()

    const Path = ""
    assert status.addNewBufferInCurrentWin(Path, Mode.logViewer).isOk

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].message = ru"message"

    status.statusLine[0].addLogViewerModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " LOG  message                                                                                   1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 4,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 5,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

suite "statusline: addQuickRunModeInfo":
  test "Active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.quickRun).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addQuickRunModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " QUICKRUN                                                                                       1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 9,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 10,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.quickRun).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addQuickRunModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      "                                                                                                1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalModeInactive)
    ]

  test "With message":
    var status = initEditorStatus()

    const Path = ""
    assert status.addNewBufferInCurrentWin(Path, Mode.quickRun).isOk

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].message = ru"message"

    status.statusLine[0].addQuickRunModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " QUICKRUN  message                                                                              1/1 "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 9,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 10,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

suite "statusline: addNormalModeInfo":
  test "Active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addNormalModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " NORMAL  No name                                                                1/1 1/0 UTF-8 Plain "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 7,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 8,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

  test "Inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].addNormalModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " No name                                                                        1/1 1/0 UTF-8 Plain "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalModeInactive)
    ]

  test "With message":
    var status = initEditorStatus()

    const Path = ""
    assert status.addNewBufferInCurrentWin(Path, Mode.normal).isOk

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true

    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    status.statusLine[0].message = ru"message"

    status.statusLine[0].addNormalModeInfo(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " NORMAL  No name message                                                        1/1 1/0 UTF-8 Plain "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 7,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 8,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
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
  test "Added line With Git branch":
    const WithGitBranch = true
    check ru" +1 ~0 -0" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Changed line With Git branch":
    const WithGitBranch = true
    check ru" +0 ~1 -0" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Deleted line With Git branch":
    const WithGitBranch = true
    check ru" +0 ~0 -1" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Changed and deleted line With Git branch":
    const WithGitBranch = true
    check ru" +0 ~1 -1" ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Mixed With Git branch":
    const WithGitBranch = true
    check ru" +1 ~2 -2" ==
      changedLinesBuffer(
        @[
          Diff(operation: OperationType.added, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)
        ],
        WithGitBranch)

  test "Only Added line":
    const WithGitBranch = false
    check ru" +1 ~0 -0 " ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Only Changed line":
    const WithGitBranch = false
    check ru" +0 ~1 -0 " ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Only Deleted line":
    const WithGitBranch = false
    check ru" +0 ~0 -1 " ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Only Changed and deleted line":
    const WithGitBranch = false
    check ru" +0 ~1 -1 " ==
      changedLinesBuffer(
        @[Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)],
        WithGitBranch)

  test "Only Mixed":
    const WithGitBranch = false
    check ru" +1 ~2 -2 " ==
      changedLinesBuffer(
        @[
          Diff(operation: OperationType.added, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.deleted, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.changed, firstLine: 0, lastLine: 0),
          Diff(operation: OperationType.changedAndDeleted, firstLine: 0, lastLine: 0)
        ],
        WithGitBranch)

suite "statusline: addGitInfo":
  test "Only Changed lines":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.settings.statusLine.gitChangedLines = true
    status.settings.statusLine.gitBranchName = false

    currentBufStatus.changedLines = @[
      Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)
    ]

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true
    status.statusLine[0].addGitInfo(
      currentBufStatus,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer == ru" +1 ~0 -0 "

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 9,
        color: EditorColorPairIndex.statusLineGitChangedLines)
    ]

  test "Only Git branch":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.settings.statusLine.gitBranchName = true
    status.settings.statusLine.gitChangedLines = false

    currentBufStatus.changedLines = @[
      Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)
    ]

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true
    status.statusLine[0].addGitInfo(
      currentBufStatus,
      IsActiveWindow,
      status.settings)

    let branchName = getCurrentGitBranchName().get

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer == fmt"  {branchName} ".toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: status.statusLine[0].buffer.high,
        color: EditorColorPairIndex.statusLineGitBranch)
    ]

  test "Git branch and Changed lines":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.settings.statusLine.gitBranchName = true
    status.settings.statusLine.gitChangedLines = true

    currentBufStatus.changedLines = @[
      Diff(operation: OperationType.added, firstLine: 0, lastLine: 0)
    ]

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true
    status.statusLine[0].addGitInfo(
      currentBufStatus,
      IsActiveWindow,
      status.settings)

    let branchName = getCurrentGitBranchName().get

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer == fmt" +1 ~0 -0  {branchName} ".toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 8,
        color: EditorColorPairIndex.statusLineGitChangedLines),
      StatusLineColorSegment(
        first: 9,
        last: status.statusLine[0].buffer.high,
        color: EditorColorPairIndex.statusLineGitBranch)
    ]

suite "statusline: modeLabel":
  test "Insert mode":
    check modeLabel(Mode.insert) == "INSERT"

  test "Visual mode":
    check modeLabel(Mode.visual) == "VISUAL"

  test "Visual block mode":
    check modeLabel(Mode.visualBlock) == "VISUAL BLOCK"

  test "Visual line mode":
    check modeLabel(Mode.visualLine) == "VISUAL LINE"

  test "Replace mode":
    check modeLabel(Mode.replace) == "REPLACE"

  test "Filer mode":
    check modeLabel(Mode.filer) == "FILER"

  test "Buffer Manager mode":
    check modeLabel(Mode.bufManager) == "BUFFER"

  test "Ex mode":
    check modeLabel(Mode.ex) == "EX"

  test "Log viewer mode":
    check modeLabel(Mode.logViewer) == "LOG"

  test "Recent file mode":
    check modeLabel(Mode.recentFile) == "RECENT"

  test "QuickRun mode":
    check modeLabel(Mode.quickRun) == "QUICKRUN"

  test "Backup mode":
    check modeLabel(Mode.backup) == "BACKUP"

  test "Diff mode":
    check modeLabel(Mode.diff) == "DIFF"

  test "Config mode":
    check modeLabel(Mode.config) == "CONFIG"

  test "Debug mode":
    check modeLabel(Mode.debug) == "DEBUG"

suite "statusline: modeLabelColor":
  test "Insert mode":
    check modeLabelColor(Mode.insert) ==
      EditorColorPairIndex.statusLineInsertModeLabel

  test "Viausl mode":
    check modeLabelColor(Mode.visual) ==
      EditorColorPairIndex.statusLineVisualModeLabel

  test "Viausl block mode":
    check modeLabelColor(Mode.visualBlock) ==
      EditorColorPairIndex.statusLineVisualModeLabel

  test "Viausl line mode":
    check modeLabelColor(Mode.visualLine) ==
      EditorColorPairIndex.statusLineVisualModeLabel

  test "Replace mode":
    check modeLabelColor(Mode.replace) ==
      EditorColorPairIndex.statusLineReplaceModeLabel

  test "Filer mode":
    check modeLabelColor(Mode.filer) ==
      EditorColorPairIndex.statusLineFilerModeLabel

  test "Ex mode":
    check modeLabelColor(Mode.ex) ==
      EditorColorPairIndex.statusLineExModeLabel

  test "Normal mode":
    check modeLabelColor(Mode.normal) ==
      EditorColorPairIndex.statusLineNormalModeLabel

suite "statusline: addModeLabel":
  test "Normal mode in active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true
    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer == ru" NORMAL "

  test "Normal mode in inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false
    status.statusLine[0].addModeLabel(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings.statusLine)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer == ru""

suite "statusline: clear":
  test "Clear":
    var s = initStatusLine()

    privateAccess(s.type)
    s.buffer = ru"test"

    privateAccess(s.highlight.type)
    privateAccess(StatusLineColorSegment.type)
    s.highlight.segments = @[
      StatusLineColorSegment(
        first: 0,
        last: 4,
        color: EditorColorPairIndex.statusLineNormalModeLabel)
    ]

    s.clear

    check s.buffer.len == 0
    check s.highlight.segments.len == 0

suite "statusline: updateStatusLineBuffer":
  test "Normal mode in active window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = true
    status.statusLine[0].updateStatusLineBuffer(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    let branchName = getCurrentGitBranchName().get

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer.startsWith(
      fmt" NORMAL   {branchName}  No name".toRunes)
    check status.statusLine[0].buffer.endsWith(ru"1/1 1/0 UTF-8 Plain ")

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 7,
        color: EditorColorPairIndex.statusLineNormalModeLabel),
      StatusLineColorSegment(
        first: 8,
        last: 8 + 4 + branchName.high,
        color: EditorColorPairIndex.statusLineGitBranch),
      StatusLineColorSegment(
        first: 8 + 4 + branchName.high + 1,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalMode)
    ]

  test "Normal mode in inactive window":
    var status = initEditorStatus()

    const Path = ""
    discard status.addNewBufferInCurrentWin(Path, Mode.normal).get

    status.resize(100, 100)
    status.update

    status.statusLine[0].clear

    const IsActiveWindow = false
    status.statusLine[0].updateStatusLineBuffer(
      currentBufStatus,
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)

    privateAccess(status.statusLine[0].type)
    check status.statusLine[0].buffer ==
      " No name                                                                        1/1 1/0 UTF-8 Plain "
      .toRunes

    privateAccess(status.statusLine[0].highlight.type)
    privateAccess(StatusLineColorSegment.type)
    check status.statusLine[0].highlight.segments == @[
      StatusLineColorSegment(
        first: 0,
        last: 99,
        color: EditorColorPairIndex.statusLineNormalModeInactive)
    ]
