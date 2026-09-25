#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import pkg/[results, chronos]

import background_process
import command_string
import syntax/tokenizer

export background_process

type
  BuildCommand = CommandArgv

  BuildProcess* = object
    command*: BackgroundProcessCommand
    filePath*: string
    process*: BackgroundProcess

proc nimBuildCommand(path: string): BuildCommand {.inline.} =
  return (cmd: "nim", args: @["c", path])

proc rustBuildCommand(path: string): BuildCommand {.inline.} =
  return (cmd: "cargo", args: @["build"])

proc buildCommand(
    path: string, lang: SourceLanguage, workspaceRoot: string
): Result[BackgroundProcessCommand, string] =
  var command: BuildCommand
  case lang
  of SourceLanguage.langNim:
    command = path.nimBuildCommand
  of SourceLanguage.langRust:
    command = path.rustBuildCommand
  else:
    return Result[BackgroundProcessCommand, string].err "Unknown language"

  return Result[BackgroundProcessCommand, string].ok BackgroundProcessCommand(
    cmd: command.cmd, args: command.args, workingDir: workspaceRoot
  )

proc buildOnSaveCommand*(
    path: string,
    language: SourceLanguage,
    customCommand: string = "",
    workspaceRoot: string = "",
): Result[BackgroundProcessCommand, string] =
  ## What a build of `path` runs: `customCommand` when given, otherwise the
  ## language's own command.
  if customCommand.len > 0:
    let parsed = parseCommandString(customCommand)
    if parsed.cmd.len == 0:
      return Result[BackgroundProcessCommand, string].err "command is empty"
    Result[BackgroundProcessCommand, string].ok BackgroundProcessCommand(
      cmd: parsed.cmd, args: parsed.args, workingDir: workspaceRoot
    )
  else:
    buildCommand(path, language, workspaceRoot).mapErr(
      proc(e: string): string =
        fmt"Failed to exec build commands: {e}"
    )

proc startBackgroundBuild*(
    command: BackgroundProcessCommand, path: string = ""
): Result[BuildProcess, string] =
  ## Start `command` as a build of `path`.
  let backgroundProcess = startBackgroundProcess(command)
  if backgroundProcess.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

  Result[BuildProcess, string].ok BuildProcess(
    command: command, filePath: path, process: backgroundProcess.get
  )

proc waitForAsync*(
    bp: BuildProcess, timeout: Duration, stop: JobStop = nil
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the build to complete and return its output. A build still
  ## running after `timeout`, or told to `stop`, is killed and reported as an
  ## error.
  return await bp.process.waitForAsync(timeout, stop)
