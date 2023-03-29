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

import ui, editorstatus, windownode, movement, editor, bufferstatus, settings,
       unicodeext

proc exitInsertMode(status: var EditorStatus) =
  if currentMainWindowNode.currentColumn > 0:
    currentMainWindowNode.currentColumn.dec
    currentMainWindowNode.expandedColumn = currentMainWindowNode.currentColumn
  status.changeMode(currentBufStatus.prevMode)

proc execInsertModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if pressCtrlC or isEscKey(key) or isControlSquareBracketsRight(key):
    status.exitInsertMode
    pressCtrlC = false
  elif isControlU(key):
    currentBufStatus.deleteBeforeCursorToFirstNonBlank(
      currentMainWindowNode)
  elif isLeftKey(key):
    currentMainWindowNode.keyLeft
  elif isRightKey(key):
    currentBufStatus.keyRight(currentMainWindowNode)
  elif isUpKey(key):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif isDownKey(key):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif isPageUpKey(key):
    pageUp(status)
  elif isPageDownKey(key):
    pageDown(status)
  elif isHomeKey(key):
    currentMainWindowNode.moveToFirstOfLine
  elif isEndKey(key):
    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
  elif isDcKey(key):
    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)
  elif isBackspaceKey(key) or isControlH(key):
    currentBufStatus.keyBackspace(
      currentMainWindowNode,
      status.settings.autoDeleteParen,
      status.settings.tabStop)
  elif isEnterKey(key):
    keyEnter(
      currentBufStatus,
      currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.tabStop)
  elif isTabKey(key) or isControlI(key):
    insertTab(
      currentBufStatus,
      currentMainWindowNode,
      status.settings.tabStop,
      status.settings.autoCloseParen)
  elif isControlE(key):
    currentBufStatus.insertCharacterBelowCursor(
      currentMainWindowNode)
  elif isControlY(key):
    currentBufStatus.insertCharacterAboveCursor(
      currentMainWindowNode)
  elif isControlW(key):
    const loop = 1
    currentBufStatus.deleteWordBeforeCursor(
      currentMainWindowNode,
      status.registers,
      loop,
      status.settings)
  elif isControlU(key):
    currentBufStatus.deleteCharactersBeforeCursorInCurrentLine(
      currentMainWindowNode)
  elif isControlT(key):
    currentBufStatus.addIndentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)
  elif isControlD(key):
    currentBufStatus.deleteIndentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)
  else:
    insertCharacter(
      currentBufStatus,
      currentMainWindowNode,
      status.settings.autoCloseParen,
      key)
