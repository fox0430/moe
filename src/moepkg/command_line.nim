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

## Command mode parser and executor (facade).
##
## Re-exports the public API from command_line/* sub-modules and owns three
## small convenience helpers used across the editor.
##
## Sub-modules:
##   - types:             CommandLineAction, ParsedCommand, ShellCommandEntry,
##                        CommandLineParser, CommandLineResult,
##                        ArgumentRequiredActions, isNoArgumentAction
##   - substitute_parser: parseSubstituteCommand and extract* helpers
##   - delete_parser:     parseDeleteCommand
##   - parser:            newCommandLineParser, addAlias/removeAlias/
##                        clearAliases, parseCommandLine
##   - executor:          execute (case dispatch -> CommandLineResult)

import command_line/[types, substitute_parser, delete_parser, parser, executor]
export types, substitute_parser, delete_parser, parser, executor

proc parseAndExecute*(parser: CommandLineParser, input: string): CommandLineResult =
  ## Convenience function to parse and execute in one step
  let parsed = parser.parseCommandLine(input)
  return parser.execute(parsed)

proc isQuitCommand*(cmdResult: CommandLineResult): bool =
  ## Check if the result is a quit command
  cmdResult.kind in {claQuit, claQuitAll, claSaveAndQuit, claSaveAllAndQuit, claCquit}

proc isSaveCommand*(cmdResult: CommandLineResult): bool =
  ## Check if the result requires saving
  cmdResult.kind in {claSave, claSaveAll, claSaveAndQuit, claSaveAllAndQuit}
