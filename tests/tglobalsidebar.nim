#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, importutils, sequtils]
import moepkg/[independentutils, unicodeext, highlight, color]

import moepkg/globalsidebar {.all.}

suite "sidebar":
  test "initGlobalSidebar":
    let sidebar = initGlobalSidebar(Rect(h: 1, w: 2, y: 3, x: 4))

    check sidebar.h == 1
    check sidebar.w == 2
    check sidebar.y == 3
    check sidebar.x == 4

    privateAccess(sidebar.type)

    check sidebar.terminalBuffer ==
      1.newSeqWith(ru" ".repeat(2))

    check sidebar.highlight == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 1,
          color: EditorColorPairIndex.default)])

  test "initHighlight":
    var sidebar = initGlobalSidebar(Rect(h: 10, w: 10, y: 0, x: 0))
    # Clear the highlight for the test.
    sidebar.highlight = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 0,
          color: EditorColorPairIndex.default)])

    sidebar.initHighlight

    check sidebar.highlight == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 9,
          lastColumn: 9,
          color: EditorColorPairIndex.default)])

  test "write 1":
    var sidebar = initGlobalSidebar(Rect(h: 100, w: 100, y: 0, x: 0))

    sidebar.write(Position(y: 0, x: 0), ru"test", EditorColorPairIndex.reservedWord)

    privateAccess(sidebar.type)

    check sidebar.terminalBuffer[0] == ru"test" & ru" ".repeat(96)
    for i in 1 .. sidebar.terminalBuffer.high:
      check sidebar.terminalBuffer[i] == ru" ".repeat(100)

    check sidebar.highlight == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 3,
          color: EditorColorPairIndex.reservedWord),
        ColorSegment(
          firstRow: 0,
          firstColumn: 4,
          lastRow: 99,
          lastColumn: 99,
          color: EditorColorPairIndex.default)])

  test "write 2":
    var sidebar = initGlobalSidebar(Rect(h: 100, w: 100, y: 0, x: 0))

    sidebar.write(Position(y: 1, x: 10), ru"test", EditorColorPairIndex.reservedWord)

    privateAccess(sidebar.type)

    for index, line in sidebar.terminalBuffer:
      if index == 1:
        check line == ru" ".repeat(10) & ru"test" & ru" ".repeat(86)
      else:
        check line == ru" ".repeat(100)

    check sidebar.highlight == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 1,
          lastColumn: 9,
          color: EditorColorPairIndex.default),
        ColorSegment(
          firstRow: 1,
          firstColumn: 10,
          lastRow: 1,
          lastColumn: 13,
          color: EditorColorPairIndex.reservedWord),
        ColorSegment(
          firstRow: 1,
          firstColumn: 14,
          lastRow: 99,
          lastColumn: 99,
          color: EditorColorPairIndex.default)])

  test "resize":
    var sidebar = initGlobalSidebar(Rect(h: 1, w: 1, y: 0, x: 0))

    sidebar.resize(Size(h: 2, w: 3))

    check sidebar.size == Size(h: 2, w: 3)

  test "resize 2":
    var sidebar = initGlobalSidebar(Rect(h: 1, w: 1, y: 0, x: 0))

    sidebar.resize(Rect(y: 2, x: 3, h: 4, w: 5))

    check sidebar.rect == Rect(y: 2, x: 3, h: 4, w: 5)

  test "move":
    var sidebar = initGlobalSidebar(Rect(h: 1, w: 1, y: 0, x: 0))

    sidebar.move(Position(y: 2, x: 3))

    check sidebar.position == Position(y: 2, x: 3)

  test "clear":
    var sidebar = initGlobalSidebar(Rect(h: 1, w: 1, y: 0, x: 0))

    sidebar.write(Position(y: 0, x: 0), ru"a")

    sidebar.clear

    privateAccess(sidebar.type)

    check sidebar.terminalBuffer == @[ru" "]
