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

import std/[strformat, json, options, sequtils]

import pkg/results

import protocol/types

type
  ExecuteCommandResult* = Result[Option[JsonNode], string]

proc initExecuteCommandParams*(
  command: string,
  args: seq[string]): ExecuteCommandParams =

    ExecuteCommandParams(
      command: command,
      arguments: args.mapIt(%*it))

proc parseExecuteCommandResponse*(res: JsonNode): ExecuteCommandResult =
  if not res.contains("result"):
    return ExecuteCommandResult.err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    return ExecuteCommandResult.ok none(JsonNode)

  return ExecuteCommandResult.ok some(res["result"])
