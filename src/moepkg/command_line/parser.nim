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

## Command-line parser construction, alias management, and parseCommandLine
## (string -> ParsedCommand).

import std/[strutils, tables]

import pkg/results

import types, delete_parser, substitute_parser

proc newCommandLineParser*(): CommandLineParser =
  ## Create a new command line parser.
  ## Aliases are defined in command_config.nim and loaded via CommandConfig.applyToParser()
  result = CommandLineParser(
    aliases: initTable[string, CommandLineAction](),
    aliasDescriptions: initTable[string, string](),
    shellCommands: initTable[string, ShellCommandEntry](),
    validators:
      initTable[CommandLineAction, proc(args: seq[string]): Result[void, string]](),
  )

proc addAlias*(parser: CommandLineParser, alias: string, action: CommandLineAction) =
  ## Add a command alias to the parser
  parser.aliases[alias] = action

proc removeAlias*(parser: CommandLineParser, alias: string) =
  ## Remove a command alias from the parser
  parser.aliases.del(alias)

proc clearAliases*(parser: CommandLineParser) =
  ## Clear all command aliases
  parser.aliases.clear

proc parseCommandLine*(parser: CommandLineParser, input: string): ParsedCommand =
  ## Parse a command line input string into a structured command
  result.rawText = input

  # Remove leading colon if present
  let cleanInput =
    if input.startsWith(":"):
      input[1 ..^ 1]
    else:
      input

  if cleanInput.len == 0:
    result.action = claUnknown
    return

  # Check if it's a line number (all digits)
  if cleanInput.allCharsInSet({'0' .. '9'}):
    result.action = claGoto
    result.args = @[cleanInput]
    return

  # Check if it's a shell command (:!command)
  if cleanInput.startsWith("!"):
    result.action = claShellCommand
    # Get the command after "!"
    let shellCmd = cleanInput[1 ..^ 1].strip()
    result.args = @[shellCmd]
    return

  # Check if it's a delete command (:%d, or N,Md)
  if cleanInput == "%d":
    result.action = claDeleteLines
    result.args = @[cleanInput]
    return

  # Check for range-prefixed delete command (e.g., 1,10d, .d, .,10d)
  if cleanInput.len > 1 and cleanInput[0] in {'0' .. '9', '.'}:
    let parsed = parseDeleteCommand(":" & cleanInput)
    if parsed.isValid:
      result.action = claDeleteLines
      result.args = @[cleanInput]
      return

  # Check if it's a substitute command (s/..., %s/..., or N,Ms/...)
  if cleanInput.startsWith("%s/") or cleanInput.startsWith("s/"):
    result.action = claSubstitute
    # Store the full substitute command for parsing in execute()
    result.args = @[cleanInput]
    return

  # Check for range-prefixed substitute command (e.g., 1,10s/..., .s/..., .,10s/...)
  if cleanInput.len > 1 and cleanInput[0] in {'0' .. '9', '.'}:
    if parseSubstituteCommand(":" & cleanInput).isValid:
      result.action = claSubstitute
      result.args = @[cleanInput]
      return

  # Split into command and arguments
  var parts = cleanInput.split(WhiteSpace)
  if parts.len == 0:
    result.action = claUnknown
    return

  # Vim treats ":cmd!arg" as ":cmd! arg" (e.g. ":w!file").
  block splitEmbeddedBang:
    let first = parts[0]
    let bangPos = first.find('!')
    if bangPos <= 0 or bangPos >= first.high:
      break splitEmbeddedBang
    let prefix = first[0 ..< bangPos].toLowerAscii()
    if prefix notin parser.aliases and prefix notin parser.shellCommands:
      break splitEmbeddedBang
    let rest = first[bangPos + 1 ..^ 1]
    parts[0] = first[0 .. bangPos]
    parts.insert(rest, 1)

  let cmd = parts[0]

  # Check for bang commands (force)
  if cmd.endsWith("!"):
    result.flags.add("force")

  # Look up command in aliases (case-insensitive)
  let baseCmd =
    if cmd.endsWith("!"):
      cmd[0 ..^ 2].toLowerAscii()
    else:
      cmd.toLowerAscii()
  if baseCmd in parser.aliases:
    result.action = parser.aliases[baseCmd]
    # Collect remaining parts as arguments
    if parts.len > 1:
      result.args = parts[1 ..^ 1]
  elif baseCmd in parser.shellCommands:
    # Custom command: resolve as shell command
    result.action = claShellCommand
    var shellCmd = parser.shellCommands[baseCmd].command
    if parts.len > 1:
      shellCmd &= " " & parts[1 ..^ 1].join(" ")
    result.args = @[shellCmd]
  else:
    result.action = claUnknown
    # Collect remaining parts as arguments
    if parts.len > 1:
      result.args = parts[1 ..^ 1]
