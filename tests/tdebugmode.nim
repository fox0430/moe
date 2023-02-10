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

import std/[unittest, os, strformat, times, options]
import moepkg/[editorstatus, bufferstatus, gapbuffer, unicodeext, ui]
import moepkg/debugmodeutils {.all.}

suite "Init debug mode buffer":
  test "Init buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    let bufferIndex = status.addNewBuffer(Mode.debug)

    status.bufStatus[bufferIndex.get].buffer =
      status.bufStatus.initDebugModeBuffer(
        mainWindow.mainWindowNode,
        currentMainWindowNode.windowIndex,
        status.settings.debugMode).toGapBuffer

    updateTerminalSize(100, 100)
    status.resize
    status.update

    let correctBuf = initGapBuffer[seq[Rune]](@[
      ru"",
      ru"-- WindowNode --",
      ru"  currentWindow           : true",
      ru"  index                   : 0",
      ru"  windowIndex             : 0",
      ru"  bufferIndex             : 0",
      ru"  parentIndex             : 0",
      ru"  child length            : 0",
      ru"  splitType               : vertical",
      ru"  HaveCursesWindow        : true",
      ru"  y                       : 1",
      ru"  x                       : 0",
      ru"  h                       : 98",
      ru"  w                       : 100",
      ru"  currentLine             : 0",
      ru"  currentColumn           : 0",
      ru"  expandedColumn          : 0",
      ru"  cursor                  : (y: 0, x: 0)",
      ru"",
      ru"-- editorview --",
      ru"  widthOfLineNum          : 2",
      ru"  height                  : 97",
      ru"  width                   : 98",
      ru"",
      ru"-- bufStatus --",
      ru"buffer Index: 0",
      ru"  path                    : ",
      ru fmt"  openDir                 : {getCurrentDir()}",
      ru"  currentMode             : normal",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {status.bufStatus[0].lastSaveTime}",
      ru"  buffer length           : 1",
      ru"",
      ru"buffer Index: 1",
      ru"  path                    : ",
      ru fmt"  openDir                 : {getCurrentDir()}",
      ru"  currentMode             : debug",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {status.bufStatus[1].lastSaveTime}",
      ru"  buffer length           : 49",
      ru""])

    for i in 0 ..< status.bufStatus[1].buffer.len:
      check status.bufStatus[1].buffer[i] == correctBuf[i]
