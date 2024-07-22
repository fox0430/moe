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

import protocol/[enums, types]
import utils

type
  LspCompletionItem* = types.CompletionItem
  LspCompletionList* = types.CompletionList
  LspCompletionOptions* = types.CompletionOptions

  LspCompletionTriggerKind* = enums.CompletionTriggerKind

  LspCompletionResut* = Result[seq[CompletionItem], string]

proc isTriggerCharacter*(
  options: LspCompletionOptions,
  ch: string): bool {.inline.} =

    options.triggerCharacters.isSome and
    options.triggerCharacters.get.contains(ch)

proc initCompletionParams*(
  path: string,
  position: BufferPosition,
  options: LspCompletionOptions,
  isIncompleteTrigger: bool,
  character: string): CompletionParams =

    let
      triggerChar =
        if isTriggerCharacter(options, character): some(character)
        else: none(string)

      triggerKind =
        if triggerChar.isSome:
          CompletionTriggerKind.TriggerCharacter.int
        elif isIncompleteTrigger:
          CompletionTriggerKind.TriggerForIncompleteCompletions.int
        else:
          CompletionTriggerKind.Invoked.int

    return CompletionParams(
      textDocument: TextDocumentIdentifier(uri: path.pathToUri),
      position: position.toLspPosition,
      context: some(CompletionContext(
        triggerKind: triggerKind,
        triggerCharacter: triggerChar)))

proc parseTextDocumentCompletionResponse*(res: JsonNode): LspCompletionResut =
  if not res.contains("result"):
    return Result[seq[CompletionItem], string].err fmt"Invalid response: {res}"

  if res["result"].kind == JNull:
    # Not found
    return Result[seq[CompletionItem], string].ok @[]

  if res["result"].kind == JObject:
    var list: CompletionList

    try:
      list = res["result"].to(CompletionList)
    except CatchableError as e:
      return Result[seq[CompletionItem], string].err fmt"Invalid response: {e.msg}"

    if list.items.isSome:
      return Result[seq[CompletionItem], string].ok list.items.get
    else:
      # Not found
      return Result[seq[CompletionItem], string].ok @[]
  else:
    var items: seq[CompletionItem]
    try:
      items = res["result"].to(seq[CompletionItem])
    except CatchableError as e:
      return Result[seq[CompletionItem], string].err fmt"Invalid response: {e.msg}"

    if items.len > 0:
      return Result[seq[CompletionItem], string].ok items
    else:
      # Not found
      return Result[seq[CompletionItem], string].ok @[]
