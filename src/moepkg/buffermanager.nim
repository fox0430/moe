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

import std/heapqueue
import gapbuffer, ui, editorstatus, unicodeext, windownode, movement,
       bufferstatus

proc initBufferManagerBuffer*(
  bufStatuses: seq[BufferStatus]): seq[Runes] =
    ## Return buffer for the buffer manager.
    ## Exclude the buffer for the buffer manager.

    for bufStatus in bufStatuses:
      if not bufStatus.mode.isBufferManagerMode:
        if bufStatus.path.len > 0:
          result.add bufStatus.path
        else:
          result.add ru"No Name"

    if result.len == 0:
      return @[ru""]

proc deleteSelectedBuffer(status: var EditorStatus) =
  ## Delete the selected buffer and close windows for it.

  let deleteIndex = currentMainWindowNode.currentLine

  # Close windows for the delete buffer.
  var qeue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    qeue.push(node)
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      var node = qeue.pop
      if node.bufferIndex == deleteIndex:
        status.closeWindow(node)
      else:
        if node.bufferIndex > deleteIndex:
          node.bufferIndex.dec
          status.bufStatus[node.bufferIndex].isUpdate = true

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

  status.resize

  status.bufStatus.delete(deleteIndex)

  currentBufStatus.buffer = status.bufStatus.initBufferManagerBuffer.toGapBuffer
  currentBufStatus.isUpdate = true

proc openSelectedBuffer(status: var EditorStatus, isNewWindow: bool) =
  if isNewWindow:
    status.verticalSplitWindow
    status.moveNextWindow

    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
    currentBufStatus.isUpdate = true

    status.resize
  else:
    # Open the selected buffer in the current (buffer manager) window.
    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
    currentBufStatus.isUpdate = true

    status.resize

    for i in 0 .. status.bufStatus.high:
      if status.bufStatus[i].isBufferManagerMode:
        # Delete the buffer for the buffer manager.
        status.bufStatus.delete(i)

proc isBufferManagerCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isCtrlK(key) or
       isCtrlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       isEnterKey(key) or
       key == ord('o') or
       key == ord('D'):
         return InputState.Valid

proc execBufferManagerCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if isCtrlK(key):
    status.moveNextWindow
  elif isCtrlJ(key):
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
