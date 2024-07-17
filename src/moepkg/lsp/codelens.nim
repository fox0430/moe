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

import protocol/types
import utils

export CodeLens

type
  CodeLensResult* = Result[seq[CodeLens], string]

  CodeLensResolveResult* = Result[CodeLens, string]

proc initCodeLensParams*(path: string): CodeLensParams =
  CodeLensParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc parseCodeLensResponse*(res: JsonNode): CodeLensResult =
  if not res.contains("result"):
    return CodeLensResult.err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    # Not found
    return CodeLensResult.ok @[]

  if res["result"].kind != JArray:
    return CodeLensResult.err fmt"Invalid response: {res}"

  if res["result"].len == 0:
    # Not found
    return CodeLensResult.ok @[]

  let codeLenses =
    try:
      res["result"].to(seq[CodeLens])
    except CatchableError as e:
      return CodeLensResult.err fmt"Invalid response: {e.msg}"

  return CodeLensResult.ok codeLenses

proc parseCodeLensResolveResponse*(res: JsonNode): CodeLensResolveResult =
  if not res.contains("result"):
    return CodeLensResolveResult.err fmt"Invalid response: {res}"

  let codeLens =
    try:
      res["result"].to(CodeLens)
    except CatchableError as e:
      return CodeLensResolveResult.err fmt"Invalid response: {e.msg}"

  return CodeLensResolveResult.ok codeLens
