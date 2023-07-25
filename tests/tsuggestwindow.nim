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

import std/[unittest, critbits, importutils, options]
import moepkg/[editorstatus, gapbuffer, unicodeext]

import moepkg/suggestionwindow {.all.}

suite "suggestionwindow: buildSuggestionWindow":
  test "Case 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(
      @["test".ru,
        "test2".ru,
        "abc".ru,
        "efg".ru,
        "t".ru])

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    currentMainWindowNode.currentColumn = 1

    const CurrentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      CurrentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isSome

    privateAccess(suggestionWin.get.type)

    check suggestionWin.get.wordDictionary.len == 4

    check suggestionWin.get.oldLine == "t".ru
    check suggestionWin.get.inputWord == "t".ru

    check suggestionWin.get.firstColumn == 0
    check suggestionWin.get.lastColumn == 0

    check suggestionWin.get.suggestoins == @["test2".ru, "test".ru]

    check suggestionWin.get.selectedSuggestion == -1

    check not suggestionWin.get.isPath

  test "Case 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(
      @["/".ru])

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    currentMainWindowNode.currentColumn = 1

    const CurrentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      CurrentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isSome

    privateAccess(suggestionWin.get.type)

    check suggestionWin.get.wordDictionary.len == 0

    check suggestionWin.get.oldLine == "/".ru
    check suggestionWin.get.inputWord.len == 0

    check suggestionWin.get.firstColumn == 0
    check suggestionWin.get.lastColumn == 0

    check suggestionWin.get.suggestoins in "home".ru
    check suggestionWin.get.suggestoins in "root".ru
    check suggestionWin.get.suggestoins in "etc".ru

    check suggestionWin.get.selectedSuggestion == -1

    check suggestionWin.get.isPath

  test "Case 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@["a".ru])

    currentMainWindowNode.currentColumn = 1

    const CurrentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      CurrentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isNone
