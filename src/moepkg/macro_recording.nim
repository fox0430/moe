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

## One `q<reg>...q` recording session over typed keys. A key's typed keys are
## recorded once it has run, so the keys that start or stop a recording stay
## out of it, as in Vim, and replayed keys, which stand for none, never reach
## it.

import std/[options, tables]

import types, key_bindings

proc isRecording*(m: MacroState): bool =
  m.recording.isSome

proc recordingRegister*(m: MacroState): Option[char] =
  if m.recording.isSome:
    some(m.recording.get.register)
  else:
    none(char)

proc startRecording*(m: var MacroState, register: char) =
  m.recording = some(MacroRecording(register: register))

proc recordTypedKeys*(m: var MacroState, keys: openArray[KeyCombo]) =
  ## Append the typed keys behind a key that has run.
  if m.recording.isNone:
    return
  for key in keys:
    m.recording.get.keys.add(keyComboToString(key))

proc stopRecording*(m: var MacroState, afterCtrlO: bool) =
  ## Save the session into its register. The key that stops it is still
  ## running, so its typed keys are not in it.
  if m.recording.isNone:
    return
  let register = m.recording.get.register
  var keys = move m.recording.get.keys
  m.recording = none(MacroRecording)
  # Like Vim, stopping with `<C-o>q` from Insert mode drops the `<C-o>` too.
  if afterCtrlO and keys.len > 0:
    let last = stringToKeyCombo(keys[^1])
    if last.isSome and last.get.isCtrlO:
      keys.setLen(keys.len - 1)
  m.registers[register] = keys

proc recordingLabel*(m: MacroState): string =
  ## Vim's "recording @a", read from state on every draw, so it shows again
  ## once a message that covered it is gone.
  if m.recording.isSome:
    "recording @" & m.recording.get.register
  else:
    ""
