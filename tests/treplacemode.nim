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

import std/unittest
import moepkg/[editorstatus, gapbuffer, bufferstatus, unicodeext, editor]

import moepkg/replacemode {.all.}

template recordCurrentPosition() =
  currentBufStatus.buffer.beginNewSuitIfNeeded
  currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

suite "Replace mode: Replace current Character":
  test "Replace current character":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    const Key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      Key)

    check currentBufStatus.buffer[0] == ru"zbc"

  test "Replace current character 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    for i in 0 ..< 5:
      const Key = ru'z'
      currentBufStatus.replaceCurrentCharacter(
        currentMainWindowNode,
        status.settings,
        Key)

    check currentBufStatus.buffer[0] == ru"zzzzz"

suite "Replace mode: Undo":
  test "undo":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    recordCurrentPosition()

    const Key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      Key)

    recordCurrentPosition()

    currentBufStatus.undoOrMoveCursor(
      currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"abc"

  test "undo 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    recordCurrentPosition()

    const Key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      Key)

    recordCurrentPosition()

    currentBufStatus.moveRight(currentMainWindowNode)

    currentBufStatus.undoOrMoveCursor(currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"zbc"

  test "undo 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    recordCurrentPosition()

    const Key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      Key)

    recordCurrentPosition()

    currentBufStatus.moveRight(currentMainWindowNode)

    currentBufStatus.undoOrMoveCursor(currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"abc"

suite "Replace mode: New line":
  test "New line and replace character":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 1

    recordCurrentPosition()

    currentBufStatus.keyEnter(
      currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.tabStop)

    const Key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      Key)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"a"
    check currentBufStatus.buffer[1] == ru"zc"
