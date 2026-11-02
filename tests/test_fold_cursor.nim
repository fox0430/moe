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
import ../src/moepkg/editor_frame
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
