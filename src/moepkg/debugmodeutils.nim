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
import bufferstatus, unicodeext, windownode, settings, gapbuffer

proc getDebugModeBufferIndex*(bufStatuses: seq[BufferStatus]): int =
  result = -1
  for index, bufStatus in bufStatuses:
    if isDebugMode(bufStatus.mode, bufStatus.prevMode): return index

proc initDebugModeBuffer*(
  bufStatus: seq[BufferStatus],
  root: WindowNode,
  currentWindowIndex: int,
  debugModeSettings: DebugModeSettings): seq[Runes] =

  result.add ru""

  if debugModeSettings.windowNode.enable:
    # Add WindowNode info
    let windowNodes = root.getAllWindowNode
    for n in windowNodes:
      result.add ru"-- WindowNode --"

      let
        haveCursesWin = if n.window.isSome: true else: false
        isCurrentWindow = if n.windowIndex == currentWindowIndex: true else: false
      if debugModeSettings.windowNode.currentWindow:
        result.add toRunes(fmt"  currentWindow           : {isCurrentWindow}")
      if debugModeSettings.windowNode.index:
        result.add toRunes(fmt"  index                   : {n.index}")
      if debugModeSettings.windowNode.windowIndex:
        result.add toRunes(fmt"  windowIndex             : {n.windowIndex}")
      if debugModeSettings.windowNode.bufferIndex:
        result.add toRunes(fmt"  bufferIndex             : {n.bufferIndex}")
      if debugModeSettings.windowNode.parentIndex:
        result.add toRunes(fmt"  parentIndex             : {n.parent.index}")
      if debugModeSettings.windowNode.childLen:
        result.add toRunes(fmt"  child length            : {n.child.len}")
      if debugModeSettings.windowNode.splitType:
        result.add toRunes(fmt"  splitType               : {n.splitType}")
      if debugModeSettings.windowNode.haveCursesWin:
        result.add toRunes(fmt"  HaveCursesWindow        : {haveCursesWin}")
      if debugModeSettings.windowNode.y:
        result.add toRunes(fmt"  y                       : {n.y}")
      if debugModeSettings.windowNode.x:
        result.add toRunes(fmt"  x                       : {n.x}")
      if debugModeSettings.windowNode.h:
        result.add toRunes(fmt"  h                       : {n.h}")
      if debugModeSettings.windowNode.w:
        result.add toRunes(fmt"  w                       : {n.w}")
      if debugModeSettings.windowNode.currentLine:
        result.add toRunes(fmt"  currentLine             : {n.currentLine}")
      if debugModeSettings.windowNode.currentColumn:
        result.add toRunes(fmt"  currentColumn           : {n.currentColumn}")
      if debugModeSettings.windowNode.expandedColumn:
        result.add toRunes(fmt"  expandedColumn          : {n.expandedColumn}")
      if debugModeSettings.windowNode.cursor:
        result.add toRunes(fmt"  cursor                  : {n.cursor}")

      result.add ru""

      # Add Editorview info
      if debugModeSettings.editorview.enable:
        result.add ru"-- editorview --"
      if debugModeSettings.editorview.widthOfLineNum:
        result.add toRunes(fmt"  widthOfLineNum          : {n.view.widthOfLineNum}")
      if debugModeSettings.editorview.height:
        result.add toRunes(fmt"  height                  : {n.view.height}")
      if debugModeSettings.editorview.width:
        result.add toRunes(fmt"  width                   : {n.view.width}")
      if debugModeSettings.editorview.originalLine:
        result.add toRunes(fmt"  originalLine            : {n.view.originalLine}")
      if debugModeSettings.editorview.start:
        result.add toRunes(fmt"  start                   : {n.view.start}")
      if debugModeSettings.editorview.length:
        result.add toRunes(fmt"  length                  : {n.view.length}")

      result.add ru""

  if debugModeSettings.bufStatus.enable:
    # Add BufferStatus info
    result.add ru"-- bufStatus --"
    for i in 0 ..< bufStatus.len:
      if debugModeSettings.bufStatus.bufferIndex:
        result.add toRunes(fmt"buffer Index: {i}")
      if debugModeSettings.bufStatus.path:
        result.add toRunes(fmt"  path                    : {bufStatus[i].path}")
      if debugModeSettings.bufStatus.openDir:
        result.add toRunes(fmt"  openDir                 : {bufStatus[i].openDir}")
      if debugModeSettings.bufStatus.currentMode:
        result.add toRunes(fmt"  currentMode             : {bufStatus[i].mode}")
      if debugModeSettings.bufStatus.prevMode:
        result.add toRunes(fmt"  prevMode                : {bufStatus[i].prevMode}")
      if debugModeSettings.bufStatus.language:
        result.add toRunes(fmt"  language                : {bufStatus[i].language}")
      if debugModeSettings.bufStatus.encoding:
        result.add toRunes(fmt"  encoding                : {bufStatus[i].characterEncoding}")
      if debugModeSettings.bufStatus.countChange:
        result.add toRunes(fmt"  countChange             : {bufStatus[i].countChange}")
      if debugModeSettings.bufStatus.cmdLoop:
        result.add toRunes(fmt"  cmdLoop                 : {bufStatus[i].cmdLoop}")
      if debugModeSettings.bufStatus.lastSaveTime:
        result.add toRunes(fmt"  lastSaveTime            : {$bufStatus[i].lastSaveTime}")
      if debugModeSettings.bufStatus.bufferLen:
        result.add toRunes(fmt"  buffer length           : {bufStatus[i].buffer.len}")

      result.add ru""
