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

## `q` while recording or running a register, as in Vim: a running register
## cannot start or stop a recording, a mapping can, after an operator it only
## cancels the operator, and the typed key that stops a recording is not kept
## in the register.

import std/[unittest, options, tables]

import
  ../src/moepkg/
    [types, editor, handler, buffer, config, key_bindings, keybind_config, registers]

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  # Keep deletes away from the system clipboard.
  result.state.registers = initRegisters()
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.syncActiveWindow()
  result.state.mode = EditorMode.Normal

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

proc macroState(e: Editor): var MacroState =
  e.state.pendingInput.macroState

suite "q in a running register":
  test "is ignored and takes no register":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["q", "i", "y", "<Escape>"]

    e.press("@", "b")

    check e.activeBuffer.getLine(0) == "yabc"
    check not e.macroState.isRecording

  test "does not stop the recording":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["q", "x"]

    e.press("q", "a", "@", "b")
    check e.activeBuffer.getLine(0) == "bc"
    check e.macroState.isRecording

    e.press("q")
    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["@", "b"]
    check e.macroState.executingDepth == 0

  test "uses up the count before it while recording":
    let e = newTestEditor("abcd")
    e.macroState.registers['b'] = @["3", "q", "x"]

    e.press("q", "a", "@", "b")

    check e.activeBuffer.getLine(0) == "bcd"
    check e.macroState.isRecording

suite "q from a mapping":
  test "starts a recording":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "qz"
    )

    e.press(",")

    check e.macroState.isRecording
    check e.macroState.register == 'z'

  test "stops the recording and leaves the mapping key out of the register":
    let e = newTestEditor("abc")
    # A key sequence: a bare "q" would name the :q command.
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "q"
    )

    e.press("q", "a", "x", ",")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x"]
    check e.activeBuffer.getLine(0) == "bc"

suite "Recording":
  test "keys replayed from a register are not recorded":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["x"]

    e.press("q", "a", "@", "b")

    check e.activeBuffer.getLine(0) == "bc"
    check e.macroState.isRecording
    check e.macroState.recordedKeys == @["@", "b"]

  test "keys replayed from a mapping are not recorded":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "x"
    )

    e.press("q", "a", ",")

    check e.activeBuffer.getLine(0) == "bc"
    check e.macroState.recordedKeys == @[","]

  test "overlay keys replayed from a register are not recorded":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["/", "c", "<Enter>"]

    e.press("q", "a", "@", "b")

    check e.state.cursor.column == 2
    check e.macroState.recordedKeys == @["@", "b"]

  test "q typed as an operand is kept":
    let e = newTestEditor("aqb")
    e.press("q", "a", "f", "q", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["f", "q"]
    check e.state.cursor.column == 1

  test "stopping with <C-o>q in Insert mode drops the <C-o>":
    let e = newTestEditor("abc")
    e.press("q", "a", "i", "f", "o", "o", "C-o", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["i", "f", "o", "o"]
    check e.state.mode == EditorMode.Insert

  test "<C-o> before another command is kept":
    let e = newTestEditor("abc")
    e.press("q", "a", "i", "C-o", "l", "Escape", "q")

    check e.macroState.registers['a'] == @["i", "<C-o>", "l", "<Escape>"]

  test "stopping with Ctrl-O read as <C-O> drops it too":
    let e = newTestEditor("abc")
    e.press("q", "a", "i", "f", "o", "o", "C-O", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["i", "f", "o", "o"]

  test "a count before the stopping q is kept":
    let e = newTestEditor("abc")
    e.press("q", "a", "x", "3", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x", "3"]

suite "q after an operator":
  test "cancels the operator and keeps recording":
    let e = newTestEditor("abc def")
    e.press("q", "a", "x", "d", "q", "w")

    check e.macroState.isRecording
    check e.activeBuffer.getLine(0) == "bc def"
    check e.state.cursor.column == 3

    e.press("q")
    check e.macroState.registers['a'] == @["x", "d", "q", "w"]

  test "drops the register named for the operator":
    let e = newTestEditor("abc def")
    e.press("\"", "b", "d", "q", "x")

    check e.state.pendingInput.pendingRegister.isNone
    check e.state.registers.getNamedRegister('b').buffer.len == 0
    check e.activeBuffer.getLine(0) == "bc def"

  test "cancels the operator in a running register":
    let e = newTestEditor("abc def")
    e.macroState.registers['b'] = @["d", "q", "w"]

    e.press("@", "b")

    check e.activeBuffer.getLine(0) == "abc def"
    check e.state.pendingInput.pendingOperator.isNone

  test "takes no register outside a recording":
    let e = newTestEditor("abc")
    e.press("d", "q", "a")

    check not e.macroState.isRecording
    check e.state.mode == EditorMode.Insert

  test "keeps recording after a text object operator":
    let e = newTestEditor("abc")
    e.press("q", "a", "c", "i", "q", "x")

    check e.macroState.isRecording
    check e.activeBuffer.getLine(0) == "bc"
