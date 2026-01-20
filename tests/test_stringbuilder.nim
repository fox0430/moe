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

## Tests for StringBuilder module
## Verifies efficient string building for repeat command optimization

import std/unittest

import ../src/moepkg/stringbuilder

suite "StringBuilder - Basic Operations":
  test "basic add operations":
    var sb = newStringBuilder()
    sb.add("hello")
    sb.add(" ")
    sb.add("world")
    check sb.toString() == "hello world"

  test "add and remove":
    var sb = newStringBuilder()
    sb.add("hello")
    sb.removeLast(2) # Remove "lo"
    sb.add("p")
    check sb.toString() == "help"

  test "remove entire parts":
    var sb = newStringBuilder()
    sb.add("hello")
    sb.add(" ")
    sb.add("world")
    sb.removeLast(6) # Remove " world"
    check sb.toString() == "hello"

  test "remove more than exists":
    var sb = newStringBuilder()
    sb.add("hi")
    sb.removeLast(10) # Remove more than available
    check sb.toString() == ""

  test "clear operation":
    var sb = newStringBuilder()
    sb.add("test")
    sb.clear()
    sb.add("new")
    check sb.toString() == "new"

  test "length tracking":
    var sb = newStringBuilder()
    check sb.len == 0
    sb.add("hello")
    check sb.len == 5
    sb.add(" world")
    check sb.len == 11
    sb.removeLast(6)
    check sb.len == 5

  test "empty string adds":
    var sb = newStringBuilder()
    sb.add("")
    sb.add("test")
    sb.add("")
    check sb.toString() == "test"

  test "unicode/multibyte characters":
    var sb = newStringBuilder()
    sb.add("Hello ")
    sb.add("世界")
    sb.add("!")
    check sb.toString() == "Hello 世界!"

suite "StringBuilder - Edge Cases":
  test "remove zero characters":
    var sb = newStringBuilder()
    sb.add("test")
    sb.removeLast(0)
    check sb.toString() == "test"

  test "remove negative characters":
    var sb = newStringBuilder()
    sb.add("test")
    sb.removeLast(-5)
    check sb.toString() == "test"

  test "multiple clear operations":
    var sb = newStringBuilder()
    sb.add("first")
    sb.clear()
    sb.add("second")
    sb.clear()
    sb.add("third")
    check sb.toString() == "third"

  test "remove from empty builder":
    var sb = newStringBuilder()
    sb.removeLast(5)
    check sb.toString() == ""
    check sb.len == 0

  test "alternating add and remove":
    var sb = newStringBuilder()
    sb.add("abc")
    sb.removeLast(1) # "ab"
    sb.add("def")
    sb.removeLast(2) # "abd" (removes "ef")
    sb.add("xyz")
    check sb.toString() == "abdxyz"
