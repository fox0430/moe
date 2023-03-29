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

import ui, unicodeext, windownode, bufferstatus, movement, commandline

proc isDebugModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if key == ord(':') or
       isControlK(key) or
       isControlJ(key) or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('g') or
       key == ord('G'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc changeModeToExMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine)  =
    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(exModePrompt)

# TODO: Resolve the recursive module dependency and move to top.
import editorstatus

proc execDebugModeCommand*(status: var EditorStatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if key == ord(':'):
      currentBufStatus.changeModeToExMode(status.commandLine)

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)

    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
