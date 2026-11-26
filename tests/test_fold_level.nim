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

proc foldRanges(b: TextBuffer): seq[(int, int)] =
  for f in b.foldState.folds:
    result.add (f.startLine, f.endLine)

proc newNestedFoldEditor(bufferBackend = bbcAuto): Editor =
  ## Lines 1-10, 2-8 and 3-5 nested, and 11-12 apart, all open.
  result =
    newVimLikeEditor(toSeq(1 .. 12).mapIt($it), 0, 0, bufferBackend = bufferBackend)
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

suite "An undo leaves folds open or closed, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`): an undo or redo never opens or closes a
  # fold, so the folds stay as zr left them and match 'foldlevel'.
  for (config, backend) in [(bbcGapBuffer, GapBuffer), (bbcPieceTable, PieceTable)]:
    for edit in [
      "Gx", "Gdd", ":12d<Enter>", ":%s/1/x/<Enter>", ":11,12s/1/y/<Enter>", "11GJ"
    ]:
      for (keys, name) in [
        ("zM" & edit & "zru", ", zr, then u"),
        ("zM" & edit & "uzr<C-r>", ", u, zr, then Ctrl-r"),
      ]:
        test $backend & ": zM, " & edit & name:
          let e = newNestedFoldEditor(config)
          check e.activeBuffer.backendKind == backend
          e.press(keys)
          check [0, 1, 2, 10].mapIt(e.foldClosed(it)) == [-1, 1, 1, -1]
          check e.activeBuffer.foldLevel == 1

    test $backend & ": a fold made after an edit stays across its undo":
      let e = newNestedFoldEditor(config)
      e.press("Gx:3<Enter>Vjzfu")
      check e.foldRanges == @[(0, 9), (1, 7), (2, 4), (2, 3), (10, 11)]

    test $backend & ": a fold zf made between u and Ctrl-r goes with its rows":
      # Ctrl-r deletes the rows again and the fold made on them; the next u
      # puts the rows back without it and brings back no fold from before.
      let e = newNestedFoldEditor(config)
      e.press(":11<Enter>dju:11<Enter>zdVjzf<C-r>u")
      check e.foldRanges == @[(0, 9), (1, 7), (2, 4)]

    test $backend & ": folds deleted after an edit stay deleted across its undo":
      let e = newNestedFoldEditor(config)
      e.press("GxzDu")
      check e.foldRanges.len == 0

    test $backend & ": a fold whose lines an edit deleted stays deleted with u":
      # Folds only follow the rows, so u puts the lines back without it.
      let e = newNestedFoldEditor(config)
      e.press(":11<Enter>dju")
      check e.foldRanges == @[(0, 9), (1, 7), (2, 4)]

    test $backend & ": a fold an edit moved and zd deleted stays deleted with u":
      let e = newNestedFoldEditor(config)
      e.press(":11<Enter>ddzdu")
      check e.foldRanges == @[(0, 9), (1, 7), (2, 4)]

    test $backend & ": folds shifted by an edit and zD deleted stay deleted with u":
      let e = newNestedFoldEditor(config)
      e.press("ggO<Esc>zDu")
      check e.foldRanges.len == 0

    test $backend & ": a fold zd deleted in Insert stays deleted with u":
      let e = newNestedFoldEditor(config)
      e.press(":7<Enter>O<C-o>zd<Esc>u")
      check e.foldRanges == @[(0, 9), (2, 4), (10, 11)]

    test $backend & ": Ctrl-r does not join the rows typed below a fold again":
      # Vim does not join them on redo either; it even shortens the fold.
      let e = newNestedFoldEditor(config)
      e.press(":5<Enter>A<Enter>x<Esc>")
      check e.foldRanges == @[(0, 10), (1, 8), (2, 5), (11, 12)]
      e.press("u<C-r>")
      check e.foldRanges == @[(0, 10), (1, 8), (2, 3), (11, 12)]

    test $backend & ": u of rows pasted at a fold's end leaves it before them":
      # Vim's undo ends the fold just before the rows it takes back.
      let b = newTextBuffer(toSeq(1 .. 12).mapIt($it).join("\n"), backend = backend)
      check b.replaceLines(5, 0, ["a", "b", "c"]).isOk
      check b.foldState.addFold(0, 5)
      check b.undo().isOk
      check b.foldRanges == @[(0, 4)]

    test $backend & ": a rollback brings back the folds of lines given up":
      let b = newTextBuffer(toSeq(1 .. 12).mapIt($it).join("\n"), backend = backend)
      check b.foldState.addFold(10, 11, collapsed = false)
      check b.beginTransaction("filter").isOk
      check b.replaceLines(9, 3, ["x"], keepRows = false).isOk
      check b.foldRanges.len == 0
      check b.rollbackTransaction().isOk
      check b.len == 12
      check b.foldRanges == @[(10, 11)]

  test "a filter and its undo move the folds as in Vim and leave zr's state":
    # Vim 9.2: folds 3,5 / 2,8 / 1,10 / 11,12, then `:10,12!printf 'x\ny\nz\n'`
    # keeps them all; zMzr and u then leave 1,9 / 2,8 / 3,5.
    let b = newTextBuffer(toSeq(1 .. 12).mapIt($it).join("\n"))
    for (first, last) in [(2, 4), (1, 7), (0, 9), (10, 11)]:
      check b.foldState.addFold(first, last, collapsed = true)
    check b.replaceLines(9, 3, ["x", "y", "z"], keepRows = false).isOk
    check b.foldRanges == @[(0, 9), (1, 7), (2, 4), (10, 11)]
    b.foldLevel = 1
    b.foldState.applyFoldLevel(1)
    check b.undo().isOk
    check b.foldState.folds.mapIt((it.startLine, it.endLine, it.collapsed)) ==
      @[(0, 8, false), (1, 7, true), (2, 4, true)]

suite "Undo and redo move the folds as Vim's u_undoredo does":
  # Typed in Vim 9.2 (`vim -u NONE`, lines 1-14, manual folds); the ranges
  # after the edit, then after each of u and Ctrl-r, 0-based.
  for (config, backend) in [(bbcGapBuffer, GapBuffer), (bbcPieceTable, PieceTable)]:
    for (folds, keys, after) in [
      (@[(5, 5)], @["5Gdd", "u", "<C-r>"], @[@[(4, 4)], @[], @[]]),
      (@[(4, 4)], @["5G$v6Gd", "u"], @[@[(4, 4)], @[]]),
      (@[(10, 11)], @["11GJ", "u"], @[@[(10, 10)], @[]]),
      (@[(2, 5)], @["4Gdj", "u"], @[@[(2, 3)], @[(2, 2)]]),
      (
        @[(2, 5), (3, 4)],
        @["5Gyyp", "u", "<C-r>"],
        @[@[(2, 6), (3, 4)], @[(2, 5), (3, 4)], @[(2, 4), (3, 4)]],
      ),
      (@[(2, 5)], @["4Goa<Enter>b<Esc>", "u"], @[@[(2, 7)], @[(2, 5)]]),
      (
        @[(2, 5), (6, 8)],
        @["6GJ", "u", "<C-r>"],
        @[@[(2, 5), (6, 7)], @[(2, 4), (7, 8)], @[(2, 4), (6, 7)]],
      ),
      # Each command saves all its rows in one entry, so all ways to delete
      # or join the same rows give the same.
      (@[(7, 9)], @["5G3dd", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @["5Gd2j", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @["7Gd2k", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @["5GVjjd", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @[":5,7d<Enter>", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @["5G$d3w", "u", "<C-r>"], @[@[(4, 6)], @[(4, 5)], @[]]),
      (@[(7, 9)], @["5Gvjjd", "u", "<C-r>"], @[@[(5, 7)], @[(7, 9)], @[(5, 7)]]),
      (@[(5, 7)], @["5G2dd", "u", "<C-r>"], @[@[(4, 5)], @[(4, 4)], @[]]),
      (@[(2, 5)], @["5G3dd", "u", "<C-r>"], @[@[(2, 3)], @[(2, 3)], @[(2, 3)]]),
      (@[(2, 4)], @["13G5dd", "u", "<C-r>"], @[@[(2, 4)], @[(2, 4)], @[(2, 4)]]),
      (@[(2, 4)], @["ggdG", "u", "<C-r>"], @[@[], @[], @[]]),
      (@[(4, 7)], @["5G3J", "u", "<C-r>"], @[@[(4, 5)], @[(4, 4)], @[]]),
      (@[(4, 7)], @["5GVjjJ", "u", "<C-r>"], @[@[(4, 5)], @[(4, 4)], @[]]),
    ]:
      test $backend & ": " & $folds & " then " & keys.join(", "):
        let e =
          newVimLikeEditor(toSeq(1 .. 14).mapIt($it), 0, 0, bufferBackend = config)
        check e.activeBuffer.backendKind == backend
        for (first, last) in folds:
          check e.activeBuffer.foldState.addFold(first, last, collapsed = false)
        for i, k in keys:
          e.press(k)
          check e.foldRanges == after[i]

    # A filter: `:{range}!` in Vim, given the rows as `replaceLines` with
    # `keepRows = false` gives them.
    for (folds, start, count, lines, after) in [
      (@[(1, 2)], 1, 2, @["a", "b"], @[@[(1, 2)], @[(1, 1)], @[]]),
      (@[(9, 10)], 9, 2, @["a", "b", "c", "d"], @[@[(9, 10)], @[(9, 9)]]),
      (@[(1, 3)], 1, 5, @["a", "b"], @[@[], @[]]),
      (@[(9, 11)], 9, 3, @["x"], @[@[]]),
      (@[(8, 10)], 9, 3, @["x"], @[@[(8, 8)]]),
    ]:
      test $backend & ": " & $folds & " then a filter of " & $count & " rows at " &
        $start & " giving " & $lines.len:
        let b = newTextBuffer(toSeq(1 .. 14).mapIt($it).join("\n"), backend = backend)
        for (first, last) in folds:
          check b.foldState.addFold(first, last, collapsed = false)
        check b.replaceLines(start, count, lines, keepRows = false).isOk
        check b.foldRanges == after[0]
        if after.len > 1:
          check b.undo().isOk
          check b.foldRanges == after[1]
        if after.len > 2:
          check b.redo().isOk
          check b.foldRanges == after[2]
