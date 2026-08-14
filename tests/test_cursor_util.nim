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

## Tests for cursor_util.nim

import std/unittest

import ../src/moepkg/[cursor_util, primitives]

suite "adjustCursorAfterInsertExit":
  test "Empty line moves cursor to column 0":
    var cursor = BufferPosition(line: 1, column: 3)
    adjustCursorAfterInsertExit(cursor, 0)
    check cursor.column == 0

  test "Cursor at column 0 stays":
    var cursor = BufferPosition(line: 1, column: 0)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 0

  test "Cursor moves one position left":
    var cursor = BufferPosition(line: 1, column: 4)
    adjustCursorAfterInsertExit(cursor, 10)
    check cursor.column == 3

  test "Cursor beyond line end is clamped":
    var cursor = BufferPosition(line: 1, column: 20)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 4

  test "Cursor at line end moves one position left":
    var cursor = BufferPosition(line: 1, column: 9)
    adjustCursorAfterInsertExit(cursor, 10)
    check cursor.column == 8

  test "Cursor column is never negative":
    var cursor = BufferPosition(line: 1, column: 0)
    adjustCursorAfterInsertExit(cursor, 0)
    check cursor.column == 0
