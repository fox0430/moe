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
  ../src/moepkg/[
    types, editor, handler, buffer, config, key_bindings, keybind_config, registers,
    editor_display, macro_recording,
  ]
import ../src/moepkg/command_handlers/[result_processor, handler_result]

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
    check e.macroState.recordingRegister == some('z')

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

  test "a mapping with a longer left-hand side drops all of it":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",m", "q"
    )

    e.press("q", "a", "x", ",", "m")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x"]

  test "a stop after the first key of its right-hand side keeps the mapping key":
    # Vim leaves out only what the stopping key's fetch took: the left-hand
    # side goes with the first key it gives, and that one ran before the q.
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "xq"
    )

    e.press("q", "a", ",")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @[","]

    # The q in it is ignored in a running register, as in Vim.
    e.press("@", "a")

    check e.activeBuffer.getLine(0) == "c"
    check not e.macroState.isRecording

  test "keys a right-hand side leaves held stand for no typed keys":
    let e = newTestEditor("abc\nabc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "ggz", "l"
    )
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "Q", "jxgg", noremap = false
    )

    # The q lets go of the g g that Q left held, then stops the recording.
    e.press("q", "a", "Q", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["Q"]
    check e.activeBuffer.getLine(1) == "bc"
    check e.state.cursor.line == 0

  test "a mapping fired by the timeout that stops drops its keys":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "q"
    )
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",m", "x"
    )

    e.press("q", "a", "x", ",")
    check e.handleKeyMappingTimeout()

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x"]

  test "q let go when a mapping does not come drops only itself":
    let e = newTestEditor("abc\nabc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "qw", "x"
    )

    e.press("q", "a", "x", "q", "j")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x"]
    check e.state.cursor.line == 1

  test "q let go by the mapping timeout drops only itself":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "qw", "x"
    )

    e.press("q", "a", "x", "q")
    check e.macroState.isRecording

    check e.handleKeyMappingTimeout()

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["x"]

suite "The typed keys behind a mapping":
  test "the held keys a mapping completes when a later key breaks a longer one":
    # Vim 9.2 with `nmap a G` and `nmap ab gg`: recording `ax` keeps both.
    let e = newTestEditor("abc\nabc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "a", "G"
    )
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "ab", "gg"
    )

    e.press("q", "z", "a", "x", "q")

    check e.macroState.registers['z'] == @["a", "x"]
    check e.activeBuffer.getLine(1) == "bc"

  test "a mapping cut off as recursive keeps its key":
    # Vim records a typed key as it reads it, whatever comes of it.
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", ";", noremap = false
    )
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ";", ",", noremap = false
    )

    e.press("q", "z", ",", "x", "q")

    check e.macroState.registers['z'] == @[",", "x"]
    check e.activeBuffer.getLine(0) == "bc"

suite "Recording":
  test "keys replayed from a register are not recorded":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["x"]

    e.press("q", "a", "@", "b")

    check e.activeBuffer.getLine(0) == "bc"
    check e.macroState.isRecording
    check e.macroState.recording.get.keys == @["@", "b"]

  test "keys replayed from a mapping are not recorded":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ",", "x"
    )

    e.press("q", "a", ",")

    check e.activeBuffer.getLine(0) == "bc"
    check e.macroState.recording.get.keys == @[","]

  test "overlay keys replayed from a register are not recorded":
    let e = newTestEditor("abc")
    e.macroState.registers['b'] = @["/", "c", "<Enter>"]

    e.press("q", "a", "@", "b")

    check e.state.cursor.column == 2
    check e.macroState.recording.get.keys == @["@", "b"]

  test "keys typed after a held register name are recorded":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, "gd", "l"
    )

    e.press("q", "g", "x")

    check e.macroState.recordingRegister == some('g')
    check e.macroState.recording.get.keys == @["x"]

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

suite "Keys let go by the key router":
  test "a key after a held one meets what that one opened":
    let e = newTestEditor("abc")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Normal, ":x", "l"
    )

    e.press(":", "w")

    check e.state.isCommandOverlay
    check e.state.input.commandText == ":w"
    check e.state.cursor.column == 0

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

suite "q resolves like any other command":
  test "Escape cancels the register wait":
    let e = newTestEditor("abc")
    e.press("q", "Escape", "x")

    check not e.macroState.isRecording
    check e.activeBuffer.getLine(0) == "bc"

  test "in Visual mode it stops the recording and stays in Visual":
    let e = newTestEditor("abc")
    e.press("q", "a", "v", "l", "q")

    check not e.macroState.isRecording
    check e.macroState.registers['a'] == @["v", "l"]
    check e.state.mode == EditorMode.Visual

  test "in Visual mode it starts a recording":
    let e = newTestEditor("abc")
    e.press("v", "q", "a", "l", "Escape", "x", "q")

    check e.macroState.registers['a'] == @["l", "<Escape>", "x"]
    check e.activeBuffer.getLine(0) == "ac"

suite "The recording label":
  test "stays on through later keys and messages":
    let e = newTestEditor("abc\nabc")
    e.press("q", "a", "j", ":", "f", "o", "o", "Enter")

    check e.state.statusMessage.len > 0
    check e.frontendStatus.recordingLabel == "recording @a"

    e.press("l")
    check e.macroState.recordingLabel == "recording @a"

    e.press("q")
    check e.macroState.recordingLabel == ""

  test "is not shown while q waits for its register, as in Vim":
    let e = newTestEditor("abc")
    e.press("q")
    check e.macroState.recordingLabel == ""
    check e.frontendStatus.recordingLabel == ""

    e.press("Up")
    check not e.macroState.isRecording

    e.press("v", "q")
    check e.macroState.recordingLabel == ""

suite "A replayed key meets what the typed key met":
  test "Escape cancels a pending operator":
    let e = newTestEditor("foo bar\nfoo bar")
    e.press("q", "a", "d", "Escape", "q")
    check e.state.pendingInput.pendingOperator.isNone

    e.press("j", "@", "a")
    check e.state.pendingInput.pendingOperator.isNone

    e.press("w")
    check e.activeBuffer.getLine(1) == "foo bar"

  test "a key that dismisses temporary messages runs as well":
    let e = newTestEditor("abc")
    e.state.ui.tempMessages = @["message"]

    check e.playbackMacro(@["x"]).kind == hrHandled

    check e.state.ui.tempMessages.len == 0
    check e.activeBuffer.getLine(0) == "bc"
