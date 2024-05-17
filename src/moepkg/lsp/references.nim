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

import std/[json, strformat]

import pkg/results

import ../independentutils

import protocol/types
import utils

type
  LspReference* = object
    path*: string
    position*: BufferPosition

  LspReferencesResult* = Result[seq[LspReference], string]

proc initReferenceParams*(
  path: string,
  position: LspPosition): ReferenceParams =

    ReferenceParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position,
      context: ReferenceContext(includeDeclaration: true))

proc parseTextDocumentReferencesResponse*(res: JsonNode): LspReferencesResult =
  if not res.contains("result"):
    return LspReferencesResult.err fmt"Invalid response: {res}"

  let locations =
    try:
      res["result"].to(seq[Location])
    except CatchableError as e:
      let msg = fmt"json to location failed {e.msg}"
      return LspReferencesResult.err fmt"Invalid response: {msg}"

  var references: seq[LspReference] = @[]
  for l in locations:
    let path = l.uri.uriToPath
    if path.isErr:
      return LspReferencesResult.err fmt"Invalid response: {path.error}"

    references.add LspReference(
      path: path.get,
      position: l.range.start.toBufferPosition)

  return LspReferencesResult.ok references
