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

## Puts a test state into a Visual selection.

import ../src/moepkg/[types, visual_selection]
export visual_selection

proc selectVisual*(state: EditorState, start, current: BufferPosition, kind = vskChar) =
  ## Select `start`..`current` in the Visual mode of `kind`, the cursor on
  ## `current`.
  state.mode = kind.visualMode
  state.selectVisualRange(start, current)

proc visualSelection*(state: EditorState): VisualSelection =
  ## The active window's selection as drawn, for assertions.
  state.activeWindow.visualSelection

proc visualAnchor*(state: EditorState): BufferPosition =
  state.activeWindow.visualAnchor

proc `visualAnchor=`*(state: EditorState, pos: BufferPosition) =
  state.activeWindow.visualAnchor = pos
