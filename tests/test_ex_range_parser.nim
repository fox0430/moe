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

import std/unittest

import pkg/results

import ../src/moepkg/command_line/range_parser

proc parsed(cmd: string): ExRangeResult =
  parseExRangePrefix(cmd)

suite "ExRangePrefix - no range":
  test "An empty command has no range and starts at 0":
    let r = parsed("")
    check r.isOk
    check r.get.range.kind != erkAddresses
    check r.get.range.kind != erkAll
    check r.get.rest == 0

  test "A name with nothing in front of it is not a failure":
    for cmd in ["d", "s/a/b/", "sort"]:
      let r = parsed(cmd)
      check r.isOk
      check r.get.range.kind != erkAddresses
      check r.get.rest == 0

suite "ExRangePrefix - whole buffer":
  test "% is every line and consumes exactly itself":
    for cmd in ["%", "%d", "%s/a/b/", "%!sort"]:
      let r = parsed(cmd)
      check r.isOk
      check r.get.range.kind == erkAll
      check r.get.range.kind != erkAddresses
      check r.get.rest == 1

  test "% does not combine with a comma":
    # Parsing stops at `%`, so the caller sees `,5d` as the name and rejects it.
    let r = parsed("%,5d")
    check r.isOk
    check r.get.range.kind == erkAll
    check r.get.rest == 1

suite "ExRangePrefix - a single address":
  test "A line number covers that line alone":
    let r = parsed("5d")
    check r.isOk
    check r.get.range.kind == erkAddresses
    check r.get.range.first == exLine(5)
    check r.get.range.last == exLine(5)
    check r.get.rest == 1

  test "A dot is the current line, which the parser cannot name":
    let r = parsed(".d")
    check r.isOk
    check r.get.range.kind == erkAddresses
    check r.get.range.first == exCurrent()
    check r.get.range.last == exCurrent()
    check r.get.rest == 1

  test "A multi-digit address consumes all of its digits":
    let r = parsed("120s/a/b/")
    check r.get.range.first == exLine(120)
    check r.get.rest == 3

  test "Line 0 parses; whether it exists is not the parser's to say":
    let r = parsed("0d")
    check r.isOk
    check r.get.range.first == exLine(0)

suite "ExRangePrefix - two addresses":
  test "Both sides given":
    let r = parsed("1,10d")
    check r.isOk
    check r.get.range.kind == erkAddresses
    check r.get.range.first == exLine(1)
    check r.get.range.last == exLine(10)
    check r.get.rest == 4

  test "A dot on either side is the current line":
    block:
      let r = parsed(".,10d")
      check r.get.range.first == exCurrent()
      check r.get.range.last == exLine(10)
    block:
      let r = parsed("1,.d")
      check r.get.range.first == exLine(1)
      check r.get.range.last == exCurrent()

  test "An omitted side is the current line too":
    block:
      let r = parsed(",10d")
      check r.isOk
      check r.get.range.kind == erkAddresses
      check r.get.range.first == exCurrent()
      check r.get.range.last == exLine(10)
    block:
      let r = parsed("1,d")
      check r.isOk
      check r.get.range.first == exLine(1)
      check r.get.range.last == exCurrent()

  test "0 beside a comma addresses the gap above the first line":
    # A bare `:0d` is not a range, but `0` either side of a comma is an address
    # like any other; the resolver answers it with the first line.
    let r = parsed("0,5d")
    check r.isOk
    check r.get.range.first == exLine(0)
    check r.get.range.last == exLine(5)

suite "ExRangePrefix - the last line and offsets":
  test "$ is the last line":
    let r = parsed("$d")
    check r.isOk
    check r.get.range.first == exLast()
    check r.get.range.last == exLast()
    check r.get.rest == 1

  test "A range can end at the last line":
    let r = parsed("1,$d")
    check r.isOk
    check r.get.range.first == exLine(1)
    check r.get.range.last == exLast()
    check r.get.rest == 3

  test "An offset moves an address":
    check parsed(".+3d").get.range.first == exCurrent(3)
    check parsed("$-2d").get.range.first == exLast(-2)
    check parsed("10+5d").get.range.first == exLine(10, 5)

  test "A bare + or - moves by one":
    check parsed("+d").get.range.first == exCurrent(1)
    check parsed("-d").get.range.first == exCurrent(-1)

  test "An address that is only an offset counts from the current line":
    let r = parsed("+2,+4d")
    check r.isOk
    check r.get.range.kind == erkAddresses
    check r.get.range.first == exCurrent(2)
    check r.get.range.last == exCurrent(4)

  test "Offsets accumulate":
    check parsed("++-d").get.range.first == exCurrent(1)

suite "ExRangePrefix - what is not an address":
  test "A number that is not one":
    # The only thing the parser can refuse. Whether a line exists is decided
    # where the buffer is: `0` and `1-1` name the same line by two spellings.
    check parsed("0d").isOk
    check parsed("1-1d").isOk

  test "A number too large to be a line":
    check parsed("99999999999999999999d").isErr

  test "Anything else ends the prefix rather than failing it":
    # The caller decides whether what follows is a name it knows, so `1.5d` is
    # a valid `1` followed by a name of `.5d` that no command answers to.
    for cmd in ["1xd", "1.5d", "..d"]:
      check parsed(cmd).isOk
    let r = parsed("1xd")
    check r.get.range.first == exLine(1)
    check r.get.rest == 1
