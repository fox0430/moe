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

import ../folding

import protocol/types
import utils

type
  LspFoldingRange* = types.FoldingRange

  LspFoldingRangeResult* = Result[FoldingRanges, string]

proc initFoldingRangeParam*(path: string): FoldingRangeParams =
  FoldingRangeParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc parseTextDocumentFoldingRangeResponse*(
  res: JsonNode): LspFoldingRangeResult =

    if res["result"].kind == JNull:
      # Not found
      return LspFoldingRangeResult.ok @[]
    elif res["result"].kind != JArray:
      return LspFoldingRangeResult.err "Invalid response"

    let lspRanges =
      try:
        res["result"].to(seq[LspFoldingRange])
      except CatchableError as e:
        return LspFoldingRangeResult.err fmt"Invalid response: {e.msg}"

    var ranges: FoldingRanges
    for r in lspRanges:
      ranges.add(r.startLine.int, r.endLine.int)

    return LspFoldingRangeResult.ok ranges
