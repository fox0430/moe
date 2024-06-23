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

import std/[unittest, oids, os, options, strutils]

import pkg/results

import utils

import moepkg/[unicodeext, editorstatus, bufferstatus, gapbuffer, windownode]
import moepkg/lsp/protocol/types
import moepkg/lsp/[callhierarchy, utils]

import moepkg/callhierarchyviewer {.all.}

suite "callhierarchyviewer: initCallHierarchyViewBuffer":
  test "Prepare calls":
    let items = @[
      CallHierarchyItem(
        name: "name0",
        kind: 0,
        detail: some("detail0"),
        uri: "file:///home/user/app/src/test0.rs",
        range: Range(
          start: Position(line: 0, character: 1),
          `end`: Position(line: 2, character: 3)
        ),
        selectionRange: Range(
          start: Position(line: 4, character: 5),
          `end`: Position(line: 6, character: 7))
      ),
      CallHierarchyItem(
        name: "name1",
        kind: 1,
        detail: some("detail1"),
        uri: "file:///home/user/app/src/test1.rs",
        range: Range(
          start: Position(line: 8, character: 9),
          `end`: Position(line: 10, character: 11)
        ),
        selectionRange: Range(
          start: Position(line: 12, character: 13),
          `end`: Position(line: 14, character: 15))
      )
    ]

    check initCallHierarchyViewBuffer(CallHierarchyType.prepare, items).get == @[
      "Prepare Call",
      "",
      "name0 detail0 /home/user/app/src/test0.rs 0 1",
      "name1 detail1 /home/user/app/src/test1.rs 8 9"
    ].toSeqRunes

  test "Incoming calls":
    let items = @[
      CallHierarchyItem(
        name: "name0",
        kind: 0,
        detail: some("detail0"),
        uri: "file:///home/user/app/src/test0.rs",
        range: Range(
          start: Position(line: 0, character: 1),
          `end`: Position(line: 2, character: 3)
        ),
        selectionRange: Range(
          start: Position(line: 4, character: 5),
          `end`: Position(line: 6, character: 7))
      ),
      CallHierarchyItem(
        name: "name1",
        kind: 1,
        detail: some("detail1"),
        uri: "file:///home/user/app/src/test1.rs",
        range: Range(
          start: Position(line: 8, character: 9),
          `end`: Position(line: 10, character: 11)
        ),
        selectionRange: Range(
          start: Position(line: 12, character: 13),
          `end`: Position(line: 14, character: 15))
      )
    ]

    check initCallHierarchyViewBuffer(CallHierarchyType.incoming, items).get == @[
      "Incoming Call",
      "",
      "name0 detail0 /home/user/app/src/test0.rs 0 1",
      "name1 detail1 /home/user/app/src/test1.rs 8 9"
    ].toSeqRunes

  test "Outgoing calls":
    let items = @[
      CallHierarchyItem(
        name: "name0",
        kind: 0,
        detail: some("detail0"),
        uri: "file:///home/user/app/src/test0.rs",
        range: Range(
          start: Position(line: 0, character: 1),
          `end`: Position(line: 2, character: 3)
        ),
        selectionRange: Range(
          start: Position(line: 4, character: 5),
          `end`: Position(line: 6, character: 7))
      ),
      CallHierarchyItem(
        name: "name1",
        kind: 1,
        detail: some("detail1"),
        uri: "file:///home/user/app/src/test1.rs",
        range: Range(
          start: Position(line: 8, character: 9),
          `end`: Position(line: 10, character: 11)
        ),
        selectionRange: Range(
          start: Position(line: 12, character: 13),
          `end`: Position(line: 14, character: 15))
      )
    ]

    check initCallHierarchyViewBuffer(
      CallHierarchyType.outgoing,
      items).get == @[
        "Outgoing Call",
        "",
        "name0 detail0 /home/user/app/src/test0.rs 0 1",
        "name1 detail1 /home/user/app/src/test1.rs 8 9"
      ].toSeqRunes

suite "callhierarchyviewer: parseDestinationLine":
  test "Basic":
    check parseDestinationLine(
      ru"name0 detail0 /home/user/app/src/test0.rs 0 1"
    ).get == (
      ru"/home/user/app/src/test0.rs",
      0,
      1)

  test "Basic 2":
    check parseDestinationLine(
      ru"name2 detail2 /home/user/app/src/test0.rs 100 20"
    ).get == (
      ru"/home/user/app/src/test0.rs",
      100,
      20)

  test "Basic 3":
    check parseDestinationLine(
      ru"name2 this is log detail /home/user/app/src/test0.rs 10 0"
    ).get == (
      ru"/home/user/app/src/test0.rs",
      10,
      0)

suite "callhierarchyviewer: jumpToDestination":
  var status: EditorStatus

  let testDir = getCurrentDir() / "callhierarchyTest"

  setup:
    status = initEditorStatus()

    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Basic":
    let filePath = testDir / $genOid() & ".rs"
    const Buffer = "main(){\n    println(\"\")\n}\n"
    writeFile(filePath, Buffer)

    assert status.addNewBufferInCurrentWin("").isOk

    status.resize(100, 100)
    status.update

    let items = @[
      CallHierarchyItem(
        name: "name0",
        kind: 0,
        detail: some("detail0"),
        uri:  filePath.pathToUri,
        range: Range(
          start: Position(line: 1, character: 4),
          `end`: Position(line: 1, character: 10)
        ),
        selectionRange: Range(
          start: Position(line: 0, character: 0),
          `end`: Position(line: 0, character: 0))
      )
    ]

    status.verticalSplitWindow
    status.moveNextWindow

    assert status.addNewBufferInCurrentWin(Mode.callhierarchyviewer).isOk
    let buf = initCallHierarchyViewBuffer(
      CallHierarchyType.prepare,
      items).get

    currentBufStatus.buffer = buf.toGapBuffer
    currentBufStatus.langId = "rust"
    currentBufStatus.callHierarchyInfo.items = items

    currentMainWindowNode.currentLine = CallHierarchyViewHeaderLength

    status.resize
    status.update

    status.jumpToDestination

    check status.mainWindow.numOfMainWindow == 2
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 4

    check $currentBufStatus.absolutePath == filePath
    check currentBufStatus.buffer.toSeqRunes == Buffer.splitLines.toSeqRunes
