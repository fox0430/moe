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

import std/[unittest, oids, os]

import pkg/results

import utils

import moepkg/lsp/references
import moepkg/[bufferstatus, editorstatus, independentutils, gapbuffer,
               windownode, unicodeext]

import moepkg/referencesmode {.all.}

template openReferencesMode(
  status: var EditorStatus,
  references: seq[LspReference]) =

    status.horizontalSplitWindow
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin(Mode.references)
    currentBufStatus.buffer = initReferencesModeBuffer(references)
      .toGapBuffer

    status.resize(100, 100)


suite "references: initReferencesModeBuffer":
  test "Basic":
    let r = @[
      LspReference(
        path: "/home/user/test1.nim",
        position: BufferPosition(line: 0, column: 0)
      ),
      LspReference(
        path: "/home/user/test1.nim",
        position: BufferPosition(line: 1, column: 0)
      ),
      LspReference(
        path: "/home/user/test2.nim",
        position: BufferPosition(line: 10, column: 5)
      )
    ]

    check initReferencesModeBuffer(r) == @[
      "/home/user/test1.nim 0 Line 0 Col",
      "/home/user/test1.nim 1 Line 0 Col",
      "/home/user/test2.nim 10 Line 5 Col",
    ]
    .toSeqRunes

suite "references: parseDestinationLine":
  test "Basic 1":
    check parseDestinationLine(ru"/home/user/test.nim 0 Line 0 Col").get == (
     ru"/home/user/test.nim", 0, 0)

  test "Basic 1":
    check parseDestinationLine(ru"/home/user/test.nim 100 Line 999 Col").get == (
     ru"/home/user/test.nim", 100, 999)

suite "references: openWindowAndJumpToReference":
  var status: EditorStatus

  let testDir = getCurrentDir() / "referencesTest"

  setup:
    status = initEditorStatus()

    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Same buffer":
    let filePath = testDir / $genOid() & ".nim"
    writeFile(filePath, "echo 1\necho 2")

    assert status.addNewBufferInCurrentWin(filePath).isOk

    status.resize(100, 100)
    status.update

    let references = @[
      LspReference(path: filePath, position: BufferPosition(line: 1, column: 0))
    ]

    status.openReferencesMode(references)

    status.openWindowAndJumpToReference

    check status.bufStatus.len == 1
    check currentBufStatus.mode == Mode.normal
    check $currentBufStatus.absolutePath == filePath

    check currentMainWindowNode.bufferPosition == BufferPosition(
      line: 1,
      column: 0)

  test "Other buffer":
    let origFilePath = testDir / $genOid() & ".nim"
    writeFile(origFilePath, "echo 1")

    let destFilePath = testDir / $genOid() & ".nim"
    writeFile(destFilePath, "echo 1\necho 2")

    assert status.addNewBufferInCurrentWin(origFilePath).isOk

    status.resize(100, 100)
    status.update

    let references = @[
      LspReference(path: destFilePath, position: BufferPosition(line: 1, column: 0))
    ]

    status.openReferencesMode(references)

    status.openWindowAndJumpToReference

    check status.bufStatus.len == 2
    check currentBufStatus.mode == Mode.normal
    check $currentBufStatus.absolutePath == destFilePath

    check currentMainWindowNode.bufferPosition == BufferPosition(
      line: 1,
      column: 0)

suite "references: closeReferencesMode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin(Mode.normal).isOk

  test "Basic":
    let references = @[
      LspReference(path: "a", position: BufferPosition(line: 0, column: 0))
    ]

    status.openReferencesMode(references)

    status.closeReferencesMode

    let nodes = mainWindowNode.getAllWindowNode

    check nodes.len == 1
    check nodes[0].bufferIndex == 0

    check status.bufStatus.len == 1
    check status.bufStatus[0].mode == Mode.normal
