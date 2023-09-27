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

import std/[strutils, unicode, strformat, math]
import ui, color, bufferstatus, independentutils, unicodeext

type
  ColorSegment = object
    firstColumn, lastColumn: int
    color: EditorColorPairIndex
    attribute: Attribute

  Highlight = ref object
    colorSegments*: seq[ColorSegment]

  TabLine* = object
    window: Window
    position: Position
    size: Size
    buffer: Runes
    highlight: Highlight

proc displayPath(b: BufferStatus): string =
  ## Return a text for a path to display.

  if b.isBackupManagerMode:
    "BACKUP"
  elif b.isConfigMode:
    "CONFIG"
  elif b.isHelpMode:
    "HELP"
  elif b.isBufferManagerMode:
    "BUFFER"
  elif b.isLogViewerMode:
    "LOG"
  elif b.isRecentFileMode:
    "RECENT"
  elif b.isDebugMode:
    "DEBUG"
  elif b.isQuickRunMode:
    "QUICKRUN"
  elif b.path.isEmpty:
    "New file"
  else:
    $b.path

proc initBuffers*(
  bufStatuses: seq[BufferStatus],
  winWidth: int): seq[Runes] =
    ## Return buffers for tablines

    for index, bufStatus in bufStatuses:
      let
        title = displayPath(bufStatus)
        tabWidth = int(ceil(winWidth / bufStatuses.len))

      if tabWidth > title.len:
        let spaces = " ".repeat(tabWidth - title.len)
        result.add toRunes(fmt" {title}{spaces}")
      elif tabWidth > 1:
        let shortTitle = title.substr(0, tabWidth - 2) & "~"
        result.add toRunes(fmt" {shortTitle}")
      else:
        result.add ru" "

proc initHighlight(buffers: seq[Runes], currentBufferIndex: int): Highlight =
  ## Return a highlight for the tabline.

  result = Highlight()
  var totalWidth = 0
  for index, buf in buffers:
    let
      firstCol =
        if totalWidth > 0: totalWidth + 1
        else: totalWidth
      color =
        if currentBufferIndex == index or buffers.len == 1:
          EditorColorPairIndex.currentTab
        else:
          EditorColorPairIndex.tab

    totalWidth += buf.high

    result.colorSegments.add ColorSegment(
      firstColumn: firstCol,
      lastColumn: totalWidth,
      color: color,
      attribute: Attribute.normal)

proc initTabLine(
  bufStatuses: seq[BufferStatus],
  currentBufferIndex: int,
  isAllbuffer: bool): TabLine =

    const
      Position = Position(y: 0, x: 0)
      Color = EditorColorPairIndex.tab.int16

    if isAllBuffer:
      # Multiple tablines for all buffers.

      let buffers = initBuffers(bufStatuses, getTerminalWidth())

      return TabLine(
        window: initWindow(1, getTerminalWidth(), 0, 0, Color),
        position: Position,
        size: Size(h: 1, w: getTerminalWidth()),
        highlight: initHighlight(buffers, currentBufferIndex),
        buffer: buffers.join)

    else:
      # Only the current buffer.
      let
        buffers = initBuffers(
          @[bufStatuses[currentBufferIndex]],
          getTerminalWidth())

      return TabLine(
        window: initWindow(1, getTerminalWidth(), 0, 0, Color),
        position: Position,
        size: Size(h: 1, w: getTerminalWidth()),
        highlight: initHighlight(buffers, currentBufferIndex),
        buffer: buffers[0])

proc update*(
  tabLine: var TabLine,
  bufStatuses: seq[BufferStatus],
  currentBufferIndex: int,
  isAllbuffer: bool) =
    ## Update tabline and window.

    tabline = initTabLine(bufStatuses, currentBufferIndex, isAllbuffer)

    # Update the window
    tabLine.window.erase
    for index, cs in tabLine.highlight.colorSegments:
      tabLine.window.write(
        tabLine.position.y,
        cs.firstColumn,
        tabLine.buffer[cs.firstColumn .. cs.lastColumn],
        cs.color.int16,
        cs.attribute)
    tabLine.window.refresh
