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

import std/[strformat, json, sequtils]

import pkg/results

import ../independentutils

import protocol/types
import utils

export SelectionRange, Range

type
  LspSelectionRangeResult* = Result[seq[SelectionRange], string]

proc initSelectionRangeParams*(
  path: string,
  positions: seq[BufferPosition]): SelectionRangeParams =

    SelectionRangeParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      positions: positions.mapIt(it.toLspPosition))

proc parseTextDocumentSelectionRangeResponse*(
  res: JsonNode): LspSelectionRangeResult =

    if res["result"].kind == JNull:
      # Not found
      return LspSelectionRangeResult.ok @[]
    elif res["result"].kind != JArray:
      return LspSelectionRangeResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspSelectionRangeResult.ok @[]

    let selectionRanges =
      try:
        res["result"].to(seq[SelectionRange])
      except CatchableError as e:
        return LspSelectionRangeResult.err fmt"Invalid response: {e.msg}"

    return LspSelectionRangeResult.ok selectionRanges
