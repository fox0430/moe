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

import ../src/moepkg/command_line/range_parser

proc parsed(cmd: string): ExRangePrefix =
  parseExRangePrefix(cmd)

suite "ExRangePrefix - no range":
  test "An empty command has no range and starts at 0":
    let r = parsed("")
    check r.isValid
    check not r.range.hasRange
    check not r.range.isGlobal
    check r.rest == 0

  test "A name with nothing in front of it is not a failure":
    for cmd in ["d", "s/a/b/", "sort"]:
      let r = parsed(cmd)
      check r.isValid
      check not r.range.hasRange
      check r.rest == 0

suite "ExRangePrefix - whole buffer":
  test "% is every line and consumes exactly itself":
    for cmd in ["%", "%d", "%s/a/b/", "%!sort"]:
      let r = parsed(cmd)
      check r.isValid
      check r.range.isGlobal
      check not r.range.hasRange
      check r.rest == 1

  test "% does not combine with a comma":
    # Parsing stops at `%`, so the caller sees `,5d` as the name and rejects it.
    let r = parsed("%,5d")
    check r.isValid
    check r.range.isGlobal
    check r.rest == 1

suite "ExRangePrefix - a single address":
  test "A line number covers that line alone":
    let r = parsed("5d")
    check r.isValid
    check r.range.hasRange
    check r.range.startLine == 5
    check r.range.endLine == 5
    check r.rest == 1

  test "A dot is the current line, which the parser cannot name":
    let r = parsed(".d")
    check r.isValid
    check r.range.hasRange
    check r.range.startLine == 0
    check r.range.endLine == 0
    check r.rest == 1

  test "A multi-digit address consumes all of its digits":
    let r = parsed("120s/a/b/")
    check r.range.startLine == 120
    check r.rest == 3

  test "Line 0 on its own is not an address":
    let r = parsed("0d")
    check not r.isValid

suite "ExRangePrefix - two addresses":
  test "Both sides given":
    let r = parsed("1,10d")
    check r.isValid
    check r.range.hasRange
    check r.range.startLine == 1
    check r.range.endLine == 10
    check r.rest == 4

  test "A dot on either side is the current line":
    block:
      let r = parsed(".,10d")
      check r.range.startLine == 0
      check r.range.endLine == 10
    block:
      let r = parsed("1,.d")
      check r.range.startLine == 1
      check r.range.endLine == 0

  test "An omitted side is the current line too":
    block:
      let r = parsed(",10d")
      check r.isValid
      check r.range.hasRange
      check r.range.startLine == 0
      check r.range.endLine == 10
    block:
      let r = parsed("1,d")
      check r.isValid
      check r.range.startLine == 1
      check r.range.endLine == 0

  test "0 beside a comma is accepted where 0 alone is not":
    # An omitted side already means the current line, so a typed 0 does too.
    let r = parsed("0,5d")
    check r.isValid
    check r.range.startLine == 0
    check r.range.endLine == 5

suite "ExRangePrefix - what is not an address":
  test "Digits and dots that do not form a number":
    for cmd in ["1.5d", "..d", "1.2,3d"]:
      check not parsed(cmd).isValid

  test "A number too large to be a line":
    check not parsed("99999999999999999999d").isValid

  test "Anything else ends the prefix rather than failing it":
    let r = parsed("1xd")
    check r.isValid
    check r.range.startLine == 1
    check r.rest == 1
