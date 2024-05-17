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

import protocol/types
import utils

type
  SemanticTokenNumber* = int8
  SemanticTokenModifierNumber* = int8

  LspSemanticToken* = object
    line*: int
    column*: int
    length*: int
    tokenType*: SemanticTokenNumber
    tokenModifiers*: seq[SemanticTokenModifierNumber]

  LspSemanticTokens* = object
    id*: int
    tokens*: seq[LspSemanticToken]

  LspSemanticTokensResult* = Result[seq[LspSemanticToken], string]

proc initSemanticTokensParams*(path: string): SemanticTokensParams =
  SemanticTokensParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc parseTextDocumentSemanticTokensResponse*(
  res: JsonNode,
  legend: SemanticTokensLegend): LspSemanticTokensResult =
    ## SemanticTokens full

    if res["result"].kind == JNull:
      return LspSemanticTokensResult.err "Invalid response"

    var semanticTokens: SemanticTokens
    try:
      semanticTokens = res["result"].to(SemanticTokens)
    except CatchableError as e:
      return LspSemanticTokensResult.err fmt"Invalid response: {e.msg}"

    var lspSemanticTokens: seq[LspSemanticToken]

    var
      line = 0
      col = 0
    for i in 0 ..< int(semanticTokens.data.len / 5):
      let startIndex = i * 5
      var newToken = LspSemanticToken()
      try:
        newToken.line = line + semanticTokens.data[startIndex + 0]
        if newToken.line > line:
          col = 0
          line = newToken.line

        newToken.column = col + semanticTokens.data[startIndex + 1]
        col = newToken.column

        newToken.length = semanticTokens.data[startIndex + 2]
        newToken.tokenType = semanticTokens.data[startIndex + 3].SemanticTokenNumber
        for i in 0 ..< legend.tokenModifiers.len:
          if (semanticTokens.data[startIndex + 4] and (1 shl i)) > 0:
            newToken.tokenModifiers.add i.SemanticTokenModifierNumber
      except CatchableError as e:
        return LspSemanticTokensResult.err fmt"Invalid SemanticTokens: {e.msg}"
      except RangeDefect as e:
        return LspSemanticTokensResult.err fmt"Invalid SemanticTokens: {e.msg}"

      lspSemanticTokens.add newToken

    return LspSemanticTokensResult.ok lspSemanticTokens
