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

## The line range an Ex command can be given in front of its name.
##
## Parsing stops at the first character that cannot be part of a range, so the
## caller recognises its own name from `rest` onwards.

import std/strutils

const
  ExAddressChars* = {'.', '0' .. '9'}
    ## Characters of a single address, the `1` or `.` of `1,.`.
  ExRangeChars* = ExAddressChars + {'%', ','} ## Characters of a whole range prefix.

type
  ExLineRange* = object ## Which lines an Ex command was pointed at.
    isGlobal*: bool ## `%`: every line; the line fields are unset.
    hasRange*: bool ## An explicit range was given.
    startLine*: int ## 1-based; 0 means the current line.
    endLine*: int

  ExRangePrefix* = object
    ## A parsed range prefix and where the command name starts after it.
    isValid*: bool ## False for a malformed address (`1.5`, `..`, a bare `0`).
    range*: ExLineRange
    rest*: int ## Index of the first character past the prefix.

proc parseExRangePrefix*(cmd: string): ExRangePrefix =
  ## Parse the range in front of an Ex command name, which may be absent.
  ##
  ## `cmd` is the command without its leading `:`. No range is a valid answer
  ## at index 0, not a failure.
  result = ExRangePrefix(isValid: true, rest: 0)
  if cmd.len == 0:
    return

  if cmd[0] == '%':
    # `%` stands alone, never combined with a comma.
    result.range.isGlobal = true
    result.rest = 1
    return

  var
    i = 0
    startStr, endStr = ""
    foundComma = false
  while i < cmd.len and cmd[i] in ExAddressChars:
    startStr.add cmd[i]
    i.inc
  if i < cmd.len and cmd[i] == ',':
    foundComma = true
    i.inc
    while i < cmd.len and cmd[i] in ExAddressChars:
      endStr.add cmd[i]
      i.inc
  result.rest = i

  if not foundComma:
    if startStr.len == 0:
      # No range, so the name starts at 0.
      return
    if startStr == ".":
      result.range = ExLineRange(hasRange: true, startLine: 0, endLine: 0)
      return
    let n =
      try:
        parseInt(startStr)
      except ValueError:
        0
    if n < 1:
      result.isValid = false
      return
    result.range = ExLineRange(hasRange: true, startLine: n, endLine: n)
    return

  # Either side of the comma may be empty or `.`, both meaning the current line.
  proc address(s: string, line: var int): bool =
    if s.len == 0 or s == ".":
      line = 0
      return true
    try:
      line = parseInt(s)
      true
    except ValueError:
      false

  var r = ExLineRange(hasRange: true)
  if not address(startStr, r.startLine) or not address(endStr, r.endLine):
    result.isValid = false
    return
  result.range = r
