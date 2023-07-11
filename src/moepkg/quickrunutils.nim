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

import std/[times, os, strutils, strformat, options, streams]
import pkg/results
import syntax/highlite
import unicodeext, settings, bufferstatus, gapbuffer, fileutils,
       backgroundprocess

type
  QuickRunProcess* = object
    command*: BackgroundProcessCommand
    filePath*: string
    isTempFile*: bool
    outputStream*: Stream
    process*: BackgroundProcess

proc quickRunStartupMessage*(path: string): string =
  fmt"Start QuickRun: {path}..."

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

proc isSh(buffer: seq[Runes]): bool {.inline.} =
  buffer[0] == ru"#!/bin/sh"

proc nimQuickRunCommand(
  path: string,
  settings: QuickRunSettings): BackgroundProcessCommand =

    const Cmd = "nim"
    var args: seq[string]

    if settings.nimAdvancedCommand.len > 0:
      args.add settings.nimAdvancedCommand

    args.add "-r"

    if settings.nimOptions.len > 0:
      args.add settings.nimOptions

    args.add path

    return BackgroundProcessCommand(cmd: Cmd, args: args)

proc clangQuickRunCommand(
  path: string,
  settings: QuickRunSettings): BackgroundProcessCommand {.inline.} =

    BackgroundProcessCommand(cmd: "/bin/bash",
     args: @["-c", fmt"'gcc {settings.clangOptions} {path} && ./.out'"])

proc cppQuickRunCommand(
  path: string,
  settings: QuickRunSettings): BackgroundProcessCommand {.inline.} =
    BackgroundProcessCommand(cmd: "/bin/bash",

     args: @["-c", fmt"'g++ {settings.cppOptions} {path} && ./.out'"])

proc shQuickRunCommand(
  path: string,
  settings: QuickRunSettings): BackgroundProcessCommand =

    var args: seq[string]

    if settings.shOptions.len > 0:
      args.add settings.shOptions

    args.add path

    BackgroundProcessCommand(cmd: "/bin/sh", args: args)

proc bashQuickRunCommand(
  path: string,
  settings: QuickRunSettings): BackgroundProcessCommand =

    var args: seq[string]

    if settings.bashOptions.len > 0:
      args.add settings.bashOptions

    args.add path

    BackgroundProcessCommand(cmd: "/bin/bash", args: args)

proc quickRunCommand(
  path: string,
  lang: SourceLanguage,
  buffer: seq[Runes],
  settings: QuickRunSettings): Result[BackgroundProcessCommand, string] =

    var command: BackgroundProcessCommand
    case lang
      of SourceLanguage.langNim:
        command = nimQuickRunCommand(path, settings)
      of SourceLanguage.langC:
        command = clangQuickRunCommand(path, settings)
      of SourceLanguage.langCpp:
         command = cppQuickRunCommand(path, settings)
      of SourceLanguage.langShell:
        if buffer.isSh:
          command = shQuickRunCommand(path, settings)
        else:
          command = bashQuickRunCommand(path, settings)
      else:
        return Result[BackgroundProcessCommand, string].err "Unknown language"

    return Result[BackgroundProcessCommand, string].ok command

proc isRunning*(p: QuickRunProcess): bool {.inline.} = p.process.isRunning

proc cancel*(p: QuickRunProcess) {.inline.} = p.process.cancel

proc kill*(p: QuickRunProcess) {.inline.} = p.process.kill

proc close*(p: QuickRunProcess) {.inline.} = p.process.close

proc isFinish*(p: QuickRunProcess): bool {.inline.} = p.process.isFinish

proc quickRunBufferExists*(
  bufStatuses: seq[BufferStatus], path: string): bool =
    ## Return true if already exists a buffer for the quickrun.

    for b in bufStatuses:
      if b.isQuickRunMode and path == $b.path: return true

proc quickRunBufferIndex*(
  bufStatuses: seq[BufferStatus], path: string): Option[int]=
    ## Return a bufStatus index if exists a buffer for the quickrun.

    for i, b in bufStatuses:
      if b.isQuickRunMode and path == $b.path: return some(i)

proc startBackgroundQuickRun*(
  bufStatus: var BufferStatus,
  settings: EditorSettings): Result[QuickRunProcess, string] =
    ## Start a background process for build and run commands.

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
        return Result[QuickRunProcess, string].err "The file has been changed by other programs"

    if settings.quickRun.saveBufferWhenQuickRun or useTempFile:
      # Create and use a temporary file if the source code file does not exist.
      try:
        saveFile(
          path.toRunes,
          bufStatus.buffer.toRunes,
          bufStatus.characterEncoding)
      except CatchableError as e:
        return Result[QuickRunProcess, string].err fmt"Failed to save the current code: {e.msg}"

      if not useTempFile:
        bufStatus.countChange = 0
        bufStatus.lastSaveTime = now()

    let command = quickRunCommand(
      path,
      bufStatus.language,
      bufStatus.buffer.toSeqRunes,
      settings.quickRun)
    if command.isErr:
      return Result[QuickRunProcess, string].err fmt"QuickRun failed: {command.error}"

    let backgroundProcess = startBackgroundProcess(command.get)
    if backgroundProcess.isErr:
      return Result[QuickRunProcess, string].err fmt"QuickRun failed: {backgroundProcess.error}"

    return Result[QuickRunProcess, string].ok QuickRunProcess(
      command: command.get,
      filePath: path,
      isTempFile: useTempFile,
      outputStream: backgroundProcess.get.outputStream,
      process: backgroundProcess.get)

proc result*(p: var QuickRunProcess): Result[seq[string], string] =
  ## Return an output of execution result.

  if p.isTempFile:
    # Cleanup temporary a source code file.
    if p.filePath.fileExists: removeFile(p.filePath)
    # Cleanup temporary a excutable.
    if p.filePath.split(".")[0].fileExists: removeFile(p.filePath.split(".")[0])

  let r = p.process.result
  if r.isOk:
    return Result[seq[string], string].ok r.get
  else:
    return Result[seq[string], string].err fmt"QuickRun failed: {$p.filePath}: {r.error}"
