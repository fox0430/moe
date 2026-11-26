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

## zo/zc/za take a count, zr/zm move 'foldlevel' and zO/zC/zA work
## recursively, as in Vim.

import std/[options, sequtils, strutils, unittest]

import pkg/celina

import ../src/moepkg/[buffer, editor, editor_frame]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  let frameBuffer = newBuffer(80, 24)
  for key in keysOf(spec):
    check e.handleKeyCombo(key)
    discard e.updateForFrame(frameBuffer)

proc foldClosed(e: Editor, line: int): int =
  ## Vim's foldclosed(), 0-based: the first line of the closed fold drawn at
  ## `line`, or -1.
  let fold = e.activeBuffer.foldState.getCollapsedFoldAt(line)
  if fold.isSome: fold.get.startLine else: -1

proc newNestedFoldEditor(): Editor =
  ## Lines 1-10, 2-8 and 3-5 nested, and 11-12 apart, all open.
  result = newVimLikeEditor(toSeq(1 .. 12).mapIt($it), 0, 0)
  for (first, last) in [(2, 4), (1, 7), (0, 9), (10, 11)]:
    doAssert result.activeBuffer.foldState.addFold(first, last, collapsed = false)

suite "Fold counts and 'foldlevel', as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`, manual folds 3,5 / 2,8 / 1,10 / 11,12);
  # foldclosed() of lines 1, 2, 3 and 11, 0-based.
  for (keys, closed, level) in [
    ("zR", [-1, -1, -1, -1], 3),
    ("zM", [0, 0, 0, 10], 0),
    ("zMzr", [-1, 1, 1, -1], 1),
    ("zMzrzr", [-1, -1, 2, -1], 2),
    ("zMzrzr5zr", [-1, -1, -1, -1], 3),
    ("zRzm", [-1, -1, 2, -1], 2),
    ("zRzm2zm", [0, 0, 0, 10], 0),
    ("zMzm", [0, 0, 0, 10], 0),
    ("zM:3<Enter>2zo", [-1, -1, 2, 10], 0),
    ("zM:3<Enter>2zozo", [-1, -1, -1, 10], 0),
    ("zR:3<Enter>2zc", [-1, 1, 1, -1], 3),
    ("zR:3<Enter>2zczc", [0, 0, 0, -1], 3),
    ("zR:3<Enter>2zczc5zc", [0, 0, 0, -1], 3),
    ("zR:3<Enter>2za", [-1, 1, 1, -1], 3),
    ("zR:3<Enter>2za2za", [-1, -1, -1, -1], 3),
    ("zR:3<Enter>zczr", [-1, -1, 2, -1], 3),
    ("zR:3<Enter>zczrzm", [-1, -1, 2, -1], 2),
    ("zMggzo", [-1, 1, 1, 10], 0),
    ("zMggzozm", [0, 0, 0, 10], 0),
    ("zMgg3zo", [-1, 1, 1, 10], 0),
    ("zMgg3zozr", [-1, 1, 1, -1], 1),
  ]:
    test keys:
      let e = newNestedFoldEditor()
      e.press(keys)
      check [0, 1, 2, 10].mapIt(e.foldClosed(it)) == closed
      check e.activeBuffer.foldLevel == level

  test "zr without folds keeps 'foldlevel' at 0":
    let e = newVimLikeEditor(@["a", "b"], 0, 0)
    e.press("zr")
    check e.activeBuffer.foldLevel == 0

  test "zm without folds still lowers 'foldlevel'":
    let e = newVimLikeEditor(@["a", "b"], 0, 0)
    e.activeBuffer.foldLevel = 2
    e.press("zm")
    check e.activeBuffer.foldLevel == 1

  test "zo on a line without a fold reports it":
    let e = newVimLikeEditor(@["a", "b", "c"], 0, 0)
    check e.activeBuffer.foldState.addFold(0, 1, collapsed = true)
    e.press("G2zo")
    check e.activeBuffer.foldState.folds.allIt(it.collapsed)
    check "No fold found" in e.state.statusMessage

  test "za opens a fold made over another with the same range a level at a time":
    let e = newVimLikeEditor(toSeq(0 .. 6).mapIt($it), 2, 0)
    check e.activeBuffer.foldState.addFold(2, 5, collapsed = true)
    check e.activeBuffer.foldState.addFold(2, 5, collapsed = true)
    e.press("za")
    check e.activeBuffer.foldState.folds.mapIt(it.collapsed) == @[false, true]
    e.press("za")
    check e.activeBuffer.foldState.folds.mapIt(it.collapsed) == @[false, false]
    e.press("za")
    check e.activeBuffer.foldState.folds.mapIt(it.collapsed) == @[false, true]

  test "an undo keeps 'foldlevel'":
    let e = newNestedFoldEditor()
    e.press("zMzrGx")
    e.press("u")
    check e.activeBuffer.foldLevel == 1

proc newSiblingFoldEditor(): Editor =
  ## Lines 1-10 hold 2-8, which holds 3-5 and 6-7; 11-12 apart. All open.
  result = newVimLikeEditor(toSeq(1 .. 12).mapIt($it), 0, 0)
  for (first, last) in [(0, 9), (1, 7), (2, 4), (5, 6), (10, 11)]:
    doAssert result.activeBuffer.foldState.addFold(first, last, collapsed = false)

suite "zO/zC/zA, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`, manual folds 1,10 / 2,8 / 3,5 / 6,7 /
  # 11,12); foldclosed() of lines 1, 2, 3, 6 and 11, 0-based. A count is
  # ignored.
  for (keys, closed) in [
    ("zMGzO", [0, 0, 0, 0, -1]),
    ("zM:4<Enter>zO", [-1, -1, -1, -1, 10]),
    ("zMggzOzc", [0, 0, 0, 0, 10]),
    ("zR:4<Enter>zC", [0, 0, 0, 0, -1]),
    ("zR:4<Enter>zCzo", [-1, 1, 1, 1, -1]),
    ("zR:4<Enter>zCzozo", [-1, -1, 2, -1, -1]),
    ("zR:4<Enter>zCzozozo", [-1, -1, -1, -1, -1]),
    ("zR:4<Enter>zC:6<Enter>zozo", [-1, -1, 2, -1, -1]),
    ("zR:4<Enter>2zCzo", [-1, 1, 1, 1, -1]),
    ("zR:3<Enter>zc:6<Enter>zcggzO", [-1, -1, 2, 5, -1]),
    ("zR:3<Enter>zc:6<Enter>zc:2<Enter>zcggzO", [-1, 1, 1, 1, -1]),
    ("zR:3<Enter>zc:6<Enter>zc:2<Enter>zcggzA", [0, 0, 0, 0, -1]),
    ("zR:3<Enter>zc:6<Enter>zc:2<Enter>zc:4<Enter>zA", [-1, -1, -1, -1, -1]),
    ("zR:3<Enter>zc:4<Enter>zA:4<Enter>zc", [-1, -1, 2, -1, -1]),
    ("zR:4<Enter>zA", [0, 0, 0, 0, -1]),
    ("zR:4<Enter>zAzozozo", [-1, -1, -1, -1, -1]),
    ("zR:9<Enter>zAzozo", [-1, -1, -1, -1, -1]),
    ("zR:3<Enter>3zO", [-1, -1, -1, -1, -1]),
  ]:
    test keys:
      let e = newSiblingFoldEditor()
      e.press(keys)
      check [0, 1, 2, 5, 10].mapIt(e.foldClosed(it)) == closed
      check e.activeBuffer.foldLevel == (if keys.startsWith("zM"): 0 else: 3)

  for keys in ["zO", "zC", "zA"]:
    test keys & " on a line without a fold reports it":
      let e = newVimLikeEditor(@["a", "b", "c"], 0, 0)
      check e.activeBuffer.foldState.addFold(0, 1, collapsed = false)
      e.press("G" & keys)
      check e.activeBuffer.foldState.folds.allIt(not it.collapsed)
      check "No fold found" in e.state.statusMessage

  test "zC on folds already closed is silent":
    let e = newSiblingFoldEditor()
    e.press("zMzC")
    check e.state.statusMessage.len == 0

  test "zO opens a fold made over another with the same range at once":
    let e = newVimLikeEditor(toSeq(0 .. 6).mapIt($it), 2, 0)
    check e.activeBuffer.foldState.addFold(2, 5, collapsed = true)
    check e.activeBuffer.foldState.addFold(2, 5, collapsed = true)
    e.press("zO")
    check e.activeBuffer.foldState.folds.mapIt(it.collapsed) == @[false, false]
