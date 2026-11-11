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

## Searches that land on an empty line or an empty match, and regex matches
## that do not overlap, as Vim's searchit with 'cpoptions' c.

import std/unittest

import ../src/moepkg/[types, editor]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    discard e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

suite "A search goes through empty lines and empty matches, as in Vim":
  # Measured in Vim 9.2 (`vim -Nu NONE -es`, `:normal`).
  const Blanks = @["foo", "", "bar", "", "baz"]
  for (lines, cursor, keys, wantLines, wantCursor) in [
    (Blanks, (0, 1), "/^$<Enter>", Blanks, (1, 0)),
    (Blanks, (0, 1), "/^$<Enter>n", Blanks, (3, 0)),
    (Blanks, (0, 1), "/^$<Enter>nn", Blanks, (1, 0)),
    (Blanks, (0, 1), "/^$<Enter>N", Blanks, (3, 0)),
    (Blanks, (4, 2), "?^$<Enter>", Blanks, (3, 0)),
    (Blanks, (4, 2), "?^$<Enter>n", Blanks, (1, 0)),
    (Blanks, (0, 2), "/^\\s*$<Enter>", Blanks, (1, 0)),
    (Blanks, (0, 0), "d/^$<Enter>", @["", "bar", "", "baz"], (0, 0)),
    (Blanks, (0, 1), "/^$<Enter>dn", @["foo", "", "baz"], (1, 0)),
    (Blanks, (0, 1), "/^$<Enter>dgn", @["foo", "bar", "", "baz"], (1, 0)),
    (Blanks, (0, 1), "/^$<Enter>gnd", @["foo", "bar", "", "baz"], (1, 0)),
    (@["foo", "", "bar"], (1, 0), "/^$<Enter>", @["foo", "", "bar"], (1, 0)),
    (@["foo", "", "bar"], (1, 0), "?^$<Enter>", @["foo", "", "bar"], (1, 0)),
    (@["ab", "", "cd"], (0, 1), "/x*<Enter>", @["ab", "", "cd"], (1, 0)),
    (@["abc", "de"], (0, 1), "/$<Enter>", @["abc", "de"], (0, 2)),
    (@["abc", "de"], (0, 2), "/$<Enter>", @["abc", "de"], (1, 1)),
    (@["aaaa", "aaaa"], (0, 0), "/aa<Enter>", @["aaaa", "aaaa"], (0, 2)),
    (@["aaaa", "aaaa"], (0, 0), "/aa<Enter>n", @["aaaa", "aaaa"], (1, 0)),
    (@["aaa", "aaa"], (0, 0), "/aa<Enter>", @["aaa", "aaa"], (1, 0)),
    # A match at the end of a line puts the cursor on the last character,
    # with an operator waiting too, but in Visual mode (normal_search's
    # check_cursor).
    (@["abc", "de"], (0, 0), "d/$<Enter>", @["c", "de"], (0, 0)),
    (@["abc", "de"], (0, 1), "d/$<Enter>", @["ac", "de"], (0, 1)),
    (@["abc", "de"], (0, 1), "/$<Enter>ggdn", @["c", "de"], (0, 0)),
    (@["abc", "de"], (0, 0), "v/$<Enter>d", @["de"], (0, 0)),
    # Nor after Ctrl-o in Insert mode, as check_cursor with restart_edit.
    (@["abc", "de"], (0, 0), "i<C-o>/$<Enter>x<Escape>", @["abcx", "de"], (0, 3)),
    (@["abc", "de"], (0, 0), "i<C-o>d/$<Enter>X<Escape>", @["X", "de"], (0, 0)),
    (@["abc", "de"], (0, 0), "/$<Enter>0i<C-o>nY<Escape>", @["abcY", "de"], (0, 3)),
    # gn and gN take the match the cursor went to.
    (@["abc", "de"], (0, 0), "/$<Enter>dgn", @["abcde"], (0, 3)),
    (@["xy", "abc", "de"], (1, 0), "/$<Enter>dgn", @["xy", "abcde"], (1, 3)),
    (@["abc", "de", "fg"], (1, 0), "/$<Enter>gNd", @["abc", "defg"], (1, 2)),
    # The character under the cursor takes its composing characters with it
    # (searchit's extra_col).
    (@["ae\u0301", "x"], (0, 1), "/$<Enter>", @["ae\u0301", "x"], (1, 0)),
    (@["ae\u0301", "x"], (0, 1), "/$<Enter>kldgn", @["ae\u0301x"], (0, 3)),
    (@["ae\u0301", "x"], (0, 1), "/$<Enter>kdgn", @["ae\u0301x"], (0, 3)),
  ]:
    test keys & " from " & $cursor & " in " & $lines:
      let e = newVimLikeEditor(lines, cursor[0], cursor[1])
      e.press(keys)
      check e.lines == wantLines
      check e.cursorAt == wantCursor
