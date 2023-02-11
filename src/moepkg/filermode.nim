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

import std/[os, options]
import editorstatus, ui, window, bufferstatus, unicodeext, filermodeutils, messages,
       commandline, messagelog

proc openNewWinAndOpenFilerOrDir(
  status: var EditorStatus,
  filerStatus: var FilerStatus) =
    let path = filerStatus.pathList[currentMainWindowNode.currentLine].path

    status.verticalSplitWindow
    status.resize
    status.moveNextWindow

    if dirExists($path):
      try:
        setCurrentDir($path)
      except OSError:
        status.commandLine.writeFileOpenError($path)
        status.bufStatus.add initBufferStatus("")

      status.bufStatus.add initBufferStatus(Mode.filer)
    else:
      status.bufStatus.add initBufferStatus($path)

      status.changeCurrentBuffer(status.bufStatus.high)

proc currentPathInfo(status: EditorStatus,): PathInfo {.inline.} =
  currentFilerStatus.pathList[currentMainWindowNode.currentLine]

proc changeModeToExMode*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(exModePrompt)

# NOTE: WIP
proc execFilerModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if key == ord(':'):
    currentBufStatus.changeModeToExMode(status.commandLine)
  elif key == ord('/'):
    const prompt = "/"
    if status.commandLine.getKeys(prompt):
      let keyword = status.commandLine.buffer
      currentBufStatus.searchFileMode(
        currentMainWindowNode,
        currentFilerStatus,
        keyword)
  elif isEscKey(key):
    if currentFilerStatus.searchMode == true:
      currentFilerStatus.isUpdateView = true
      currentFilerStatus.searchMode = false
  elif key == ord('D'):
    let r = status.currentPathInfo.deleteFile
    if r.ok: status.commandLine.write(r.mess)
    else: status.commandLine.write(r.mess)
    addMessageLog r.mess
  elif key == ord('i'):
    currentBufStatus.writeFileDetail(
      currentMainWindowNode,
      status.settings,
      currentFilerStatus.pathList.len,
      currentFilerStatus.pathList[currentMainWindowNode.currentLine][1])
    currentFilerStatus.isUpdateView = true
  elif key == 'j' or isDownKey(key):
    currentFilerStatus.keyDown(currentMainWindowNode.currentLine)
  elif key == ord('k') or isUpKey(key):
    currentFilerStatus.keyUp(currentMainWindowNode.currentLine)
  elif key == ord('g'):
    currentFilerStatus.moveToTopOfList(currentMainWindowNode.currentLine)
  elif key == ord('G'):
    currentFilerStatus.moveToLastOfList(currentMainWindowNode.currentLine)
  elif key == ord('y'):
    currentFilerStatus.copyFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('C'):
    currentFilerStatus.cutFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('p'):
    status.commandLine.pasteFile(
      currentFilerStatus,
      currentBufStatus.path)
  elif key == ord('s'):
    currentFilerStatus.changeSortBy
  elif key == ord('N'):
    let err = currentFilerStatus.createDir(status.commandLine)
    if err.len > 0:
      status.commandLine.writeError(err)
      addMessageLog err
  elif key == ord('v'):
    status.openNewWinAndOpenFilerOrDir(currentFilerStatus)
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlK(key):
    status.moveNextWindow
  elif isEnterKey(key):
    status.bufStatus.openFileOrDir(
      currentMainWindowNode,
      currentFilerStatus)
