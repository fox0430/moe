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
  LspDocumentHighlightResult* = Result[seq[BufferRange], string]

proc initDocumentHighlightParamas*(
  path: string,
  posi: BufferPosition): DocumentHighlightParams =

    DocumentHighlightParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: posi.toLspPosition)

proc parseDocumentHighlightResponse*(
  res: JsonNode): LspDocumentHighlightResult =

    if res["result"].kind != JArray:
      return LspDocumentHighlightResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspDocumentHighlightResult .ok @[]

    let items =
      try:
        res["result"].to(seq[DocumentHighlight])
      except CatchableError as e:
        return LspDocumentHighlightResult.err fmt"Invalid response: {e.msg}"

    var ranges: seq[BufferRange]
    for it in items:
      ranges.add(BufferRange(
        first: BufferPosition(
          line: it.range.start.line,
          column: it.range.start.character),
        last: BufferPosition(
          line: it.range.`end`.line,
          column: it.range.`end`.character - 1)
      ))

    return LspDocumentHighlightResult.ok ranges
