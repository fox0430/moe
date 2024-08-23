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

import std/[options, os, sequtils, strformat, tables]

import pkg/results

import ui, unicodeext, editorstatus, movement, gapbuffer, bufferstatus,
       messages, commandline

import
  lsp/protocol/types,
  lsp/callhierarchy,
  lsp/client,
  lsp/utils

type
  Destination = tuple[path: Runes, line, column: int]

const
  # The length pf header lines.
  CallHierarchyViewHeaderLength* = 2

template headerLines(t: CallHierarchyType): seq[Runes] =
  case t:
    of CallHierarchyType.prepare:
      @["Prepare Call", ""].toSeqRunes
    of CallHierarchyType.incoming:
      @["Incoming Call", ""].toSeqRunes
    of CallHierarchyType.outgoing:
      @["Outgoing Call", ""].toSeqRunes

proc initCallHierarchyViewBuffer*(
  callHierarchyType: CallHierarchyType,
  items: seq[CallHierarchyItem]): Result[seq[Runes], string] =

    var lines = headerLines(callHierarchyType)
    for i in items:
      let detail =
        if i.detail.isSome: i.detail.get
        else: ""

      let path = i.uri.uriToPath
      if path.isErr:
        return Result[seq[Runes], string].err fmt"Invalid uri: {i.uri}"

      lines.add toRunes(
        fmt"{i.name} {detail} {path.get} {$i.range.start.line} {$i.range.start.character}")

    return Result[seq[Runes], string].ok lines

proc getLangId(status: EditorStatus): Option[string] =
  let bufferId = currentBufStatus.callHierarchyInfo.bufferId
  for b in status.bufStatus:
    if b.id == bufferId:
      return some(b.langId)

proc closeCallHierarchyViewer(status: var EditorStatus) =
  ## Close the window and remove the buffer.

  status.deleteBuffer(currentMainWindowNode.bufferIndex)

proc incomingCalls(status: var EditorStatus) =
  if currentBufStatus.callHierarchyInfo.items.len == 0:
    status.commandLine.writeLspCallHierarchyError("Not found")
    return

  let langId = status.getLangId
  if langId.isNone:
    status.commandLine.writeLspCallHierarchyError("Lang ID is not found")
    return

  let infoIndex =
    currentMainWindowNode.currentLine - CallHierarchyViewHeaderLength

  let r = status.lspClients[langId.get].textDocumentIncomingCalls(
    currentBufStatus.id,
    currentBufStatus.callHierarchyInfo.items[infoIndex])
  if r.isErr:
    status.commandLine.writeLspCallHierarchyError(r.error)
    return

proc outgoingCalls(status: var EditorStatus) =
  if currentBufStatus.callHierarchyInfo.items.len == 0:
    status.commandLine.writeLspCallHierarchyError("Not found")
    return

  let langId = status.getLangId
  if langId.isNone:
    status.commandLine.writeLspCallHierarchyError("Lang ID is not found")
    return

  let infoIndex =
    currentMainWindowNode.currentLine - CallHierarchyViewHeaderLength

  let r = status.lspClients[langId.get].textDocumentOutgoingCalls(
    currentBufStatus.id,
    currentBufStatus.callHierarchyInfo.items[infoIndex])
  if r.isErr:
    status.commandLine.writeLspCallHierarchyError(r.error)
    return

proc parseDestinationLine(line: Runes): Result[Destination, string] =
  let lineSplit = line.split(ru' ').filterIt(it.len > 0)
  if lineSplit.len < 3:
    return Result[Destination, string].err "Invalid destination"

  let
    lastIndex = lineSplit.high

    line =
      try:
        parseInt(lineSplit[lastIndex - 1])
      except ValueError:
        return Result[Destination, string].err "Invalid format: line"

    column =
      try:
        parseInt(lineSplit[lastIndex])
      except ValueError:
        return Result[Destination, string].err "Invalid format: column"

  return Result[Destination, string].ok (lineSplit[lastIndex - 2], line, column)

template selectedDestination: Runes =
  currentBufStatus.buffer[currentMainWindowNode.currentLine]

proc jumpToDestination(status: var EditorStatus) =
  ## Open a new window and go to the destination.

  if currentLineBuffer.len == CallHierarchyViewHeaderLength: return

  let d = parseDestinationLine(selectedDestination)
  if d.isErr:
    status.commandLine.writeLspCallHierarchyError(d.error)
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

template isIncomingCall(command: Runes): bool =
  command == ru"i"

template isOutgoingCall(command: Runes): bool =
  command == ru"o"

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
       isJump(command) or
       isIncomingCall(command) or
       isOutgoingCall(command):
         return InputState.Valid

proc execCallHierarchyViewerCommand*(status: var EditorStatus, command: Runes) =
  if isMoveUp(command):
    currentBufStatus.keyUp(currentMainWindowNode, CallHierarchyViewHeaderLength)
  elif isMoveDown(command):
    currentBufStatus.keyDown(currentMainWindowNode)
  elif isMoveToFirstLine(command):
    currentBufStatus.moveToFirstLine(
      currentMainWindowNode,
      CallHierarchyViewHeaderLength)
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
  elif isIncomingCall(command):
    status.incomingCalls
  elif isOutgoingCall(command):
    status.outgoingCalls
