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

import std/[unittest, options]

import pkg/results

import moepkg/[editorstatus, editorview, independentutils]

import utils

import moepkg/windownode {.all.}

suite "windownode: absolutePosition":
  test "Enable EditorView.Sidebar":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentMainWindowNode.view.initSidebar

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 4)

  test "Disable EditorView.Sidebar":
    var status = initEditorStatus()
    status.settings.view.sidebar = false
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 2)

suite "windownode: moveCursor":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    let beforeWindowPosition = Position(
      y: currentMainWindowNode.y,
      x: currentMainWindowNode.x)

    currentMainWindowNode.moveCursor(BufferPosition(line: 10, column: 5))

    check currentMainWindowNode.currentLine == 10
    check currentMainWindowNode.currentColumn == 5
    check currentMainWindowNode.window.get.y == beforeWindowPosition.y
    check currentMainWindowNode.window.get.x == beforeWindowPosition.x

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    let beforeWindowPosition = Position(
      y: currentMainWindowNode.y,
      x: currentMainWindowNode.x)

    currentMainWindowNode.moveCursor(10, 5)

    check currentMainWindowNode.currentLine == 10
    check currentMainWindowNode.currentColumn == 5
    check currentMainWindowNode.window.get.y == beforeWindowPosition.y
    check currentMainWindowNode.window.get.x == beforeWindowPosition.x
