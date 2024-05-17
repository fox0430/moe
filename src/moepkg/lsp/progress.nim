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

type
  ProgressToken* = string
    # ProgressParams.token
    # Can be also int but the editor only use string.

  ProgressState* = enum
    create
    begin
    report
    `end`

  ProgressReport* = ref object
    state*: ProgressState
    title*: string
    message*: string
    percentage*: Option[Natural]

  LspWindowWorkDnoneProgressCreateResult* = Result[ProgressToken, string]
  LspWorkDoneProgressBeginResult* = Result[WorkDoneProgressBegin, string]
  LspWorkDoneProgressReportResult* = Result[WorkDoneProgressReport, string]
  LspWorkDoneProgressEndResult* = Result[WorkDoneProgressEnd, string]

proc parseWindowWorkDnoneProgressCreateNotify*(
  n: JsonNode): LspWindowWorkDnoneProgressCreateResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_workDoneProgress_create

    if not n.contains("params") or n["params"].kind != JObject:
      return LspWindowWorkDnoneProgressCreateResult.err "Invalid notify"

    var params: WorkDoneProgressCreateParams
    try:
      params = n["params"].to(WorkDoneProgressCreateParams)
    except CatchableError as e:
      return LspWindowWorkDnoneProgressCreateResult.err fmt"Invalid notify: {e.msg}"

    if params.token.isNone:
      return LspWindowWorkDnoneProgressCreateResult.err fmt"Invalid notify: token is empty"

    return LspWindowWorkDnoneProgressCreateResult.ok params.token.get.getStr

template isProgressNotify(j: JsonNode): bool =
  ## `$/ptgoress` notification

  j.contains("params") and
  j["params"].kind == JObject and
  j["params"].contains("token") and
  j["params"].contains("value") and
  j["params"]["value"].contains("kind") and
  j["params"]["value"]["kind"].kind == JString

template isWorkDoneProgressBegin*(j: JsonNode): bool =
  isProgressNotify(j) and
  "begin" == j["params"]["value"]["kind"].getStr

template isWorkDoneProgressReport*(j: JsonNode): bool =
  isProgressNotify(j) and
  "report" == j["params"]["value"]["kind"].getStr

template isWorkDoneProgressEnd*(j: JsonNode): bool =
  isProgressNotify(j) and
  "end" == j["params"]["value"]["kind"].getStr

template workDoneProgressToken*(j: JsonNode): string =
  j["params"]["token"].getStr

proc parseWorkDoneProgressBegin*(
  n: JsonNode): LspWorkDoneProgressBeginResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressBegin(n):
      return LspWorkDoneProgressBeginResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressBeginResult.ok n["params"]["value"].to(
        WorkDoneProgressBegin)
    except CatchableError as e:
      return LspWorkDoneProgressBeginResult.err fmt"Invalid notify: {e.msg}"

proc parseWorkDoneProgressReport*(
  n: JsonNode): LspWorkDoneProgressReportResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressReport(n):
      return LspWorkDoneProgressReportResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressReportResult.ok n["params"]["value"].to(
        WorkDoneProgressReport)
    except CatchableError as e:
      return LspWorkDoneProgressReportResult.err fmt"Invalid notify: {e.msg}"

proc parseWorkDoneProgressEnd*(
  n: JsonNode): LspWorkDoneProgressEndResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#progress

    if not isWorkDoneProgressEnd(n):
      return LspWorkDoneProgressEndResult.err "Invalid notify"

    try:
      return LspWorkDoneProgressEndResult.ok n["params"]["value"].to(
        WorkDoneProgressEnd)
    except CatchableError as e:
      return LspWorkDoneProgressEndResult.err fmt"Invalid notify: {e.msg}"

template isCancellable*(
  p: WorkDoneProgressBegin | WorkDoneProgressReport): bool =

    some(true) == p.cancellable
