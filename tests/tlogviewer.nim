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

import moepkg/[editorstatus, bufferstatus, unicodeext, messagelog, gapbuffer,
               logviewerutils]

import moepkg/exmode {.all.}
import moepkg/normalmode {.all.}

import utils

suite "Log editor viewer":
  setup:
    clearMessageLog()

  test "Open the log viewer (Fix #1455)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    addMessageLog "line1"
    addMessageLog "line2"

    status.openEditorLogViewer
    status.update

    check currentBufStatus.isReadonly
    check currentBufStatus.logContent == LogContentKind.editor
    check currentBufStatus.buffer.toSeqRunes == @["line1", "line2"].toSeqRunes

  test "Enter visual mode (Fix #2017)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    status.openEditorLogViewer
    status.update

    status.movePrevWindow
    addMessageLog "test"
    status.update

    status.moveNextWindow
    status.update

    status.changeModeToVisualMode
    status.update

