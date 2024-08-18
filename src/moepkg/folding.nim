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

type
  FoldingRange* = object
    first*, last*: int

  FoldingRanges* = seq[FoldingRange]

proc isStartLine*(ranges: FoldingRanges, line: int): bool =
  for r in ranges:
    if line == r.first: return true

proc inRange*(ranges: FoldingRanges, line: int): bool =
  for r in ranges:
    if line >= r.first and line <= r.last: return true

proc find*(ranges: FoldingRanges, line: int): Option[FoldingRange] =
  for r in ranges:
    if line >= r.first and line <= r.last: return some(r)

proc find*(ranges: FoldingRanges, range: FoldingRange): Option[int] =
  for i, r in ranges:
    if r == range: return some(i)

proc remove*(ranges: var FoldingRanges, range: FoldingRange) =
  for i, r in ranges:
    if r == range:
      ranges.delete(i)
      break

proc remove*(ranges: var FoldingRanges, line: int) =
  for i, r in ranges:
    if line >= r.first and line <= r.last:
      ranges.delete(i)
      break

proc removeAll*(ranges: var FoldingRanges, first, last: int) =
  var i = 0
  while i < ranges.len:
    if ranges[i].first >= first and ranges[i].last <= last:
      ranges.delete(i)
    elif ranges[i].last > first:
      break
    else:
      i.inc

proc removeAll*(ranges: var FoldingRanges, range: FoldingRange) {.inline.} =
  ranges.removeAll(range.first, range.last)

proc removeAll*(ranges: var FoldingRanges, line: int) =
  var i = 0
  while i < ranges.len:
    if line >= ranges[i].first  and line <= ranges[i].last:
      ranges.delete(i)
    elif ranges[i].last > line:
      break
    else:
      i.inc

proc clear*(ranges: var FoldingRanges) {.inline.} = ranges = @[]

proc add*(ranges: var FoldingRanges, range: FoldingRange) =
  ## Added ranges are sorted from smallest to largest by `FoldingRange.first`.

  var insertPosi = 0
  if ranges.len > 0 and range.last > ranges[0].first:
    for i in 0 .. ranges.high:
      if range.first == ranges[i].first:
        for j in i .. ranges.high:
          if ranges[i].last > range.last:
            insertPosi = i - 1
            break
        break
      elif range.first < ranges[i].first:
        insertPosi = i
        break
      elif insertPosi == 0 and i == ranges.high:
        insertPosi = ranges.len

  ranges.insert(range, insertPosi)

proc add*(ranges: var FoldingRanges, firstLine, lastLine: int) {.inline.} =
  ranges.add(FoldingRange(first: firstLine, last: lastLine))

proc shiftLines*(ranges: var FoldingRanges, startLine, shiftLen: int) =
  for i in 0 .. ranges.high:
    if ranges[i].first >= startLine:
      ranges[i].first += shiftLen
      ranges[i].last += shiftLen
