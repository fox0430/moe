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

import std/[strutils, strformat, json, options]

import pkg/results

import ../independentutils
import ../unicodeext

import protocol/types
import utils

type
  HoverContent* = object
    title*: Runes
    description*: seq[Runes]
    range*: BufferRange

  LspHoverResult* = Result[Option[Hover], string]

proc initHoverParams*(
  path: string,
  position: LspPosition): HoverParams {.inline.} =

    HoverParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position)



proc parseTextDocumentHoverResponse*(res: JsonNode): LspHoverResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#hover
  if not res.contains("result"):
    return LspHoverResult.err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    return LspHoverResult.ok none(Hover)
  try:
    return LspHoverResult.ok some(res["result"].to(Hover))
  except CatchableError as e:
    let msg = fmt"json to Hover failed {e.msg}"
    return LspHoverResult.err fmt"Invalid response: {msg}"

proc toHoverContent*(hover: Hover): HoverContent =
  let contents = %*hover.contents
  case contents.kind:
    of JArray:
      if contents.len == 1:
        if contents[0].contains("value"):
          result.description = contents[0]["value"].getStr.splitLines.toSeqRunes
      else:
        if contents[0].contains("value"):
          result.title = contents[0]["value"].getStr.toRunes

        for i in 1 ..< contents.len:
          if contents[i].contains("value"):
            result.description.add contents[i]["value"].getStr.splitLines.toSeqRunes
            if i < contents.len - 1: result.description.add ru""
    else:
      result.description = contents["value"].getStr.splitLines.toSeqRunes

  if hover.range.isSome:
    let range = %*hover.range
    result.range.first = BufferPosition(
      line: range["start"]["line"].getInt,
      column: range["start"]["character"].getInt)
    result.range.last = BufferPosition(
      line: range["end"]["line"].getInt,
      column: range["end"]["character"].getInt)
