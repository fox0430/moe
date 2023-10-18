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
import moepkg/[editorstatus, bufferstatus, unicodeext, ui]

import moepkg/buffermanager {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "buffermanager: initBufferManagerBuffer":
  test "Single empty buffer":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    check status.bufStatus.initBufferManagerBuffer == @[ru"No Name"]

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
