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

import ../independentutils

export InlineValueContext, InlineValueParams

type
  LspInlineValues* = object
    range*: independentutils.Range
      # Line range to request
    values*: seq[InlineValueText]

  LspInlineValueTextResult* = Result[seq[InlineValueText], string]

  LspInlineValueVariableLookupResult* = Result[
    seq[InlineValueVariableLookup],
    string]

  LspInlineValueEvaluatableExpressionResult* = Result[
    seq[InlineValueEvaluatableExpression],
    string]

proc initInlineValueParams*(
  path: string,
  range: LspRange,
  context: InlineValueContext): InlineValueParams =

    return InlineValueParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      range: range,
      context: context)

proc parseInlineValueTextResponse*(res: JsonNode): LspInlineValueTextResult =
  if res["result"].kind != JArray:
    return LspInlineValueTextResult.err "Invalid response"
  elif res["result"].len == 0:
    # Not found
    return LspInlineValueTextResult.ok @[]

  let texts =
    try:
      res["result"].to(seq[InlineValueText])
    except CatchableError as e:
      return LspInlineValueTextResult.err fmt"Invalid response: {e.msg}"

  return LspInlineValueTextResult.ok texts

proc parseInlineValueVariableLookupResponse*(
  res: JsonNode): LspInlineValueVariableLookupResult =

    if res["result"].kind != JArray:
      return LspInlineValueVariableLookupResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspInlineValueVariableLookupResult.ok @[]

    let lookups =
      try:
        res["result"].to(seq[InlineValueVariableLookup])
      except CatchableError as e:
        return LspInlineValueVariableLookupResult.err fmt"Invalid response: {e.msg}"

    return LspInlineValueVariableLookupResult.ok lookups

proc parseInlineValueEvaluatableExpressionResponse*(
  res: JsonNode): LspInlineValueEvaluatableExpressionResult =

    if res["result"].kind != JArray:
      return LspInlineValueEvaluatableExpressionResult .err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspInlineValueEvaluatableExpressionResult.ok @[]

    let expressions =
      try:
        res["result"].to(seq[InlineValueEvaluatableExpression])
      except CatchableError as e:
        return LspInlineValueEvaluatableExpressionResult.err fmt"Invalid response: {e.msg}"

    return LspInlineValueEvaluatableExpressionResult.ok expressions

