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

import std/[unittest, options]

import ../src/moepkg/command_handlers/number_increment

proc add(line: string, startByte, endByte, delta: int): string =
  let change = addToNumber(line, startByte, endByte, delta)
  check change.isSome
  change.get.line

suite "numberStartAt":
  test "walks back to the first digit":
    check numberStartAt("a 199", 4) == 2
    check numberStartAt("a 199", 2) == 2

  test "takes in the minus before the number":
    check numberStartAt("-15", 2) == 0
    check numberStartAt("foo-1", 4) == 3

  test "stays put off a digit":
    check numberStartAt("a 1", 1) == 1
    check numberStartAt("a -1", 2) == 2
    check numberStartAt("a 1", 3) == 3
    check numberStartAt("", 0) == 0

suite "addToNumber":
  test "the first number at or after the start":
    check add("a 1 b 2", 0, 7, 1) == "a 2 b 2"
    check add("a 1 b 2", 3, 7, 1) == "a 1 b 3"

  test "reports the start of the replaced number":
    check addToNumber("ab 9 c", 0, 6, 1).get ==
      NumberChange(line: "ab 10 c", numberStart: 3, numberEnd: 5)
    check addToNumber("x -1", 0, 4, -1).get.numberStart == 2
    check addToNumber("x 1", 0, 3, -2).get ==
      NumberChange(line: "x -1", numberStart: 2, numberEnd: 4)

  test "delta of any size":
    check add("x 10", 0, 4, 5) == "x 15"
    check add("x 10", 0, 4, -15) == "x -5"

  test "a minus inside the range makes it negative":
    check add("foo -10", 0, 7, 1) == "foo -9"
    check add("foo -10", 4, 7, 1) == "foo -9"

  test "a minus before the range is ignored":
    check add("foo -10", 5, 7, 10) == "foo -20"

  test "digits past the end are not part of the number":
    check add("a 123 b", 2, 3, 1) == "a 223 b"
    check add("199", 0, 2, 1) == "209"

  test "starting inside a number takes the digits from the start":
    check add("a 123 b", 3, 7, 1) == "a 124 b"

  test "no number in the range":
    check addToNumber("abc", 0, 3, 1).isNone
    check addToNumber("a 1", 0, 2, 1).isNone
    check addToNumber("a 1", 3, 3, 1).isNone
    check addToNumber("", 0, 0, 1).isNone
    check addToNumber("a -", 0, 3, 1).isNone

  test "the end is clamped to the line":
    check add("x 7", 0, 100, 1) == "x 8"

  test "multibyte text around the number":
    check add("あ1い", 0, "あ1い".len, 1) == "あ2い"

  test "goes past int, like Vim's unsigned magnitude":
    check add($high(int), 0, 100, 1) == "9223372036854775808"
    check add($low(int), 0, 100, -1) == "-9223372036854775809"
    check add("0", 0, 1, low(int)) == $low(int)

  test "wraps around past the largest magnitude, flipping the sign, as Vim":
    check add($high(uint64), 0, 100, 1) == "-" & $high(uint64)
    check add($high(uint64), 0, 100, 3) == "-" & $(high(uint64) - 2)
    check add("-" & $high(uint64), 0, 100, -1) == $high(uint64)

  test "a number too large to hold is clamped, and nothing is added":
    check add("99999999999999999999", 0, 20, -1) == $high(uint64)
    check add("99999999999999999999", 0, 20, 1) == $high(uint64)
    check add("-99999999999999999999", 0, 21, 1) == "-" & $high(uint64)

  test "crossing zero":
    check add("-1", 0, 2, 1) == "0"
    check add("-0", 0, 2, 1) == "1"
    check add("3", 0, 1, -5) == "-2"

  test "a zero-padded number keeps its digit count":
    check add("007", 0, 3, 1) == "008"
    check add("item 01", 0, 7, 9) == "item 10"
    check add("099", 0, 3, 1) == "100"
    check add("010", 0, 3, -11) == "-001"
    check add("-01", 0, 3, 2) == "01"

  test "an unpadded number does not gain zeros":
    check add("10", 0, 2, -1) == "9"
