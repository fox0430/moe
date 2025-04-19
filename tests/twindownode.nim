#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[unittest, options]

import pkg/results

import moepkg/[editorstatus, editorview, independentutils]

import utils

import moepkg/windownode {.all.}

suite "windownode: resize":
  const
    StatusLineHeight = 1
    TabLineHeight = 1

  var status: EditorStatus

  setup:
    status = initEditorStatus().get
    assert status.addNewBufferInCurrentWin.isOk

  test "Single window":
    status.resize(100, 100)

    check mainWindow.numOfMainWindow == 1
    check mainWindow.root.y == 1
    check mainWindow.root.x == 0
    check mainWindow.root.h == 100 - StatusLineHeight - TabLineHeight
    check mainWindow.root.w == 100
    check not mainWindow.root.isActualWin

    check currentMainWindowNode.y == 0
    check currentMainWindowNode.x == 0
    check currentMainWindowNode.h == 100 - StatusLineHeight - TabLineHeight
    check currentMainWindowNode.w == 100
    check currentMainWindowNode.isActualWin
    check currentMainWindowNode.windowIndex == 0

  test "Horizontal split":
    status.resize(100, 100)

    assert status.horizontalSplitWindow.isOk
    status.resize(100, 100)

    check mainWindow.numOfMainWindow == 2
    check mainWindow.root.y == 1
    check mainWindow.root.x == 0
    check mainWindow.root.h == 100 - StatusLineHeight - TabLineHeight
    check mainWindow.root.w == 100
    check not mainWindow.root.isActualWin

    let nodes = mainWindow.root.getAllWindowNode

    check nodes.len == 2

    check nodes[0].y == 0
    check nodes[0].x == 0
    check nodes[0].h == 49
    check nodes[0].w == 100
    check nodes[0].isActualWin
    check nodes[0].windowIndex == 0

    check nodes[1].y == 49
    check nodes[1].x == 0
    check nodes[1].h == 49
    check nodes[1].w == 100
    check nodes[1].isActualWin
    check nodes[1].windowIndex == 1

  test "Vertical split":
    status.resize(100, 100)

    assert status.verticalSplitWindow.isOk
    status.resize(100, 100)

    check mainWindow.numOfMainWindow == 2
    check mainWindow.root.y == 1
    check mainWindow.root.x == 0
    check mainWindow.root.h == 100 - StatusLineHeight - TabLineHeight
    check mainWindow.root.w == 100
    check not mainWindow.root.isActualWin

    let nodes = mainWindow.root.getAllWindowNode

    check nodes.len == 2

    check nodes[0].y == 0
    check nodes[0].x == 0
    check nodes[0].h == 100 - StatusLineHeight - TabLineHeight
    check nodes[0].w == 50
    check nodes[0].isActualWin
    check nodes[0].windowIndex == 0

    check nodes[1].y == 0
    check nodes[1].x == 50
    check nodes[1].h == 100 - StatusLineHeight - TabLineHeight
    check nodes[1].w == 50
    check nodes[1].isActualWin
    check nodes[1].windowIndex == 1

  test "Vertical split and horizontal split":
    status.resize(100, 100)

    assert status.verticalSplitWindow.isOk
    status.resize(100, 100)

    assert status.horizontalSplitWindow.isOk
    status.resize(100, 100)

    check mainWindow.numOfMainWindow == 3
    check mainWindow.root.y == 1
    check mainWindow.root.x == 0
    check mainWindow.root.h == 100 - StatusLineHeight - TabLineHeight
    check mainWindow.root.w == 100
    check not mainWindow.root.isActualWin

    let nodes = mainWindow.root.getAllWindowNode

    check nodes.len == 3

    check nodes[0].y == 0
    check nodes[0].x == 50
    check nodes[0].h == 100 - StatusLineHeight - TabLineHeight
    check nodes[0].w == 50
    check nodes[0].isActualWin
    check nodes[0].windowIndex == 0

    check nodes[1].y == 0
    check nodes[1].x == 0
    check nodes[1].h == 49
    check nodes[1].w == 50
    check nodes[1].isActualWin
    check nodes[1].windowIndex == 1

    check nodes[2].y == 49
    check nodes[2].x == 0
    check nodes[2].h == 49
    check nodes[2].w == 50
    check nodes[2].isActualWin
    check nodes[2].windowIndex == 2

suite "windownode: absolutePosition":
  test "Enable EditorView.Sidebar":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentMainWindowNode.view.initSidebar

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 4)

  test "Disable EditorView.Sidebar":
    var status = initEditorStatus().get
    status.settings.view.sidebar = false
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 2)

suite "windownode: moveCursor":
  test "Basic":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    let beforeWindowPosition =
      Position(y: currentMainWindowNode.y, x: currentMainWindowNode.x)

    currentMainWindowNode.moveCursor(BufferPosition(line: 10, column: 5))

    check currentMainWindowNode.cursor.y == 10
    check currentMainWindowNode.cursor.x == 5
    check currentMainWindowNode.y == beforeWindowPosition.y
    check currentMainWindowNode.x == beforeWindowPosition.x

  test "Basic 2":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    let beforeWindowPosition =
      Position(y: currentMainWindowNode.y, x: currentMainWindowNode.x)

    currentMainWindowNode.moveCursor(10, 5)

    check currentMainWindowNode.cursor.y == 10
    check currentMainWindowNode.cursor.x == 5
    check currentMainWindowNode.y == beforeWindowPosition.y
    check currentMainWindowNode.x == beforeWindowPosition.x
