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
import pkg/results
import moepkg/[editorstatus, bufferstatus, unicodeext, ui, gapbuffer,
               windownode]

import moepkg/buffermanager {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

proc openBufferManager(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.bufManager)
  currentBufStatus.buffer = status.bufStatus.initBufferManagerBuffer.toGapBuffer
  status.resize

suite "buffermanager: initBufferManagerBuffer":
  test "Single empty buffer":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"
    status.resize(100, 100)
    status.update

    check status.bufStatus.initBufferManagerBuffer == @[ru"first"]

  test "2 buffers":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"
    status.resize(100, 100)
    status.update

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[1].path = ru"second"
    status.resize(100, 100)
    status.update

    check status.bufStatus.initBufferManagerBuffer == @[ru"first", ru"second"]

suite "buffermanager: deleteSelectedBuffer":
  test "Single empty buffer":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Delete status.bufStatus[0]
    status.deleteSelectedBuffer

    check status.bufStatus.len == 1
    check status.bufStatus[0].isBufferManagerMode
    check status.bufStatus[0].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[0].isUpdate

    status.update

  test "2 buffers and delete first buffer":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[1].path = ru"second"

    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Delete status.bufStatus[0]
    status.deleteSelectedBuffer

    check status.bufStatus.len == 2
    check status.bufStatus[0].isNormalMode
    check status.bufStatus[1].isBufferManagerMode
    check status.bufStatus[1].buffer.toSeqRunes == @[ru"second"]
    check status.bufStatus[1].isUpdate

    status.update

  test "2 buffers and delete second buffer":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[1].path = ru"second"

    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Delete status.bufStatus[1]
    currentMainWindowNode.currentLine = 1
    status.deleteSelectedBuffer

    check status.bufStatus.len == 2
    check status.bufStatus[0].isNormalMode
    check status.bufStatus[1].isBufferManagerMode
    check status.bufStatus[1].buffer.toSeqRunes == @[ru"first"]
    check status.bufStatus[1].isUpdate

    status.update

  test "2 windows":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"
    status.resize(100, 100)
    status.update

    status.verticalSplitWindow
    status.resize(100, 100)
    status.update

    check mainWindow.numOfMainWindow == 2

    status.openBufferManager

    # Delete status.bufStatus[0]
    status.deleteSelectedBuffer

    check status.bufStatus.len == 1
    check status.bufStatus[0].isBufferManagerMode
    check status.bufStatus[0].buffer.toSeqRunes == @[ru""]
    check status.bufStatus[0].isUpdate
    check mainWindow.numOfMainWindow == 1

    status.update

suite "buffermanager: openSelectedBuffer":
  test "Open in current win":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"
    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Open status.bufStatus[0] in the current window.
    const IsNewWin = false
    status.openSelectedBuffer(IsNewWin)

    check mainWindow.numOfMainWindow == 2
    let nodes = mainWindowNode.getAllWindowNode
    check nodes.len == 2
    for n in nodes: check n.bufferIndex == 0

    status.update

  test "Open in new win":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"
    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Open status.bufStatus[0] in a new window.
    const IsNewWin = true
    status.openSelectedBuffer(IsNewWin)

    check mainWindow.numOfMainWindow == 3
    let nodes = mainWindowNode.getAllWindowNode
    check nodes.len == 3
    for n in nodes:
      if n.windowIndex == 1: check n.bufferIndex == 1
      else: check n.bufferIndex == 0

    status.update

  test "2 buffers and open first":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[1].path = ru"second"

    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Open status.bufStatus[0] in the current win.
    const IsNewWin = false
    status.openSelectedBuffer(IsNewWin)

    check mainWindow.numOfMainWindow == 2
    let nodes = mainWindowNode.getAllWindowNode
    check nodes.len == 2
    check nodes[0].bufferIndex == 1
    check nodes[1].bufferIndex == 0

    status.update

  test "2 buffers and open second":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].path = ru"first"

    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[1].path = ru"second"

    status.resize(100, 100)
    status.update

    status.openBufferManager

    # Open status.bufStatus[1] in the current win.
    const IsNewWin = false
    currentMainWindowNode.currentLine = 1
    status.openSelectedBuffer(IsNewWin)

    check mainWindow.numOfMainWindow == 2
    let nodes = mainWindowNode.getAllWindowNode
    check nodes.len == 2
    check nodes[0].bufferIndex == 1
    check nodes[1].bufferIndex == 1

    status.update
