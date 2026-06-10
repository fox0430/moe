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

## Lightweight type definitions for the debug viewer.
##
## Split out from `debug_viewer` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in the full
## `debug_viewer` module (which depends on `modes` and the whole debug-dump
## machinery).

type DebugViewerState* = ref object ## State for the debug mode viewer
  lines*: seq[string] # Debug information lines
  topLine*: int # Top visible line (for scrolling)
  selectedLine*: int # Currently selected line (for navigation)
