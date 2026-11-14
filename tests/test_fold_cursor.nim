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

import std/[options, unittest]

import pkg/celina

import ../src/moepkg/[buffer, types, editor]
import ../src/moepkg/[editor_frame, fold_open]
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
