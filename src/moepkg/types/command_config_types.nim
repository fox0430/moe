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

## Lightweight type definitions for command aliases and shell commands.
##
## Split out from `command_config` so modules that only need `CommandConfig`
## (notably `types/editor_types` for the `Editor.commandConfig` field) do not
## transitively pull in `command_line_commands` and the derived
## `CommandNameTable` / `keyMappableCommandModeAliases` constants.

import std/tables

import ../command_line/types

type
  CommandConfig* = ref object ## Configuration for command line commands
    aliases*: Table[string, CommandLineAction]
    aliasDescriptions*: Table[string, string] ## Custom descriptions for aliases
    shellCommands*: Table[string, ShellCommandEntry] ## Shell command definitions
    disabledCommands*: seq[CommandLineAction] ## Disabled built-in commands

  KeyMappableCommandAlias* = tuple[name, description: string]
    ## (alias name, human-readable description) pair used when registering a
    ## Command mode command alias as a keymap RHS target.
