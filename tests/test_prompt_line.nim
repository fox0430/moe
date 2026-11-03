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

## Tests for prompt_line.nim: the line every prompt edits. The results are
## Vim 9.2's getcmdline.

import std/[options, unittest]

import ../src/moepkg/[types, key_bindings, prompt_line]
from ../src/moepkg/unicode_utils import charLen

proc key(name: string): KeyCombo =
  parseKeyCombo(name).get

proc press(
    line: var PromptLine, history: seq[string], keys: varargs[string]
): LineEdit =
  ## `keys` as the prompt takes each, the last one's edit returned.
  for k in keys:
    discard line.takeKey(key(k), typed = true)
    result = line.edit(key(k), history)

proc typed(text: string): PromptLine =
  PromptLine(text: text, cursor: text.charLen)

# Newest first: "ab3" was run last.
const History = @["ab3", "ab2", "xy", "ab1"]

suite "prompt_line: history":
  test "Up goes to the entries that start with the text before the cursor":
    var line = typed("a")
    check line.press(History, "Up") == leRecalled
    check line.text == "ab3"
    check line.cursor == 3
    discard line.press(History, "Up", "Up")
    check line.text == "ab1"
    check line.entry == some(3)

  test "Up past the oldest match stays and beeps":
    var line = typed("a")
    discard line.press(History, "Up", "Up", "Up")
    check line.press(History, "Up") == leBeep
    check line.text == "ab1"

  test "Down past the newest puts back what Up looked for":
    var line = typed("a")
    discard line.press(History, "Up", "Up")
    check line.press(History, "Down") == leRecalled
    check line.text == "ab3"
    check line.press(History, "Down") == leRecalled
    check line.text == "a"
    check line.entry.isNone
    check line.press(History, "Down") == leBeep

  test "only the text before the cursor is looked for":
    var line = typed("ax")
    check line.press(History, "Left", "Up") == leRecalled
    check line.text == "ab3"
    discard line.press(History, "Down")
    check line.text == "a"

  test "an edit keeps the entry, and Up and Down go on from it":
    var line = typed("a")
    discard line.press(History, "Up", "Up", "Backspace")
    check line.text == "ab"
    check line.entry == some(1)
    check line.press(History, "Up") == leRecalled
    check line.text == "ab1"

    line = typed("a")
    discard line.press(History, "Up", "Up", "Backspace", "Down")
    check line.text == "ab3"

  test "Left and Right keep what Up looks for, Home does not":
    let h = @["ab3", "ac", "ab1"]
    var line = typed("a")
    discard line.press(h, "Up", "Left", "Right", "Up")
    check line.text == "ac"

    line = typed("a")
    discard line.press(@["ab3", "xy", "ab1"], "Up", "Home", "Up")
    check line.text == "xy"

    line = typed("a")
    discard line.press(@["ab3", "xy", "ab1"], "Up", "S-Left", "Up")
    check line.text == "xy"

  test "Shift-Up, PageUp and Ctrl-P go through every entry":
    for (up, down) in [("S-Up", "S-Down"), ("PageUp", "PageDown"), ("C-p", "C-n")]:
      checkpoint(up)
      var line = typed("a")
      discard line.press(History, up, up)
      check line.text == "ab2"
      discard line.press(History, down, down)
      check line.text == "a"

  test "nowhere to go beeps":
    var line = typed("")
    check line.press(@[], "Up") == leBeep
    line = typed("z")
    check line.press(History, "Up") == leBeep
    check line.text == "z"
    line = typed("")
    check line.press(History, "Down") == leBeep

  test "an entry the history has lost since is not read":
    var line = typed("")
    discard line.press(History, "Up", "Up", "Up")
    check line.entry == some(2)
    check line.press(@["ab3"], "Down") == leBeep
    check line.entry.isNone
    check line.press(@["ab3"], "Up") == leRecalled
    check line.text == "ab3"

suite "prompt_line: moving":
  test "Shift-Left and Ctrl-Left go to just after a space":
    var line = typed("ab cd  ef")
    for want in [7, 6, 3, 0]:
      discard line.press(@[], "S-Left")
      check line.cursor == want
    check line.press(@[], "C-Left") == leStill

  test "Shift-Right and Ctrl-Right go to a space or the end":
    var line = PromptLine(text: "ab cd  ef")
    for want in [2, 5, 6, 9]:
      discard line.press(@[], "C-Right")
      check line.cursor == want
    check line.press(@[], "S-Right") == leStill

  test "words of wide characters":
    var line = typed("あい うえ")
    line.cursor = 5
    discard line.press(@[], "S-Left")
    check line.cursor == 3
    line.cursor = 0
    discard line.press(@[], "S-Right")
    check line.cursor == 2

  test "Home, End, Ctrl-B and Ctrl-E move even to where the cursor is":
    var line = typed("abc")
    check line.press(@[], "C-b") == leMoved
    check line.cursor == 0
    check line.press(@[], "Home") == leMoved
    check line.press(@[], "C-b") == leMoved
    check line.press(@[], "Left") == leStill
    check line.press(@[], "C-e") == leMoved
    check line.cursor == 3
    check line.press(@[], "End") == leMoved
    check line.press(@[], "C-e") == leMoved
    check line.press(@[], "Right") == leStill

suite "prompt_line: editing":
  test "a character goes in at the cursor":
    var line = typed("ac")
    check line.press(@[], "Left", "b") == leTyped
    check line.text == "abc"
    check line.cursor == 2

  test "an erase on an empty line is told apart":
    var line = typed("")
    check line.press(@[], "Backspace") == leEmptyErase
    line = typed("a")
    discard line.press(@[], "Home")
    check line.press(@[], "Backspace") == leStill
    check line.press(@[], "Delete") == leErased
    check line.text == ""

  test "a paste puts its first line in and ends what Up looks for":
    var line = typed("a")
    discard line.press(History, "Up")
    check line.insertPasted("x\r\ny")
    check line.text == "ab3x"
    check line.lookfor.isNone
    check not line.insertPasted("\nz")

  test "a key with a modifier the line does not take is left alone":
    var line = typed("a")
    check line.press(@[], "C-x") == leNone
    check line.text == "a"
