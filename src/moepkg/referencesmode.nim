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

import std/[os, options, strformat, sequtils]

import pkg/results

import independentutils, ui, unicodeext, editorstatus, movement, gapbuffer,
       bufferstatus, messages

import lsp/references

type
  Destination = tuple[path: Runes, line, column: int]

proc initReferencesModeBuffer*(references: seq[LspReference]): seq[Runes] =
  for r in references:
    result.add toRunes(
      fmt"{r.path} {r.position.line} Line {r.position.column} Col")

proc closeReferencesMode(status: var EditorStatus) =
  ## Close the window and remove the buffer.

  status.deleteBuffer(currentMainWindowNode.bufferIndex)

proc parseDestinationLine(line: Runes): Result[Destination, string] =
  let lineSplit = line.split(ru' ').filterIt(it.len > 0)
  if lineSplit.len != 5:
    return Result[Destination, string].err "Invalid destination"

  let
    line =
      try:
        parseInt(lineSplit[1])
      except ValueError:
        return Result[Destination, string].err "Invalid format: line"

    column =
      try:
        parseInt(lineSplit[3])
      except ValueError:
        return Result[Destination, string].err "Invalid format: column"

  return Result[Destination, string].ok (lineSplit[0], line, column)

proc openWindowAndJumpToReference(status: var EditorStatus) =
  let d = parseDestinationLine(
    currentBufStatus.buffer[currentMainWindowNode.currentLine])

  if d.isErr:
    status.commandLine.writeLspReferencesError(d.error)
    return

  if not fileExists($d.get.path):
    status.commandLine.writeLspReferencesError("File not found")
    return

  # Close references mode
  status.closeReferencesMode

  status.resize

  # Open a window for the destination.
  status.verticalSplitWindow
  status.moveNextWindow

  template canMove(): bool =
    d.get.line < currentBufStatus.buffer.len and
    d.get.column < currentBufStatus.buffer[d.get.line].len

  let bufferIndex = status.bufStatus.checkBufferExist(d.get.path)
  if isSome(bufferIndex):
    # Already exist.
    status.changeCurrentBuffer(bufferIndex.get)
    if not canMove():
      status.commandLine.writeLspReferencesError("Destination not found")
      return
  else:
    let r = status.addNewBufferInCurrentWin($d.get.path)
    if r.isErr:
      status.commandLine.writeLspReferencesError(r.error)
      return

    if not canMove():
      status.commandLine.writeLspReferencesError("Destination not found")
      return

  status.resize

  jumpLine(currentBufStatus, currentMainWindowNode, d.get.line)
  currentMainWindowNode.currentColumn = d.get.column

template isCancel(command: Runes): bool =
  command.len == 1 and (isCtrlC(command[0]) or isEscKey(command[0]))

template isMoveUp(command: Runes): bool =
  command == ru"k" or isUpKey(command)

template isMoveDown(command: Runes): bool =
  command == ru"j" or isDownKey(command)

template isMoveToFirstLine(command: Runes): bool =
  command == ru"g"

template isMoveToLastLine(command: Runes): bool =
  command == ru"G"

proc isReferencesModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 0:
    return InputState.Continue
  else:
    if isCancel(command) or
       isMoveUp(command) or
       isMoveDown(command) or
       isMoveToFirstLine(command) or
       isMoveToLastLine(command) or
       isEnterKey(command):
         return InputState.Valid

proc execReferencesModeCommand*(status: var EditorStatus, command: Runes) =
  if isCancel(command):
    status.closeReferencesMode
  elif isMoveUp(command):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif isMoveDown(command):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif isMoveToFirstLine(command):
    currentBufStatus.moveToFirstLine(currentMainWindowNode)
  elif isMoveToLastLine(command):
    currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif isEnterKey(command):
    status.openWindowAndJumpToReference
