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

## Tests for command_registry/operator_driver.nim

import std/unittest

import ../src/moepkg/[types, buffer, motion, key_bindings]
import ../src/moepkg/command_registry/core
import ../src/moepkg/command_registry/operator_driver

proc pos(line, column: int): BufferPosition =
  BufferPosition(line: line, column: column)

proc target(start, finish: BufferPosition, kind: MotionType): MotionTarget =
  MotionTarget(start: start, finish: finish, motionType: kind)

suite "toOperatorRange":
  test "an exclusive span stops before where it lands, either way round":
    let buffer = newTextBuffer("abcdef")
    for (start, finish) in [(pos(0, 1), pos(0, 4)), (pos(0, 4), pos(0, 1))]:
      let range = buffer.toOperatorRange(target(start, finish, mtExclusive), OpYank)

      check range.start == pos(0, 1)
      check range.endPos == pos(0, 3)
      check not range.isLinewise
      check not range.isEmpty

  test "an exclusive span that goes nowhere is empty":
    let buffer = newTextBuffer("abc")

    check buffer.toOperatorRange(target(pos(0, 1), pos(0, 1), mtExclusive), OpYank).isEmpty

  test "an inclusive span takes where it lands":
    let buffer = newTextBuffer("abcdef")
    let range =
      buffer.toOperatorRange(target(pos(0, 1), pos(0, 4), mtInclusive), OpYank)

    check range.start == pos(0, 1)
    check range.endPos == pos(0, 4)

  test "a linewise span takes whole lines":
    let buffer = newTextBuffer("one\ntwo\nthree")
    let range = buffer.toOperatorRange(target(pos(2, 3), pos(0, 1), mtLinewise), OpYank)

    check range.isLinewise
    check range.start == pos(0, 0)
    check range.endPos == pos(2, 5)

  test "an exclusive span that ends at a line start stops at the end of the line before":
    let buffer = newTextBuffer("abc\nde\nf")
    let range =
      buffer.toOperatorRange(target(pos(0, 1), pos(2, 0), mtExclusive), OpYank)

    check not range.isLinewise
    check range.start == pos(0, 1)
    check range.endPos == pos(1, 1)

  test "and takes whole lines when it starts in the indent":
    let buffer = newTextBuffer("  abc\nde\nf")
    for start in [pos(0, 0), pos(0, 2)]:
      let range = buffer.toOperatorRange(target(start, pos(2, 0), mtExclusive), OpYank)

      check range.isLinewise
      check range.start == pos(0, 0)
      check range.endPos.line == 1

  test "an empty line before the end leaves the span at the line break ahead of it":
    let buffer = newTextBuffer("abc\nd\n\ne")
    let range =
      buffer.toOperatorRange(target(pos(0, 1), pos(3, 0), mtExclusive), OpYank)

    check not range.isLinewise
    check range.endPos == pos(1, 1)

  test "an empty object keeps its place for `c`":
    let buffer = newTextBuffer("<a></a>")
    let range = buffer.toOperatorRange(
      MotionTarget(
        start: pos(0, 3), finish: pos(0, 2), motionType: mtInclusive, empty: true
      ),
      OpChange,
    )

    check range.isEmpty
    check range.start == pos(0, 2)

suite "operandCount":
  test "the two counts multiply, capped as a typed count is":
    let op = PendingOperator(operatorType: OpDelete, operatorCount: 2)

    check op.operandCount(3) == 6
    check op.operandCount(0) == 2
    check PendingOperator(operatorCount: MaxNumericPrefix).operandCount(
      MaxNumericPrefix
    ) == MaxNumericPrefix
