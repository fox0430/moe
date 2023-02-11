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
import moepkg/[editorstatus, logviewer, bufferstatus, unicodeext, ui]

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Log viewer":
  test "Open the log viewer (Fix #1455)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    status.messageLog = @[ru "test"]

    status.verticalSplitWindow
    status.resize(100, 100)
    status.moveNextWindow

    status.addNewBufferInCurrentWin
    status.changeCurrentBuffer(status.bufStatus.high)
    status.changeMode(bufferstatus.Mode.logviewer)

    # In the log viewer
    currentBufStatus.path = ru"Log viewer"

    status.resize(100, 100)
    status.update

    status.update

  test "Exit viewer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("Log viewer", Mode.logViewer)

    status.resize(100, 100)
    status.update

    status.exitLogViewer

    status.resize(100, 100)
