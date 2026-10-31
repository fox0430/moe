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

## A typed command that takes the cursor into a closed fold opens it, as Vim's
## default 'foldopen' (block,hor,mark,percent,quickfix,search,tag,undo).

import std/[unittest, options]

import pkg/celina

import ../src/moepkg/[buffer, types, editor]
import ../src/moepkg/editor_frame
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    check e.handleKeyCombo(key)

proc pressWithFrames(e: Editor, spec: string) =
  let frameBuffer = newBuffer(80, 24)
  for key in keysOf(spec):
    check e.handleKeyCombo(key)
    discard e.updateForFrame(frameBuffer)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

proc closedLines(e: Editor): seq[int] =
  for i in 0 ..< e.activeBuffer.len:
    if e.activeBuffer.foldState.getCollapsedFoldAt(i).isSome:
      result.add i

suite "A typed command opens the closed fold it takes the cursor into, as in Vim":
  # Typed in Vim 9.2 (`vim --clean`) a key at a time, lines 2-3 folded.
  const
    Lines = @["aa bb cc", "aa (bb) cc dd", "aa bb cc", "aa bb cc", "", "x"]
    Folded = @[1, 2]
    Open: seq[int] = @[]
  for (keys, wantCursor, wantClosed) in [
    ("jl", (1, 1), Open),
    ("jh", (1, 0), Folded),
    ("j$", (1, 12), Open),
    ("j0", (1, 0), Open),
    ("j^", (1, 0), Open),
    ("jfb", (1, 4), Open),
    ("jtb", (1, 3), Open),
    ("jFa", (1, 0), Folded),
    ("fbj;", (1, 4), Open),
    ("fbj,", (1, 3), Folded),
    ("j3|", (1, 2), Folded),
    ("jg_", (1, 12), Folded),
    ("j%", (1, 6), Folded),
    ("lllj", (1, 3), Folded),
    ("llljyl", (1, 0), Folded),
    ("llljl", (1, 4), Open),
    ("llljh", (1, 2), Open),
    ("lllj$", (1, 12), Open),
    ("/dd<Enter>", (1, 11), Open),
    ("4G?bb c<Enter>", (2, 3), Open),
    ("jmagg'a", (1, 0), Open),
    ("j5lma0zc'a", (1, 0), Open),
    ("jmagg`a", (1, 0), Open),
    ("jGgg<C-o><C-o>", (1, 0), Open),
    ("jzojxzcggu", (2, 0), Open),
    ("jzojxzcgg:u<Enter>", (2, 0), Open),
    ("jzojxzcgguzcgg<C-r>", (2, 0), Open),
    ("jzojxzcGg;", (2, 0), Open),
  ]:
    test keys:
      let e = newVimLikeEditor(Lines, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
      e.press(keys)
      check e.cursorAt == wantCursor
      check e.closedLines == wantClosed

    test keys & " with a frame after each key":
      let e = newVimLikeEditor(Lines, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
      e.pressWithFrames(keys)
      check e.cursorAt == wantCursor
      check e.closedLines == wantClosed

  test "a word motion opens the fold it lands in, but not ge":
    const Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
    for (keys, wantCursor) in [("ww", (1, 0)), ("Gb", (3, 3)), ("vww", (1, 0))]:
      let e = newVimLikeEditor(Five, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.press(keys)
      checkpoint keys
      check e.cursorAt == wantCursor
      check e.closedLines.len == 0
    for keys in ["Gge", "GgE"]:
      let e = newVimLikeEditor(Five, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.press(keys)
      checkpoint keys
      check e.closedLines == @[1, 2, 3]

  test "a paragraph motion opens the fold it lands in":
    const Paragraphs = @["aa", "", "bb", "cc", "", "dd"]
    for (keys, wantCursor) in [("}", (1, 0)), ("G{{", (1, 0))]:
      let e = newVimLikeEditor(Paragraphs, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.press(keys)
      checkpoint keys
      check e.cursorAt == wantCursor
      check e.closedLines.len == 0

  test "a key a register puts in opens no fold":
    let e = newVimLikeEditor(Lines, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press("qqlqgg0j@q")
    check e.cursorAt == (1, 1)
    check e.closedLines == Folded

  test "an operator opens no fold":
    let e = newVimLikeEditor(@["abcdef", "abcdef", "abcdef", "abcdef"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press("jyl")
    check e.closedLines == @[1, 2]

  test "an operator back into a fold keeps the column":
    let e = newVimLikeEditor(@["start", "hello (world", "more", ") end"], 3, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press("y%")
    check e.cursorAt == (1, 6)
    check e.closedLines == @[1, 2]

  test "a key a mapping puts in opens no fold":
    let e = newVimLikeEditor(Lines, 0, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press(":nnoremap Q l<Enter>jQ")
    check e.cursorAt == (1, 1)
    check e.closedLines == Folded

  test "a $ that fails opens no fold":
    let e = newVimLikeEditor(@["abc", "abc", "abc"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press("j2$")
    check e.closedLines == @[1, 2]

  test "after ^ opens the fold, j aims for the cell of its text":
    let e =
      newVimLikeEditor(@["x long line", "    foo", "bar bar", "baz baz baz"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.press("llllj^j")
    check e.cursorAt == (2, 4)
