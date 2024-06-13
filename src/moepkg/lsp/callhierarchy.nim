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

import protocol/[types, enums]
import utils

type
  LspPrepareCallHierarchyResult* = Result[seq[CallHierarchyItem], string]

proc initCallHierarchyPrepareParams*(
  path: string,
  posi: BufferPosition): CallHierarchyPrepareParams =

    CallHierarchyPrepareParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: posi.toLspPosition)

proc initCallHierarchyIncomingParams*(
  item: CallHierarchyItem): CallHierarchyIncomingCallsParams =

    CallHierarchyIncomingCallsParams(item: some(item))

proc parseTextDocumentPrepareCallHierarchyResponse*(
  res: JsonNode): LspPrepareCallHierarchyResult =

    if res["result"].kind != JArray:
      return LspPrepareCallHierarchyResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspPrepareCallHierarchyResult.ok @[]

    let items =
      try:
        res["result"].to(seq[CallHierarchyItem])
      except CatchableError as e:
        return LspPrepareCallHierarchyResult.err fmt"Invalid response: {e.msg}"

    return LspPrepareCallHierarchyResult.ok items
