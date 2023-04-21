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
import ui, windownode, color, bufferstatus, independentutils

type
  TabLine = object
    position: Position
    buffer: string
    color: EditorColorPair

## Return buffer for a tab line to display.
proc tabLineBuffer*(title: string, tabWidth: int): string =
  if tabWidth > title.len:
    let spaces = " ".repeat(tabWidth - title.len)
    return fmt" {title}{spaces}"
  elif tabWidth > 2:
    let shortTitle = title.substr(0, tabWidth - 2) & "~"
    return fmt" {shortTitle}"

## Return a text for a path to display.
proc displayedPath(b: BufferStatus): string =
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

proc initTabLines(
  bufStatuses: seq[BufferStatus],
  currentBufferIndex: int,
  isAllbuffer: bool,
  mainWindowNode: WindowNode): seq[TabLine] =

    if isAllBuffer:
      # Display all buffer

      let numOfBuffer = bufStatuses.len
      for index, bufStatus in bufStatuses:
        let
          title = bufStatus.displayedPath
          tabWidth = int(ceil(getTerminalWidth() / numOfBuffer))
          color =
            if currentBufferIndex == index: EditorColorPair.currentTab
            else: EditorColorPair.tab

        result.add TabLine(
          position: Position(y: 0, x: index * tabWidth),
          buffer: tabLineBuffer(title, tabWidth),
          color: color)
    else:
      # Only the current buffer.

      let allBufferIndex = mainWindowNode.getAllBufferIndex
      for index, bufIndex in allBufferIndex:
        let
          title = bufStatuses[bufIndex].displayedPath
          tabWidth = getTerminalWidth()

        return @[
          TabLine(
            position: Position(y: 0, x: 0),
            buffer: tabLineBuffer(title, tabWidth),
            color: EditorColorPair.currentTab)]

## Write buffer to the terminal (UI).
## Need to refresh after writing.
proc write(win: var Window, tabLine: TabLine) {.inline.} =
  win.write(
    tabLine.position.y,
    tabLine.position.x,
    tabLine.buffer,
    tabline.color)

## Write all tab lines.
proc writeTabLineBuffers*(
  tabWin: var Window,
  bufStatuses: seq[BufferStatus],
  currentBufferIndex: int,
  mainWindowNode: WindowNode,
  isAllbuffer: bool) =

    let tablines = bufStatuses.initTabLines(
      currentBufferIndex,
      isAllbuffer,
      mainWindowNode)

    tabWin.erase
    for t in tabLines: tabWin.write(t)
    tabWin.refresh
