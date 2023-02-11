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

import std/[times, strformat, options]
import bufferstatus, unicodeext, window, settings, gapbuffer

proc getDebugModeBufferIndex*(bufStatus: seq[BufferStatus]): int =
  result = -1
  for index, bufStatus in bufStatus:
    if isDebugMode(bufStatus.mode, bufStatus.prevMode): result = index

proc initDebugModeBuffer*(
  bufStatus: seq[BufferStatus],
  root: WindowNode,
  currentWindowIndex: int,
  debugModeSettings: DebugModeSettings): seq[Runes] =

  result.add "".toRunes

  # Add WindowNode info
  if debugModeSettings.windowNode.enable:
    let windowNodes = root.getAllWindowNode
    for n in windowNodes:
      result.add(ru fmt"-- WindowNode --")

      let
        haveCursesWin = if n.window.isSome: true else: false
        isCurrentWindow = if n.windowIndex == currentWindowIndex: true else: false
      if debugModeSettings.windowNode.currentWindow:
        result.add(ru fmt"  currentWindow           : {isCurrentWindow}")
      if debugModeSettings.windowNode.index:
        result.add(ru fmt"  index                   : {n.index}")
      if debugModeSettings.windowNode.windowIndex:
        result.add(ru fmt"  windowIndex             : {n.windowIndex}")
      if debugModeSettings.windowNode.bufferIndex:
        result.add(ru fmt"  bufferIndex             : {n.bufferIndex}")
      if debugModeSettings.windowNode.parentIndex:
        result.add(ru fmt"  parentIndex             : {n.parent.index}")
      if debugModeSettings.windowNode.childLen:
        result.add(ru fmt"  child length            : {n.child.len}")
      if debugModeSettings.windowNode.splitType:
        result.add(ru fmt"  splitType               : {n.splitType}")
      if debugModeSettings.windowNode.haveCursesWin:
        result.add(ru fmt"  HaveCursesWindow        : {haveCursesWin}")
      if debugModeSettings.windowNode.y:
        result.add(ru fmt"  y                       : {n.y}")
      if debugModeSettings.windowNode.x:
        result.add(ru fmt"  x                       : {n.x}")
      if debugModeSettings.windowNode.h:
        result.add(ru fmt"  h                       : {n.h}")
      if debugModeSettings.windowNode.w:
        result.add(ru fmt"  w                       : {n.w}")
      if debugModeSettings.windowNode.currentLine:
        result.add(ru fmt"  currentLine             : {n.currentLine}")
      if debugModeSettings.windowNode.currentColumn:
        result.add(ru fmt"  currentColumn           : {n.currentColumn}")
      if debugModeSettings.windowNode.expandedColumn:
        result.add(ru fmt"  expandedColumn          : {n.expandedColumn}")
      if debugModeSettings.windowNode.cursor:
        result.add(ru fmt"  cursor                  : {n.cursor}")

      result.add(ru "")

      # Add Editorview info
      if debugModeSettings.editorview.enable:
        result.add(ru fmt"-- editorview --")
      if debugModeSettings.editorview.widthOfLineNum:
        result.add(ru fmt"  widthOfLineNum          : {n.view.widthOfLineNum}")
      if debugModeSettings.editorview.height:
        result.add(ru fmt"  height                  : {n.view.height}")
      if debugModeSettings.editorview.width:
        result.add(ru fmt"  width                   : {n.view.width}")
      if debugModeSettings.editorview.originalLine:
        result.add(ru fmt"  originalLine            : {n.view.originalLine}")
      if debugModeSettings.editorview.start:
        result.add(ru fmt"  start                   : {n.view.start}")
      if debugModeSettings.editorview.length:
        result.add(ru fmt"  length                  : {n.view.length}")

      result.add(ru "")

  # Add BufferStatus info
  if debugModeSettings.bufStatus.enable:
    result.add(ru fmt"-- bufStatus --")
    for i in 0 ..< bufStatus.len:
      if debugModeSettings.bufStatus.bufferIndex:
        result.add(ru fmt"buffer Index: {i}")
      if debugModeSettings.bufStatus.path:
        result.add(ru fmt"  path                    : {bufStatus[i].path}")
      if debugModeSettings.bufStatus.openDir:
        result.add(ru fmt"  openDir                 : {bufStatus[i].openDir}")
      if debugModeSettings.bufStatus.currentMode:
        result.add(ru fmt"  currentMode             : {bufStatus[i].mode}")
      if debugModeSettings.bufStatus.prevMode:
        result.add(ru fmt"  prevMode                : {bufStatus[i].prevMode}")
      if debugModeSettings.bufStatus.language:
        result.add(ru fmt"  language                : {bufStatus[i].language}")
      if debugModeSettings.bufStatus.encoding:
        result.add(ru fmt"  encoding                : {bufStatus[i].characterEncoding}")
      if debugModeSettings.bufStatus.countChange:
        result.add(ru fmt"  countChange             : {bufStatus[i].countChange}")
      if debugModeSettings.bufStatus.cmdLoop:
        result.add(ru fmt"  cmdLoop                 : {bufStatus[i].cmdLoop}")
      if debugModeSettings.bufStatus.lastSaveTime:
        result.add(ru fmt"  lastSaveTime            : {$bufStatus[i].lastSaveTime}")
      if debugModeSettings.bufStatus.bufferLen:
        result.add(ru fmt"  buffer length           : {bufStatus[i].buffer.len}")

      result.add(ru "")
