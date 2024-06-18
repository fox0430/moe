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

export CallHierarchyItem, CallHierarchyIncomingCall, CallHierarchyOutgoingCall

type
  LspPrepareCallHierarchyResult* = Result[seq[CallHierarchyItem], string]
  LspIncomingCallsResult* = Result[seq[CallHierarchyIncomingCall], string]
  LspOutgoingCallsResult* = Result[seq[CallHierarchyOutgoingCall], string]

proc initCallHierarchyPrepareParams*(
  path: string,
  posi: BufferPosition): CallHierarchyPrepareParams =

    CallHierarchyPrepareParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: posi.toLspPosition)

proc initCallHierarchyIncomingParams*(
  item: CallHierarchyItem): CallHierarchyIncomingCallsParams =

    CallHierarchyIncomingCallsParams(item: item)

proc initCallHierarchyOutgoingParams*(
  item: CallHierarchyItem): CallHierarchyOutgoingCallsParams =

    CallHierarchyOutgoingCallsParams(item: item)

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

proc parseCallhierarchyIncomingCallsResponse*(
  res: JsonNode): LspIncomingCallsResult =

    if res["result"].kind != JArray:
      return LspIncomingCallsResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspIncomingCallsResult.ok @[]

    let items =
      try:
        res["result"].to(seq[CallHierarchyIncomingCall])
      except CatchableError as e:
        return LspIncomingCallsResult.err fmt"Invalid response: {e.msg}"

    return LspIncomingCallsResult.ok items

proc parseCallhierarchyOutgoingCallsResponse*(
  res: JsonNode): LspOutgoingCallsResult =

    return LspOutgoingCallsResult.ok @[]
    if res["result"].kind != JArray:
      return LspOutgoingCallsResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return LspOutgoingCallsResult.ok @[]

    let items =
      try:
        res["result"].to(seq[CallHierarchyOutgoingCall])
      except CatchableError as e:
        return LspOutgoingCallsResult.err fmt"Invalid response: {e.msg}"

    return LspOutgoingCallsResult.ok items
