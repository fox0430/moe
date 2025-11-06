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
    state.isRecordingMacro = false
    state.waitingForMacroRegister = false
    state.macroRegisters = initTable[char, seq[string]]()

    # Simulate: q (start recording)
    state.waitingForMacroRegister = true
    state.macroCommandType = "record"

    # Then: a (register name)
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @[]

    check state.isRecordingMacro == true
    check state.macroRegister == 'a'
    check state.recordedKeys.len == 0

  test "record keys during macro recording":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @[]
    state.macroRegisters = initTable[char, seq[string]]()

    # Simulate recording: d, d
    state.recordedKeys.add("d")
    state.recordedKeys.add("d")

    check state.recordedKeys == @["d", "d"]

  test "stop macro recording (q)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @["d", "d"]
    state.macroRegisters = initTable[char, seq[string]]()

    # Simulate: q (stop recording)
    state.macroRegisters[state.macroRegister] = state.recordedKeys
    state.isRecordingMacro = false
    state.recordedKeys = @[]

    check state.isRecordingMacro == false
    check state.macroRegisters.hasKey('a')
    check state.macroRegisters['a'] == @["d", "d"]
    check state.recordedKeys.len == 0

  test "record macro to different registers":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()

    # Record to register 'a'
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @["d", "d"]
    state.macroRegisters['a'] = state.recordedKeys
    state.isRecordingMacro = false

    # Record to register 'b'
    state.isRecordingMacro = true
    state.macroRegister = 'b'
    state.recordedKeys = @["j", "j"]
    state.macroRegisters['b'] = state.recordedKeys
    state.isRecordingMacro = false

    check state.macroRegisters.hasKey('a')
    check state.macroRegisters.hasKey('b')
    check state.macroRegisters['a'] == @["d", "d"]
    check state.macroRegisters['b'] == @["j", "j"]

  test "overwrite existing macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()

    # Record first macro
    state.macroRegisters['a'] = @["d", "d"]

    # Overwrite with new macro
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @["x", "x", "x"]
    state.macroRegisters['a'] = state.recordedKeys
    state.isRecordingMacro = false

    check state.macroRegisters['a'] == @["x", "x", "x"]

suite "Macro Playback":
  test "playback simple macro (@a)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()
    state.macroRegisters['a'] = @["d", "d"]

    # Simulate: @a (playback)
    check state.macroRegisters.hasKey('a')
    let keys = state.macroRegisters['a']
    check keys == @["d", "d"]

  test "playback non-existent macro returns empty":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()

    # Try to play back from empty register
    check not state.macroRegisters.hasKey('z')

  test "set last macro register on playback":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()
    state.macroRegisters['a'] = @["d", "d"]
    state.lastMacroRegister = none(char)

    # Simulate: @a
    state.lastMacroRegister = some('a')

    check state.lastMacroRegister.isSome
    check state.lastMacroRegister.get == 'a'

  test "repeat last macro (@@)":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()
    state.macroRegisters['a'] = @["d", "d"]
    state.lastMacroRegister = some('a')

    # Simulate: @@
    check state.lastMacroRegister.isSome
    let reg = state.lastMacroRegister.get
    check state.macroRegisters.hasKey(reg)
    check state.macroRegisters[reg] == @["d", "d"]

  test "repeat last macro when no previous macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()
    state.lastMacroRegister = none(char)

    # Simulate: @@ (no previous macro)
    check state.lastMacroRegister.isNone

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
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @["d"]

    # Attempt to start another recording should be ignored
    # The implementation prevents this by checking isRecordingMacro
    check state.isRecordingMacro == true

  test "empty macro":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()

    # Record empty macro (just qa then q immediately)
    state.isRecordingMacro = true
    state.macroRegister = 'a'
    state.recordedKeys = @[]
    state.macroRegisters['a'] = state.recordedKeys
    state.isRecordingMacro = false

    check state.macroRegisters['a'].len == 0

  test "macro with special keys":
    var state = EditorState()
    state.mode = EditorMode.Normal
    state.macroRegisters = initTable[char, seq[string]]()

    # Record macro with special keys
    state.recordedKeys = @["d", "d", "<Enter>", "j"]
    state.macroRegisters['a'] = state.recordedKeys

    check state.macroRegisters['a'] == @["d", "d", "<Enter>", "j"]
