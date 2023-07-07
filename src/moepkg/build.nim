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

import std/strformat
import pkg/results
import syntax/highlite
import unicodeext, backgroundprocess

type
  BuildCommand* = object
    command*: string
    args*: seq[string]

  BuildProcess* = object
    buildCommand*: BuildCommand
    filePath*: Runes
    process*: BackgroundProcess

proc isFinish*(bp: BuildProcess): bool {.inline.} = bp.process.isFinish

proc result*(bp: var BuildProcess): Result[seq[string], string] {.inline.} =
  bp.process.result

proc nimBuildCommand(path: string): BuildCommand {.inline.} =
  BuildCommand(command: "nim", args: @["c", path])

proc buildCommand(
  path: string,
  lang: SourceLanguage): Result[BuildCommand, string] =

    case lang:
      of SourceLanguage.langNim:
        return Result[BuildCommand, string].ok path.nimBuildCommand
      else:
        return Result[BuildCommand, string].err "Unknown language"

proc startBackgroundBuild*(
  path: Runes,
  language: SourceLanguage,
  workspaceRoot: Runes = ru""): Result[BuildProcess, string] =
    ## Start a background process for exec the build command.

    let cmd = buildCommand($path, language)
    if cmd.isErr:
      return Result[BuildProcess, string].err fmt"Failed to exec build commands: {cmd.error}"

    let backgroundProcess = startBackgroundProcess(
      cmd.get.command,
      cmd.get.args,
      $workspaceRoot)
    if backgroundProcess.isOk:
      return Result[BuildProcess, string].ok BuildProcess(
        buildCommand: cmd.get,
        filePath: path,
        process: backgroundProcess.get)
    else:
      return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

proc startBackgroundBuild*(
  customCommand: BuildCommand,
  language: SourceLanguage,
  workspaceRoot: Runes = ru""): Result[BuildProcess, string] =
    ## Start the build on a background process.

    if customCommand.command.len == 0:
      return Result[BuildProcess, string].err fmt"command is empty"

    let backgroundProcess = startBackgroundProcess(
      customCommand.command,
      customCommand.args,
      $workspaceRoot)
    if backgroundProcess.isOk:
      return Result[BuildProcess, string].ok BuildProcess(
        buildCommand: customCommand,
        process: backgroundProcess.get)
    else:
      return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"
