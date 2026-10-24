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

## Tests for Ctrl-A / Ctrl-X in the Visual modes.

import std/[unittest, options, deques, tables]

import ../src/moepkg/[buffer, types, modes, editor, config, key_bindings, handler]
import visual_test_helper

proc pos(line, column: int): BufferPosition =
  BufferPosition(line: line, column: column)

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftCell: 0)
  result.syncActiveWindow()
  result.state.mode = EditorMode.Normal

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

proc lines(e: Editor): seq[string] =
  for i in 0 ..< e.activeBuffer.len:
    result.add e.activeBuffer.getLine(i)

suite "Visual Ctrl-A / Ctrl-X":
  test "leaves Visual so a shorter number does not join lines":
    let e = newTestEditor("foo -10\nbar")
    e.press("$", "v", "0", "C-a")

    check e.lines == @["foo -9", "bar"]
    check e.state.mode == EditorMode.Normal
    check e.cursor == pos(0, 0)

    e.press("d", "d")
    check e.lines == @["bar"]

  test "linewise changes the first number on every line":
    let e = newTestEditor("1\nx 2 3\nnone\n4")
    e.press("V", "G", "C-a")

    check e.lines == @["2", "x 3 3", "none", "5"]
    check e.state.mode == EditorMode.Normal
    check e.cursor == pos(0, 0)

  test "the cursor goes to the start even when the selection was made upward":
    let e = newTestEditor("a 1\nb 2\nc 3")
    e.press("G", "$", "V", "g", "g", "C-x")

    check e.lines == @["a 0", "b 1", "c 2"]
    check e.cursor == pos(0, 0)

  test "count is added to each number":
    let e = newTestEditor("1\n2\n3")
    e.press("V", "j", "j", "5", "C-a")

    check e.lines == @["6", "7", "8"]

  test "count with Ctrl-X":
    let e = newTestEditor("10\n20")
    e.press("V", "j", "3", "C-x")

    check e.lines == @["7", "17"]

  test "charwise uses only the selected digits":
    let e = newTestEditor("a 123 b")
    e.press("l", "l", "v", "C-a")

    check e.lines == @["a 223 b"]
    check e.cursor == pos(0, 2)

  test "charwise ignores a minus outside the selection":
    let e = newTestEditor("foo -10")
    e.press("$", "h", "v", "l", "C-a")

    check e.lines == @["foo -11"]

  test "charwise limits the first line to the start and the last to the end":
    let e = newTestEditor("x 1 y 2\nz 3 w 4")
    e.press("w", "w", "v", "j", "C-a")

    check e.lines == @["x 1 y 3", "z 4 w 4"]
    check e.cursor == pos(0, 4)

  test "blockwise uses the selected columns":
    let e = newTestEditor("ab 1 2\ncd 3 4\nef 5 6")
    e.press("w", "C-v", "j", "j", "C-a")

    check e.lines == @["ab 2 2", "cd 4 4", "ef 6 6"]
    check e.state.mode == EditorMode.Normal
    check e.cursor == pos(0, 3)

  test "blockwise takes the characters inside the block's screen cells":
    # The block covers cell 2 only, which is a blank on the second line.
    let e = newTestEditor("あ1\na1 2")
    e.press("l", "C-v", "j", "C-a")

    check e.lines == @["あ2", "a1 2"]
    check e.cursor == pos(0, 1)

  test "the change is one undo step":
    let e = newTestEditor("1\n2")
    e.press("V", "j", "C-a")
    check e.lines == @["2", "3"]

    e.press("u")
    check e.lines == @["1", "2"]

  test "no number leaves Visual without changes":
    let e = newTestEditor("a\nb")
    e.press("V", "j", "C-a")

    check e.lines == @["a", "b"]
    check e.state.mode == EditorMode.Normal

  test "gv reselects the area afterwards":
    let e = newTestEditor("1\n2\n3")
    e.press("j", "V", "j", "C-a", "g", "g", "g", "v")

    check e.lines == @["1", "3", "4"]
    check e.state.mode == EditorMode.VisualLine
    check e.state.visualSelection.start == pos(1, 0)

  test "the largest number wraps around to negative, as Vim":
    let e = newTestEditor($high(uint64) & "\n1")
    e.press("V", "C-a")

    check e.lines == @["-" & $high(uint64), "1"]

suite "Visual g Ctrl-A / g Ctrl-X":
  test "adds one more on each line":
    let e = newTestEditor("1\n1\n1")
    e.press("V", "j", "j", "g", "C-a")

    check e.lines == @["2", "3", "4"]
    check e.state.mode == EditorMode.Normal
    check e.cursor == pos(0, 0)

  test "count sets the step":
    let e = newTestEditor("1\n1\n1")
    e.press("V", "j", "j", "2", "g", "C-a")

    check e.lines == @["3", "5", "7"]

  test "g Ctrl-X subtracts the growing amount":
    let e = newTestEditor("10\n10\n10")
    e.press("V", "j", "j", "3", "g", "C-x")

    check e.lines == @["7", "4", "1"]

  test "numbers a zero-padded list keeping its width":
    let e = newTestEditor("item 00\nitem 00\nitem 00")
    e.press("V", "j", "j", "g", "C-a")

    check e.lines == @["item 01", "item 02", "item 03"]

  test "a line without a number does not advance the amount":
    let e = newTestEditor("1\na\n1")
    e.press("V", "j", "j", "g", "C-a")

    check e.lines == @["2", "a", "3"]

  test "charwise limits the first line to the start and the last to the end":
    let e = newTestEditor("a 1 b 1\n1 1\nc 1 d 1")
    e.press("w", "w", "v", "j", "j", "g", "C-a")

    check e.lines == @["a 1 b 2", "3 1", "c 4 d 1"]
    check e.cursor == pos(0, 4)

  test "blockwise":
    let e = newTestEditor("x 0 0\ny 0 0")
    e.press("w", "C-v", "j", "g", "C-a")

    check e.lines == @["x 1 0", "y 2 0"]
    check e.cursor == pos(0, 2)

  test "the change is one undo step":
    let e = newTestEditor("1\n1")
    e.press("V", "j", "g", "C-a", "u")

    check e.lines == @["1", "1"]

suite "Visual increment on a read-only buffer":
  test "every increment command leaves the buffer alone":
    for keys in [@["C-a"], @["C-x"], @["g", "C-a"], @["g", "C-x"]]:
      let e = newTestEditor("1\n1")
      e.activeBuffer.readOnly = true
      e.press("V", "j")
      e.press(keys)

      check e.lines == @["1", "1"]
      check e.state.statusMessage == "Buffer is read-only"
      check e.state.mode == EditorMode.Normal

suite "Normal Ctrl-A / Ctrl-X keys":
  test "a mapping with its own amount keeps it under a count":
    let e = newTestEditor("1 1")
    var cmd = e.keyBindingRegistry.commandRegistry["increment-number"]
    cmd.args = @["10"]
    check e.keyBindingRegistry.setRuntimeCommandMapping(
      EditorMode.Normal, "X", "increment-number 10", cmd
    ) == ""
    e.press("3", "X")

    check e.lines == @["11 1"]

  test "count reaches the command":
    let e = newTestEditor("1 1")
    e.press("5", "C-a")
    check e.lines == @["6 1"]

    e.press("3", "C-x")
    check e.lines == @["3 1"]

  test "undo puts the cursor back where Ctrl-A was typed":
    let e = newTestEditor("x 9 y")
    e.press("l", "C-a", "u")

    check e.lines == @["x 9 y"]
    check e.cursor == pos(0, 1)

  test "the cursor ends on the last digit":
    let e = newTestEditor("x 9 y")
    e.press("C-a")

    check e.lines == @["x 10 y"]
    check e.cursor == pos(0, 3)

suite "Repeating Ctrl-A / Ctrl-X with .":
  test "Normal mode repeats the same amount":
    let e = newTestEditor("1 1")
    e.press("5", "C-a", ".")
    check e.lines == @["11 1"]

    let e2 = newTestEditor("1 1")
    e2.press("5", "C-a", "w", ".")
    check e2.lines == @["6 6"]

  test "a Ctrl-A that finds no number is still what . repeats":
    let e = newTestEditor("ab\nxy 1")
    e.press("x", "C-a", "j", ".")

    check e.lines == @["b", "xy 2"]

  test "a count given to . replaces the amount, and the next . keeps it":
    let e = newTestEditor("1 1")
    e.press("5", "C-a", "2", ".")
    check e.lines == @["8 1"]

    e.press(".")
    check e.lines == @["10 1"]

    let e2 = newTestEditor("1 1")
    e2.press("5", "C-x", "2", ".")
    check e2.lines == @["-6 1"]

  test "linewise repeats over as many lines from the cursor":
    let e = newTestEditor("1\n1\n1\n1")
    e.press("V", "j", "5", "C-a", "j", "j", ".")

    check e.lines == @["6", "6", "6", "6"]
    check e.cursor == pos(2, 0)

  test "a count given to . is ignored, as Vim's Visual repeats":
    let e = newTestEditor("1\n1\n1\n1")
    e.press("V", "j", "5", "C-a", "j", "j", "3", ".")

    check e.lines == @["6", "6", "6", "6"]

  test "progressive restarts the amount on the repeated area":
    let e = newTestEditor("1\n1\n1\n1")
    e.press("V", "j", "g", "C-a", "j", "j", ".")

    check e.lines == @["2", "3", "2", "3"]

  test "single-line charwise repeats as many characters":
    let e = newTestEditor("12 34 56")
    e.press("v", "l", "C-a", "w", ".")

    check e.lines == @["13 35 56"]

  test "multi-line charwise ends the last line at the recorded column":
    let e = newTestEditor("x 1 y 1\n1 1\n1 1\n1 1")
    e.press("w", "w", "v", "j", "C-a", "j", "j", ".")

    check e.lines == @["x 1 y 2", "2 1", "1 2", "2 1"]
    check e.cursor == pos(2, 2)

  test "blockwise repeats the block size":
    let e = newTestEditor("ab 1 2\ncd 3 4")
    e.press("w", "C-v", "j", "C-a", "w", ".")

    check e.lines == @["ab 2 3", "cd 4 5"]

  test "an area running past the last line is cut off":
    let e = newTestEditor("a\n1")
    e.press("V", "j", "C-a", "j", ".")

    check e.lines == @["a", "3"]

  test "the repeat is one undo step":
    let e = newTestEditor("1\n1")
    e.press("V", "j", "C-a", ".", "u")

    check e.lines == @["2", "2"]

  test "an area cut to the last line runs back to the recorded column":
    let e = newTestEditor("1\n1\nx 1 1")
    e.press("v", "j", "C-a", "G", "$", ".")

    check e.lines == @["2", "2", "x 2 1"]
    check e.cursor == pos(2, 0)
