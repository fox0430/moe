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

## Command mode parser and executor
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
    claDeleteLines # :d, :%d (delete lines)
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
    claFiler # :filer (open file explorer)
    claLogViewer # :log (open log viewer)
    claQuickRun # :run (quick run)
    claBufferManager # :buffers, :ls (open buffer manager)
    claBackupManager # :backup (open backup manager)
    claRecentFile # :recent (open recent file selection mode)
    claClearSearchHighlight # :nohlsearch (clear search highlighting)
    claShellCommand # :! (execute shell command)
    claBackground # :bg (pause editor and show terminal)
    claJumpList # :jump (show jump list)
    claChanges # :changes (show change list)
    claBookmarks # :bookmarks (show bookmark list)
    claBuild # :build (build current buffer)
    claDebug # :debug (open debug mode)
    claConfig # :config (open configuration mode)
    claPutConfigFile # :putconfigfile (write sample config file)
    claMan # :man (show manual page)
    claTheme # :theme (change color theme)
    claLspLog # :lsplog (open LSP log viewer)
    claLspFormat # :lspformat (LSP document formatting)
    claLspRestart # :lsprestart (restart LSP server)
    claLspFold # :lspfold (LSP folding range)
    claLspExecuteCommand # :lspexecommand (LSP execute command)
    claLspCallHierarchyIncoming # :lspcallhierarchyincoming (LSP incoming calls)
    claLspCallHierarchyOutgoing # :lspcallhierarchyoutgoing (LSP outgoing calls)
    claTerminal # :terminal (open terminal emulator)
    claMap # :map {lhs} {rhs} (all modes)
    claNmap # :nmap {lhs} {rhs} (normal mode)
    claImap # :imap {lhs} {rhs} (insert mode)
    claVmap # :vmap {lhs} {rhs} (visual modes)
    claRmap # :rmap {lhs} {rhs} (replace mode)
    claCmap # :cmap {lhs} {rhs} (command-line mode)
    claUnmap # :unmap {lhs} (all modes)
    claNunmap # :nunmap {lhs} (normal mode)
    claIunmap # :iunmap {lhs} (insert mode)
    claVunmap # :vunmap {lhs} (visual modes)
    claRunmap # :runmap {lhs} (replace mode)
    claCunmap # :cunmap {lhs} (command-line mode)
    claMapclear # :mapclear (all modes)
    claNmapclear # :nmapclear (normal mode)
    claImapclear # :imapclear (insert mode)
    claVmapclear # :vmapclear (visual modes)
    claRmapclear # :rmapclear (replace mode)
    claCmapclear # :cmapclear (command-line mode)
    claOnlyWindow # :only (close all other windows)
    claEditConfigFile # :moerc (open config file for editing)
    claFileTree # :filetree (toggle file tree sidebar)
    claCquit # :cq, :cquit (quit with non-zero exit code)
    claUnknown # Unknown command

  ParsedCommand* = object
    action*: CommandLineAction
    args*: seq[string]
    flags*: seq[string]
    rawText*: string

  ShellCommandEntry* = object
    command*: string ## The shell command to execute
    description*: string ## Optional description for completion

  CommandLineParser* = ref object
    aliases*: Table[string, CommandLineAction]
    aliasDescriptions*: Table[string, string] ## Custom descriptions for aliases
    shellCommands*: Table[string, ShellCommandEntry] ## Shell command definitions
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
      editFilename*: Option[string]
      forceEdit*: bool # true for :e!
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
    of claDeleteLines:
      deleteHasRange*: bool # Whether a line range is specified
      deleteIsGlobal*: bool # Whether % prefix (all lines)
      deleteStartLine*: int # Start line (1-based, 0 means current line)
      deleteEndLine*: int # End line (1-based, 0 means current line)
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
    of claChanges:
      discard
    of claBookmarks:
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
    of claTerminal:
      terminalCommand*: string # Optional command (empty = default shell)
    of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
      mapLhs*: string
      mapRhs*: string
    of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
      unmapLhs*: string
    of claMapclear, claNmapclear, claImapclear, claVmapclear, claRmapclear, claCmapclear:
      discard
    of claOnlyWindow:
      discard
    of claEditConfigFile:
      discard
    of claFileTree:
      fileTreePath*: Option[string] # Optional root path for file tree
    of claCquit:
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
  claTerminal, # optional but user may want to specify command
  claFileTree, # optional but user may want to specify path
  claMap, # requires lhs and rhs
  claNmap, # requires lhs and rhs
  claImap, # requires lhs and rhs
  claVmap, # requires lhs and rhs
  claRmap, # requires lhs and rhs
  claCmap, # requires lhs and rhs
  claUnmap, # requires lhs
  claNunmap, # requires lhs
  claIunmap, # requires lhs
  claVunmap, # requires lhs
  claRunmap, # requires lhs
  claCunmap, # requires lhs
  claUnknown, # invalid command
}

proc isNoArgumentAction*(parser: CommandLineParser, command: string): bool =
  ## Check if a command requires no arguments based on its action
  ## Returns true for actions not in ArgumentRequiredActions
  if command in parser.aliases:
    return parser.aliases[command] notin ArgumentRequiredActions
  if command in parser.shellCommands:
    return false # Custom commands may accept arguments
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

type DeleteParseResult* = object ## Result of parsing a delete command
  isValid*: bool # Whether this is a valid delete command
  isGlobal*: bool # Whether the % prefix is present (all lines)
  hasRange*: bool # Whether a line range is specified (e.g., 1,10)
  startLine*: int # Start line (1-based, 0 means current line)
  endLine*: int # End line (1-based, 0 means current line)

proc parseDeleteCommand*(commandText: string): DeleteParseResult =
  ## Parse a delete command and extract range information
  ## Supports formats:
  ##   :d - delete current line
  ##   :%d - delete all lines
  ##   :1,10d - delete lines 1 to 10
  ##   :.,10d - delete from current line to line 10
  ##   :1,.d - delete from line 1 to current line
  result = DeleteParseResult(isValid: false)

  if commandText.len < 1:
    return

  # Remove leading ":"
  let cmd =
    if commandText[0] == ':':
      commandText[1 ..^ 1]
    else:
      commandText

  if cmd.len == 0:
    return

  # Check for simple :d
  if cmd == "d":
    result.isValid = true
    return

  # Check for :%d
  if cmd == "%d":
    result.isValid = true
    result.isGlobal = true
    return

  # Try to parse range: number/dot, comma, number/dot, then d
  var i = 0
  var foundComma = false
  var startStr = ""
  var endStr = ""

  # Parse first part of range (before comma)
  while i < cmd.len:
    let c = cmd[i]
    if c == ',':
      foundComma = true
      i.inc
      break
    elif c == 'd' and i + 1 == cmd.len:
      # Single line range (e.g., "5d")
      break
    elif c in {'0' .. '9', '.'}:
      startStr.add(c)
      i.inc
    else:
      return # Invalid character in range

  if not foundComma and startStr.len > 0 and i < cmd.len and cmd[i] == 'd' and
      i + 1 == cmd.len:
    # Single line: "5d"
    result.isValid = true
    result.hasRange = true
    if startStr == ".":
      result.startLine = 0 # 0 means current line
      result.endLine = 0
    else:
      try:
        let lineNum = parseInt(startStr)
        if lineNum < 1:
          result.isValid = false
          return
        result.startLine = lineNum
        result.endLine = lineNum
      except ValueError:
        return
  elif foundComma:
    # Parse second part of range (after comma)
    while i < cmd.len:
      let c = cmd[i]
      if c == 'd' and i + 1 == cmd.len:
        break
      elif c in {'0' .. '9', '.'}:
        endStr.add(c)
        i.inc
      else:
        return # Invalid character in range

    if i < cmd.len and cmd[i] == 'd' and i + 1 == cmd.len:
      result.isValid = true
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
    return CommandLineResult(
      kind: claEdit,
      editFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
      forceEdit: "force" in cmd.flags,
    )
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
  of claDeleteLines:
    # Parse delete command using parseDeleteCommand
    if cmd.args.len > 0:
      let parsed = parseDeleteCommand(":" & cmd.args[0])
      if not parsed.isValid:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Invalid delete command format"
        )
      return CommandLineResult(
        kind: claDeleteLines,
        deleteHasRange: parsed.hasRange,
        deleteIsGlobal: parsed.isGlobal,
        deleteStartLine: parsed.startLine,
        deleteEndLine: parsed.endLine,
      )
    else:
      # Simple :d with no range — delete current line
      return CommandLineResult(kind: claDeleteLines)
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
  of claChanges:
    return CommandLineResult(kind: claChanges)
  of claBookmarks:
    return CommandLineResult(kind: claBookmarks)
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
  of claTerminal:
    let termCmd =
      if cmd.args.len > 0:
        cmd.args.join(" ")
      else:
        ""
    return CommandLineResult(kind: claTerminal, terminalCommand: termCmd)
  of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
    if cmd.args.len == 0:
      # No arguments: list mappings
      case cmd.action
      of claMap:
        return CommandLineResult(kind: claMap, mapLhs: "", mapRhs: "")
      of claNmap:
        return CommandLineResult(kind: claNmap, mapLhs: "", mapRhs: "")
      of claImap:
        return CommandLineResult(kind: claImap, mapLhs: "", mapRhs: "")
      of claVmap:
        return CommandLineResult(kind: claVmap, mapLhs: "", mapRhs: "")
      of claRmap:
        return CommandLineResult(kind: claRmap, mapLhs: "", mapRhs: "")
      of claCmap:
        return CommandLineResult(kind: claCmap, mapLhs: "", mapRhs: "")
      else:
        discard
    if cmd.args.len < 2:
      let cmdName =
        case cmd.action
        of claNmap: "nmap"
        of claImap: "imap"
        of claVmap: "vmap"
        of claRmap: "rmap"
        of claCmap: "cmap"
        else: "map"
      return CommandLineResult(
        kind: claUnknown, errorMessage: "Usage: :" & cmdName & " {lhs} {rhs}"
      )
    let lhs = cmd.args[0]
    let rhs = cmd.args[1 ..^ 1].join(" ")
    case cmd.action
    of claMap:
      return CommandLineResult(kind: claMap, mapLhs: lhs, mapRhs: rhs)
    of claNmap:
      return CommandLineResult(kind: claNmap, mapLhs: lhs, mapRhs: rhs)
    of claImap:
      return CommandLineResult(kind: claImap, mapLhs: lhs, mapRhs: rhs)
    of claVmap:
      return CommandLineResult(kind: claVmap, mapLhs: lhs, mapRhs: rhs)
    of claRmap:
      return CommandLineResult(kind: claRmap, mapLhs: lhs, mapRhs: rhs)
    of claCmap:
      return CommandLineResult(kind: claCmap, mapLhs: lhs, mapRhs: rhs)
    else:
      discard
  of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
    if cmd.args.len < 1:
      let cmdName =
        case cmd.action
        of claNunmap: "nunmap"
        of claIunmap: "iunmap"
        of claVunmap: "vunmap"
        of claRunmap: "runmap"
        of claCunmap: "cunmap"
        else: "unmap"
      return CommandLineResult(
        kind: claUnknown, errorMessage: "Usage: :" & cmdName & " {lhs}"
      )
    let lhs = cmd.args[0]
    case cmd.action
    of claUnmap:
      return CommandLineResult(kind: claUnmap, unmapLhs: lhs)
    of claNunmap:
      return CommandLineResult(kind: claNunmap, unmapLhs: lhs)
    of claIunmap:
      return CommandLineResult(kind: claIunmap, unmapLhs: lhs)
    of claVunmap:
      return CommandLineResult(kind: claVunmap, unmapLhs: lhs)
    of claRunmap:
      return CommandLineResult(kind: claRunmap, unmapLhs: lhs)
    of claCunmap:
      return CommandLineResult(kind: claCunmap, unmapLhs: lhs)
    else:
      discard
  of claMapclear:
    return CommandLineResult(kind: claMapclear)
  of claNmapclear:
    return CommandLineResult(kind: claNmapclear)
  of claImapclear:
    return CommandLineResult(kind: claImapclear)
  of claVmapclear:
    return CommandLineResult(kind: claVmapclear)
  of claRmapclear:
    return CommandLineResult(kind: claRmapclear)
  of claCmapclear:
    return CommandLineResult(kind: claCmapclear)
  of claOnlyWindow:
    return CommandLineResult(kind: claOnlyWindow)
  of claEditConfigFile:
    return CommandLineResult(kind: claEditConfigFile)
  of claFileTree:
    return CommandLineResult(
      kind: claFileTree,
      fileTreePath:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claCquit:
    return CommandLineResult(kind: claCquit)
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
  cmdResult.kind in {claQuit, claQuitAll, claSaveAndQuit, claSaveAllAndQuit, claCquit}

proc isSaveCommand*(cmdResult: CommandLineResult): bool =
  ## Check if the result requires saving
  cmdResult.kind in {claSave, claSaveAll, claSaveAndQuit, claSaveAllAndQuit}
