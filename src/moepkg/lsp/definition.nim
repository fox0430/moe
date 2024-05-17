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

import std/[strformat, json, options]

import pkg/results

import ../independentutils

import protocol/types
import utils

type
  LspDefinition* = object
    path*: string
    position*: BufferPosition

  LspDefinitionResult* = Result[Option[LspDefinition], string]

proc initDefinitionParams*(
  path: string,
  posi: BufferPosition): DefinitionParams =

    DefinitionParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: posi.toLspPosition)

proc parseTextDocumentDefinition*(res: JsonNode): LspDefinitionResult =
  if res["result"].kind != JArray:
    return LspDefinitionResult.err "Invalid response"
  elif res["result"].len == 0:
    # Not found
    return LspDefinitionResult.ok none(LspDefinition)

  let location =
    try:
      res["result"][0].to(Location)
    except CatchableError as e:
      return LspDefinitionResult.err fmt"Invalid response: {e.msg}"

  let path = location.uri.uriToPath
  if path.isErr:
    return LspDefinitionResult.err "Invalid uri"

  return LspDefinitionResult.ok some(LspDefinition(
    path: path.get,
    position: location.range.start.toBufferPosition))
