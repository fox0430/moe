#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import moepkg/[gapbuffer, unicodeext]

import moepkg/editorview {.all.}

suite "editorview: initEditorView":
  test "Basic":
    let
      buffer = @["abc", "def"].toSeqRunes.toGapBuffer
      view = initEditorView(buffer, 2, 3)

    check view.lines.toSeqRunes == @["abc", "def"].toSeqRunes

  test "Basic 2":
    let
      buffer = @["abcあd", "いうefgh", "ij"]
        .toSeqRunes
        .toGapBuffer
      view = initEditorView(buffer, 8, 4)

    check view.lines.toSeqRunes == @[
      "abc",
      "あd",
      "いう",
      "efgh",
      "ij",
      "",
      "",
      ""]
      .toSeqRunes

    check view.originalLine[5] == -1
    check view.originalLine[6] == -1
    check view.originalLine[7] == -1

suite "editorview: seekCursor":
  test "Basic":
    let buffer = @["aaa", "bbbb", "ccccc", "ddd"]
      .toSeqRunes.
      toGapBuffer
    var view = initEditorView(buffer, 2, 3)

    check view.lines.toSeqRunes == @["aaa", "bbb"].toSeqRunes

    view.seekCursor(buffer, 2, 3)
    check view.lines.toSeqRunes == @["ccc", "cc"].toSeqRunes

    view.seekCursor(buffer, 3, 1)
    check view.lines.toSeqRunes == @["cc", "ddd"].toSeqRunes

  test "Basic 2":
    let buffer = @["aaaaaaa", "bbbb", "ccc", "d"].toSeqRunes.toGapBuffer
    var view = initEditorView(buffer, 2, 3)

    check view.lines.toSeqRunes == @["aaa", "aaa"].toSeqRunes

    view.seekCursor(buffer, 3, 0)
    check view.lines.toSeqRunes == @["ccc", "d"].toSeqRunes

    view.seekCursor(buffer, 1, 3)
    check view.lines.toSeqRunes == @["b", "ccc"].toSeqRunes

    view.seekCursor(buffer, 0, 6)
    check view.lines.toSeqRunes == @["a", "bbb"].toSeqRunes
