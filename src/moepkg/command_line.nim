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
    claNew # :new (new empty buffer in horizontal split)
    claVnew # :vnew (new empty buffer in vertical split)
    claBufferNext # :bnext, :bn (next buffer)
    claBufferPrev # :bprev, :bp (previous buffer)
    claBufferFirst # :bfirst, :bf (first buffer)
    claBufferLast # :blast, :bl (last buffer)
    claBufferDelete # :bd, :bdelete (delete buffer)
    claBuffer # :b (switch to buffer by number or name)
    claStripWhitespace # :stripwhitespace, :stripws (remove trailing whitespace)
    claFiler # :Filer (open file explorer)
    claLogViewer # :log (open log viewer)
    claQuickRun # :run (quick run)
    claBufferManager # :buffers, :ls (open buffer manager)
    claBackupManager # :backup (open backup manager)
    claRecentFile # :recent (open recent file selection mode)
    claClearSearchHighlight # :noh, :nohlsearch (clear search highlighting)
    claShellCommand # :! (execute shell command)
    claBackground # :bg (pause editor and show terminal)
    claJumpList # :ju, :jump (show jump list)
    claBuild # :build (build current buffer)
    claDebug # :debug (open debug mode)
    claConfig # :conf (open configuration mode)
    claPutConfigFile # :putConfigFile (write sample config file)
    claMan # :man (show manual page)
    claTheme # :theme (change color theme)
    claLspLog # :lspLog (open LSP log viewer)
    claLspFormat # :lspFormat (LSP document formatting)
    claLspRestart # :lspRestart (restart LSP server)
    claLspFold # :lspFold (LSP folding range)
    claLspExecuteCommand # :lspExeCommand (LSP execute command)
    claLspCallHierarchyIncoming # :lspCallHierarchyIncoming (LSP incoming calls)
    claLspCallHierarchyOutgoing # :lspCallHierarchyOutgoing (LSP outgoing calls)
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
      forceSave*: bool # true for :w!
    of claSaveAll:
      forceSaveAll*: bool # true for :wa!
    of claSaveAndQuit:
      saveFilename*: Option[string]
      forceSaveAndQuit*: bool # true for :wq!
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
      hasRange*: bool # Whether a line range is specified
      isGlobal*: bool # Whether % prefix (all lines)
      startLine*: int # Start line (1-based, 0 means current line)
      endLine*: int # End line (1-based, 0 means current line)
    of claHelp:
      topic*: Option[string]
    of claVSplit:
      vsplitFilename*: Option[string]
    of claHSplit:
      hsplitFilename*: Option[string]
    of claNew:
      discard
    of claVnew:
      discard
    of claBufferNext, claBufferPrev, claBufferFirst, claBufferLast:
      discard
    of claBufferDelete:
      forceBufferDelete*: bool # true for :bd!
    of claBuffer:
      bufferArg*: string # Buffer number or name
    of claStripWhitespace:
      discard
    of claFiler:
      filerPath*: Option[string] # Optional path to open in filer
    of claLogViewer:
      discard
    of claQuickRun:
      discard
    of claBufferManager:
      discard
    of claBackupManager:
      discard
    of claRecentFile:
      discard
    of claClearSearchHighlight:
      discard
    of claShellCommand:
      shellCommand*: string
    of claBackground:
      discard
    of claJumpList:
      discard
    of claBuild:
      discard
    of claDebug:
      discard
    of claConfig:
      discard
    of claPutConfigFile:
      discard
    of claMan:
      manPage*: string # Manual page name
    of claTheme:
      themeName*: string # Theme name
    of claLspLog:
      discard
    of claLspFormat:
      discard
    of claLspRestart:
      discard
    of claLspFold:
      discard
    of claLspExecuteCommand:
      lspCommand*: string # LSP command to execute
      lspCommandArgs*: seq[string] # LSP command arguments
    of claLspCallHierarchyIncoming:
      discard
    of claLspCallHierarchyOutgoing:
      discard
    of claUnknown:
      errorMessage*: string

# Actions that require arguments (cannot be executed immediately)
# All other actions are considered no-argument actions
const ArgumentRequiredActions* = {
  claEdit, # requires filename
  claGoto, # requires line number
  claSet, # requires option name
  claSubstitute, # requires pattern
  claBuffer, # requires buffer number/name
  claShellCommand, # requires command
  claMan, # requires page name
  claTheme, # requires theme name
  claLspExecuteCommand, # requires command
  claVSplit, # optional but user may want to specify file
  claHSplit, # optional but user may want to specify file
  claFiler, # optional but user may want to specify path
  claUnknown, # invalid command
}

proc isNoArgumentAction*(parser: CommandLineParser, command: string): bool =
  ## Check if a command requires no arguments based on its action
  ## Returns true for actions not in ArgumentRequiredActions
  if command in parser.aliases:
    return parser.aliases[command] notin ArgumentRequiredActions
  return false

# Substitute command utilities

proc processEscapeSequences*(s: string): string =
  ## Process escape sequences in a string
  ## Converts \n to newline, \t to tab, \\ to backslash, \/ to slash
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i + 1]
      of 'n':
        result.add('\n')
        i += 2
      of 't':
        result.add('\t')
        i += 2
      of '\\':
        result.add('\\')
        i += 2
      of '/':
        result.add('/')
        i += 2
      else:
        result.add(s[i])
        i += 1
    else:
      result.add(s[i])
      i += 1

type SubstituteParseResult* = object ## Result of parsing a substitute command
  isValid*: bool # Whether this is a valid substitute command
  isGlobal*: bool # Whether the % prefix is present (all lines)
  hasRange*: bool # Whether a line range is specified (e.g., 1,10)
  startLine*: int # Start line (1-based, 0 means current line)
  endLine*: int # End line (1-based, 0 means current line)
  pattern*: string # Search pattern
  replacement*: string # Replacement text
  flags*: string # Flags (e.g., "g" for global within line)
  hasReplacement*: bool # Whether we've reached the replacement section

proc parseSubstituteCommand*(commandText: string): SubstituteParseResult =
  ## Parse a substitute command and extract pattern, replacement, and flags
  ## Supports formats:
  ##   :s/pattern/replacement/flags - current line only
  ##   :%s/pattern/replacement/flags - all lines
  ##   :1,10s/pattern/replacement/flags - lines 1 to 10
  ##   :.,10s/pattern/replacement/flags - current line to line 10
  ##   :1,.s/pattern/replacement/flags - line 1 to current line
  ## Handles escaped slashes properly (including \\/ which is backslash + end delimiter)
  result = SubstituteParseResult(isValid: false)

  if commandText.len < 2:
    return

  # Remove leading ":"
  let cmd =
    if commandText[0] == ':':
      commandText[1 ..^ 1]
    else:
      commandText

  # Check for substitute command patterns
  var startIdx = 0

  # Parse range prefix if present
  # Formats: %, N,M, .,M, N,., .,.
  if cmd.startsWith("%s/"):
    startIdx = 3
    result.isGlobal = true
  elif cmd.startsWith("s/"):
    startIdx = 2
    result.isGlobal = false
  else:
    # Try to parse range: number/dot, comma, number/dot, then s/
    var rangeEnd = 0
    var foundComma = false
    var startStr = ""
    var endStr = ""

    # Parse first part of range (before comma)
    while rangeEnd < cmd.len:
      let c = cmd[rangeEnd]
      if c == ',':
        foundComma = true
        rangeEnd.inc
        break
      elif c == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
        # Single line range (e.g., "5s/...")
        break
      elif c in {'0' .. '9', '.'}:
        startStr.add(c)
        rangeEnd.inc
      else:
        return # Invalid character in range

    if not foundComma and startStr.len > 0 and rangeEnd < cmd.len and
        cmd[rangeEnd] == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
      # Single line: "5s/..."
      result.hasRange = true
      if startStr == ".":
        result.startLine = 0 # 0 means current line
        result.endLine = 0
      else:
        try:
          let lineNum = parseInt(startStr)
          result.startLine = lineNum
          result.endLine = lineNum
        except ValueError:
          return
      startIdx = rangeEnd + 2
    elif foundComma:
      # Parse second part of range (after comma)
      while rangeEnd < cmd.len:
        let c = cmd[rangeEnd]
        if c == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
          break
        elif c in {'0' .. '9', '.'}:
          endStr.add(c)
          rangeEnd.inc
        else:
          return # Invalid character in range

      if rangeEnd < cmd.len and cmd[rangeEnd] == 's' and rangeEnd + 1 < cmd.len and
          cmd[rangeEnd + 1] == '/':
        result.hasRange = true
        # Parse start line
        if startStr == "." or startStr.len == 0:
          result.startLine = 0 # 0 means current line
        else:
          try:
            result.startLine = parseInt(startStr)
          except ValueError:
            return
        # Parse end line
        if endStr == "." or endStr.len == 0:
          result.endLine = 0 # 0 means current line
        else:
          try:
            result.endLine = parseInt(endStr)
          except ValueError:
            return
        startIdx = rangeEnd + 2
      else:
        return # No s/ found after range
    else:
      return # Not a valid substitute command

  result.isValid = true

  # Parse using state machine to properly handle escapes
  type ParseState = enum
    psPattern
    psReplacement
    psFlags

  var state = psPattern
  var escaped = false
  var i = startIdx

  while i < cmd.len:
    let c = cmd[i]

    if escaped:
      # Previous char was backslash - add this char literally (except for special sequences)
      case state
      of psPattern:
        result.pattern.add('\\')
        result.pattern.add(c)
      of psReplacement:
        result.replacement.add('\\')
        result.replacement.add(c)
      of psFlags:
        result.flags.add(c)
      escaped = false
      i += 1
      continue

    if c == '\\':
      escaped = true
      i += 1
      continue

    if c == '/':
      # Unescaped slash - delimiter
      case state
      of psPattern:
        state = psReplacement
        result.hasReplacement = true
      of psReplacement:
        state = psFlags
      of psFlags:
        discard # Ignore extra slashes in flags
      i += 1
      continue

    # Regular character
    case state
    of psPattern:
      result.pattern.add(c)
    of psReplacement:
      result.replacement.add(c)
    of psFlags:
      result.flags.add(c)
    i += 1

  # Handle trailing backslash
  if escaped:
    case state
    of psPattern:
      result.pattern.add('\\')
    of psReplacement:
      result.replacement.add('\\')
    of psFlags:
      result.flags.add('\\')

proc extractSubstitutePattern*(commandText: string): string =
  ## Extract the search pattern from a substitute command
  ## Supports formats like :%s/pattern/replacement/flags or :s/pattern/...
  ## Returns empty string if not a substitute command or pattern is incomplete
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    # Return raw pattern without escape processing (for display/matching)
    return parsed.pattern
  return ""

proc extractSubstituteReplacement*(
    commandText: string
): tuple[replacement: string, hasReplacement: bool] =
  ## Extract the replacement text from a substitute command
  ## Returns (replacement, true) if replacement section exists (even if empty)
  ## Returns ("", false) if we haven't reached the replacement section yet
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid and parsed.hasReplacement:
    return (parsed.replacement, true)
  return ("", false)

proc extractSubstituteFlags*(commandText: string): string =
  ## Extract the flags from a substitute command
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    return parsed.flags
  return ""

proc newCommandLineParser*(): CommandLineParser =
  ## Create a new command line parser.
  ## Aliases are defined in command_config.nim and loaded via CommandConfig.applyToParser()
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

  # Check if it's a shell command (:!command)
  if cleanInput.startsWith("!"):
    result.action = claShellCommand
    # Get the command after "!"
    let shellCmd = cleanInput[1 ..^ 1].strip()
    result.args = @[shellCmd]
    return

  # Check if it's a substitute command (s/..., %s/..., or N,Ms/...)
  if cleanInput.startsWith("%s/") or cleanInput.startsWith("s/"):
    result.action = claSubstitute
    # Store the full substitute command for parsing in execute()
    result.args = @[cleanInput]
    return

  # Check for range-prefixed substitute command (e.g., 1,10s/..., .s/..., .,10s/...)
  if cleanInput.len > 0 and cleanInput[0] in {'0' .. '9', '.'}:
    # Look for "s/" pattern after range
    var i = 0
    while i < cleanInput.len:
      if cleanInput[i] == 's' and i + 1 < cleanInput.len and cleanInput[i + 1] == '/':
        result.action = claSubstitute
        result.args = @[cleanInput]
        return
      elif cleanInput[i] in {'0' .. '9', '.', ','}:
        i.inc
      else:
        break

  # Split into command and arguments
  let parts = cleanInput.split(WhiteSpace)
  if parts.len == 0:
    result.action = claUnknown
    return

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
      forceSave: "force" in cmd.flags,
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
      forceSaveAndQuit: "force" in cmd.flags,
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
    # Parse substitute command using parseSubstituteCommand
    if cmd.args.len > 0:
      let parsed = parseSubstituteCommand(":" & cmd.args[0])
      if not parsed.isValid:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Invalid substitute command format"
        )
      if parsed.pattern.len == 0:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Pattern required for substitute"
        )
      return CommandLineResult(
        kind: claSubstitute,
        pattern: parsed.pattern,
        replacement: parsed.replacement,
        substituteFlags: parsed.flags,
        hasRange: parsed.hasRange,
        isGlobal: parsed.isGlobal,
        startLine: parsed.startLine,
        endLine: parsed.endLine,
      )
    else:
      return CommandLineResult(
        kind: claUnknown, errorMessage: "Invalid substitute command format"
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
  of claNew:
    return CommandLineResult(kind: claNew)
  of claVnew:
    return CommandLineResult(kind: claVnew)
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
  of claBuffer:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claBuffer, bufferArg: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "E86: Buffer name required")
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
  of claBufferManager:
    return CommandLineResult(kind: claBufferManager)
  of claBackupManager:
    return CommandLineResult(kind: claBackupManager)
  of claRecentFile:
    return CommandLineResult(kind: claRecentFile)
  of claClearSearchHighlight:
    return CommandLineResult(kind: claClearSearchHighlight)
  of claShellCommand:
    if cmd.args.len > 0 and cmd.args[0].len > 0:
      return CommandLineResult(kind: claShellCommand, shellCommand: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "No shell command specified")
  of claBackground:
    return CommandLineResult(kind: claBackground)
  of claJumpList:
    return CommandLineResult(kind: claJumpList)
  of claBuild:
    return CommandLineResult(kind: claBuild)
  of claDebug:
    return CommandLineResult(kind: claDebug)
  of claConfig:
    return CommandLineResult(kind: claConfig)
  of claPutConfigFile:
    return CommandLineResult(kind: claPutConfigFile)
  of claMan:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claMan, manPage: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "Manual page name required")
  of claTheme:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claTheme, themeName: cmd.args[0])
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "Theme name required")
  of claLspLog:
    return CommandLineResult(kind: claLspLog)
  of claLspFormat:
    return CommandLineResult(kind: claLspFormat)
  of claLspRestart:
    return CommandLineResult(kind: claLspRestart)
  of claLspFold:
    return CommandLineResult(kind: claLspFold)
  of claLspExecuteCommand:
    if cmd.args.len > 0:
      let args =
        if cmd.args.len > 1:
          cmd.args[1 ..^ 1]
        else:
          @[]
      return CommandLineResult(
        kind: claLspExecuteCommand, lspCommand: cmd.args[0], lspCommandArgs: args
      )
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "LSP command required")
  of claLspCallHierarchyIncoming:
    return CommandLineResult(kind: claLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    return CommandLineResult(kind: claLspCallHierarchyOutgoing)
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
