#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## A picker's list: the items the query matches, best first, and the selection
## over it. `advancePicker` brings the list up to the query, a slice per frame
## with a time budget, and to the end before a key that reads the list, so a
## key typed ahead of the frame acts on what was typed.

import std/[algorithm, monotimes, options, strutils, times]

import ../types
import nav

const MatchCheckEvery = 64 ## Items matched between looks at the clock.

proc rowCount*(s: PickerSession): int =
  if s.matches.everyItem: s.items.len else: s.matches.ranks.len

proc rowItem*(s: PickerSession, row: int): int =
  if s.matches.everyItem:
    row
  else:
    s.matches.ranks[row].index

proc matchedAll*(s: PickerSession): bool =
  let m = s.matches
  m.everyItem or (m.pendingAt >= m.pending.len and m.upTo >= s.items.len)

proc merge(ranks: var seq[FuzzyRank], batch: var seq[FuzzyRank]) =
  ## Add `batch` to `ranks`, both kept in the order they show.
  if batch.len == 0:
    return
  batch.sort(cmpFuzzyRank)
  if ranks.len == 0:
    swap(ranks, batch)
    return
  var merged = newSeqOfCap[FuzzyRank](ranks.len + batch.len)
  var
    i = 0
    j = 0
  while i < ranks.len and j < batch.len:
    if cmpFuzzyRank(batch[j], ranks[i]) < 0:
      merged.add batch[j]
      inc j
    else:
      merged.add ranks[i]
      inc i
  merged.add ranks.toOpenArray(i, ranks.high)
  merged.add batch.toOpenArray(j, batch.high)
  ranks = move merged
  batch.setLen 0

proc restartMatches(s: PickerSession, query: string) =
  ## Match `query` from the start, or only over what the last query matched
  ## when this one adds to it: a longer or an added word matches fewer items.
  template m(): untyped =
    s.matches

  let pattern = initFuzzyPattern(query)
  let narrows =
    m.valid and not m.everyItem and s.matchedAll and m.query.len > 0 and
    query.startsWith(m.query)
  var pending: seq[int]
  var upTo = 0
  if narrows:
    for rank in m.ranks:
      pending.add rank.index
    pending.sort()
    upTo = m.upTo
  m.valid = true
  m.query = query
  m.everyItem = pattern.isEmpty
  m.pattern = pattern
  m.ranks.setLen 0
  m.pending = pending
  m.pendingAt = 0
  m.upTo = upTo

proc matchItems(s: PickerSession, deadline: Option[MonoTime]) =
  if s.matchedAll:
    return
  template m(): untyped =
    s.matches

  var
    batch: seq[FuzzyRank]
    count = 0
  template outOfTime(): bool =
    deadline.isSome and count mod MatchCheckEvery == 0 and count > 0 and
      getMonoTime() >= deadline.get

  template matchItem(i: int) =
    let rank = m.scratch.fuzzyRank(m.pattern, s.items[i].key, i)
    if rank.isSome:
      batch.add rank.get
    inc count

  block matching:
    while m.pendingAt < m.pending.len:
      if outOfTime():
        break matching
      matchItem(m.pending[m.pendingAt])
      inc m.pendingAt
    while m.upTo < s.items.len:
      if outOfTime():
        break matching
      matchItem(m.upTo)
      inc m.upTo
  m.ranks.merge(batch)

proc selectedRow*(s: PickerSession): int =
  ## The row of the selection, the first while it follows the best; -1 with no
  ## rows.
  let count = s.rowCount
  if count == 0:
    return -1
  if s.selected.isNone:
    return 0
  let item = s.selected.get
  if s.matches.everyItem:
    return (if item < count: item else: 0)
  for row, rank in s.matches.ranks:
    if rank.index == item:
      return row
  0

proc advancePicker*(s: PickerSession, query: string, budget = none(Duration)) =
  ## Bring the list up to `query`: a new query puts the selection back on the
  ## best, then the items are matched, for `budget` at most.
  if not s.matches.valid or s.matches.query != query:
    s.selected = none(int)
    s.restartMatches(query)
  let deadline =
    if budget.isSome:
      some(getMonoTime() + budget.get)
    else:
      none(MonoTime)
  s.matchItems(deadline)
  # A query that moved the selection off the scrolled item drops its scroll,
  # as `moveSelection` does.
  let scrolled = s.preview.scrollItem
  if scrolled.isSome:
    let row = s.selectedRow
    if row < 0 or s.rowItem(row) != scrolled.get:
      s.preview.scrollItem = none(int)

proc selectedItem*(s: PickerSession): Option[PickerItem] =
  let row = s.selectedRow
  if row < 0:
    none(PickerItem)
  else:
    some(s.items[s.rowItem(row)])

proc moveSelection*(s: PickerSession, rows: int) =
  ## Move the selection `rows` down, up when negative. The item it lands on
  ## shows its preview from the start, also one scrolled before, as
  ## telescope's does.
  let row = s.selectedRow
  if row < 0:
    return
  let item = s.rowItem(clamp(row + rows, 0, s.rowCount - 1))
  if item != s.rowItem(row):
    s.preview.scrollItem = none(int)
  s.selected = some(item)

proc keepSelectionVisible*(s: PickerSession, height: int) =
  ## Scroll the list so the selection shows in `height` rows, which the list
  ## fills down to its last row when it can.
  pickerEnsureVisible(max(0, s.selectedRow), s.topIndex, height)
  if height > 0:
    s.topIndex = min(s.topIndex, max(0, s.rowCount - height))
