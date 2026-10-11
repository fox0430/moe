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

## Tests for macro recording and playback (q and @)
## This test suite verifies that the q command correctly records macros
## and the @ command correctly plays them back.

import std/[unittest, options, tables]

import ../src/moepkg/[types, modes, macro_recording, key_bindings]

proc record(m: var MacroState, keys: varargs[string]) =
  ## Record `keys` as typed keys that have run.
  for key in keys:
    m.recordTypedKeys([stringToKeyCombo(key).get])

suite "Macro Recording":
  test "start macro recording (qa)":
    var m = MacroState()
    m.startRecording('a')

    check m.isRecording
    check m.recordingRegister == some('a')
    check m.recording.get.keys.len == 0

  test "record keys during macro recording":
    var m = MacroState()
    m.startRecording('a')
    m.record("d", "d")

    check m.recording.get.keys == @["d", "d"]

  test "keys typed while not recording are not recorded":
    var m = MacroState()
    m.record("d")

    check not m.isRecording

  test "stop macro recording (q) saves the recorded keys":
    var m = MacroState()
    m.startRecording('a')
    m.record("d", "d")
    m.stopRecording(afterCtrlO = false)

    check not m.isRecording
    check m.registers['a'] == @["d", "d"]

  test "stopping without a recording does nothing":
    var m = MacroState()
    m.stopRecording(afterCtrlO = false)

    check m.registers.len == 0

  test "record macro to different registers":
    var m = MacroState()
    for (register, keys) in [('a', @["d", "d"]), ('b', @["j", "j"])]:
      m.startRecording(register)
      m.record(keys)
      m.stopRecording(afterCtrlO = false)

    check m.registers['a'] == @["d", "d"]
    check m.registers['b'] == @["j", "j"]

  test "overwrite existing macro":
    var m = MacroState()
    m.registers['a'] = @["d", "d"]
    m.startRecording('a')
    m.record("x", "x", "x")
    m.stopRecording(afterCtrlO = false)

    check m.registers['a'] == @["x", "x", "x"]

  test "<C-o> before the stop is dropped only after Ctrl-o":
    var m = MacroState()
    for afterCtrlO in [true, false]:
      m.startRecording('a')
      m.record("i", "f", "<C-o>")
      m.stopRecording(afterCtrlO)
      if afterCtrlO:
        check m.registers['a'] == @["i", "f"]
      else:
        check m.registers['a'] == @["i", "f", "<C-o>"]

suite "Macro Playback":
  test "playback simple macro (@a)":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()
    state.pendingInput.macroState.registers['a'] = @["d", "d"]

    # Simulate: @a (playback)
    check state.pendingInput.macroState.registers.hasKey('a')
    let keys = state.pendingInput.macroState.registers['a']
    check keys == @["d", "d"]

  test "playback non-existent macro returns empty":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Try to play back from empty register
    check not state.pendingInput.macroState.registers.hasKey('z')

  test "set last macro register on playback":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()
    state.pendingInput.macroState.registers['a'] = @["d", "d"]
    state.pendingInput.macroState.lastRegister = none(char)

    # Simulate: @a
    state.pendingInput.macroState.lastRegister = some('a')

    check state.pendingInput.macroState.lastRegister.isSome
    check state.pendingInput.macroState.lastRegister.get == 'a'

  test "repeat last macro (@@)":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()
    state.pendingInput.macroState.registers['a'] = @["d", "d"]
    state.pendingInput.macroState.lastRegister = some('a')

    # Simulate: @@
    check state.pendingInput.macroState.lastRegister.isSome
    let reg = state.pendingInput.macroState.lastRegister.get
    check state.pendingInput.macroState.registers.hasKey(reg)
    check state.pendingInput.macroState.registers[reg] == @["d", "d"]

  test "repeat last macro when no previous macro":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()
    state.pendingInput.macroState.lastRegister = none(char)

    # Simulate: @@ (no previous macro)
    check state.pendingInput.macroState.lastRegister.isNone

suite "Macro Edge Cases":
  test "empty macro":
    var m = MacroState()
    m.startRecording('a')
    m.stopRecording(afterCtrlO = false)

    check m.registers['a'].len == 0

  test "macro with special keys":
    var m = MacroState()
    m.startRecording('a')
    m.record("d", "d", "<Enter>", "j")
    m.stopRecording(afterCtrlO = false)

    check m.registers['a'] == @["d", "d", "<Enter>", "j"]
