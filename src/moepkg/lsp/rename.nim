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

import std/[json, strformat, options]

import pkg/results

import ../independentutils

import protocol/types
import utils

type
  RenameChange* = object
    range*: BufferRange
    text*: string

  LspRename* = object
    path*: string
    changes*: seq[RenameChange]

  LspRenamesResult* = Result[seq[LspRename], string]

proc initRenameParams*(
  path: string,
  position: LspPosition,
  newName: string): RenameParams =

    RenameParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position,
      newName: newName)

proc parseTextDocumentRenameResponse*(res: JsonNode): LspRenamesResult =
  if not res.contains("result"):
    return LspRenamesResult.err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    # Not found
    return LspRenamesResult.ok @[]

  var lspRenames: seq[LspRename]

  try:
    let wEdit = res["result"].to(WorkspaceEdit)
    for uri, changes in wEdit.changes.get.pairs:
      lspRenames.add LspRename()

      let path = uri.uriToPath
      if path.isErr:
        return LspRenamesResult.err fmt"Invalid response: {res}"
      lspRenames[^1].path = path.get

      for v in changes:
        lspRenames[^1].changes.add RenameChange(
          range: v["range"].to(LspRange).toBufferRange,
          text: v["newText"].getStr)

  except CatchableError as e:
    let msg = fmt"Invalid WorkspaceEdit: {e.msg}"
    return LspRenamesResult.err fmt"Invalid response: {msg}"

  return LspRenamesResult.ok lspRenames
