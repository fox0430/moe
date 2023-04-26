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
import moepkg/[editorstatus, gapbuffer, unicodeext, editorview, ui]

import moepkg/windownode {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "windownode: absolutePosition":
  test "Eanble EditorView.Sidebar":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentMainWindowNode.view.initSidebar

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 4)

  test "Disable EditorView.Sidebar":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    check currentMainWindowNode.absolutePosition(0, 0) == (y: 1, x: 2)
