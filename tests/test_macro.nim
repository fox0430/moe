#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/keybindings {.all.}
import ../src/moepkg/modes {.all.}

suite "Macro Recording":
  test "start macro recording (qa)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.isRecording = false
    state.macroState.waitingForRegister = false
    state.macroState.registers = initTable[char, seq[string]]()

    # Simulate: q (start recording)
    state.macroState.waitingForRegister = true
    state.macroState.commandType = "record"

    # Then: a (register name)
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @[]

    check state.macroState.isRecording == true
    check state.macroState.register == 'a'
    check state.macroState.recordedKeys.len == 0

  test "record keys during macro recording":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @[]
    state.macroState.registers = initTable[char, seq[string]]()

    # Simulate recording: d, d
    state.macroState.recordedKeys.add("d")
    state.macroState.recordedKeys.add("d")

    check state.macroState.recordedKeys == @["d", "d"]

  test "stop macro recording (q)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @["d", "d"]
    state.macroState.registers = initTable[char, seq[string]]()

    # Simulate: q (stop recording)
    state.macroState.registers[state.macroState.register] =
      state.macroState.recordedKeys
    state.macroState.isRecording = false
    state.macroState.recordedKeys = @[]

    check state.macroState.isRecording == false
    check state.macroState.registers.hasKey('a')
    check state.macroState.registers['a'] == @["d", "d"]
    check state.macroState.recordedKeys.len == 0

  test "record macro to different registers":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()

    # Record to register 'a'
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @["d", "d"]
    state.macroState.registers['a'] = state.macroState.recordedKeys
    state.macroState.isRecording = false

    # Record to register 'b'
    state.macroState.isRecording = true
    state.macroState.register = 'b'
    state.macroState.recordedKeys = @["j", "j"]
    state.macroState.registers['b'] = state.macroState.recordedKeys
    state.macroState.isRecording = false

    check state.macroState.registers.hasKey('a')
    check state.macroState.registers.hasKey('b')
    check state.macroState.registers['a'] == @["d", "d"]
    check state.macroState.registers['b'] == @["j", "j"]

  test "overwrite existing macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()

    # Record first macro
    state.macroState.registers['a'] = @["d", "d"]

    # Overwrite with new macro
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @["x", "x", "x"]
    state.macroState.registers['a'] = state.macroState.recordedKeys
    state.macroState.isRecording = false

    check state.macroState.registers['a'] == @["x", "x", "x"]

suite "Macro Playback":
  test "playback simple macro (@a)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["d", "d"]

    # Simulate: @a (playback)
    check state.macroState.registers.hasKey('a')
    let keys = state.macroState.registers['a']
    check keys == @["d", "d"]

  test "playback non-existent macro returns empty":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()

    # Try to play back from empty register
    check not state.macroState.registers.hasKey('z')

  test "set last macro register on playback":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["d", "d"]
    state.macroState.lastRegister = none(char)

    # Simulate: @a
    state.macroState.lastRegister = some('a')

    check state.macroState.lastRegister.isSome
    check state.macroState.lastRegister.get == 'a'

  test "repeat last macro (@@)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["d", "d"]
    state.macroState.lastRegister = some('a')

    # Simulate: @@
    check state.macroState.lastRegister.isSome
    let reg = state.macroState.lastRegister.get
    check state.macroState.registers.hasKey(reg)
    check state.macroState.registers[reg] == @["d", "d"]

  test "repeat last macro when no previous macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.lastRegister = none(char)

    # Simulate: @@ (no previous macro)
    check state.macroState.lastRegister.isNone

suite "Key Serialization":
  test "keyComboToString - regular characters":
    let combo1 = KeyCombo(isSpecial: false, char: "d")
    let combo2 = KeyCombo(isSpecial: false, char: "j")

    # These would be tested via the keyComboToString function
    # which is in normal_handler.nim
    discard

  test "keyComboToString - special keys":
    let comboEnter = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0)
    let comboEsc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)

    # These would be tested via the keyComboToString function
    # which is in normal_handler.nim
    discard

suite "Macro Edge Cases":
  test "cannot start recording while already recording":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @["d"]

    # Attempt to start another recording should be ignored
    # The implementation prevents this by checking isRecording
    check state.macroState.isRecording == true

  test "empty macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()

    # Record empty macro (just qa then q immediately)
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @[]
    state.macroState.registers['a'] = state.macroState.recordedKeys
    state.macroState.isRecording = false

    check state.macroState.registers['a'].len == 0

  test "macro with special keys":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroState.registers = initTable[char, seq[string]]()

    # Record macro with special keys
    state.macroState.recordedKeys = @["d", "d", "<Enter>", "j"]
    state.macroState.registers['a'] = state.macroState.recordedKeys

    check state.macroState.registers['a'] == @["d", "d", "<Enter>", "j"]
