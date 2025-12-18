#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Command line mode parser and executor
##
## This module handles parsing and execution of commands entered in command mode
## (e.g., :q, :w, :wq, :e filename, :set number, etc.)

import std/[strutils, tables, options]

import pkg/results

type
  CommandLineAction* = enum
    claQuit # :q
    claQuitAll # :qa (quit all)
    claSave # :w
    claSaveAll # :wa (write all)
    claSaveAndQuit # :wq, :x
    claSaveAllAndQuit # :wqa, :xa (save all and quit)
    claEdit # :e
    claEnew # :ene, :enew (new empty buffer)
    claSet # :set
    claHelp # :help, :h
    claSubstitute # :s
    claGoto # :123 (go to line 123)
    claVSplit # :vs (vertical split)
    claHSplit # :sp (horizontal split)
    claBufferNext # :bnext, :bn (next buffer)
    claBufferPrev # :bprev, :bp (previous buffer)
    claBufferFirst # :bfirst, :bf (first buffer)
    claBufferLast # :blast, :bl (last buffer)
    claBufferDelete # :bd, :bdelete (delete buffer)
    claStripWhitespace # :stripwhitespace, :stripws (remove trailing whitespace)
    claFiler # :Filer (open file explorer)
    claLogViewer # :log (open log viewer)
    claQuickRun # :run (quick run)
    claUnknown # Unknown command

  ParsedCommand* = object
    action*: CommandLineAction
    args*: seq[string]
    flags*: seq[string]
    rawText*: string

  CommandLineParser* = ref object
    aliases*: Table[string, CommandLineAction]
    validators: Table[CommandLineAction, proc(args: seq[string]): Result[void, string]]

  CommandLineResult* = object
    case kind*: CommandLineAction
    of claQuit:
      forceQuit*: bool # true for :q!
    of claQuitAll:
      forceQuitAll*: bool # true for :qa!
    of claSave:
      filename*: Option[string]
    of claSaveAll:
      forceSaveAll*: bool # true for :wa!
    of claSaveAndQuit:
      saveFilename*: Option[string]
    of claSaveAllAndQuit:
      forceSaveAllAndQuit*: bool # true for :wqa!
    of claEdit:
      editFilename*: string
    of claEnew:
      discard
    of claGoto:
      lineNumber*: int
    of claSet:
      option*: string
      value*: Option[string]
    of claSubstitute:
      pattern*: string
      replacement*: string
      substituteFlags*: string
    of claHelp:
      topic*: Option[string]
    of claVSplit:
      vsplitFilename*: Option[string]
    of claHSplit:
      hsplitFilename*: Option[string]
    of claBufferNext, claBufferPrev, claBufferFirst, claBufferLast:
      discard
    of claBufferDelete:
      forceBufferDelete*: bool # true for :bd!
    of claStripWhitespace:
      discard
    of claFiler:
      filerPath*: Option[string] # Optional path to open in filer
    of claLogViewer:
      discard
    of claQuickRun:
      discard
    of claUnknown:
      errorMessage*: string

proc newCommandLineParser*(): CommandLineParser =
  ## Create a new command line parser.
  ## Aliases are defined in commandconfig.nim and loaded via CommandConfig.applyToParser()
  result = CommandLineParser(
    aliases: initTable[string, CommandLineAction](),
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

  # Split into command and arguments
  let parts = cleanInput.split(WhiteSpace)
  if parts.len == 0:
    result.action = claUnknown
    return

  let cmd = parts[0]

  # Check for bang commands (force)
  if cmd.endsWith("!"):
    result.flags.add("force")

  # Look up command in aliases
  let baseCmd =
    if cmd.endsWith("!"):
      cmd[0 ..^ 2]
    else:
      cmd
  if baseCmd in parser.aliases:
    result.action = parser.aliases[baseCmd]
  else:
    result.action = claUnknown

  # Collect remaining parts as arguments
  if parts.len > 1:
    result.args = parts[1 ..^ 1]

proc execute*(parser: CommandLineParser, cmd: ParsedCommand): CommandLineResult =
  ## Execute a parsed command and return the result
  case cmd.action
  of claQuit:
    return CommandLineResult(kind: claQuit, forceQuit: "force" in cmd.flags)
  of claQuitAll:
    return CommandLineResult(kind: claQuitAll, forceQuitAll: "force" in cmd.flags)
  of claSave:
    return CommandLineResult(
      kind: claSave,
      filename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claSaveAll:
    return CommandLineResult(kind: claSaveAll, forceSaveAll: "force" in cmd.flags)
  of claSaveAndQuit:
    return CommandLineResult(
      kind: claSaveAndQuit,
      saveFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claSaveAllAndQuit:
    return CommandLineResult(
      kind: claSaveAllAndQuit, forceSaveAllAndQuit: "force" in cmd.flags
    )
  of claEdit:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claEdit, editFilename: cmd.args[0])
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "E32: No file name")
  of claEnew:
    return CommandLineResult(kind: claEnew)
  of claGoto:
    if cmd.args.len > 0:
      try:
        let lineNum = parseInt(cmd.args[0])
        return CommandLineResult(kind: claGoto, lineNumber: lineNum)
      except ValueError:
        return CommandLineResult(kind: claUnknown, errorMessage: "Invalid line number")
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "No line number specified")
  of claSet:
    if cmd.args.len > 0:
      let option = cmd.args[0]
      # Parse set command (e.g., "set number", "set tabstop=4")
      if "=" in option:
        let parts = option.split("=", 1)
        return CommandLineResult(kind: claSet, option: parts[0], value: some(parts[1]))
      else:
        return CommandLineResult(kind: claSet, option: option, value: none(string))
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "No option specified")
  of claSubstitute:
    # Basic substitute command parsing
    # TODO: Implement full regex substitute parsing
    return CommandLineResult(
      kind: claSubstitute, pattern: "", replacement: "", substituteFlags: ""
    )
  of claHelp:
    return CommandLineResult(
      kind: claHelp,
      topic:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claVSplit:
    return CommandLineResult(
      kind: claVSplit,
      vsplitFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claHSplit:
    return CommandLineResult(
      kind: claHSplit,
      hsplitFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claBufferNext:
    return CommandLineResult(kind: claBufferNext)
  of claBufferPrev:
    return CommandLineResult(kind: claBufferPrev)
  of claBufferFirst:
    return CommandLineResult(kind: claBufferFirst)
  of claBufferLast:
    return CommandLineResult(kind: claBufferLast)
  of claBufferDelete:
    return
      CommandLineResult(kind: claBufferDelete, forceBufferDelete: "force" in cmd.flags)
  of claStripWhitespace:
    return CommandLineResult(kind: claStripWhitespace)
  of claFiler:
    return CommandLineResult(
      kind: claFiler,
      filerPath:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claLogViewer:
    return CommandLineResult(kind: claLogViewer)
  of claQuickRun:
    return CommandLineResult(kind: claQuickRun)
  of claUnknown:
    return CommandLineResult(
      kind: claUnknown, errorMessage: "Not an editor command: " & cmd.rawText
    )

proc parseAndExecute*(parser: CommandLineParser, input: string): CommandLineResult =
  ## Convenience function to parse and execute in one step
  let parsed = parser.parseCommandLine(input)
  return parser.execute(parsed)

proc isQuitCommand*(cmdResult: CommandLineResult): bool =
  ## Check if the result is a quit command
  cmdResult.kind in {claQuit, claQuitAll, claSaveAndQuit, claSaveAllAndQuit}

proc isSaveCommand*(cmdResult: CommandLineResult): bool =
  ## Check if the result requires saving
  cmdResult.kind in {claSave, claSaveAll, claSaveAndQuit, claSaveAllAndQuit}
