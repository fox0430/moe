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

## Expectations are Vim 9.2's: `==?` for folding and tolower() for upper case.

import std/[unittest, unicode]

import ../src/moepkg/char_case

proc sameFold(a, b: int32): bool =
  Rune(a).utfFold == Rune(b).utfFold

suite "utfFold":
  test "ASCII and Latin-1":
    check sameFold(0x41, 0x61)
    check sameFold(0xc9, 0xe9)

  test "Characters that lower casing leaves apart":
    check sameFold(0x3c3, 0x3c2) # sigma and final sigma
    check sameFold(0x3bc, 0xb5) # mu and the micro sign
    check sameFold(0x73, 0x17f) # s and long s

  test "A capital that does not fold to what it lower cases to":
    check not sameFold(0x130, 0x69) # Dotted capital I and i

suite "utfIsUpper":
  test "ASCII":
    check Rune('A').utfIsUpper
    check not Rune('a').utfIsUpper
    check not Rune('1').utfIsUpper

  test "Beyond ASCII":
    check Rune(0xc9).utfIsUpper
    check Rune(0x3a3).utfIsUpper
    check not Rune(0xe9).utfIsUpper
    check not Rune(0x3042).utfIsUpper
