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
  LspImplementation*  = object
    location*: BufferLocation

  LspImplementationResult* = Result[Option[LspImplementation], string]

proc initImplementationParams*(
  path: string,
  posi: BufferPosition): ImplementationParams =

    ImplementationParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: posi.toLspPosition)

proc parseTextDocumentImplementation*(res: JsonNode): LspImplementationResult =
  if res["result"].kind != JArray:
    return LspImplementationResult.err "Invalid response"
  elif res["result"].len == 0:
    # Not found
    return LspImplementationResult.ok none(LspImplementation)

  let location =
    try:
      let l = res["result"][0].to(Location)
      l.toBufferLocation
    except CatchableError as e:
      return LspImplementationResult.err fmt"Invalid response: {e.msg}"

  return LspImplementationResult.ok some(LspImplementation(location: location))
