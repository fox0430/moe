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

import protocol/types
import utils

type
  DocumentLinkResult* = Result[seq[DocumentLink], string]

  DocumentLinkResolveResult* = Result[DocumentLink, string]

proc isResolve*(l: DocumentLink): bool {.inline.} = l.target.isNone

proc initDocumentLinkParams*(path: string): DocumentLinkParams =
  DocumentLinkParams(
    textDocument: TextDocumentIdentifier(uri: path.pathToUri))

proc parseDocumentLinkResponse*(res: JsonNode): DocumentLinkResult =
  if res["result"].kind != JNull and res["result"].kind != JArray:
    return DocumentLinkResult.err "Invalid response"
  elif res["result"].kind == JNull:
    # Not found
    return DocumentLinkResult.ok @[]
  elif res["result"].len == 0:
    # Not found
    return DocumentLinkResult.ok @[]

  let links =
    try:
      res["result"].to(seq[DocumentLink])
    except CatchableError as e:
      return DocumentLinkResult.err fmt"Invalid response: {e.msg}"

  return DocumentLinkResult.ok links

proc parseDocumentLinkResolveResponse*(
  res: JsonNode): DocumentLinkResolveResult =

    let link =
      try:
        res["result"].to(DocumentLink)
      except CatchableError as e:
        return DocumentLinkResolveResult.err fmt"Invalid response: {e.msg}"

    return DocumentLinkResolveResult.ok link
