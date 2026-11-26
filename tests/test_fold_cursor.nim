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

## The cursor in a closed fold stays on the line a command puts it on, as in
## Vim: only vertical moves and scrolls take it to the fold's first line.

import std/[algorithm, options, unittest]

import pkg/celina

import ../src/moepkg/[buffer, types, editor]
import ../src/moepkg/[editor_frame, fold_open]
import ../src/moepkg/command_handlers/insert_commands
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc pressWithFrames(e: Editor, spec: string) =
  let frameBuffer = newBuffer(80, 24)
  for key in keysOf(spec):
    check e.handleKeyCombo(key)
    discard e.updateForFrame(frameBuffer)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

suite "The cursor in a closed fold, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`, `set foldopen=`) a key at a time.
  const
    Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
    Three = @["aa bb", "cc dd", "ee ff"]
  for (lines, fold, keys, want, wantCursor) in [
    (Five, (1, 3), ":3<Enter>", Five, (2, 0)),
    (Five, (1, 3), ":3<Enter>j", Five, (4, 0)),
    (Five, (1, 3), ":3<Enter>k", Five, (0, 0)),
    (Five, (1, 3), ":3<Enter>w", Five, (4, 0)),
    (Five, (1, 3), ":3<Enter>b", Five, (0, 3)),
    (Five, (1, 3), ":3<Enter>x", @["aa bb", "ii jj"], (1, 0)),
    (Five, (1, 3), ":3<Enter>X", Five, (2, 0)),
    (
      Five,
      (1, 3),
      ":3<Enter>rX",
      @["aa bb", "cc dd", "Xe ff", "gg hh", "ii jj"],
      (2, 0),
    ),
    (Five, (1, 3), ":4<Enter>~", @["aa bb", "cc dd", "ee ff", "Gg hh", "ii jj"], (3, 1)),
    (
      Five,
      (1, 3),
      ":3<Enter>~~",
      @["aa bb", "cc dd", "EE ff", "gg hh", "ii jj"],
      (2, 2),
    ),
    (
      Five,
      (1, 3),
      ":3<Enter>AX<Esc>",
      @["aa bb", "cc dd", "ee ffX", "gg hh", "ii jj"],
      (2, 5),
    ),
    (Five, (1, 3), ":3<Enter>yl", Five, (1, 0)),
    (Five, (1, 3), ":3<Enter>yiw", Five, (1, 0)),
    (Five, (1, 3), ":3<Enter>yy", Five, (1, 0)),
    (
      Five,
      (1, 3),
      ":3<Enter>ylP",
      @["aa bb", "cc dd", "ee ff", "gg hhcc dd", "ee ff", "gg hh", "ii jj"],
      (1, 0),
    ),
    (
      Five,
      (1, 3),
      ":3<Enter>gUl",
      @["aa bb", "CC DD", "EE FF", "GG HH", "ii jj"],
      (1, 0),
    ),
    (Five, (1, 3), ":3<Enter>dk", @["ii jj"], (0, 0)),
    (Five, (1, 3), ":3<Enter>dj", @["aa bb"], (0, 0)),
    (
      Five,
      (1, 3),
      ":3<Enter>Ox<Esc>",
      @["aa bb", "x", "cc dd", "ee ff", "gg hh", "ii jj"],
      (1, 0),
    ),
    (
      Five,
      (1, 3),
      "joX<Esc>",
      @["aa bb", "cc dd", "ee ff", "gg hh", "X", "ii jj"],
      (4, 0),
    ),
    (
      Five,
      (1, 3),
      ":3<Enter>2oX<Esc>",
      @["aa bb", "cc dd", "ee ff", "gg hh", "X", "X", "ii jj"],
      (5, 0),
    ),
    (
      Five,
      (1, 3),
      ":3<Enter>oX<Esc>.",
      @["aa bb", "cc dd", "ee ff", "gg hh", "X", "X", "ii jj"],
      (5, 0),
    ),
    (Three, (1, 2), "jj", Three, (1, 0)),
    (Three, (1, 2), "jgj", Three, (2, 0)),
    (Three, (1, 2), "jgjx", @["aa bb"], (0, 0)),
    (Three, (1, 2), "jdgj", @["aa bb", "ee ff"], (1, 0)),
    (Three, (1, 2), ":3<Enter>j", Three, (2, 0)),
    (Three, (1, 2), ":3<Enter>k", Three, (0, 0)),
    (Three, (1, 2), ":3<Enter>dj", Three, (2, 0)),
    (Three, (1, 2), "joX<Esc>", @["aa bb", "cc dd", "ee ff", "X"], (3, 0)),
  ]:
    test keys & " with lines " & $(fold[0] + 1) & "-" & $(fold[1] + 1) & " folded":
      let e = newVimLikeEditor(lines, 0, 0)
      check e.activeBuffer.foldState.addFold(fold[0], fold[1], collapsed = true)
      e.pressWithFrames(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

suite "Closing a fold over the cursor keeps it on its line, as in Vim":
  const Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
  for (keys, want, wantCursor, closed) in [
    ("jzojlzc", Five, (2, 1), true),
    ("jzojza", Five, (2, 0), true),
    ("jzojzM", Five, (2, 0), true),
    ("jzojzcAX<Esc>", @["aa bb", "cc dd", "ee ffX", "gg hh", "ii jj"], (2, 5), false),
    ("jzojzMAX<Esc>", @["aa bb", "cc dd", "ee ffX", "gg hh", "ii jj"], (2, 5), false),
  ]:
    test keys & " with lines 2-4 in a fold":
      let e = newVimLikeEditor(Five, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.pressWithFrames(keys)
      check e.lines == want
      check e.cursorAt == wantCursor
      check e.activeBuffer.foldState.getCollapsedFoldAt(2).isSome == closed

suite "Insert and Replace open the closed fold the cursor is in, as Vim's edit()":
  const Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
  for (keys, wantCursor) in [
    (":3<Enter>A", (2, 5)), (":2<Enter>i", (1, 0)), (":3<Enter>R", (2, 0))
  ]:
    test keys & " with lines 2-4 folded":
      let e = newVimLikeEditor(Five, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.pressWithFrames(keys)
      check e.cursorAt == wantCursor
      check e.activeBuffer.foldState.getCollapsedFoldAt(2).isNone
      e.pressWithFrames("<Esc>")
      check e.activeBuffer.foldState.getCollapsedFoldAt(2).isNone

suite "Insert opens a closed fold only as Vim's edit() does":
  # Typed in Vim 9.2 (`vim -u NONE`): moving up or down leaves a closed fold
  # closed, and <Up> lands on its last line; typing and moving sideways open
  # it, a command after Ctrl-o does not.
  const Indented = @["aa bb", "    cc dd", "    ee ff", "    gg hh", "ii jj"]
  for (keys, wantCursor, closed) in [
    ("A<Down>", (1, 5), true),
    ("A<Down><Down>", (4, 5), false),
    ("GA<Up>", (3, 5), true),
    ("GA<Up><Up>", (0, 5), false),
    ("Gi<Up><Esc>j", (4, 0), false),
    ("GR<Up><Up>", (0, 0), false),
    (":3<Enter>o<Up>", (3, 0), true),
    ("i<C-o>:3<Enter><Down>", (4, 0), false),
    ("i<C-o>:3<Enter><Up>", (0, 0), false),
    ("A<Down><Esc>k", (0, 0), false),
    ("GA<Up>x<Up>", (2, 6), false),
    ("GA<Up><Backspace><Up>", (2, 4), false),
    ("GR<Up>x<Up>", (2, 1), false),
    ("GA<Up><Left><Up>", (2, 4), false),
    ("GA<Up><Right><Up>", (2, 6), false),
    ("Gi<Up><Home><Up>", (2, 0), false),
    (":3<Enter>i<Up>", (1, 4), false),
    (":3<Enter>R<Down>", (3, 4), false),
    (":3<Enter>i<C-o>j", (3, 4), false),
    ("GR<Backspace>", (3, 9), true),
    ("GR<Backspace><Backspace>", (3, 8), false),
  ]:
    test keys & " with lines 2-4 folded":
      let e = newVimLikeEditor(Indented, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.pressWithFrames(keys)
      check e.cursorAt == wantCursor
      check e.activeBuffer.foldState.getCollapsedFoldAt(e.cursorAt[0]).isSome == closed

  test "Ctrl-o x in a closed fold deletes the fold's lines":
    let e = newVimLikeEditor(Indented, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("GA<Up><C-o>x")
    check e.lines == @["aa bb", "ii jj"]
    check e.cursorAt == (1, 0)

  test "<Down> off an unused auto-indent leaves the fold closed":
    let e =
      newVimLikeEditor(@["    aa", "bb", "cc", "dd", "ee"], 0, 0, autoIndent = true)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("o<Down>")
    check e.lines[1] == ""
    check e.cursorAt[0] == 2
    check e.activeBuffer.foldState.getCollapsedFoldAt(2).isSome

  test "<Enter> on the last line of a closed fold opens it":
    let e = newVimLikeEditor(Indented, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("GA<Up><Enter>")
    check e.cursorAt == (4, 0)
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isNone

  test "A paste in a closed fold opens it":
    let e = newVimLikeEditor(Indented, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("GA<Up>")
    check e.handlePasteText("zz")
    check e.lines[3] == "    gzzg hh"
    check e.activeBuffer.foldState.getCollapsedFoldAt(3).isNone

  test "<BS> joining a line up leaves the fold below closed":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 1, 0)
    check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    e.pressWithFrames("i<Backspace>")
    check e.lines[0] == "aabb"
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isSome

  test "<C-w> joining a line up leaves the fold below closed":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 1, 0)
    check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    e.pressWithFrames("i<C-w>")
    check e.lines[0] == "aabb"
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isSome

  test "Replace <BS> taking back a line break leaves the fold below closed":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 2)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("R<Enter><Backspace>")
    check e.lines[0] == "aa"
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isSome

  test "<Enter> at the end of a closed fold's last line opens it":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames(":5<Enter>A<Up><Enter>")
    check e.cursorAt == (4, 0)
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isNone

  test "A combining mark typed in a closed fold opens it":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames(":5<Enter>A<Up>")
    check e.handleTextInput("\u0301")
    check e.lines[3] == "dd\u0301"
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isNone

  test "An edit away from the cursor leaves the fold it is in closed":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("GA")
    e.state.anchorEdits(e.activeBuffer)
    check e.activeBuffer.insertTextEnd(BufferPosition(line: 2, column: 0), "X").isOk
    e.state.openFoldsOfEdits(e.activeBuffer)
    check e.lines[2] == "Xcc"
    check e.activeBuffer.foldState.getCollapsedFoldAt(1).isSome

  test "<C-o>a in a closed fold opens it":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("i<C-o>:3<Enter>")
    check e.activeBuffer.foldState.getCollapsedFoldAt(2).isSome
    e.pressWithFrames("<C-o>a")
    check e.activeBuffer.foldState.getCollapsedFoldAt(2).isNone

  test "Deleting the cursor's row leaves the fold after it closed":
    let e = newVimLikeEditor(@["aa", "bb", "cc", "dd", "ee", "ff"], 0, 0)
    check e.activeBuffer.foldState.addFold(3, 4, collapsed = true)
    e.pressWithFrames(":3<Enter>i")
    e.state.anchorEdits(e.activeBuffer)
    check e.activeBuffer.deleteLine(2).isOk
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    e.state.openFoldsOfEdits(e.activeBuffer)
    check e.lines == @["aa", "bb", "dd", "ee", "ff"]
    check e.activeBuffer.foldState.getCollapsedFoldAt(2).isSome

suite "A page scroll takes the cursor in a closed fold to its first line, as in Vim":
  const
    Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
    Three = @["aa bb", "cc dd", "ee ff"]
    Indented = @["aa bb", "    cc dd", "    ee ff", "    gg hh", "ii jj"]
    IndentedThree = @["aa bb", "    cc dd", "    ee ff"]
  for (lines, fold, keys, wantCursor) in [
    (Five, (1, 3), ":3<Enter><C-b>", (1, 0)),
    (Five, (1, 3), ":3<Enter><C-f>", (4, 0)),
    (Five, (1, 3), ":3<Enter><C-d>", (4, 0)),
    (Five, (1, 3), ":3<Enter><C-u>", (0, 0)),
    (Indented, (1, 3), ":3<Enter>9|<C-b>", (1, 4)),
    (Indented, (1, 3), ":3<Enter>9|<C-b>j", (4, 0)),
    (Indented, (1, 3), ":3<Enter>9|<C-d>", (4, 0)),
    (IndentedThree, (1, 2), ":3<Enter>9|<C-d>", (1, 4)),
    (IndentedThree, (1, 2), ":3<Enter>9|<C-f>", (1, 4)),
    (Three, (1, 2), ":3<Enter><C-b>", (1, 0)),
    (Three, (1, 2), ":3<Enter><C-f>", (1, 0)),
    (Three, (1, 2), ":3<Enter><C-d>", (1, 0)),
    (Three, (1, 2), ":3<Enter><C-u>", (0, 0)),
  ]:
    test keys & " with lines " & $(fold[0] + 1) & "-" & $(fold[1] + 1) & " folded":
      let e = newVimLikeEditor(lines, 0, 0)
      e.config.smoothScroll.enable = false
      check e.activeBuffer.foldState.addFold(fold[0], fold[1], collapsed = true)
      e.pressWithFrames(keys)
      check e.lines == lines
      check e.cursorAt == wantCursor

suite "Relative line numbers with the cursor in a closed fold":
  test "the fold's row is the cursor's row":
    let e = newVimLikeEditor(@["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"], 0, 0)
    e.state.relativeLineNumbers = true
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames(":3<Enter>")
    var screen = newBuffer(80, 24)
    e.render(screen)
    proc numberAt(y: int): string =
      for x in 0 ..< 3:
        result.add screen[x, y].symbol

    check numberAt(1) == "  1"
    check numberAt(2) == "  2"
    check numberAt(3) == "  1"

  test "a closed fold counts as one line":
    let e = newVimLikeEditor(@["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"], 0, 0)
    e.state.relativeLineNumbers = true
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("")
    var screen = newBuffer(80, 24)
    e.render(screen)
    proc numberAt(y: int): string =
      for x in 0 ..< 3:
        result.add screen[x, y].symbol

    check numberAt(1) == "  1"
    check numberAt(2) == "  1"
    check numberAt(3) == "  2"

suite "Lines typed below a fold's last line go into the fold, as Vim's foldMarkAdjust":
  # Typed in Vim 9.2 (`vim -u NONE`) on lines l1..l6 with `:2,4fold`.
  const Six = @["l1", "l2", "l3", "l4", "l5", "l6"]

  for (keys, want) in [
    (":4<Enter>A<Enter>x<Esc>", @[(1, 4)]),
    (":4<Enter>0i<Enter><Esc>", @[(1, 4)]),
    (":4<Enter>A<Enter><Enter>x<Esc>", @[(1, 5)]),
    (":4<Enter>$R<Enter><Esc>", @[(1, 4)]),
    (":2<Enter>0i<Enter><Esc>", @[(1, 4)]),
    (":1<Enter>A<Enter>x<Esc>", @[(2, 4)]),
    (":5<Enter>0i<Enter><Esc>", @[(1, 3)]),
    (":4<Enter>ox<Esc>", @[(1, 3)]),
    (":5<Enter>Ox<Esc>", @[(1, 3)]),
    (":4<Enter>A<C-o>ox<Esc>", @[(1, 3)]),
    (":4<Enter>A<Enter>x<Esc>u", @[(1, 3)]),
    (":4s/$/\\r/<Enter>", @[(1, 3)]),
  ]:
    test keys:
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = false)
      e.pressWithFrames(keys)
      check e.foldRanges == want

  for (keys, want) in [
    (":4<Enter>A<Enter>x<Esc>", @[(2, 4), (1, 5)]),
    (":5<Enter>A<Enter>x<Esc>", @[(2, 3), (1, 5)]),
  ]:
    test keys & " with folds 2-5 and 3-4":
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(2, 3, collapsed = false)
      check e.activeBuffer.foldState.addFold(1, 4, collapsed = false)
      e.pressWithFrames(keys)
      check e.foldRanges.sorted == want.sorted

  test "A paste of two lines at a fold's last line goes into the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = false)
    e.pressWithFrames(":4<Enter>A")
    check e.handlePasteText("p\nq\n")
    check e.lines[3 .. 5] == @["l4p", "q", ""]
    check e.foldRanges == @[(1, 5)]

  for (keys, want) in [
    ("GA<Enter>x<Esc>", @[(3, 6)]), ("GA<Enter><Enter>x<Esc>", @[(3, 7)])
  ]:
    test keys & " with a fold ending on the last line":
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(3, 5, collapsed = false)
      e.pressWithFrames(keys)
      check e.foldRanges == want

  for keys in ["3GA<Enter>p<Enter>q<Esc>8G.", "3GA<Enter>p<Enter>q<Esc>8GA<C-a><Esc>"]:
    test keys & " with folds 2-3 and 5-6 types the lines again into the fold":
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 2, collapsed = false)
      check e.activeBuffer.foldState.addFold(4, 5, collapsed = false)
      e.pressWithFrames(keys)
      check e.lines == @["l1", "l2", "l3", "p", "q", "l4", "l5", "l6", "p", "q"]
      check e.foldRanges.sorted == @[(1, 4), (6, 9)]

  for keys in ["8G.", "8GA<C-a><Esc>"]:
    test "A paste repeated with " & keys & " types the lines again into the fold":
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 2, collapsed = false)
      check e.activeBuffer.foldState.addFold(4, 5, collapsed = false)
      e.pressWithFrames("3GA")
      check e.handlePasteText("\np\nq")
      e.pressWithFrames("<Esc>" & keys)
      check e.lines == @["l1", "l2", "l3", "p", "q", "l4", "l5", "l6", "p", "q"]
      check e.foldRanges.sorted == @[(1, 4), (6, 9)]

  test "<Up> after <Enter> below a closed fold lands in the grown fold":
    let e = newVimLikeEditor(Six[0 .. 4], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.pressWithFrames("GA<Up><Enter><Up><Up>")
    check e.foldRanges == @[(1, 4)]
    check e.cursorAt[0] == 2

  test "Two lines added by one edit at a fold's last line stay out of the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    e.pressWithFrames(":4<Enter>A")
    check b.insertTextEnd(
      BufferPosition(line: 3, column: 2), "\np\nq", foldJoin = fjTyped
    ).isOk
    check e.foldRanges == @[(1, 3)]

  test "A rolled back deletion below a fold's last line leaves the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    check b.beginTransaction("t").isOk
    e.state.anchorEdits(b)
    check b.deleteLine(4).isOk
    check e.foldRanges == @[(1, 3)]
    check b.rollbackTransaction().isOk
    b.dropEditAnchor()
    check e.lines == Six
    check e.foldRanges == @[(1, 3)]

  test "A line an Insert key adds other than by a line break stays out of the fold":
    # As an LSP completion's import: Vim joins only open_line's line.
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    e.pressWithFrames("GA")
    e.state.anchorEdits(b)
    check b.insertTextEnd(BufferPosition(line: 3, column: 2), "\nimport x").isOk
    b.dropEditAnchor()
    check e.lines[4] == "import x"
    check e.foldRanges == @[(1, 3)]

  for mode in [bsmNoIndent, bsmIndent]:
    test "<Enter> splitting a bracket pair on a fold's last line, " & $mode:
      let e = newVimLikeEditor(@["l1", "l2", "l3", "l4()", "l5"], 0, 0)
      e.config.standard.bracketSplit = mode
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = false)
      e.pressWithFrames(":4<Enter>$i<Enter>x<Esc>")
      check e.lines.len == 7
      check e.lines[6] == "l5"
      check e.foldRanges == @[(1, 5)]

  test "<Enter> in Replace on a fold's last line":
    let e = newVimLikeEditor(Six, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = false)
    e.pressWithFrames(":4<Enter>$R<Enter>x<Esc>")
    check e.foldRanges == @[(1, 4)]

  test "A line break run in Insert with no key to anchor it goes into the fold":
    # As a script running insert.newline.
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    e.state.mode = EditorMode.Insert
    e.state.cursor = BufferPosition(line: 3, column: 2)
    check b.editAnchor.isNone
    insertNewline(b, e.state)
    check e.lines.len == 7
    check e.foldRanges == @[(1, 4)]

  test "A line break run in Insert with no key to anchor it opens the fold it joins":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = true)
    e.state.mode = EditorMode.Insert
    e.state.cursor = BufferPosition(line: 3, column: 2)
    insertNewline(b, e.state)
    check e.foldRanges == @[(1, 4)]
    check not b.foldState.folds[0].collapsed
    check b.editAnchor.isNone

  test "A line break run in Insert on a buffer no window shows opens no fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let other = newTextBuffer("l1\nl2\nl3\nl4\nl5\nl6")
    check other.foldState.addFold(1, 3, collapsed = true)
    e.state.mode = EditorMode.Insert
    e.state.cursor = BufferPosition(line: 3, column: 2)
    insertNewline(other, e.state)
    check other.len == 7
    check other.foldState.folds[0].collapsed
    check other.editAnchor.isNone

  test "A line break a key types leaves the opening of its fold to the key":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = true)
    e.state.mode = EditorMode.Insert
    e.state.cursor = BufferPosition(line: 3, column: 2)
    e.state.anchorEdits(b)
    insertNewline(b, e.state)
    check b.editAnchor.isSome
    check b.foldState.folds[0].collapsed
    b.dropEditAnchor()

  test "A line break run outside Insert leaves the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    e.state.cursor = BufferPosition(line: 3, column: 2)
    insertNewline(b, e.state)
    check e.lines.len == 7
    check e.foldRanges == @[(1, 3)]

  test "Lines opened below a fold's last line leave it whatever the join":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    check b.insertText(
      BufferPosition(line: 4, column: 0), "x\n", openLine = olAbove, foldJoin = fjTyped
    ).isOk
    check e.foldRanges == @[(1, 3)]

  test "A redo of a typed line break below a fold's last line leaves the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    check b.insertText(BufferPosition(line: 3, column: 2), "\n", foldJoin = fjTyped).isOk
    check e.foldRanges == @[(1, 4)]
    check b.undo().isOk
    check e.foldRanges == @[(1, 3)]
    check b.redo().isOk
    check e.foldRanges == @[(1, 3)]

  test "A redo of a transaction with a typed line break leaves the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    let b = e.activeBuffer
    check b.foldState.addFold(1, 3, collapsed = false)
    check b.beginTransaction("t").isOk
    check b.insertText(BufferPosition(line: 3, column: 2), "\n", foldJoin = fjTyped).isOk
    check b.commitTransaction().isOk
    check e.foldRanges == @[(1, 4)]
    check b.undo().isOk
    check e.foldRanges == @[(1, 3)]
    check b.redo().isOk
    check e.foldRanges == @[(1, 3)]

suite "Deleting lines past a fold's end, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`, manual folds 1,7 and 3,6 in 12 lines).
  # A charwise delete drops its rows in one edit, so the fold it runs past the
  # end of must end just before them.
  for (keys, want) in [
    (":5<Enter>5dd", @[(0, 3), (2, 3)]),
    (":3<Enter>dG", @[(0, 1)]),
    (":5,9d<Enter>", @[(0, 3), (2, 3)]),
    (":5<Enter>Vjjjjd", @[(0, 3), (2, 3)]),
    (":5<Enter>d4j", @[(0, 3), (2, 3)]),
    (":5<Enter>vjjjj$d", @[(0, 4), (2, 4)]),
    (":5<Enter>vjjjjd", @[(0, 4), (2, 4)]),
    (":5<Enter>4J", @[(0, 4), (2, 4)]),
    (":4<Enter>$vjjjjd", @[(0, 3), (2, 3)]),
  ]:
    test keys:
      let e = newVimLikeEditor(
        @["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"], 0, 0
      )
      check e.activeBuffer.foldState.addFold(0, 6, collapsed = false)
      check e.activeBuffer.foldState.addFold(2, 5, collapsed = false)
      e.pressWithFrames(keys)
      check e.foldRanges == want
