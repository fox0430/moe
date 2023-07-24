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

import std/[unittest, deques]
import moepkg/[editorview, gapbuffer, unicodeext]

test "initEditorView 1":
  const Lines = @[ru"abc", ru"def"]
  let
    buffer = initGapBuffer[Runes](Lines)
    view = initEditorView(buffer, 2, 3)

  check(view.lines[0] == ru"abc")
  check(view.lines[1] == ru"def")

test "initEditorView 2":
  const Lines = @[ru"abcあd", ru"いうefgh", ru"ij"]
  let
    buffer = initGapBuffer[Runes](Lines)
    view = initEditorView(buffer, 8, 4)

  check(view.lines[0] == ru"abc")
  check(view.lines[1] == ru"あd")
  check(view.lines[2] == ru"いう")
  check(view.lines[3] == ru"efgh")
  check(view.lines[4] == ru"ij")
  check(view.originalLine[5] == -1)
  check(view.originalLine[6] == -1)
  check(view.originalLine[7] == -1)

test "seekCursor 1":
  const Lines = @[ru"aaa", ru"bbbb", ru"ccccc", ru"ddd"]
  let buffer = initGapBuffer[Runes](Lines)
  var view = initEditorView(buffer, 2, 3)

  check(view.lines[0] == ru"aaa")
  check(view.lines[1] == ru"bbb")

  view.seekCursor(buffer, 2, 3)
  check(view.lines[0] == ru"ccc")
  check(view.lines[1] == ru"cc")

  view.seekCursor(buffer, 3, 1)
  check(view.lines[0] == ru"cc")
  check(view.lines[1] == ru"ddd")

test "seekCursor 2":
  const Lines = @[ru"aaaaaaa", ru"bbbb", ru"ccc", ru"d"]
  let buffer = initGapBuffer(Lines)
  var view = initEditorView(buffer, 2, 3)

  check(view.lines[0] == ru"aaa")
  check(view.lines[1] == ru"aaa")

  view.seekCursor(buffer, 3, 0)

  check(view.lines[0] == ru"ccc")
  check(view.lines[1] == ru"d")

  view.seekCursor(buffer, 1, 3)

  check(view.lines[0] == ru"b")
  check(view.lines[1] == ru"ccc")

  view.seekCursor(buffer, 0, 6)

  check(view.lines[0] == ru"a")
  check(view.lines[1] == ru"bbb")
