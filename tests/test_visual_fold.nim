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

## A Visual selection over a closed fold, as Vim: after each command, an end in
## a closed fold is taken to the fold's edge (foldAdjustVisual), so an operator
## acts on the whole fold.

import std/unittest

import pkg/celina

import ../src/moepkg/[buffer, types, editor, registers, visual_selection]
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

suite "A Visual selection over a closed fold, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`) a key at a time: `:normal` skips
  # foldAdjustVisual.
  const
    Four = @["abcdef", "abcdef", "abcdef", "abcdef"]
    Uneven = @["abcdef", "abcdefghij", "abc", "x"]
    Six = @["aaa", "bbb", "ccc", "ddd", "eee", "fff"]
  for (lines, fold, keys, want, wantCursor) in [
    (Four, (1, 2), "<C-v>jd", @["", "", "", "abcdef"], (0, 0)),
    (
      Four,
      (1, 2),
      "<C-v>jIfoo<Esc>",
      @["fooabcdef", "fooabcdef", "fooabcdef", "abcdef"],
      (0, 0),
    ),
    (Four, (1, 2), "<C-v>jcfoo<Esc>", @["foo", "foo", "foo", "abcdef"], (0, 2)),
    (
      Four,
      (1, 2),
      "<C-v>jAfoo<Esc>",
      @["abcdef foo", "abcdef foo", "abcdef foo", "abcdef"],
      (0, 0),
    ),
    (
      Four,
      (1, 2),
      "jj<C-v>kAfoo<Esc>",
      @["abcdef", "afoobcdef", "afoobcdef", "afoobcdef"],
      (1, 0),
    ),
    (Four, (1, 2), "vjd", @["abcdef"], (0, 0)),
    (Four, (1, 2), "vjrx", @["xxxxxx", "xxxxxx", "xxxxxx", "abcdef"], (0, 0)),
    (Four, (1, 2), "vjcfoo<Esc>", @["fooabcdef"], (0, 2)),
    (Four, (1, 2), "Vjd", @["abcdef"], (0, 0)),
    (Four, (1, 2), "jjVkd", @["abcdef"], (0, 0)),
    (Four, (1, 2), "vjjd", @["bcdef"], (0, 0)),
    (Four, (1, 2), "vjkd", @["bcdef", "abcdef", "abcdef", "abcdef"], (0, 0)),
    (Four, (1, 2), "lvjod", @["aabcdef"], (0, 1)),
    (Four, (1, 2), "jvd", @["abcdef", "abcdef"], (1, 0)),
    (Four, (1, 2), "jVd", @["abcdef", "abcdef"], (1, 0)),
    (Four, (1, 2), "j<C-v>d", @["abcdef", "", "", "abcdef"], (1, 0)),
    (Four, (1, 2), "jvkd", @["abcdef"], (0, 0)),
    (Four, (1, 2), "jvjd", @["abcdef", "bcdef"], (1, 0)),
    (Four, (1, 2), "j<C-v>jd", @["abcdef", "bcdef", "bcdef", "bcdef"], (1, 0)),
    (Four, (1, 2), "jjjlvkkd", @["acdef"], (0, 1)),
    (Uneven, (1, 2), "j<C-v>d", @["abcdef", "efghij", "", "x"], (1, 0)),
    (Uneven, (1, 2), "jvd", @["abcdef", "x"], (1, 0)),
    (Uneven, (1, 2), "<C-v>jd", @["ef", "efghij", "", "x"], (0, 0)),
    (Six, (2, 4), "lvjjjd", @["af"], (0, 1)),
    (Six, (2, 4), "l<C-v>jjjd", @["aa", "bb", "cc", "dd", "ee", "ff"], (0, 1)),
    (Six, (2, 4), "jjvj<Esc>gvd", @["aaa", "bbb", "ff"], (2, 0)),
    (Six, (2, 4), "vjdj.", @["bb", "dd", "eee", "fff"], (1, 0)),
  ]:
    test keys & " with lines " & $(fold[0] + 1) & "-" & $(fold[1] + 1) & " folded":
      let e = newVimLikeEditor(lines, 0, 0)
      check e.activeBuffer.foldState.addFold(fold[0], fold[1], collapsed = true)
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

    test keys & " with lines " & $(fold[0] + 1) & "-" & $(fold[1] + 1) &
      " folded and a frame after each key":
      let e = newVimLikeEditor(lines, 0, 0)
      check e.activeBuffer.foldState.addFold(fold[0], fold[1], collapsed = true)
      e.pressWithFrames(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

  for (keys, want, wantCursor) in [
    ("lvjjy", "aa\nbbb\nccc\nddd\neee\n", (0, 1)),
    ("jjjjjvkky", "bbb\nccc\nddd\neee\nf", (1, 0)),
    ("jj<C-v>jy", "c\nd\ne\nf", (2, 0)),
  ]:
    test keys & " yanks the whole fold":
      let e = newVimLikeEditor(Six, 0, 0)
      check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
      e.press(keys)
      check e.state.registers.getNoNamedRegister().getContent() == want
      check e.cursorAt == wantCursor

  test "a selection gv brings back covers a fold closed since":
    let e = newVimLikeEditor(Six, 0, 0)
    e.press("vjj<Esc>")
    check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    e.press("gggvd")
    check e.lines == @["fff"]
    check e.cursorAt == (0, 0)

  test "a selection a command sets outside an input covers the fold":
    let e = newVimLikeEditor(Six, 0, 0)
    check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    e.asCommand:
      e.state.enterVisual(
        vskChar, BufferPosition(line: 0, column: 1), BufferPosition(line: 3, column: 1)
      )
    e.press("y")
    check e.state.registers.getNoNamedRegister().getContent() ==
      "aa\nbbb\nccc\nddd\neee\n"

  test "a command that raised leaves the selection uncovered":
    let e = newVimLikeEditor(Six, 0, 0)
    check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    expect ValueError:
      e.asCommand:
        e.state.enterVisual(
          vskChar,
          BufferPosition(line: 0, column: 1),
          BufferPosition(line: 3, column: 1),
        )
        raise newException(ValueError, "failed")
    check e.cursorAt == (3, 1)

  for (keys, want) in [
    ("y", @["aaa", "bbb", "ccc", "ddd", "eee", "fff"]), ("d", @["fff"])
  ]:
    test "an operator covers a fold closed outside a command: " & keys:
      let e = newVimLikeEditor(Six, 0, 0)
      e.press("vjj")
      check e.activeBuffer.foldState.addFold(2, 4, collapsed = true)
      e.press(keys)
      check e.lines == want
      if keys == "y":
        check e.state.registers.getNoNamedRegister().getContent() ==
          "aaa\nbbb\nccc\nddd\neee\n"

suite "A word motion over a closed fold, as in Vim":
  # Typed in Vim 9.2 (`vim -u NONE`, `set foldopen=`) a key at a time.
  const
    Five = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj"]
    Seven = @["aa bb", "cc dd", "ee ff", "gg hh", "ii jj", "kk ll", "mm nn"]
  for (lines, fold, keys, wantCursor) in [
    (Five, (1, 3), "jw", (4, 0)),
    (Five, (1, 3), "jb", (0, 3)),
    (Five, (1, 3), "je", (4, 1)),
    (Five, (1, 3), "jge", (0, 4)),
    (Five, (1, 3), "jW", (4, 0)),
    (Five, (1, 3), "jB", (0, 3)),
    (Five, (1, 3), "jE", (4, 1)),
    (Five, (1, 3), "jgE", (0, 4)),
    (Five, (1, 3), "vjw", (4, 0)),
    (Five, (1, 3), "vjb", (0, 3)),
    (Five, (1, 3), "vje", (4, 1)),
    (Five, (1, 3), "vjge", (3, 5)),
    (Five, (1, 3), "vjB", (0, 3)),
    (Five, (1, 3), "vjE", (4, 1)),
    (Five, (1, 3), "Gvkw", (4, 0)),
    (Five, (1, 3), "Gvkb", (0, 3)),
    (Five, (1, 3), "Gvke", (4, 1)),
    (Five, (1, 3), "Gvkge", (0, 4)),
    (Seven, (1, 2), "kj2w", (3, 3)),
    (Seven, (1, 2), "3w", (3, 0)),
    (Seven, (1, 2), "j2e", (3, 4)),
  ]:
    test keys & " with lines " & $(fold[0] + 1) & "-" & $(fold[1] + 1) & " folded":
      let e = newVimLikeEditor(lines, 0, 0)
      check e.activeBuffer.foldState.addFold(fold[0], fold[1], collapsed = true)
      e.press(keys)
      check e.cursorAt == wantCursor

  for (keys, want, wantCursor) in [
    ("jdw", @["aa bb", "gg hh", "ii jj", "kk ll", "mm nn"], (1, 0)),
    ("jcwX<Esc>", @["aa bb", "X", "gg hh", "ii jj", "kk ll", "mm nn"], (1, 0)),
    ("jdb", @["aa ", "cc dd", "ee ff", "gg hh", "ii jj", "kk ll", "mm nn"], (0, 2)),
  ]:
    test keys & " with lines 2-3 folded":
      let e = newVimLikeEditor(Seven, 0, 0)
      check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor
