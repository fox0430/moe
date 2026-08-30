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

## Configuration-driven editor mode policy.

import pkg/results

import types/editor_types
import command_handlers/mode_dispatchers

func forceInsertMode(e: Editor): bool =
  not e.isNil and not e.config.isNil and e.config.standard.forceInsertMode

func effectiveMode*(e: Editor, requestedMode: EditorMode): EditorMode =
  ## Resolve a requested mode through the configured editing policy.
  if e.forceInsertMode and requestedMode == EditorMode.Normal:
    EditorMode.Insert
  else:
    requestedMode

proc enforceModePolicy*(e: Editor) =
  ## Keep an editable window in a valid Insert session when Normal mode is
  ## disabled. Special and Visual modes remain available.
  if not e.forceInsertMode or e.currentMode notin {EditorMode.Normal, EditorMode.Insert}:
    return

  let transactionResult = beginInsertModeSession(e.activeBuffer, e.state)
  if transactionResult.isErr:
    e.state.statusMessage = "Failed to begin transaction: " & transactionResult.error
    return

  if e.currentMode == EditorMode.Normal:
    e.setMode(EditorMode.Insert)
