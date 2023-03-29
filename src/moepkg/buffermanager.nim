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

import std/[os, heapqueue]
import gapbuffer, ui, editorstatus, unicodeext, windownode, movement,
       bufferstatus

proc initBufferManagerBuffer*(
  bufStatuses: seq[BufferStatus]): seq[Runes] =
    for bufStatus in bufStatuses:
      let currentMode = bufStatus.mode
      if currentMode != Mode.bufManager:
        let
          prevMode = bufStatus.prevMode
          line =
            if (currentMode == Mode.filer) or
               (prevMode == Mode.filer and
                currentMode == Mode.ex): getCurrentDir().toRunes
            else: bufStatus.path

        result.add line

proc deleteSelectedBuffer(status: var EditorStatus) =
  let deleteIndex = currentMainWindowNode.currentLine

  var qeue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    qeue.push(node)
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.bufferIndex == deleteIndex:
        status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

  status.resize

  if status.mainWindow.numOfMainWindow > 0:
    status.bufStatus.delete(deleteIndex)

    var qeue = initHeapQueue[WindowNode]()
    for node in mainWindowNode.child:
      qeue.push(node)
    while qeue.len > 0:
      for i in 0 ..< qeue.len:
        var node = qeue.pop
        if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

        if node.child.len > 0:
          for node in node.child: qeue.push(node)

    if status.bufferIndexInCurrentWindow > deleteIndex:
      dec(currentMainWindowNode.bufferIndex)
    if currentMainWindowNode.currentLine > 0:
      dec(currentMainWindowNode.currentLine)

    let index = status.mainWindow.numOfMainWindow - 1
    currentMainWindowNode = mainWindowNode.searchByWindowIndex(index)
    currentBufStatus.buffer =
      status.bufStatus.initBufferManagerBuffer.toGapBuffer

    status.resize

proc openSelectedBuffer(status: var EditorStatus, isNewWindow: bool) =
  if isNewWindow:
    status.verticalSplitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
  else:
    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc isBufferManagerCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isControlK(key) or
       isControlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       isEnterKey(key) or
       key == ord('o') or
       key == ord('D'):
         return InputState.Valid

proc execBufferManagerCommand*(status: var EditorStatus, command: Runes) =
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
  elif isEnterKey(key):
    status.openSelectedBuffer(false)
  elif key == ord('o'):
    status.openSelectedBuffer(true)
  elif key == ord('D'):
    status.deleteSelectedBuffer

  if status.bufStatus.len < 2: status.exitEditor
