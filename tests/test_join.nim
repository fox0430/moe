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

## Where J leaves the cursor: at the last join, as Vim's do_join.

import std/[unittest, sequtils, tables]

import pkg/results

import ../src/moepkg/[types, editor, buffer, motion, command_registry]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    discard e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

suite "J leaves the cursor at the last join, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`), typed.
  const Four = @["aa", "bb", "cc", "dd"]
  for (lines, cursor, keys, want, wantCursor) in [
    (@["aa bb", "cc dd"], (0, 0), "J", @["aa bb cc dd"], (0, 5)),
    (@["aa bb", "cc dd"], (0, 3), "J", @["aa bb cc dd"], (0, 5)),
    (Four, (0, 0), "3J", @["aa bb cc", "dd"], (0, 5)),
    (Four, (0, 0), "4J", @["aa bb cc dd"], (0, 8)),
    (@["aa", "   bb"], (0, 0), "J", @["aa bb"], (0, 2)),
    (@["aa", "\tbb"], (0, 0), "J", @["aa bb"], (0, 2)),
    (@["aa", "  )bb"], (0, 0), "J", @["aa)bb"], (0, 2)),
    (@["aa", "   "], (0, 0), "J", @["aa"], (0, 1)),
    (@["", "bb"], (0, 0), "J", @["bb"], (0, 0)),
    (@["", ""], (0, 0), "J", @[""], (0, 0)),
    (@["aa", "", "cc"], (0, 0), "3J", @["aa cc"], (0, 2)),
    (@["aa", "bb"], (0, 0), "5J", @["aa bb"], (0, 2)),
    (@["aa", "bb", "cc"], (1, 0), "9J", @["aa", "bb cc"], (1, 2)),
    (
      @["a", "b", "c", "d", "e", "f", "g"],
      (4, 0),
      "9Jgg.",
      @["a b c", "d", "e f g"],
      (0, 3),
    ),
    (
      @["a", "b", "c", "d", "e", "f", "g"],
      (5, 0),
      "9Jgg.",
      @["a b", "c", "d", "e", "f g"],
      (0, 1),
    ),
    (@["a", "b", "c", "d"], (3, 0), "3Jgg.", @["a b", "c", "d"], (0, 1)),
    (@["abc", "xxx", "last"], (2, 2), "3J", @["abc", "xxx", "last"], (2, 0)),
    (@["\u3000", "bb"], (0, 0), "J", @["\u3000 bb"], (0, 1)),
    (@["aa\u3000", "bb"], (0, 0), "J", @["aa\u3000 bb"], (0, 3)),
    (@["aa", "\u3000bb"], (0, 0), "J", @["aa \u3000bb"], (0, 2)),
    (@["aa\u00a0", "bb"], (0, 0), "J", @["aa\u00a0 bb"], (0, 3)),
    (@["aa", "bb"], (1, 0), "J", @["aa", "bb"], (1, 0)),
    (@["aa\tbb", "cc"], (0, 0), "J", @["aa\tbb cc"], (0, 5)),
    (@["aa ", "bb"], (0, 0), "J", @["aa bb"], (0, 3)),
    (@["aa ", "  bb"], (0, 0), "J", @["aa bb"], (0, 3)),
    (@["aa ", "bb ", "cc"], (0, 0), "3J", @["aa bb cc"], (0, 6)),
    (@["あい", "うえ"], (0, 0), "J", @["あい うえ"], (0, 2)),
    (@["あい", "うえ", "お"], (0, 0), "3J", @["あい うえ お"], (0, 5)),
    (@["aa", "bb", "cccccc"], (0, 0), "Jj", @["aa bb", "cccccc"], (1, 2)),
    (@["aa bb", "cc", "dd", "ee"], (0, 3), "J.", @["aa bb cc dd", "ee"], (0, 8)),
    (
      @["a", "b", "c", "d", "e", "f", "g"],
      (0, 0),
      "Jj3.",
      @["a b", "c d e", "f", "g"],
      (1, 3),
    ),
    (
      @["a", "b", "c", "d", "e", "f", "g"],
      (0, 0),
      "3Jj.",
      @["a b c", "d e f", "g"],
      (1, 3),
    ),
    (@["aa bb", "cc"], (0, 3), "Ju", @["aa bb", "cc"], (0, 3)),
    (@["aa bb", "cc", "dd", "ee"], (0, 3), "JjJu", @["aa bb cc", "dd", "ee"], (1, 1)),
    (Four, (0, 0), "VjjJ", @["aa bb cc", "dd"], (0, 5)),
    (Four, (1, 0), "VkJ", @["aa bb", "cc", "dd"], (0, 2)),
    (Four, (0, 0), "vJ", @["aa bb", "cc", "dd"], (0, 2)),
    (Four, (0, 0), "Vj<C-v>J", @["aa bb", "cc", "dd"], (0, 2)),
    (@["aa", "bb", "cccccc"], (0, 0), "VjJj", @["aa bb", "cccccc"], (1, 2)),
  ]:
    test keys & " on " & $lines:
      let e = newVimLikeEditor(lines, cursor[0], cursor[1])
      e.press(keys)
      check e.state.mode == EditorMode.Normal
      check e.lines == want
      check e.cursorAt == wantCursor

  test "J shows no message":
    let e = newVimLikeEditor(Four, 0, 0)
    e.state.statusMessage = ""
    e.press("3J")
    check e.state.statusMessage == ""
    e.press("jVkJ")
    check e.state.statusMessage == ""

  test "J on a closed fold joins from the cursor line":
    for (cursor, keys, want, wantCursor) in [
      ((2, 0), "J", @["a", "b", "c d", "e"], (2, 1)),
      ((1, 0), "3J", @["a", "b c d", "e"], (1, 3)),
    ]:
      let e = newVimLikeEditor(@["a", "b", "c", "d", "e"], cursor[0], cursor[1])
      check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

  test "J after trailing blanks leaves the cursor on the joined text":
    # Unlike Vim, J trims them to one space; Vim's cursor goes to the text
    # after them, which this keeps.
    for (lines, want, wantCursor) in [
      (@["aa\t", "bb"], @["aa bb"], (0, 3)), (@["   ", "bb"], @["bb"], (0, 0))
    ]:
      let e = newVimLikeEditor(lines, 0, 0)
      e.press("J")
      check e.lines == want
      check e.cursorAt == wantCursor

  test "a count of three or more on the last line does not stop a macro":
    # Vim's nv_join fails only for a count below three.
    for (keys, want) in [("3J", @["", "b", "c"]), ("2J", @["a", "b", "c"])]:
      let e = newVimLikeEditor(@["a", "b", "c"], 0, 0)
      e.state.pendingInput.macroState.registers['q'] =
        @["G"] & keys.toSeq.mapIt($it) & @["g", "g", "x"]
      e.press("@q")
      check e.lines == want

  test "a count cut to the last line still fails on a buffer that cannot change":
    # Vim's do_join gives E21 when 'modifiable' is off.
    let e = newVimLikeEditor(@["a", "b", "c"], 2, 0)
    e.activeBuffer.readOnly = true
    let ctx = CommandContext(
      buffer: e.activeBuffer, state: e.state, motionController: MotionController()
    )
    check e.commandRegistry.execute(ctx, custom("join.lines"), @["3"]).isErr
