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
  Diagnostics* = object
    path*: string
      # File path
    diagnostics*: seq[Diagnostic]
      # Diagnostics results

  LspDiagnosticsResult* = Result[Option[Diagnostics], string]

proc parseTextDocumentPublishDiagnosticsNotify*(
  n: JsonNode): LspDiagnosticsResult =
    ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#publishDiagnosticsParams

    if not n.contains("params") or n["params"].kind != JObject:
      return LspDiagnosticsResult.err "Invalid notify"

    var params: PublishDiagnosticsParams
    try:
      params = n["params"].to(PublishDiagnosticsParams)
    except CatchableError as e:
      return LspDiagnosticsResult.err fmt"Invalid notify: {e.msg}"

    if params.diagnostics.isNone:
      return LspDiagnosticsResult.ok none(Diagnostics)

    let path = params.uri.uriToPath
    if path.isErr:
      return LspDiagnosticsResult.err fmt"Invalid uri: {path.error}"

    return LspDiagnosticsResult.ok some(Diagnostics(
      path: path.get,
      diagnostics: params.diagnostics.get))
