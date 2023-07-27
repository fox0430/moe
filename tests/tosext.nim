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

import std/[unittest, macros]
import moepkg/[osext, unicodeext]

suite "osext: isPath":
  # Generate test code
  # Check return values of suggestionwindow.isPath
  macro isPathTest(testIndex: int, expectVal: bool, line: Runes): untyped =
    quote do:
      let testTitle = "Case " & $`testIndex` & ": " & $`line`

      # Generate test code
      test testTitle:
        check `expectVal` == isPath(`line`)

  const TestCases: seq[tuple[expectVal: bool, line: Runes]] = @[
    (expectVal: true, line: "/".ru),
    (expectVal: true, line: "/h".ru),
    (expectVal: true, line: "/home/".ru),
    (expectVal: true, line: "/home/user".ru),
    (expectVal: true, line: "./".ru),
    (expectVal: true, line: "./Downloads".ru),
    (expectVal: true, line: "./Downloads/Images/".ru),
    (expectVal: false, line: "test /home/".ru),
    (expectVal: false, line: "test".ru),
    (expectVal: false, line: "te/st".ru)]

  # Generate test code by macro
  for i, c in TestCases:
    isPathTest(i, c.expectVal, c.line)

suite "osext: splitPathExt":
  # Generate test code
  # Check return values of suggestionwindow.splitPathExtTest
  macro splitPathExtTest(
    testIndex: int,
    expectVal: tuple[head, tail: Runes],
    path: Runes): untyped =

    quote do:
      let testTitle = "Case " & $`testIndex` & ": " & $`path`

      # Generate test code
      test testTitle:
        check `expectVal` == splitPathExt(`path`)

  const
    TestCases: seq[tuple[expectVal: tuple[head, tail: Runes], path: Runes]] = @[
      (expectVal: (head: "/".ru, tail: "".ru), path: "/".ru),
      (expectVal: (head: "./".ru, tail: "".ru), path: "./".ru),
      (expectVal: (head: "../".ru, tail: "".ru), path: "../".ru),
      (expectVal: (head: "/".ru, tail: "home".ru), path: "/home".ru),
      (expectVal: (head: "/home/".ru, tail: "".ru), path: "/home/".ru),
      (expectVal: (head: "/home/".ru, tail: "dir".ru), path: "/home/dir".ru),
      (expectVal: (head: "../".ru, tail: "home".ru), path: "../home".ru),
      (expectVal: (head: "../home/".ru, tail: "dir".ru), path: "../home/dir".ru)]

  # Generate test code by macro
  for i, c in TestCases:
    splitPathExtTest(i, c.expectVal, c.path)
