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

## What `.` does again after a Visual operator: the same operator over an area
## as big at the cursor, as Vim's redo_VIsual.

import std/unittest

import pkg/results

import ../src/moepkg/[buffer, types, editor, motion, command_registry]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    check e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

suite "`.` acts again over a Visual area as big at the cursor, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`).
  const
    Letters = @["a", "b", "c", "d", "e"]
    Two = @["abcdef", "abcdef"]
    Four = @["abcdef", "abcdef", "abcdef", "abcdef"]
  for (lines, cursor, keys, want, wantCursor) in [
    (Letters, (0, 0), "Vjd.", @["e"], (0, 0)),
    (Letters, (3, 0), "Vjdk.", @["a"], (0, 0)),
    (Letters, (0, 0), "Vjd2.", @["e"], (0, 0)),
    (Letters, (0, 0), "Vjd.u", @["c", "d", "e"], (0, 0)),
    (Letters, (0, 0), "Vj>j.", @["\ta", "\t\tb", "\tc", "d", "e"], (1, 2)),
    (
      Letters,
      (0, 0),
      "Vj3>j.",
      @["\t\t\ta", "\t\t\t\t\t\tb", "\t\t\tc", "d", "e"],
      (1, 6),
    ),
    (
      Letters,
      (0, 0),
      "Vj3>j2.",
      @["\t\t\ta", "\t\t\t\t\t\tb", "\t\t\tc", "d", "e"],
      (1, 6),
    ),
    (
      @["\t\t\ta", "\t\t\tb", "\t\t\tc"],
      (0, 0),
      "Vj<j.",
      @["\t\ta", "\tb", "\t\tc"],
      (1, 1),
    ),
    (@["\t\t\ta", "\t\t\tb", "\t\t\tc"], (0, 0), "Vj2<j.", @["\ta", "b", "\tc"], (1, 0)),
    (Two, (0, 0), "vl~j0.", @["ABcdef", "ABcdef"], (1, 0)),
    (Two, (0, 0), "vlUj0.", @["ABcdef", "ABcdef"], (1, 0)),
    (@["ABCDEF", "ABCDEF"], (0, 0), "vluj0.", @["abCDEF", "abCDEF"], (1, 0)),
    (Two, (0, 0), "vldj0.", @["cdef", "cdef"], (1, 0)),
    (@["abcdef", "ab", "x"], (0, 0), "vlllldj0.", @["f", "x"], (1, 0)),
    (@["a\tbc", "abcdefghij"], (0, 0), "vlldj0.", @["c", "j"], (1, 0)),
    (Letters, (0, 0), "Vjdu", Letters, (0, 0)),
    (Letters, (0, 0), "jVkdu", Letters, (0, 0)),
    (Letters, (0, 0), "Vj>", @["\ta", "\tb", "c", "d", "e"], (0, 1)),
    (Two, (0, 1), "vjl~u", Two, (0, 1)),
    (Two, (1, 3), "vkh~u", Two, (0, 2)),
    (Two, (0, 1), "<C-v>jlUu", Two, (0, 1)),
    (Two, (1, 3), "<C-v>khUu", Two, (0, 2)),
    (Letters, (0, 0), "Vj>u", Letters, (0, 0)),
    (Four, (1, 2), "<C-v>jl>u", Four, (1, 2)),
    (Four, (2, 3), "<C-v>kh>u", Four, (1, 2)),
    (@["abcdef", "ghi"], (0, 3), "vjJu", @["abcdef", "ghi"], (0, 3)),
    (@["abcdef", "ghi"], (1, 1), "vkJu", @["abcdef", "ghi"], (0, 1)),
    (@["abcdef", "ghijkl"], (0, 3), "<C-v>jlJu", @["abcdef", "ghijkl"], (0, 3)),
    (@["abcdef", "ghi", "x"], (0, 3), "VjJu", @["abcdef", "ghi", "x"], (0, 0)),
    (
      @["abcdef", "ghijkl", "mnopqr", "stuvwx"],
      (0, 2),
      "vjdj.",
      @["abjkl", "mnvwx"],
      (1, 2),
    ),
    (Four, (0, 0), "<C-v>jldjj0.", @["cdef", "cdef", "cdef", "cdef"], (2, 0)),
    (Four, (0, 0), "<C-v>j$djj0.", @["", "", "", ""], (2, 0)),
    (Four, (0, 1), "<C-v>jl~jj0.", @["aBCdef", "aBCdef", "ABcdef", "ABcdef"], (2, 0)),
    (Two, (0, 0), "xvly.", @["cdef", "abcdef"], (0, 0)),
    (
      @["abcdef", "abcdef", "abcdef"],
      (0, 0),
      "vl\"adj0.j\"ap",
      @["cdef", "cdef", "aabbcdef"],
      (2, 2),
    ),
  ]:
    test keys:
      let e = newVimLikeEditor(lines, cursor[0], cursor[1])
      e.press(keys)
      check e.state.mode == EditorMode.Normal
      check e.lines == want
      check e.cursorAt == wantCursor

  test "a refused `.` fails":
    let e = newVimLikeEditor(Two, 0, 0)
    e.press("vl~j0")
    e.activeBuffer.readOnly = true
    let ctx = CommandContext(
      buffer: e.activeBuffer, state: e.state, motionController: MotionController()
    )
    check e.commandRegistry.execute(ctx, custom("edit.repeat"), @[]).isErr
    check e.lines == @["ABcdef", "abcdef"]

  test "a refused operator leaves what `.` repeats":
    let e = newVimLikeEditor(@["abcdef", "abcdef"], 0, 0)
    e.press("x")
    e.activeBuffer.readOnly = true
    e.press("vl~")
    e.activeBuffer.readOnly = false
    e.press("j0.")
    check e.lines == @["bcdef", "bcdef"]

  # Vim leaves the cursor where the lines were joined, moe on the line's start.
  for (lines, keys, want) in [
    (Letters, "VjJj.", @["a b", "c d", "e"]),
    (Letters, "VjjJj.", @["a b c", "d e"]),
    (@["ab", "cd", "ef", "gh"], "VJj.", @["ab cd", "ef gh"]),
    (@["abc", "def", "ghi", "jkl"], "vjJj.", @["abc def", "ghi jkl"]),
  ]:
    test keys:
      let e = newVimLikeEditor(lines, 0, 0)
      e.press(keys)
      check e.lines == want

  for (keys, wantCursor) in [("VJ", (1, 0)), ("vhJ", (1, 1))]:
    test keys & " on the last line leaves the cursor where the area starts":
      let e = newVimLikeEditor(@["abc", "def"], 1, 2)
      e.press(keys)
      check e.state.mode == EditorMode.Normal
      check e.lines == @["abc", "def"]
      check e.cursorAt == wantCursor

  test "a closed fold is not covered whole":
    let e = newVimLikeEditor(@["abcdef", "abcdef", "abcdef", "abcdef", "abcdef"], 0, 0)
    e.press("vld")
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.press("j0.")
    check e.lines == @["cdef", "cdef", "abcdef", "abcdef", "abcdef"]
