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

## `\r` in a :s replacement breaks the line, and :s lands the cursor on the
## last line it changed and marks where it started as a jump, as Vim's do_sub.

import std/unittest

import ../src/moepkg/[types, editor, editor_window, buffer]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    discard e.handleKeyCombo(key)

proc newEditorWith(lines: seq[string], line, column: int): Editor =
  ## Registered and active as a loaded buffer is, so the jump list follows
  ## its edits.
  result = newVimLikeEditor(lines, line, column)
  result.addBuffer(result.activeBuffer)
  result.syncActiveWindow()

proc text(e: Editor): seq[string] =
  for line in e.activeBuffer.lines:
    result.add line

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

proc jumps(e: Editor): seq[(int, int)] =
  for jump in e.state.jumpList.list:
    result.add (jump.line, jump.column)

suite ":s breaks lines and lands the cursor as Vim's do_sub":
  # Measured in Vim 9.2 (`vim -Nu NONE -es`), 0-based here.
  const Lines = @["  a,b", "x", "  c,d", "y"]
  for (lines, cursor, keys, wantText, wantCursor, wantJumps) in [
    (Lines, (3, 0), ":%s/,/-/<Enter>", @["  a-b", "x", "  c-d", "y"], (2, 2), @[(3, 0)]),
    (
      Lines,
      (0, 3),
      ":%s/,/\\r/<Enter>",
      @["  a", "b", "x", "  c", "d", "y"],
      (4, 0),
      @[(0, 3)],
    ),
    (
      @["  a,b,c", "x", "  c,d", "y"],
      (3, 0),
      ":1s/,/\\r  /g<Enter>",
      @["  a", "  b", "  c", "x", "  c,d", "y"],
      (2, 2),
      @[(5, 0)],
    ),
    (
      Lines,
      (1, 0),
      ":3s/,/\\r/<Enter>",
      @["  a,b", "x", "  c", "d", "y"],
      (3, 0),
      @[(1, 0)],
    ),
    (
      @["a,b", "c,d", "e"],
      (2, 0),
      ":1,2s/,/\\r/<Enter>",
      @["a", "b", "c", "d", "e"],
      (3, 0),
      @[(4, 0)],
    ),
    (@["abc", "z"], (1, 0), ":s/$/\\r/<Enter>", @["abc", "z", ""], (2, 0), @[(1, 0)]),
    (
      @["ab", "cd"],
      (1, 1),
      ":%s/^/\\r/<Enter>",
      @["", "ab", "", "cd"],
      (3, 0),
      @[(2, 1)],
    ),
    (@["ab"], (0, 0), ":s/a/\\u\\rx/<Enter>", @["", "xb"], (1, 0), @[(0, 0)]),
    (Lines, (3, 0), ":%s/,/\\r/n<Enter>", Lines, (3, 0), @[(3, 0)]),
  ]:
    test keys & " from " & $cursor:
      let e = newEditorWith(lines, cursor[0], cursor[1])
      e.press(keys)
      check e.text == wantText
      check e.cursorAt == wantCursor
      check e.jumps == wantJumps

  test "a :s that finds nothing leaves the cursor and marks no jump":
    let e = newEditorWith(Lines, 3, 0)
    e.press(":%s/q/\\r/<Enter>")
    check e.text == Lines
    check e.cursorAt == (3, 0)
    check e.jumps.len == 0

  test "Ctrl-o goes back to where it started, moved down with its line":
    let e = newEditorWith(@["a,b", "x", "  y"], 2, 2)
    e.press(":1s/,/\\r/<Enter>")
    check e.cursorAt == (1, 0)
    e.press("<C-o>")
    check e.cursorAt == (3, 2)

  test "a mark below a broken line moves down with it":
    # Vim 9.2: `'k` on line 3 goes to line 4.
    let e = newEditorWith(@["a,b", "x", "y"], 2, 0)
    e.press("mk")
    e.press(":1s/,/\\r/<Enter>")
    e.press("gg'k")
    check e.cursorAt == (3, 0)

  test "one undo takes every broken line back":
    let e = newEditorWith(Lines, 0, 0)
    e.press(":%s/,/\\r/g<Enter>")
    check e.text.len == 6
    e.press("u")
    check e.text == Lines

  test "\\n puts a NUL, as Vim keeps one in a line":
    let e = newEditorWith(@["a,b"], 0, 0)
    e.press(":s/,/\\n/<Enter>")
    check e.text == @["a\0b"]

  test "a NUL typed with Ctrl-V puts a NUL, next to a line break too":
    let e = newEditorWith(@["a,b", "c,d"], 0, 0)
    e.press(":s/,/<C-v><C-@>/<Enter>")
    check e.text == @["a\0b", "c,d"]
    e.press("j:s/,/<C-v><C-@>\\r/<Enter>")
    check e.text == @["a\0b", "c\0", "d"]

suite ":s preview breaks lines and takes them back":
  test "the preview shows the broken lines":
    let e = newEditorWith(@["a,b", "x"], 0, 0)
    e.press(":%s/,/\\r")
    check e.text == @["a", "b", "x"]

  test "Esc takes the lines back, and the marks below with them":
    let e = newEditorWith(@["a,b", "x", "y"], 2, 0)
    e.press("mk")
    e.press(":1s/,/\\r")
    check e.text == @["a", "b", "x", "y"]
    e.press("<Escape>")
    check e.text == @["a,b", "x", "y"]
    check e.cursorAt == (2, 0)
    e.press("gg'k")
    check e.cursorAt == (2, 0)

  test "the jumps stay while it shows, and Esc puts back the bookmarks it moved":
    let e = newEditorWith(@["a,b", "x", "y"], 2, 0)
    e.press("gg")
    e.activeBuffer.toggleBookmark(2)
    e.press(":1s/,/\\r")
    check e.jumps == @[(2, 0)]
    check e.activeBuffer.bookmarks == @[3]
    e.press("<Escape>")
    check e.jumps == @[(2, 0)]
    check e.activeBuffer.bookmarks == @[2]

  test "a mark on a broken line keeps its column":
    let e = newEditorWith(@["aaaa,bbbbbbbbbb", "x"], 0, 8)
    e.press("mk")
    e.press(":1s/,/\\r")
    e.press("<Escape>")
    e.press("G`k")
    check e.cursorAt == (0, 8)

  test "'incsearch' puts the cursor on the match where the preview moved it":
    # The `i` flag breaks the line above it; 'incsearch' reads no flags.
    let e = newEditorWith(@["x FOO y", "a", "foo"], 0, 0)
    e.state.ignorecase = false
    e.state.incsearch = true
    e.press(":%s/foo/\\r/i")
    check e.text == @["x ", " y", "a", "", ""]
    check e.cursorAt == (3, 0)
    e.press("<Escape>")
    check e.cursorAt == (0, 0)

  test "the range goes by the lines the preview started from":
    # `$-1` read in the broken lines would reach the last line.
    let e = newEditorWith(@["a,b", "c", "d", "e,f"], 0, 0)
    e.press(":1,$-1s/,/\\r/g")
    check e.text == @["a", "b", "c", "d", "e,f"]

  test "a cursor on a broken line stays on what is left of it":
    let e = newEditorWith(@["aaaa,bbbbbbbbbb"], 0, 10)
    e.state.incsearch = false
    e.press(":s/,/\\r")
    check e.text == @["aaaa", "bbbbbbbbbb"]
    check e.cursorAt == (0, 3)
    e.press("<Escape>")
    check e.cursorAt == (0, 10)

  test "without 'incsearch' the cursor goes down with its line":
    let e = newEditorWith(@["a,b", "x", "y"], 2, 0)
    e.state.incsearch = false
    e.press(":1s/,/\\r")
    check e.cursorAt == (3, 0)
    # Back to the pattern alone, which changes nothing.
    e.press("<Backspace><Backspace><Backspace>")
    check e.text == @["a,b", "x", "y"]
    check e.cursorAt == (2, 0)

  test "editing the replacement takes the broken lines back first":
    let e = newEditorWith(@["a,b,c"], 0, 0)
    e.press(":s/,/\\r/g")
    check e.text == @["a", "b", "c"]
    e.press("<Backspace><Backspace><Backspace>-")
    check e.text == @["a-b,c"]
