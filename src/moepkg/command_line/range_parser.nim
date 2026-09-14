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
## caller recognises its own name from `rest` onwards. Addresses are left
## unresolved: `.` needs the cursor and `$` needs the buffer.

import std/strutils

import pkg/results

const
  ExAddressChars* = {'.', '$', '+', '-', '0' .. '9'}
    ## Characters of a single address, the `1` or `.` of `1,.`.
  ExRangeChars* = ExAddressChars + {'%', ','} ## Characters of a whole range prefix.

type
  ExAddressBase* = enum
    ## What an address counts from.
    eabCurrent ## `.`, or an address that is only an offset.
    eabLine ## A typed line number.
    eabLast ## `$`.

  ExAddress* = object ## One side of a range, unresolved.
    offset*: int ## Signed, applied once the base resolves.
    case base*: ExAddressBase
    of eabLine:
      line*: int ## 1-based, as typed.
    of eabCurrent, eabLast:
      discard

  ExRangeKind* = enum
    ## Which lines an Ex command was pointed at.
    erkCurrent ## No range was given; the command acts on the current line.
    erkAll ## `%`: every line.
    erkAddresses ## One or two addresses.

  ExLineRange* = object
    case kind*: ExRangeKind
    of erkAddresses:
      first*, last*: ExAddress
    of erkCurrent, erkAll:
      discard

  ExRangePrefix* = object
    ## A parsed range prefix and where the command name starts after it.
    range*: ExLineRange
    rest*: int ## Index of the first character past the prefix.

  ExRangeResult* = Result[ExRangePrefix, string]

func exCurrent*(offset = 0): ExAddress =
  ExAddress(base: eabCurrent, offset: offset)

func exLine*(line: int, offset = 0): ExAddress =
  ExAddress(base: eabLine, line: line, offset: offset)

func exLast*(offset = 0): ExAddress =
  ExAddress(base: eabLast, offset: offset)

func `==`*(a, b: ExAddress): bool =
  # Written out because the compiler cannot derive equality for a case object.
  a.base == b.base and a.offset == b.offset and (a.base != eabLine or a.line == b.line)

func `==`*(a, b: ExLineRange): bool =
  a.kind == b.kind and
    (a.kind != erkAddresses or (a.first == b.first and a.last == b.last))

func exAddresses*(first, last: ExAddress): ExLineRange =
  ExLineRange(kind: erkAddresses, first: first, last: last)

func satAdd*(a, b: int): int =
  ## Add, saturating instead of wrapping. The user can type a number large
  ## enough to overflow before it is refused.
  if b > 0 and a > high(int) - b:
    high(int)
  elif b < 0 and a < low(int) - b:
    low(int)
  else:
    a + b

proc parseAddress(
    cmd: string, i: var int
): Result[tuple[address: ExAddress, found: bool], string] =
  ## Parse an optional base followed by any number of `+N` / `-N` offsets.
  ## An address that is only offsets counts from the current line.
  var
    base = eabCurrent
    line = 0
    offset = 0
    found = false

  if i < cmd.len:
    case cmd[i]
    of '.':
      found = true
      i.inc
    of '$':
      base = eabLast
      found = true
      i.inc
    of '0' .. '9':
      var digits = ""
      while i < cmd.len and cmd[i] in {'0' .. '9'}:
        digits.add cmd[i]
        i.inc
      line =
        try:
          parseInt(digits)
        except ValueError:
          return err("Line number out of range: " & digits)
      base = eabLine
      found = true
    else:
      discard

  while i < cmd.len and cmd[i] in {'+', '-'}:
    let sign = if cmd[i] == '+': 1 else: -1
    i.inc
    var digits = ""
    while i < cmd.len and cmd[i] in {'0' .. '9'}:
      digits.add cmd[i]
      i.inc
    # A bare `+` or `-` moves by one, as in vim.
    let step =
      if digits.len == 0:
        1
      else:
        try:
          parseInt(digits)
        except ValueError:
          return err("Line offset out of range: " & digits)
    offset = satAdd(offset, sign * step)
    found = true

  let address =
    case base
    of eabCurrent:
      exCurrent(offset)
    of eabLine:
      exLine(line, offset)
    of eabLast:
      exLast(offset)
  ok((address: address, found: found))

proc parseExRangePrefix*(cmd: string): ExRangeResult =
  ## Parse the range in front of an Ex command name, which may be absent.
  ##
  ## `cmd` is the command without its leading `:`. No range is a valid answer
  ## at index 0, and so is an out-of-buffer address; only an unparsable number
  ## fails here.
  if cmd.len == 0:
    return ok ExRangePrefix(rest: 0)

  if cmd[0] == '%':
    # `%` stands alone, never combined with a comma.
    return ok ExRangePrefix(range: ExLineRange(kind: erkAll), rest: 1)

  var i = 0
  let first = ?parseAddress(cmd, i)
  var last = first

  let foundComma = i < cmd.len and cmd[i] == ','
  if foundComma:
    i.inc
    last = ?parseAddress(cmd, i)

  if not (first.found or foundComma):
    # Nothing that could be a range, so the name starts at 0.
    return ok ExRangePrefix(rest: 0)

  ok ExRangePrefix(range: exAddresses(first.address, last.address), rest: i)
