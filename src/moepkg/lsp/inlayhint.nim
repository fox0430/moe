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
  LspInlayHints* = object
    range*: independentutils.Range
      # Line range to request
    hints*: seq[InlayHint]

  LspInlayHintsResult* = Result[seq[InlayHint], string]

proc initInlayHintParams*(path: string, range: BufferRange): InlayHintParams =
  InlayHintParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri),
    range: range.toLspRange)

proc parseTextDocumentInlayHintResponse*(res: JsonNode): LspInlayHintsResult =
  if res["result"].kind == JNull:
    # Not found
    return LspInlayHintsResult.ok @[]

  var hints: seq[InlayHint]
  try:
    for h in res["result"].items:
      hints.add h.to(InlayHint)
  except CatchableError as e:
    return LspInlayHintsResult.err fmt"Invalid response: {e.msg}"

  return LspInlayHintsResult.ok hints
