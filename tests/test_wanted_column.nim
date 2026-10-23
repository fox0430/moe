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

import ../src/moepkg/wanted_column

suite "shownFrom":
  test "from the line start":
    check shownFrom("abc", 0, 10, 4) == (column: 0, cell: 0, startByte: 0, endByte: 3)

  test "ascii":
    check shownFrom("hello", 2, 10, 4) == (column: 2, cell: 2, startByte: 2, endByte: 5)

  test "a tab cut by the left edge shows":
    check shownFrom("x\tx", 3, 10, 8) == (column: 1, cell: 1, startByte: 1, endByte: 3)

  test "a tab ending at the left edge does not":
    check shownFrom("x\tx", 8, 10, 8) == (column: 2, cell: 8, startByte: 2, endByte: 3)

  test "a wide character cut by the left edge shows":
    check shownFrom("日本語", 3, 10, 4) ==
      (column: 1, cell: 2, startByte: 3, endByte: 9)

  test "the row ends with the last character starting inside it":
    # 'e' starts at the row's last cell; 'f' is past it.
    check shownFrom("abcdefgh", 1, 4, 4) ==
      (column: 1, cell: 1, startByte: 1, endByte: 5)
    # 本 starts at the row's last cell, which cuts it.
    check shownFrom("日本語", 0, 3, 4) ==
      (column: 0, cell: 0, startByte: 0, endByte: 6)

  test "a combining mark goes with the character before it":
    # Hidden with 'b', and kept with 'b' at the row's end.
    check shownFrom("ab\u0301c", 2, 10, 4) ==
      (column: 3, cell: 2, startByte: 4, endByte: 5)
    check shownFrom("ab\u0301c", 0, 2, 4) ==
      (column: 0, cell: 0, startByte: 0, endByte: 4)

  test "a combining mark starting the text stands alone":
    check shownFrom("\u0301a", 0, 10, 4).column == 0
    # The text takes 1 cell, so scrolled by 1 nothing of it shows.
    check shownFrom("\u0301a", 1, 10, 4).column == 2

  test "past the end, a column per cell":
    check shownFrom("abc", 3, 10, 4) == (column: 3, cell: 3, startByte: 3, endByte: 3)
    check shownFrom("abc", 5, 10, 4) == (column: 5, cell: 5, startByte: 3, endByte: 3)
    check shownFrom("", 2, 10, 4) == (column: 2, cell: 2, startByte: 0, endByte: 0)
