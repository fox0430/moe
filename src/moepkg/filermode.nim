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
import pkg/results
import editorstatus, ui, windownode, bufferstatus, unicodeext, filermodeutils,
       messages, commandline, messagelog

proc openNewWinAndOpenFilerOrDir(
  status: var EditorStatus,
  filerStatus: var FilerStatus) =

    let path = filerStatus.pathList[currentMainWindowNode.currentLine].path

    if dirExists($path):
      try:
        setCurrentDir($path)
      except OSError:
        status.commandLine.writeFileOpenError($path)
        return

      let b = initBufferStatus(Mode.filer)
      if b.isErr:
        status.commandLine.writeFileOpenError($path)
        return

      status.verticalSplitWindow
      status.resize
      status.moveNextWindow

      status.bufStatus.add b.get
    else:
      let b = initBufferStatus($path)
      if b.isErr:
        status.commandLine.writeFileOpenError($path)
        return

      status.verticalSplitWindow
      status.resize
      status.moveNextWindow

      status.bufStatus.add b.get
      status.changeCurrentBuffer(status.bufStatus.high)

proc currentPathInfo(status: EditorStatus): PathInfo {.inline.} =
  currentFilerStatus.pathList[currentMainWindowNode.currentLine]

proc changeModeToExMode*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(ExModePrompt)

proc execFilerModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if key == ord(':'):
    currentBufStatus.changeModeToExMode(status.commandLine)
  elif key == ord('/'):
    const Prompt = "/"
    if status.commandLine.getKeys(Prompt):
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
    if r.isOk:
      status.commandLine.write(r.get.toRunes)
      addMessageLog r.get
    else:
      status.commandLine.writeError(r.error.toRunes)
      addMessageLog r.error
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
    let r = currentFilerStatus.createDir(status.commandLine)
    if r.isErr:
      status.commandLine.writeError(r.error.toRunes)
      addMessageLog r.error
  elif key == ord('v'):
    status.openNewWinAndOpenFilerOrDir(currentFilerStatus)
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlK(key):
    status.moveNextWindow
  elif isEnterKey(key):
    let r = status.bufStatus.openFileOrDir(
      currentMainWindowNode,
      currentFilerStatus)
    if r.isErr:
      status.commandLine.writeError(r.error.toRunes)
      addMessageLog r.error
