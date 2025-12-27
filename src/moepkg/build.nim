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

import pkg/results

import syntax/highlite, backgroundprocess

export backgroundprocess

type
  BuildCommand = tuple[cmd: string, args: seq[string]]

  BuildProcess* = object
    command*: BackgroundProcessCommand
    filePath*: string
    process*: BackgroundProcess

proc isRunning*(bp: BuildProcess): bool {.inline.} =
  bp.process.isRunning

proc isFinish*(bp: BuildProcess): bool {.inline.} =
  bp.process.isFinish

proc result*(bp: var BuildProcess): Result[seq[string], string] {.inline.} =
  bp.process.result

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

proc startBackgroundBuild*(
    path: string, language: SourceLanguage, workspaceRoot: string = ""
): Result[BuildProcess, string] =
  ## Start a background process for exec the build command.

  let command = buildCommand(path, language, workspaceRoot)
  if command.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {command.error}"

  let backgroundProcess = startBackgroundProcess(command.get)
  if backgroundProcess.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

  return Result[BuildProcess, string].ok BuildProcess(
    command: command.get, filePath: path, process: backgroundProcess.get
  )

proc startBackgroundBuild*(
    customCommand: BuildCommand, language: SourceLanguage, workspaceRoot: string = ""
): Result[BuildProcess, string] =
  ## Start the build on a background process.

  if customCommand.cmd.len == 0:
    return Result[BuildProcess, string].err fmt"command is empty"

  let command = BackgroundProcessCommand(
    cmd: customCommand.cmd, args: customCommand.args, workingDir: workspaceRoot
  )

  let backgroundProcess = startBackgroundProcess(command)
  if backgroundProcess.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

  return Result[BuildProcess, string].ok BuildProcess(
    command: command, process: backgroundProcess.get
  )

proc parseCommandString*(cmdStr: string): BuildCommand =
  ## Parse a command string into BuildCommand tuple.
  ## E.g., "nim c -d:release file.nim" -> (cmd: "nim", args: @["c", "-d:release", "file.nim"])
  let parts = cmdStr.split(' ')
  if parts.len == 0:
    return (cmd: "", args: @[])
  elif parts.len == 1:
    return (cmd: parts[0], args: @[])
  else:
    return (cmd: parts[0], args: parts[1 .. ^1])

proc startBackgroundBuildOnSave*(
    path: string,
    language: SourceLanguage,
    customCommand: string = "",
    workspaceRoot: string = "",
): Result[BuildProcess, string] =
  ## Start a background build for buildOnSave.
  ## If customCommand is provided, use it; otherwise use language-specific command.

  if customCommand.len > 0:
    let parsed = parseCommandString(customCommand)
    return startBackgroundBuild(parsed, language, workspaceRoot)
  else:
    return startBackgroundBuild(path, language, workspaceRoot)
