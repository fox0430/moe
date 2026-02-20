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

import std/unittest

import ../src/moepkg/types
import ../src/moepkg/modes
import ../src/moepkg/key_bindings
import ../src/moepkg/command_handlers/normal_commands

suite "normal_commands - switchMode":
  test "switch from Normal to Insert":
    let state = EditorState()
    state.mode = EditorMode.Normal
    let registry = newKeyBindingRegistry()
    switchMode(state, EditorMode.Insert, registry)
    check state.mode == EditorMode.Insert

  test "switch from Insert to Normal":
    let state = EditorState()
    state.mode = EditorMode.Insert
    let registry = newKeyBindingRegistry()
    switchMode(state, EditorMode.Normal, registry)
    check state.mode == EditorMode.Normal

  test "switch from Normal to Visual":
    let state = EditorState()
    state.mode = EditorMode.Normal
    let registry = newKeyBindingRegistry()
    switchMode(state, EditorMode.Visual, registry)
    check state.mode == EditorMode.Visual

  test "switch from Normal to Replace":
    let state = EditorState()
    state.mode = EditorMode.Normal
    let registry = newKeyBindingRegistry()
    switchMode(state, EditorMode.Replace, registry)
    check state.mode == EditorMode.Replace

  test "switch with nil registry does not crash":
    let state = EditorState()
    state.mode = EditorMode.Normal
    switchMode(state, EditorMode.Insert, nil)
    check state.mode == EditorMode.Insert

  test "switching clears key sequence state":
    let state = EditorState()
    state.mode = EditorMode.Normal
    let registry = newKeyBindingRegistry()
    # Add some pending key state
    registry.sequenceState.keys.add(toKeyCombo('g'))
    switchMode(state, EditorMode.Insert, registry)
    check state.mode == EditorMode.Insert
    check registry.sequenceState.keys.len == 0
