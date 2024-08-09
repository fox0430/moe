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

import std/[options]

import independentutils

type
  FoldingRange* = Range
    # First line .. Last line

  FoldingRanges* = seq[FoldingRange]

proc isFoldingStartLine*(ranges: FoldingRanges, line: int): bool =
  for r in ranges:
    if line == r.first: return true

proc inFoldingRange*(ranges: FoldingRanges, line: int): bool =
  for r in ranges:
    if line >= r.first and line <= r.last: return true

proc findFoldingRange*(ranges: FoldingRanges, line: int): Option[FoldingRange] =
  for r in ranges:
    if line >= r.first and line <= r.last: return some(r)

proc findFoldingRange*(
  ranges: FoldingRanges,
  range: FoldingRange): Option[int] =

    for i, r in ranges:
      if r == range: return some(i)

proc removeFoldingRange*(ranges: var FoldingRanges, range: FoldingRange) =
  for i, r in ranges:
    if r == range:
      ranges.del(i)
      break

proc removeFoldingRange*(ranges: var FoldingRanges, line: int) =
  for i, r in ranges:
    if line >= r.first and line <= r.last:
      ranges.del(i)
      break

proc addFoldingRange*(ranges: var FoldingRanges, range: FoldingRange) =
  let index = ranges.findFoldingRange(range)
  if index.isNone:
    var insertPosi = 0
    for i in 0 .. ranges.high - 1:
      if ranges[i].last > range.first and range.first < ranges[i + 1].first:
        insertPosi = i
    ranges.insert(range, insertPosi)
  else:
    let first = min(ranges[index.get].first, range.first)
    var
      last = max(ranges[index.get].last, range.last)
      removeRanges = 0
    for i in index.get .. ranges.high:
      if last < ranges[i].first:
        break
      elif last < ranges[i].last:
        last = ranges[i].last
        removeRanges.inc
        break
      else:
        removeRanges.inc

    for _ in 0 .. removeRanges: ranges.del(index.get)

    ranges[index.get] = FoldingRange(first: first, last: last)

proc addFoldingRange*(
  ranges: var FoldingRanges,
  firstLine, lastLine: int) {.inline.} =

    ranges.addFoldingRange(FoldingRange(first: firstLine, last: lastLine))
