#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/options
import unicodeext

type
  CompletionLabel* = Runes

  CompletionItem* = object
    label*: CompletionLabel
    insertText*: Runes

  CompletionList* = ref object
    items*: seq[CompletionItem]
      # Items for completion.

proc initCompletionList*(): CompletionList {.inline.} =
  CompletionList()

proc `[]`*(list: CompletionList, label: Runes): CompletionItem =
  for i in 0 .. list.items.high:
    if label == list.items[i].label: return list.items[i]

proc high*(list: CompletionList): int {.inline.} =
  ## Return CompletionList.items.high

  list.items.high

proc len*(list: CompletionList): int {.inline.} =
  ## Return CompletionList.items.len

  list.items.len

proc add*(list: var CompletionList, item: CompletionItem) {.inline.} =
  list.items.add item

proc del*(list: var CompletionList, index: int) {.inline.} =
  list.items.del(index)

proc del*(list: var CompletionList, label: Runes) =
  for i in 0 .. list.items.high:
    if label == list.items[i].label: list.items.del(i)

proc find*(list: CompletionList, label: Runes): Option[CompletionItem] =
  ## Find a item with the label.

  for i in 0 .. list.items.high:
    if label == list.items[i].label: return some(list.items[i])

proc clear*(list: var CompletionList) {.inline.} =
  ## Clear `items`.

  list.items = @[]
