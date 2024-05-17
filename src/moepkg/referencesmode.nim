#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[os, strformat, sequtils]

import pkg/results

import independentutils, ui, unicodeext, editorstatus, movement, gapbuffer,
       bufferstatus

import lsp/references

type
  Destination = tuple[path: Runes, line, column: int]

proc initReferencesModeBuffer*(references: seq[LspReference]): seq[Runes] =
  for r in references:
    result.add toRunes(
      fmt"{r.path} {r.position.line} Line {r.position.column} Col")

proc closeReferencesMode(status: var EditorStatus) =
  ## Close the window and remove the buffer.

  let bufIndex = currentMainWindowNode.bufferIndex
  status.closeWindow(currentMainWindowNode)
  status.deleteBuffer(bufIndex)

proc parseDestinationLine(line: Runes): Result[Destination, string] =
  let lineSplited = line.split(ru' ').filterIt(it.len > 0)
  if lineSplited.len != 5:
    return Result[Destination, string].err "Invalid destination"

  let
    line =
      try:
        parseInt(lineSplited[1])
      except ValueError:
        # TODO: Error message
        return

    column =
      try:
        parseInt(lineSplited[3])
      except ValueError:
        # TODO: Error message
        return

  return Result[Destination, string].ok (lineSplited[0], line, column)

proc openWindowAndJumpToReference(status: var EditorStatus) =
  let d = parseDestinationLine(
    currentBufStatus.buffer[currentMainWindowNode.currentLine])

  if d.isErr:
    # TODO: Error message
    return

  if not fileExists($d.get.path):
    # TODO: Error message
    return

  # Close references mode
  status.closeReferencesMode

  # Open a window for the destination.
  status.verticalSplitWindow
  status.moveNextWindow

  for i, b in status.bufStatus:
    if b.absolutePath == d.get.path:
      status.changeCurrentBuffer(i)
      return

  let r = status.addNewBufferInCurrentWin($d.get.path)
  if r.isErr:
    # TODO: Error message
    return

  template canMove(): bool =
    d.get.line < currentBufStatus.buffer.len and
    d.get.column < currentBufStatus.buffer[d.get.line].len

  if not canMove():
    # TODO: Error message
    return

  status.resize
  status.update

  jumpLine(currentBufStatus, currentMainWindowNode, d.get.line)
  currentMainWindowNode.currentColumn = d.get.column

template isCancel(command: Runes): bool =
  command.len == 1 and (isCtrlC(command[0]) or isEscKey(command[0]))

template isMoveUp(command: Runes): bool =
  command == ru"k" or isUpKey(command)

template isMoveDown(command: Runes): bool =
  command == ru"j" or isDownKey(command)

proc isReferencesModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 0:
    return InputState.Continue
  else:
    if isCancel(command) or
       isMoveUp(command) or
       isMoveDown(command) or
       isEnterKey(command):
         return InputState.Valid

proc execReferencesModeCommand*(status: var EditorStatus, command: Runes) =
  if isCancel(command):
    let bufIndex = currentMainWindowNode.bufferIndex
    status.closeWindow(currentMainWindowNode)
    status.deleteBuffer(bufIndex)
  elif isMoveUp(command):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif isMoveDown(command):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif isEnterKey(command):
    status.openWindowAndJumpToReference
