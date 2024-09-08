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

import protocol/[enums, types]
import utils

export SymbolKind, DocumentSymbol, SymbolInformation

type
  DocumentSymbolsResult* = Result[seq[DocumentSymbol], string]
  SymbolInformationsResult* = Result[seq[SymbolInformation], string]

proc initDocumentSymbolParams*(path: string): DocumentSymbolParams =
  DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc parseTextDocumentDocumentSymbolsResponse*(
  res: JsonNode): DocumentSymbolsResult =

    if res["result"].kind != JArray:
      return DocumentSymbolsResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return DocumentSymbolsResult.ok @[]

    var symbols: seq[DocumentSymbol]
    for r in res["result"]:
      let s =
        try:
          r.to(DocumentSymbol)
        except CatchableError as e:
          return DocumentSymbolsResult.err fmt"Invalid response: {e.msg}"

      if s.kind < 1 or s.kind > 26:
        return DocumentSymbolsResult.err fmt"Invalid response: kind: {r.kind}"

      symbols.add s

    return DocumentSymbolsResult.ok symbols

proc parseTextDocumentSymbolInformationsResponse*(
  res: JsonNode): SymbolInformationsResult =

    if res["result"].kind != JArray:
      return SymbolInformationsResult.err "Invalid response"
    elif res["result"].len == 0:
      # Not found
      return SymbolInformationsResult.ok @[]

    var infos: seq[SymbolInformation]
    for r in res["result"]:
      let i =
        try:
          r.to(SymbolInformation)
        except CatchableError as e:
          return SymbolInformationsResult.err fmt"Invalid response: {e.msg}"

      if i.kind < 1 or i.kind > 26:
        return SymbolInformationsResult.err fmt"Invalid response: kind: {r.kind}"

      infos.add i

    return SymbolInformationsResult.ok infos
