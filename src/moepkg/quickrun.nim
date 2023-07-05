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

import std/[osproc, times, os, strutils, strformat]
import pkg/results
import syntax/highlite
import unicodeext, settings, bufferstatus, gapbuffer, messages, ui,
       editorstatus, movement, windownode, fileutils, commandline

proc languageExtension(lang: SourceLanguage): Result[string, string] =
  case lang:
    of SourceLanguage.langNim:
      Result[string, string].ok "nim"
    of SourceLanguage.langC:
      Result[string, string].ok"c"
    of SourceLanguage.langCpp:
      Result[string, string].ok "cpp"
    of SourceLanguage.langShell:
      # TODO: Add support for other shells.
      Result[string, string].ok "bash"
    else:
      Result[string, string].err "Unknown language"

proc generateCommand(
  path: string,
  lang: SourceLanguage,
  buffer: seq[Runes],
  settings: QuickRunSettings): Result[string, string] =

    var command = "timeout " & $settings.timeout & " "
    case lang
      of SourceLanguage.langNim:
        let
          advancedCommand = settings.nimAdvancedCommand
          options = settings.nimOptions
        command &= "nim " & advancedCommand & " -r " & options & " " & path
      of SourceLanguage.langC:
        command &= "gcc " & settings.clangOptions & " " & path & " && ./a.out"
      of SourceLanguage.langCpp:
        command &= "g++ " & settings.cppOptions & " " & path & " && ./a.out"
      of SourceLanguage.langShell:
        # TODO: Add support for other shells.
        if buffer[0] == ru"#!/bin/sh":
          command &= "sh " & settings.shOptions & " "  & path
        else:
          command &= "bash " & settings.bashOptions & " " & path
      else:
        return Result[string, string].err "Unknown language"

    return Result[string, string].ok command

proc getQuickRunBufferIndex*(
  bufStatus: seq[BufferStatus],
  mainWindowNode: WindowNode): int =

    result = -1
    let allBufferIndex = mainWindowNode.getAllBufferIndex
    for index in allBufferIndex:
      if bufStatus[index].mode == Mode.quickRun: return index

proc runQuickRun*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine,
  settings: EditorSettings): Result[seq[Runes], string] =

    let
      useTempFile = not fileExists($bufStatus.path)
      path =
        if useTempFile:
          # A temporary file name.
          "quickruntemp." & ?bufStatus.language.languageExtension
        else:
          $bufStatus.path

    if settings.quickRun.saveBufferWhenQuickRun and not useTempFile:
      let lastModificationTime = getLastModificationTime($bufStatus.path)
      if lastModificationTime > bufStatus.lastSaveTime.toTime:
        return Result[seq[Runes], string].err "The file has been changed by other programs"

    if settings.quickRun.saveBufferWhenQuickRun or useTempFile:
      # Create and use a temporary file if the source code file does not exist.
      try:
        saveFile(
          path.toRunes,
          bufStatus.buffer.toRunes,
          bufStatus.characterEncoding)
      except CatchableError as e:
        return Result[seq[Runes], string].err fmt"Failed to save the current code: {e.msg}"

      if not useTempFile:
        bufStatus.countChange = 0
        bufStatus.lastSaveTime = now()

    let command = generateCommand(
      path,
      bufStatus.language,
      bufStatus.buffer.toSeqRunes,
      settings.quickRun)
    if command.isErr:
      return Result[seq[Runes], string].err "Quickrun: {command.error}"

    commandLine.writeRunQuickRunMessage(settings.notification)
    let cmdResult = execCmdEx(command.get)
    commandLine.clear

    if useTempFile:
      # Cleanup temporary files.
      if path.fileExists: removeFile(path)
      if path.split(".")[0].fileExists: removeFile(path.split(".")[0])

    case cmdResult.exitCode:
      of 124:
        return Result[seq[Runes], string].err "Quickrun: timeout"
      else:
        var cmdOutput = @[ru""]
        for line in cmdResult.output.splitLines:
          cmdOutput.add line.toRunes

        return Result[seq[Runes], string].ok cmdOutput

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
