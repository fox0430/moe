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

## Lightweight type definitions for the window manager.
##
## Split out from `window_manager` so modules that only need
## `EditorWindowManager` (notably `types/editor_types` for the
## `Editor.windowManager` field) do not transitively pull in the ~1300 lines
## of split/resize/layout procs. `EditorWindow` itself lives in `types.nim`.

import ../types

type EditorWindowManager* = ref object ## Manages multiple split windows
  windows*: seq[EditorWindow]
  activeWindowIndex*: int
