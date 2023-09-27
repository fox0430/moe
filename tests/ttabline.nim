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
import pkg/results
import moepkg/[bufferstatus, editorstatus, ui, color, independentutils,
               unicodeext]

import moepkg/tabline {.all.}

proc resize(status: var EditorStatus, size: Size) =
  updateTerminalSize(size)
  status.resize

suite "tabline: initBuffers":
  test "Basic":
    const
      WinWidth = 100
      Path = ru"test.txt"
    let bufStatuses = @[BufferStatus(path: Path)]

    check initBuffers(bufStatuses, WinWidth) == @[
      " test.txt" & " ".repeat(100 - Path.len)].toSeqRunes

  test "Short":
    const
      WinWidth = 5
      Path = ru"test.txt"
    let bufStatuses = @[BufferStatus(path: Path)]

    check initBuffers(bufStatuses, WinWidth) == @[ " test~"].toSeqRunes

suite "tabline: displayedPath":
  test "Backup mode":
    let bufStatus = initBufferStatus("", Mode.backup).get
    check bufStatus.displayPath == "BACKUP"

  test "Config mode":
    let bufStatus = initBufferStatus("", Mode.config).get
    check bufStatus.displayPath == "CONFIG"

  test "Help mode":
    let bufStatus = initBufferStatus("", Mode.help).get
    check bufStatus.displayPath == "HELP"

  test "Buffer manager mode":
    let bufStatus = initBufferStatus("", Mode.bufManager).get
    check bufStatus.displayPath == "BUFFER"

  test "Log viewer mode":
    let bufStatus = initBufferStatus("", Mode.logViewer).get
    check bufStatus.displayPath == "LOG"

  test "Recent file mode":
    let bufStatus = initBufferStatus("", Mode.recentFile).get
    check bufStatus.displayPath == "RECENT"

  test "Debug mode":
    let bufStatus = initBufferStatus("", Mode.debug).get
    check bufStatus.displayPath == "DEBUG"

  test " Quickrun mode":
    let bufStatus = initBufferStatus("", Mode.quickRun).get
    check bufStatus.displayPath == "QUICKRUN"

  test "Normal mode":
    let bufStatus = initBufferStatus("test.txt", Mode.normal).get
    check bufStatus.displayPath == "test.txt"

  test "Normal mode and empty path":
    let bufStatus = initBufferStatus("", Mode.normal).get
    check bufStatus.displayPath == "New file"

suite "tabline: update":
  privateAccess(TabLine)
  privateAccess(ColorSegment)

  test "Single buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.resize(Size(h: 100, w: 100))

    const
      CurrentBufferIndex = 0
      IsAllbuffer = true

    status.tabLine.update(
      status.bufStatus,
      CurrentBufferIndex,
      IsAllbuffer)

    check status.tabLine.position == Position(x: 0, y: 0)
    check status.tabLine.size == Size(h: 1, w: 100)
    check status.tabLine.buffer == toRunes(" New file" & " ".repeat(92))
    check status.tabLine.highlight.colorSegments == @[
      ColorSegment(
        firstColumn: 0,
        lastColumn: 100,
        color: EditorColorPairIndex.currentTab,
        attribute: Attribute.normal)
    ]

  test "Single buffer 2":
    const Path = ru"text.txt"
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path
    status.resize(Size(h: 100, w: 100))

    const
      CurrentBufferIndex = 0
      IsAllbuffer = true

    status.tabLine.update(
      status.bufStatus,
      CurrentBufferIndex,
      IsAllbuffer)

    check status.tabLine.position == Position(x: 0, y: 0)
    check status.tabLine.size == Size(h: 1, w: 100)
    check status.tabLine.buffer == toRunes(
      fmt" {$Path}" & ' '.repeat(100 - Path.len))
    check status.tabLine.highlight.colorSegments == @[
      ColorSegment(
        firstColumn: 0,
        lastColumn: 100,
        color: EditorColorPairIndex.currentTab,
        attribute: Attribute.normal)
    ]

  test "Single buffer 3":
    const Path = ru"text.txt"
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path
    status.resize(Size(h: 100, w: 5))

    const
      CurrentBufferIndex = 0
      IsAllbuffer = true

    status.tabLine.update(
      status.bufStatus,
      CurrentBufferIndex,
      IsAllbuffer)

    check status.tabLine.position == Position(x: 0, y: 0)
    check status.tabLine.size == Size(h: 1, w: 5)
    check status.tabLine.buffer == ru" text~"
    check status.tabLine.highlight.colorSegments == @[
      ColorSegment(
        firstColumn: 0,
        lastColumn: 5,
        color: EditorColorPairIndex.currentTab,
        attribute: Attribute.normal)
    ]

  test "Single buffer 4":
    const
      Path1 = ru"text.txt"
      Path2 = ru"text2.txt"
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path1

    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path2

    status.resize(Size(h: 100, w: 100))

    const
      CurrentBufferIndex = 0
      IsAllbuffer = false

    status.tabLine.update(
      status.bufStatus,
      CurrentBufferIndex,
      IsAllbuffer)

    check status.tabLine.position == Position(x: 0, y: 0)
    check status.tabLine.size == Size(h: 1, w: 100)
    check status.tabLine.buffer == toRunes(
        fmt" {$Path1}{' '.repeat(100 - Path1.len)}")
    check status.tabLine.highlight.colorSegments == @[
      ColorSegment(
        firstColumn: 0,
        lastColumn: 100,
        color: EditorColorPairIndex.currentTab,
        attribute: Attribute.normal)
    ]


  test "Multiple buffer":
    const
      Path1 = ru"text.txt"
      Path2 = ru"text2.txt"
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path1

    status.addNewBufferInCurrentWin
    currentBufStatus.path = Path2

    status.resize(Size(h: 100, w: 100))

    const
      CurrentBufferIndex = 0
      IsAllbuffer = true

    status.tabLine.update(
      status.bufStatus,
      CurrentBufferIndex,
      IsAllbuffer)

    check status.tabLine.position == Position(x: 0, y: 0)
    check status.tabLine.size == Size(h: 1, w: 100)
    check status.tabLine.buffer == toRunes(
        fmt" {$Path1}{' '.repeat(50 - Path1.len)} {Path2}{' '.repeat(50 - Path2.len)}")
    check status.tabLine.highlight.colorSegments == @[
      ColorSegment(
        firstColumn: 0,
        lastColumn: 50,
        color: EditorColorPairIndex.currentTab,
        attribute: Attribute.normal),
      ColorSegment(
        firstColumn: 51,
        lastColumn: 100,
        color: EditorColorPairIndex.tab,
        attribute: Attribute.normal)
    ]
