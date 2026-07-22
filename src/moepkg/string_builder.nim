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

## StringBuilder - Efficient string building for repeat command optimization
##
## This module provides a StringBuilder type that optimizes string concatenation
## from O(n²) to O(n) by collecting parts and joining once at the end.
##
## Used primarily in extractInsertedText() to efficiently track Insert mode changes.

import std/strutils

type StringBuilder* = object
  ## Efficient string building using seq[string]
  ## Avoids O(n²) string concatenation by collecting parts and joining once
  parts: seq[string]
  totalLen: int

proc newStringBuilder*(): StringBuilder =
  ## Create a new StringBuilder with empty state
  result.parts = @[]
  result.totalLen = 0

proc add*(sb: var StringBuilder, s: string) =
  ## Add a string to the builder
  ## O(1) operation - just appends to seq
  if s.len > 0:
    sb.parts.add(s)
    sb.totalLen += s.len

proc removeLast*(sb: var StringBuilder, count: int) =
  ## Remove last 'count' bytes from the builder, snapping the cut point back
  ## to a UTF-8 rune boundary so the tail is never left mid-sequence.
  if count <= 0:
    return

  var remaining = count

  while remaining > 0 and sb.parts.len > 0:
    let lastIdx = sb.parts.len - 1
    let lastLen = sb.parts[lastIdx].len

    if lastLen <= remaining:
      sb.totalLen -= lastLen
      sb.parts.delete(lastIdx)
      remaining -= lastLen
    else:
      var newLen = lastLen - remaining
      while newLen > 0 and (sb.parts[lastIdx][newLen].uint8 and 0xC0'u8) == 0x80'u8:
        dec newLen
      if newLen == 0:
        sb.totalLen -= lastLen
        sb.parts.delete(lastIdx)
      else:
        sb.totalLen -= (lastLen - newLen)
        sb.parts[lastIdx] = sb.parts[lastIdx][0 ..< newLen]
      remaining = 0

proc clear*(sb: var StringBuilder) =
  ## Clear all content from the builder
  ## O(1) operation
  sb.parts = @[]
  sb.totalLen = 0

proc toString*(sb: StringBuilder): string =
  ## Convert builder to final string
  ## O(n) operation - joins all parts once
  return sb.parts.join("")

proc len*(sb: StringBuilder): int =
  ## Get total length of accumulated text
  ## O(1) operation
  return sb.totalLen
