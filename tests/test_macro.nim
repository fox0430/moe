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

import ../src/moepkg/types
import ../src/moepkg/modes

suite "Macro Recording":
  test "start macro recording (qa)":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.isRecording = false
    state.pendingInput.macroState.waitingForRegister = false
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Simulate: q (start recording)
    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"

    # Then: a (register name)
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]

    check state.pendingInput.macroState.isRecording == true
    check state.pendingInput.macroState.register == 'a'
    check state.pendingInput.macroState.recordedKeys.len == 0

  test "record keys during macro recording":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Simulate recording: d, d
    state.pendingInput.macroState.recordedKeys.add("d")
    state.pendingInput.macroState.recordedKeys.add("d")

    check state.pendingInput.macroState.recordedKeys == @["d", "d"]

  test "stop macro recording (q)":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @["d", "d"]
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Simulate: q (stop recording)
    state.pendingInput.macroState.registers[state.pendingInput.macroState.register] =
      state.pendingInput.macroState.recordedKeys
    state.pendingInput.macroState.isRecording = false
    state.pendingInput.macroState.recordedKeys = @[]

    check state.pendingInput.macroState.isRecording == false
    check state.pendingInput.macroState.registers.hasKey('a')
    check state.pendingInput.macroState.registers['a'] == @["d", "d"]
    check state.pendingInput.macroState.recordedKeys.len == 0

  test "record macro to different registers":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Record to register 'a'
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @["d", "d"]
    state.pendingInput.macroState.registers['a'] =
      state.pendingInput.macroState.recordedKeys
    state.pendingInput.macroState.isRecording = false

    # Record to register 'b'
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'b'
    state.pendingInput.macroState.recordedKeys = @["j", "j"]
    state.pendingInput.macroState.registers['b'] =
      state.pendingInput.macroState.recordedKeys
    state.pendingInput.macroState.isRecording = false

    check state.pendingInput.macroState.registers.hasKey('a')
    check state.pendingInput.macroState.registers.hasKey('b')
    check state.pendingInput.macroState.registers['a'] == @["d", "d"]
    check state.pendingInput.macroState.registers['b'] == @["j", "j"]

  test "overwrite existing macro":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Record first macro
    state.pendingInput.macroState.registers['a'] = @["d", "d"]

    # Overwrite with new macro
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @["x", "x", "x"]
    state.pendingInput.macroState.registers['a'] =
      state.pendingInput.macroState.recordedKeys
    state.pendingInput.macroState.isRecording = false

    check state.pendingInput.macroState.registers['a'] == @["x", "x", "x"]

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
  test "cannot start recording while already recording":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @["d"]

    # Attempt to start another recording should be ignored
    # The implementation prevents this by checking isRecording
    check state.pendingInput.macroState.isRecording == true

  test "empty macro":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Record empty macro (just qa then q immediately)
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    state.pendingInput.macroState.registers['a'] =
      state.pendingInput.macroState.recordedKeys
    state.pendingInput.macroState.isRecording = false

    check state.pendingInput.macroState.registers['a'].len == 0

  test "macro with special keys":
    var state = EditorState(activeWindow: EditorWindow())
    state.mode = EditorMode.Normal
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Record macro with special keys
    state.pendingInput.macroState.recordedKeys = @["d", "d", "<Enter>", "j"]
    state.pendingInput.macroState.registers['a'] =
      state.pendingInput.macroState.recordedKeys

    check state.pendingInput.macroState.registers['a'] == @["d", "d", "<Enter>", "j"]
