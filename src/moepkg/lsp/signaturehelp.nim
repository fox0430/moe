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

import std/[json, options, strformat]

import pkg/results

import protocol/[types, enums]
import utils

export SignatureHelp, SignatureHelpTriggerKind, SignatureInformation

type
  SignatureHelpResult* = Result[SignatureHelp, string]

proc isTriggerCharacter*(o: SignatureHelpOptions, str: string): bool {.inline.} =
  str in o.triggerCharacters.get

proc initSignatureHelpParams*(
  path: string,
  position: LspPosition,
  kind: SignatureHelpTriggerKind,
  triggerChar: Option[string] = none(string),
  active: Option[SignatureHelp] = none(SignatureHelp)): SignatureHelpParams =

    SignatureHelpParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position,
      context: SignatureHelpContext(
        triggerKind: ord(kind),
        triggerCharacter: triggerChar,
        isRetrigger: active.isSome,
        activeSignatureHelp: active))

proc parseSignatureHelpResponse*(res: JsonNode): SignatureHelpResult =
  if not res.contains("result"):
    return SignatureHelpResult.err fmt"Invalid response: {res}"
  elif res["result"].kind == JNull:
    return SignatureHelpResult.err fmt"Not found"

  let sig =
    try:
      res["result"].to(SignatureHelp)
    except CatchableError as e:
      return SignatureHelpResult.err fmt"Invalid response: {e.msg}"

  return SignatureHelpResult.ok sig
