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

import std/[json, options, strformat]

import pkg/results

import protocol/types
import utils

type
  DocumentFormattingResponseResult* = Result[seq[TextEdit], string]

export TextEdit

proc initDocumentFormattingParams*(path: string): DocumentFormattingParams =
  DocumentFormattingParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri),
    options: none(JsonNode) # FormattingOptions
  )

proc parseDocumentFormattingResponse*(
  res: JsonNode): DocumentFormattingResponseResult =

    if res["result"].kind == JNull:
      # Not found
      return DocumentFormattingResponseResult.ok @[]
    elif res["result"].kind != JArray:
      return DocumentFormattingResponseResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return DocumentFormattingResponseResult.ok @[]

    let edits =
      try:
        res.to(seq[TextEdit])
      except CatchableError as e:
        return DocumentFormattingResponseResult.err fmt"Invalid response: {e.msg}"

    return DocumentFormattingResponseResult.ok edits
