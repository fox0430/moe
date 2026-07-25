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
import syntax/tokenizer

export background_process

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
): Future[Result[BuildProcess, string]] {.async: (raises: []).} =
  ## Start a background process for exec the build command.

  let command = buildCommand(path, language, workspaceRoot)
  if command.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {command.error}"

  let backgroundProcess = await startBackgroundProcess(command.get)
  if backgroundProcess.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

  return Result[BuildProcess, string].ok BuildProcess(
    command: command.get, filePath: path, process: backgroundProcess.get
  )

proc startBackgroundBuild*(
    customCommand: BuildCommand, language: SourceLanguage, workspaceRoot: string = ""
): Future[Result[BuildProcess, string]] {.async: (raises: []).} =
  ## Start the build on a background process.

  if customCommand.cmd.len == 0:
    return Result[BuildProcess, string].err fmt"command is empty"

  let command = BackgroundProcessCommand(
    cmd: customCommand.cmd, args: customCommand.args, workingDir: workspaceRoot
  )

  let backgroundProcess = await startBackgroundProcess(command)
  if backgroundProcess.isErr:
    return Result[BuildProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

  return Result[BuildProcess, string].ok BuildProcess(
    command: command, process: backgroundProcess.get
  )

proc parseCommandString*(cmdStr: string): BuildCommand =
  ## Parse a command string into BuildCommand tuple, honoring POSIX-style
  ## single/double quotes and backslash escapes so args containing whitespace
  ## survive as a single token.
  ## E.g., `nim c "-d:foo bar" file.nim` -> (cmd: "nim", args: @["c", "-d:foo bar", "file.nim"])
  var
    tokens: seq[string] = @[]
    current = ""
    inSingle = false
    inDouble = false
    hasToken = false
    i = 0
  while i < cmdStr.len:
    let c = cmdStr[i]
    if inSingle:
      if c == '\'':
        inSingle = false
      else:
        current.add c
    elif inDouble:
      if c == '"':
        inDouble = false
      elif c == '\\' and i + 1 < cmdStr.len and cmdStr[i + 1] in {'"', '\\'}:
        current.add cmdStr[i + 1]
        inc i
      else:
        current.add c
    else:
      case c
      of ' ', '\t':
        if hasToken:
          tokens.add current
          current = ""
          hasToken = false
      of '\'':
        inSingle = true
        hasToken = true
      of '"':
        inDouble = true
        hasToken = true
      of '\\':
        if i + 1 < cmdStr.len:
          current.add cmdStr[i + 1]
          inc i
        else:
          current.add c
        hasToken = true
      else:
        current.add c
        hasToken = true
    inc i
  if hasToken or inSingle or inDouble:
    tokens.add current

  if tokens.len == 0:
    return (cmd: "", args: @[])
  elif tokens.len == 1:
    return (cmd: tokens[0], args: @[])
  else:
    return (cmd: tokens[0], args: tokens[1 .. ^1])

proc startBackgroundBuildOnSave*(
    path: string,
    language: SourceLanguage,
    customCommand: string = "",
    workspaceRoot: string = "",
): Future[Result[BuildProcess, string]] {.async: (raises: []).} =
  ## Start a background build for buildOnSave.
  ## If customCommand is provided, use it; otherwise use language-specific command.

  if customCommand.len > 0:
    let parsed = parseCommandString(customCommand)
    return await startBackgroundBuild(parsed, language, workspaceRoot)
  else:
    return await startBackgroundBuild(path, language, workspaceRoot)

proc waitForAsync*(
    bp: BuildProcess, timeout: Duration
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the build to complete and return its output. A build still
  ## running after `timeout` is killed and reported as an error.
  return await bp.process.waitForAsync(timeout)
