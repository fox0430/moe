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

import moepkg/[editorstatus, bufferstatus, unicodeext, messagelog, gapbuffer]

import utils

suite "Log viewer":
  test "Open the log viewer (Fix #1455)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    addMessageLog "line1"
    addMessageLog "line2"

    status.verticalSplitWindow
    status.resize(100, 100)
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin(Mode.logViewer).get
    status.resize(100, 100)

    status.changeCurrentBuffer(status.bufStatus.high)

    status.update

    check currentBufStatus.isReadonly
    check currentBufStatus.buffer.toSeqRunes == @["line1", "line2"].toSeqRunes
