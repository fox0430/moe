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

import ../src/moepkg/primitives

suite "primitives - BufferPosition":
  test "default values":
    let pos = BufferPosition()
    check pos.line == 0
    check pos.column == 0

  test "construct with specific values":
    let pos = BufferPosition(line: 10, column: 5)
    check pos.line == 10
    check pos.column == 5

  test "field assignment":
    var pos = BufferPosition()
    pos.line = 42
    pos.column = 99
    check pos.line == 42
    check pos.column == 99

  test "equality":
    let a = BufferPosition(line: 1, column: 2)
    let b = BufferPosition(line: 1, column: 2)
    let c = BufferPosition(line: 3, column: 4)
    check a == b
    check a != c
