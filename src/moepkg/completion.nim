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

import std/[options, os, strutils, sequtils, algorithm]

import pkg/unicodedb/properties

import unicodeext, fileutils, algo

type
  CompletionLabel* = Runes

  CompletionItem* = object
    label*: CompletionLabel
    insertText*: Runes

  CompletionList* = ref object
    items*: seq[CompletionItem]
      # Items for completion.

proc initCompletionItem*(label: Runes): CompletionItem {.inline.} =
  CompletionItem(label: label, insertText: label)

proc initCompletionItem*(label, insertText: Runes): CompletionItem {.inline.} =
  CompletionItem(label: label, insertText: insertText)

proc initCompletionList*(): CompletionList {.inline.} =
  CompletionList()

proc `[]`*(list: CompletionList, index: int): CompletionItem {.inline.} =
  ## Return the CompletionList.items[index].

  list.items[index]

proc `[]`*(list: CompletionList, label: Runes): CompletionItem =
  ## Return a item: label == CompletionList.items.label.

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
  list.items.del index

proc del*(list: var CompletionList, label: Runes) =
  for i in 0 .. list.items.high:
    if label == list.items[i].label: list.items.del(i)

proc find*(list: CompletionList, label: Runes): Option[CompletionItem] =
  ## Find a item with the label.

  for i in 0 .. list.items.high:
    if label == list.items[i].label: return some(list.items[i])

proc clear*(list: var CompletionList) {.inline.} =
  ## Clear `CompletionList.items`.

  list.items = @[]

proc maxLabelLen*(list: CompletionList): int =
  ## Return a max length of `list.label`.

  for item in list.items:
    if item.label.len > result: result = item.label.len

proc maxInsertTextLen*(list: CompletionList): int =
  ## Return a max length of `list.insertText`.

  for item in list.items:
    if item.insertText.len > result: result = item.insertText.len

proc isCompletionCharacter*(r: Rune): bool {.inline.} =
  # '/', '.' and '~' are path completion.
  r in [ru'/', ru'.', ru'~'] or
  r.unicodeCategory in LetterCharacter

proc isPathCompletion*(r: Rune | Runes): bool {.inline.} =
  r.toRunes.startsWith(ru"/") or
  r.toRunes.startsWith(ru"./") or
  r.toRunes.startsWith(ru"~/")

proc pathCompletionList*(path: Runes): CompletionList =
  result = initCompletionList()

  if path.len == 0: return

  let
    (inputPathHead, inputPathTail) = splitPath(path)
    pattern =
      if inputPathHead.len == 0: getCurrentDir()
      elif inputPathHead.startsWith(ru'~'): expandTilde($inputPathHead)
      else: $inputPathHead

  for k in walkDir(pattern):
    let p = k.path.splitPath.tail.toRunes
    if inputPathTail.len == 0 or p.startsWith(inputPathTail):
      if k.kind == pcDir: result.items.add initCompletionItem(p & ru"/")
      else: result.items.add initCompletionItem(p)

proc fuzzySort*(list: var CompletionList, runes: Runes) =
  var scores: seq[tuple[index, score: int]]
  for i, item in list.items:
    scores.add (index: i, score: runes.fuzzyScore(item.insertText))

  list.items = scores.sortedByIt(it.score).reversed.mapIt(list.items[it.index])
