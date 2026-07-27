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

## Lightweight type definitions for configuration mode.
##
## Split out from `config_mode` so modules that only need `ConfigModeState`
## (notably `types` and its many importers) do not transitively pull in the
## full config-mode implementation (`pkg/results`, the descriptor table, and
## all the UI procs) via the `config_mode` module. The private getter/setter
## closures and `ConfigItemDescriptor` stay in `config_mode` because they are
## implementation details of the descriptor table.

import ../[config, color]

type
  ConfigValueKind* = enum
    ## Types of configuration values
    cvkBool # true/false
    cvkInt # integer
    cvkFloat # floating point
    cvkString # string
    cvkColor # theme color (hex or "termDefault")
    cvkEnum # enumerated value
    cvkSection # section header (not editable)

  ConfigItem* = object ## Represents a single configuration item in the list
    displayName*: string
    section*: string
    depth*: int # Indentation depth (0 for section, 1 for item)
    descriptorIndex*: int # Index into descriptor table (-1 for sections)
    case kind*: ConfigValueKind
    of cvkBool:
      boolValue*: bool
    of cvkInt:
      intValue*: int
      intMin*: int
      intMax*: int
    of cvkFloat:
      floatValue*: float
      floatMin*: float
      floatMax*: float
      floatStep*: float
    of cvkString:
      stringValue*: string
    of cvkEnum:
      enumValue*: string
      enumOptions*: seq[string]
    of cvkColor:
      colorIndex*: EditorColorPairIndex
      colorIsFg*: bool
      colorValue*: string # current value as "#rrggbb" or "termDefault"
    of cvkSection:
      discard

  ConfigModeState* = ref object ## State for the configuration mode UI
    items*: seq[ConfigItem] # All configuration items
    selectedIndex*: int # Index in items
    editMode*: bool # Whether we're editing a value (Int/String)
    editBuffer*: string # Buffer for editing text
    editCursor*: int # Cursor position in edit buffer (rune index, not bytes)
    enumPopupOpen*: bool # Whether enum selection popup is open
    enumPopupIndex*: int # Selected index in enum popup
    searchQuery*: string # Active search query ("" when no search)
    searchStartIndex*: int # Selection index when the current search began
    config*: EditorConfig # Reference to the config being edited
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    lastKeyWasEscape*: bool # Waiting for second Escape to clear highlight
    pendingApply*: bool
      # applyChange writes to EditorConfig; consumed by the
      # main loop to gate applyConfigSettings so cursor movement is cheap
