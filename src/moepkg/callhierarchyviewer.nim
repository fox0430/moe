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

import std/[options, os, sequtils, strformat]

import pkg/results

import independentutils, ui, unicodeext, editorstatus, movement, gapbuffer,
       bufferstatus, messages, commandline

import
  lsp/protocol/types,
  lsp/callhierarchy,
  lsp/utils

type
  Destination = tuple[path: Runes, line, column: int]

proc initCallHierarchyViewBuffer*(
  items: seq[CallHierarchyItem]): seq[Runes] =

    for i in items:
      result.add toRunes(
        fmt"{i.name} {$i.detail} {i.uri.uriToPath} {$i.range.start.line} {$i.range.start.character}")

proc closeCallHierarchyViewer(status: var EditorStatus) =
  ## Close the window and remove the buffer.

  status.deleteBuffer(currentMainWindowNode.bufferIndex)

proc parseDestinationLine(line: Runes): Result[Destination, string] =
  let lineSplited = line.split(ru' ').filterIt(it.len > 0)
  if lineSplited.len < 3:
    return Result[Destination, string].err "Invalid destination"

  let
    lastIndex = lineSplited.high

    line =
      try:
        parseInt(lineSplited[lastIndex - 1])
      except ValueError:
        return Result[Destination, string].err "Invalid format: line"

    column =
      try:
        parseInt(lineSplited[lastIndex])
      except ValueError:
        return Result[Destination, string].err "Invalid format: column"

  return Result[Destination, string].ok (lineSplited[lastIndex - 2], line, column)

template currentLineBuffer: Runes =
  currentBufStatus.buffer[currentMainWindowNode.currentLine]

proc jumpToDestination(status: var EditorStatus) =
  if currentLineBuffer.len == 0: return

  let d = parseDestinationLine(currentLineBuffer)
  if d.isErr:
    status.commandLine.writeLspCallHierarchyError(d.error)
    # TODO: Show error
    return

  if not fileExists($d.get.path):
    status.commandLine.writeLspCallHierarchyError("File not found")
    return

  status.closeCallHierarchyViewer

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

proc changeModeToExMode*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) {.inline.} =

    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(ExModePrompt)

template isMoveUp(command: Runes): bool =
  command == ru"k" or isUpKey(command)

template isMoveDown(command: Runes): bool =
  command == ru"j" or isDownKey(command)

template isMoveToFirstLine(command: Runes): bool =
  command == ru"g"

template isMoveToLastLine(command: Runes): bool =
  command == ru"G"

template isMoveToPrevWindow(command: Runes): bool =
 isCtrlJ(command)

template isMoveToNextWindow(command: Runes): bool =
 isCtrlK(command)

template isEnterExMode(command: Runes): bool =
  command == ru":"

template isJump(command: Runes): bool =
  isEnterKey(command)

proc isCallHierarchyViewerCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 0:
    return InputState.Continue
  else:
    if isMoveUp(command) or
       isMoveDown(command) or
       isMoveToFirstLine(command) or
       isMoveToLastLine(command) or
       isMoveToPrevWindow(command) or
       isMoveToNextWindow(command) or
       isEnterExMode(command) or
       isJump(command):
         return InputState.Valid

proc execCallHierarchyViewerCommand*(status: var EditorStatus, command: Runes) =
  if isMoveUp(command):
    currentBufStatus.keyUp(currentMainWindowNode)
  elif isMoveDown(command):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif isMoveToFirstLine(command):
    currentBufStatus.moveToFirstLine(currentMainWindowNode)
  elif isMoveToLastLine(command):
    currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif isMoveToPrevWindow(command):
    status.movePrevWindow
  elif isMoveToNextWindow(command):
    status.moveNextWindow
  elif isEnterExMode(command):
    currentBufStatus.changeModeToExMode(status.commandLine)
  elif isJump(command):
    status.jumpToDestination
