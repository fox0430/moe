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

import std/[unittest, strutils, strformat, importutils]
import moepkg/[bufferstatus, editorstatus, ui, color, independentutils,
               unicodeext]

import moepkg/tabline {.all.}

proc resize(status: var EditorStatus, size: Size) =
  updateTerminalSize(size)
  status.resize

suite "tabline: tabLineBuffer":
  test "Basic":
    const
      path = "test.txt"
      tabWidth = 100

    check path.tabLineBuffer(tabWidth) ==
      " test.txt" & " ".repeat(100 - path.len)

  test "Short":
    const
      path = "test.txt"
      tabWidth = 5

    check path.tabLineBuffer(tabWidth) == " test~"

  test "Ignore":
    const path = "test.txt"

    for i in 0 .. 1:
      let tabWidth = i
      check path.tabLineBuffer(tabWidth) == ""

suite "tabline: displayedPath":
  test "Backup mode":
    let bufStatus = initBufferStatus("", Mode.backup)
    check bufStatus.displayedPath == "BACKUP"

  test "Config mode":
    let bufStatus = initBufferStatus("", Mode.config)
    check bufStatus.displayedPath == "CONFIG"

  test "Help mode":
    let bufStatus = initBufferStatus("", Mode.help)
    check bufStatus.displayedPath == "HELP"

  test "Buffer manager mode":
    let bufStatus = initBufferStatus("", Mode.bufManager)
    check bufStatus.displayedPath == "BUFFER"

  test "Log viewer mode":
    let bufStatus = initBufferStatus("", Mode.logViewer)
    check bufStatus.displayedPath == "LOG"

  test "Recent file mode":
    let bufStatus = initBufferStatus("", Mode.recentFile)
    check bufStatus.displayedPath == "RECENT"

  test "Debug mode":
    let bufStatus = initBufferStatus("", Mode.debug)
    check bufStatus.displayedPath == "DEBUG"

  test " Quickrun mode":
    let bufStatus = initBufferStatus("", Mode.quickRun)
    check bufStatus.displayedPath == "QUICKRUN"

  test "Normal mode":
    let bufStatus = initBufferStatus("test.txt", Mode.normal)
    check bufStatus.displayedPath == "test.txt"

  test "Normal mode and empty path":
    let bufStatus = initBufferStatus("", Mode.normal)
    check bufStatus.displayedPath == "New file"

suite "tabline: initTabLines":
  test "Single buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.resize(Size(h: 100, w: 100))

    const
      currentBufferIndex = 0
      isAllbuffer = true

    let t = status.bufStatus.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    check t.len == 1

    privateAccess(t[0].type)
    check t[0] == TabLine(
      position: Position(x: 0, y: 0),
      buffer: " New file" & " ".repeat(92),
      color: EditorColorPairIndex.currentTab)

  test "Single buffer 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text.txt"
    status.resize(Size(h: 100, w: 100))

    const
      currentBufferIndex = 0
      isAllbuffer = true

    let t = status.bufStatus.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    check t.len == 1

    let path = currentBufStatus.path

    privateAccess(t[0].type)
    check t[0] == TabLine(
      position: Position(x: 0, y: 0),
      buffer: fmt" {$path}" & ' '.repeat(100 - path.len),
      color: EditorColorPairIndex.currentTab)

  test "Single buffer 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text.txt"

    status.resize(Size(h: 100, w: 5))

    const
      currentBufferIndex = 0
      isAllbuffer = true

    let t = status.bufStatus.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    check t.len == 1

    privateAccess(t[0].type)
    check t[0] == TabLine(
      position: Position(x: 0, y: 0),
      buffer: " text~",
      color: EditorColorPairIndex.currentTab)

  test "Multiple buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text.txt"

    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text2.txt"

    status.resize(Size(h: 100, w: 100))

    const
      currentBufferIndex = 0
      isAllbuffer = true

    let t = status.bufStatus.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    check t.len == 2

    block:
      let path = status.bufStatus[0].path

      privateAccess(t[0].type)
      check t[0] == TabLine(
        position: Position(x: 0, y: 0),
        buffer: fmt" {$path}" & ' '.repeat(50 - path.len),
        color: EditorColorPairIndex.currentTab)

    block:
      let path = status.bufStatus[1].path

      privateAccess(t[1].type)
      check t[1] == TabLine(
        position: Position(x: 50, y: 0),
        buffer: fmt" {$path}" & ' '.repeat(50 - path.len),
        color: EditorColorPairIndex.tab)

  test "Multiple buffer 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text.txt"

    status.addNewBufferInCurrentWin
    currentBufStatus.path = ru"text2.txt"

    status.resize(Size(h: 100, w: 100))

    const
      currentBufferIndex = 0

      # Show only the current buffer
      isAllbuffer = false

    let t = status.bufStatus.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    check t.len == 1

    let path = currentBufStatus.path

    privateAccess(t[0].type)
    check t[0] == TabLine(
      position: Position(x: 0, y: 0),
      buffer: fmt" {$path}" & ' '.repeat(100 - path.len),
      color: EditorColorPairIndex.currentTab)
