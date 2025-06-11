#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[strformat, strutils]

import jumplist, unicodeext, ui, editorstatus, bufferstatus, movement, commandline

proc calcPositionStrMaxLen(h: seq[JumpInfo]): tuple[line: int, col: int] =
  var
    # Text length
    line = 0
    col = 0
  for ji in h:
    if len($ji.position.line) > line:
      line = len($ji.position.line)
    if len($ji.position.column) > col:
      col = len($ji.position.column)

  return (line, col)

proc initJumpListBuffer*(list: JumpList): seq[Runes] =
  let positionMaxLen = calcPositionStrMaxLen(list.history)

  # Header line
  block:
    let
      lineFieldWidth = max(4, positionMaxLen.line)
      colFieldWidth = max(6, positionMaxLen.col)
      lineHeader = "line" & " ".repeat(max(lineFieldWidth - 4, 0))
      colHeader = "column" & " ".repeat(max(colFieldWidth - 6, 0))
      pathHeader = "path"
    result.add toRunes(fmt" {lineHeader} {colHeader} {pathHeader}")

  # Data lines
  for i, l in list.history:
    let
      lineStr = $l.position.line
      colStr = $l.position.column
      lineFieldWidth = max(4, positionMaxLen.line)
      colFieldWidth = max(6, positionMaxLen.col)

      # Padding
      linePadded = lineStr & " ".repeat(max(lineFieldWidth - lineStr.len, 0))
      colPadded = colStr & " ".repeat(max(colFieldWidth - colStr.len, 0))

    if i == list.currentPosition:
      let currentPositionMark = ru">"
      result.add currentPositionMark & linePadded.toRunes & ru" " & colPadded.toRunes &
        ru" " & l.path
    else:
      let currentPositionPadded = ru" "
      result.add currentPositionPadded & linePadded.toRunes & ru" " & colPadded.toRunes &
        ru" " & l.path

proc isJumpListCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isCtrlK(key) or isCtrlJ(key) or key == ord(':') or key == ord('k') or isUpKey(
      key
    ) or key == ord('j') or isDownKey(key) or isEnterKey(key) or key == ord('o') or
        key == ord('D'):
      return InputState.Valid

template changeModeToExMode*(bufStatus: BufferStatus, commandLine: CommandLine) =
  bufStatus.changeMode(Mode.ex)
  commandLine.clear
  commandLine.setPrompt(CommandLinePrompt.ex)

proc execJumpListCommand*(status: EditorStatus, command: Runes) =
  let key = command[0]

  if isCtrlK(key):
    status.moveNextWindow
  elif isCtrlJ(key):
    status.movePrevWindow
  elif key == ord(':'):
    currentBufStatus.changeModeToExMode(status.commandLine)
  elif key == ord('k') or isUpKey(key):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif key == ord('j') or isDownKey(key):
    currentBufStatus.keyDown(currentMainWindowNode)
