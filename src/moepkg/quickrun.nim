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

import std/[osproc, times, os]
import syntax/highlite
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui,
       editorstatus, movement, window, fileutils, commandline

proc generateCommand(bufStatus: BufferStatus,
                     settings: QuickRunSettings): string =

  let filename = $bufStatus.path

  result = "timeout " & $settings.timeout & " "
  if bufStatus.language == SourceLanguage.langNim:
    let
      advancedCommand = settings.nimAdvancedCommand
      options = settings.nimOptions
    result &= "nim " & advancedCommand & " -r " & options & " " & filename
  elif bufStatus.language == SourceLanguage.langC:
    result &= "gcc " & settings.clangOptions & " " & filename & " && ./a.out"
  elif bufStatus.language == SourceLanguage.langCpp:
    result &= "g++ " & settings.cppOptions & " " & filename & " && ./a.out"
  elif bufStatus.language == SourceLanguage.langShell:
    if bufStatus.buffer[0] == ru"#!/bin/bash":
      result &= "bash " & settings.bashOptions & " " & filename
    else:
      result &= "sh " & settings.shOptions & " "  & filename
  else:
    result = ""

proc getQuickRunBufferIndex*(bufStatus: seq[BufferStatus],
                             mainWindowNode: WindowNode): int =

  result = -1
  let allBufferIndex = mainWindowNode.getAllBufferIndex
  for index in allBufferIndex:
    if bufStatus[index].mode == Mode.quickRun: return index

proc runQuickRun*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine,
  settings: EditorSettings): seq[seq[Rune]] =

  if bufStatus.path.len == 0: return @[ru""]

  let filename = bufStatus.path

  if settings.quickRun.saveBufferWhenQuickRun:
    block:
      let lastModificationTime = getLastModificationTime($bufStatus.path)
      if lastModificationTime > bufStatus.lastSaveTime.toTime:
        # TODO: Show error message
        # Cancel if the file was edited by a program other than moe.
        return @["".ru]

    saveFile(filename, bufStatus.buffer.toRunes, bufStatus.characterEncoding)

    bufStatus.countChange = 0
    bufStatus.lastSaveTime = now()

  let command = bufStatus.generateCommand(settings.quickRun)
  if command == "": return @[ru""]

  commandLine.writeRunQuickRunMessage(settings.notification)
  let cmdResult = execCmdEx(command)
  commandLine.clear

  result = @[ru""]

  case cmdResult.exitCode:
    of 124:
      commandLine.writeRunQuickRunTimeoutMessage
    else:
      for i in 0 ..< cmdResult.output.len:
        if cmdResult.output[i] == '\n': result.add(@[ru""])
        else: result[^1].add(toRunes($cmdResult.output[i])[0])

proc isQuickRunCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isControlK(key) or
       isControlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('G'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc execQuickRunCommand*(status: var EditorStatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
