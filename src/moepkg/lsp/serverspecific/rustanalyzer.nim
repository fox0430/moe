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

import std/[json, sequtils, strformat, options, os]

import pkg/results

import ../../backgroundprocess
import ../../quickrunutils
import ../protocol/types

type
  CodeLensArgs* = ref object
    overrideCargo*: JsonNode
    workspaceRoot*: string
    cargoArgs*: seq[string]
    cargoExtraArgs*: seq[string]
    executableArgs*: seq[string]

  RACodeLensResult* = Result[QuickRunProcess, string]

proc experimentClientCapabilities*(): JsonNode =
  ## Experimental client capabilities for rust-analyzer

  %*{
    "commands": {
      "commands": [
        "rust-analyzer.runSingle",
        "rust-analyzer.debugSingle"
      ]
    }
  }

proc runSingle*(lens: CodeLens, path: string): RACodeLensResult =
  ## `commands.rust-analyzer.runSingle`

  if lens.command.isNone or
     lens.command.get.arguments.isNone or
     lens.command.get.arguments.get.kind != JArray or
     lens.command.get.arguments.get.len != 1:
       return RACodeLensResult.err fmt"Invalid command"

  let
    codeLensArgs =
      try:
        lens.command.get.arguments.get[0]["args"].to(CodeLensArgs)
      except CatchableError as e:
        return RACodeLensResult.err fmt"Invalid command: {e.msg}"

  var
    cmd = ""
    args: seq[string]
  try:
    cmd = lens.command.get.arguments.get[0]["kind"].getStr
    args.add codeLensArgs.cargoArgs.mapIt(it)
    args.add codeLensArgs.executableArgs.mapIt(it)
  except CatchableError as e:
    return RACodeLensResult.err fmt"Invalid command: {e.msg}"

  let command = BackgroundProcessCommand(
    cmd: cmd,
    args: args,
    workingDir: getCurrentDir())

  let p = startBackgroundProcess(command)
  if p.isErr:
    return RACodeLensResult.err fmt"rust-analyzer.runSingle failed: {p.error}"

  return RACodeLensResult.ok QuickRunProcess(
    command: command,
    filePath: path,
    process: p.get)

proc debugSingle*(lens: CodeLens, path: string): RACodeLensResult =
  if lens.command.isNone or
     lens.command.get.arguments.isNone or
     lens.command.get.arguments.get.kind != JArray or
     lens.command.get.arguments.get.len != 1:
       return RACodeLensResult.err fmt"Invalid command"

  let
    codeLensArgs =
      try:
        lens.command.get.arguments.get[0]["args"].to(CodeLensArgs)
      except CatchableError as e:
        return RACodeLensResult.err fmt"Invalid command: {e.msg}"

  var
    cmd = ""
    args: seq[string]
  try:
    cmd = lens.command.get.arguments.get[0]["kind"].getStr

    case codeLensArgs.cargoArgs[0]
      of "test": args.add "--no-run"
      of "run": args.add "build"
    args.add codeLensArgs.cargoArgs[1 .. codeLensArgs.cargoArgs.high].mapIt(it)

    args.add codeLensArgs.executableArgs.mapIt(it)
  except CatchableError as e:
    return RACodeLensResult.err fmt"Invalid command: {e.msg}"

  let command = BackgroundProcessCommand(
    cmd: cmd,
    args: args,
    workingDir: getCurrentDir())

  let p = startBackgroundProcess(command)
  if p.isErr:
    return RACodeLensResult.err fmt"rust-analyzer.debugSingle failed: {p.error}"

  return RACodeLensResult.ok QuickRunProcess(
    command: command,
    filePath: path,
    process: p.get)

proc runCodeLensCommand*(lens: CodeLens, path: string): RACodeLensResult =
  if lens.command.isNone:
    return RACodeLensResult.err fmt"Invalid command"

  case lens.command.get.command:
    of "rust-analyzer.runSingle":
      return lens.runSingle(path)
    of "rust-analyzer.debugSingle":
      return lens.debugSingle(path)
    else:
      return RACodeLensResult.err fmt"Unknown command"
