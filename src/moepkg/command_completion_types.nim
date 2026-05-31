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

## Lightweight type definitions for command-mode completion.
##
## Split out from `command_completion` so modules that only need
## `CommandCompletionManager` (notably `types` and its importers) do not
## transitively pull in `command_line` / `fuzzy_match` / `help_description` /
## `setting_options` via the full `command_completion` module.

type
  CommandCompletionState* = enum
    ccsIdle ## No completion active
    ccsActive ## Popup visible, items available

  CompletionMode* = enum
    cmCommand ## Completing command names
    cmFilePath ## Completing file/directory paths
    cmSetOption ## Completing :set options

  CommandCompletionEntry* = object ## A single completion entry
    command*: string ## The command text (without :)
    description*: string ## Brief description of the command
    matchScore*: int ## Score for sorting (higher = better match)

  CommandCompletionMenu* = object ## Completion popup state
    entries*: seq[CommandCompletionEntry]
    selectedIndex*: int ## Currently selected item (0-based, -1 = no selection)
    scrollOffset*: int ## For scrolling long lists
    maxVisible*: int ## Max items to show (default: 10)
    prefix*: string ## Current filter prefix

  CommandCompletionManager* = ref object ## Manages command completion state
    state*: CommandCompletionState
    mode*: CompletionMode ## Current completion mode
    menu*: CommandCompletionMenu
    allCommands*: seq[CommandCompletionEntry] ## All available commands
    baseCommand*: string ## The command being completed (for argument mode)
    argStartX*: int ## X position where argument starts (for popup positioning)
    originalDirPrefix*: string ## Original directory prefix when completion started
