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

import types, substitute_parser

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
  parser.aliases[alias.toLowerAscii()] = action

proc removeAlias*(parser: CommandLineParser, alias: string) =
  ## Remove a command alias from the parser
  parser.aliases.del(alias.toLowerAscii())

proc clearAliases*(parser: CommandLineParser) =
  ## Clear all command aliases
  parser.aliases.clear

proc parseCommandLine*(parser: CommandLineParser, input: string): ParsedCommand =
  ## Parse a command line input string into a structured command
  result.rawText = input

  # Remove leading colon if present
  var cleanInput =
    if input.startsWith(":"):
      input[1 ..^ 1]
    else:
      input

  cleanInput = normalizeSubstituteLongForm(cleanInput)

  if cleanInput.len == 0:
    result.action = claUnknown
    return

  # The range comes off once, before anything looks at a name.
  let prefix = parseExRangePrefix(cleanInput).valueOr:
    result.action = claUnknown
    return
  result.range = prefix.range
  let rest = cleanInput[prefix.rest ..^ 1]

  if result.range.kind != erkCurrent:
    # A range was given, so only a command that takes one can follow it.
    if rest.len == 0:
      # A bare address moves the cursor there: `:5`, `:$`, `:.+3`.
      result.action = if result.range.kind == erkAddresses: claGoto else: claUnknown
      return
    if rest == "d":
      result.action = claDeleteLines
      return
    if rest.startsWith("s/"):
      result.action = claSubstitute
      result.args = @[rest]
      return
    if rest.startsWith("!"):
      # A range before `!` filters those lines; a bare `!` drops to the shell.
      result.action = claFilter
      result.args = @[rest[1 ..^ 1].strip()]
      return
    result.action = claUnknown
    return

  # Check if it's a shell command (:!command)
  if cleanInput.startsWith("!"):
    result.action = claShellCommand
    # Get the command after "!"
    result.args = @[cleanInput[1 ..^ 1].strip()]
    return

  if cleanInput == "d":
    result.action = claDeleteLines
    return

  if cleanInput.startsWith("s/"):
    result.action = claSubstitute
    result.args = @[cleanInput]
    return

  var parts = cleanInput.splitWhitespace()
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
