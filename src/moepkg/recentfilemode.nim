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

import std/[os, re]
import editorstatus, ui, unicodeext, bufferstatus, movement, gapbuffer,
       messages, window

proc openSelectedBuffer(status: var EditorStatus) =
  let
    line = currentMainWindowNode.currentLine
    filename = status.bufStatus[currentMainWindowNode.bufferIndex].buffer[line]

  if fileExists($filename):
    status.addNewBufferInCurrentWin($filename)
  else:
    status.commandLine.writeFileNotFoundError(filename)

proc initRecentFileModeBuffer*(bufStatus: var BufferStatus) =
  var f = open(getHomeDir() / ".local/share/recently-used.xbel")
  let text = f.readAll
  f.close

  let recentUsedFiles = text.findAll(re"""(?<=file://).*?(?=")""")
  for index, str in recentUsedFiles:
    if index == 0: bufStatus.buffer[0] = str.toRunes
    else: bufStatus.buffer.add(str.toRunes)

proc isRecentFileCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isControlK(key) or
       isControlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('h') or isLeftKey(key) or isBackspaceKey(key) or
       key == ord('l') or isRightKey(key) or
       key == ord('G') or
       isEnterKey(key):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc execRecentFileCommand*(status: var EditorStatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      currentMainWindowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
    elif isEnterKey(key):
      status.openSelectedBuffer
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
