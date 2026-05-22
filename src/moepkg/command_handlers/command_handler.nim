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

## Command mode handler
##
## This module handles commands specific to Command mode, including:
## - File operations (:w, :e, :q)
## - Search and replace (:s)
## - Settings (:set)
## - Navigation (:123 for line jumping)

import std/[options, strutils, os]

import ../[buffer, modes, command_line, command_config, command_registry, config_loader]
import ../setting_options
import handler_types
export setting_options, handler_types

type
  CommandModeResultKind* = enum
    cmrQuit # Application should quit
    cmrCloseWindow # Close current window
    cmrModeSwitch # Switch to different mode
    cmrMessage # Show status message
    cmrGotoLine # Jump to specific line
    cmrVSplit # Vertical split window
    cmrHSplit # Horizontal split window
    cmrNew # Create new empty buffer in horizontal split
    cmrVnew # Create new empty buffer in vertical split
    cmrEnew # Create new empty buffer
    cmrEdit # Edit/open file in current window
    cmrSetBoolOption # Set boolean option
    cmrSetIntOption # Set integer option
    cmrSetFloatOption # Set float option
    cmrSave # Save file
    cmrSaveAll # Save all modified buffers (:wa)
    cmrSaveAndQuit # Save file and quit
    cmrSaveAllAndQuit # Save all modified buffers and quit (:wqa, :xa)
    cmrBufferNext # Switch to next buffer
    cmrBufferPrev # Switch to previous buffer
    cmrBufferFirst # Switch to first buffer
    cmrBufferLast # Switch to last buffer
    cmrBuffer # Switch to buffer by number or name
    cmrBufferDelete # Delete current buffer
    cmrStripWhitespace # Remove trailing whitespace
    cmrFiler # Open file explorer
    cmrLogViewer # Open log viewer
    cmrHelpViewer # Open help viewer
    cmrQuickRun # Run the current buffer
    cmrBufferManager # Open buffer manager
    cmrBackupManager # Open backup manager
    cmrRecentFile # Open recent file selection mode
    cmrClearSearchHighlight # Clear search highlighting (:noh)
    cmrShellCommand # Execute shell command (:!)
    cmrBackground # Pause editor and show terminal (:bg)
    cmrJumpList # Show jump list (:ju, :jump)
    cmrChanges # Show change list (:changes)
    cmrBookmarks # Show bookmark list (:bookmarks)
    cmrConflictNext # Jump to next git conflict block (:conflictnext)
    cmrConflictPrev # Jump to previous git conflict block (:conflictprev)
    cmrBuild # Build current buffer (:build)
    cmrDebug # Open debug mode (:debug)
    cmrConfig # Open configuration mode (:conf)
    cmrPutConfigFile # Write sample config file (:putConfigFile)
    cmrMan # Show manual page (:man)
    cmrTheme # Change color theme (:theme)
    cmrLspLog # Open LSP log viewer (:lspLog)
    cmrLspFormat # LSP document formatting (:lspFormat)
    cmrLspRestart # Restart LSP server (:lspRestart)
    cmrLspFold # LSP folding range (:lspFold)
    cmrLspExecuteCommand # LSP execute command (:lspExeCommand)
    cmrLspCallHierarchyIncoming # LSP incoming calls (:lspCallHierarchyIncoming)
    cmrLspCallHierarchyOutgoing # LSP outgoing calls (:lspCallHierarchyOutgoing)
    cmrSubstitute # Search and replace (:s)
    cmrDeleteLines # Delete lines (:d, :%d)
    cmrTerminal # Open terminal emulator (:terminal)
    cmrMapAdd # Add runtime key mapping (:map, :nmap, etc.)
    cmrMapRemove # Remove runtime key mapping (:unmap, :nunmap, etc.)
    cmrMapClear # Clear runtime key mappings (:mapclear, :nmapclear, etc.)
    cmrMapList # List runtime key mappings (:map, :nmap, etc. with no args)
    cmrOnlyWindow # Close all other windows (:only)
    cmrFileTree # Toggle file tree sidebar (:filetree)
    cmrCquit # Quit with non-zero exit code (:cq)
    cmrError # Command error

  CommandModeResult* = object ## Result of command mode execution
    case kind*: CommandModeResultKind
    of cmrQuit:
      forceQuit*: bool
    of cmrCloseWindow:
      forceClose*: bool
    of cmrModeSwitch:
      targetMode*: EditorMode
    of cmrMessage:
      message*: string
    of cmrGotoLine:
      lineNumber*: int
    of cmrVSplit:
      vsplitFilename*: Option[string]
    of cmrHSplit:
      hsplitFilename*: Option[string]
    of cmrNew:
      discard
    of cmrVnew:
      discard
    of cmrEnew:
      discard
    of cmrEdit:
      editFilename*: Option[string]
      forceEdit*: bool
    of cmrSetBoolOption:
      boolOption*: BoolSettingOption
      boolValue*: bool
    of cmrSetIntOption:
      intOption*: IntSettingOption
      intValue*: int
    of cmrSetFloatOption:
      floatOption*: FloatSettingOption
      floatValue*: float
    of cmrSave:
      saveFilename*: Option[string]
      forceSave*: bool
    of cmrSaveAll:
      forceSaveAll*: bool
    of cmrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceSaveAndQuit*: bool
    of cmrSaveAllAndQuit:
      forceSaveAllAndQuit*: bool
    of cmrBufferNext, cmrBufferPrev, cmrBufferFirst, cmrBufferLast:
      discard
    of cmrBuffer:
      bufferArg*: string # Buffer number or name
    of cmrBufferDelete:
      forceBufferDelete*: bool
    of cmrStripWhitespace:
      strippedLineCount*: int
    of cmrFiler:
      filerPath*: Option[string] # Optional path for filer
    of cmrLogViewer:
      discard
    of cmrHelpViewer:
      discard
    of cmrQuickRun:
      discard
    of cmrBufferManager:
      discard
    of cmrBackupManager:
      discard
    of cmrRecentFile:
      discard
    of cmrClearSearchHighlight:
      discard
    of cmrShellCommand:
      shellCommand*: string
    of cmrBackground:
      discard
    of cmrJumpList:
      discard
    of cmrChanges:
      discard
    of cmrBookmarks:
      discard
    of cmrConflictNext:
      discard
    of cmrConflictPrev:
      discard
    of cmrBuild:
      discard
    of cmrDebug:
      discard
    of cmrConfig:
      discard
    of cmrPutConfigFile:
      discard
    of cmrMan:
      manPage*: string
    of cmrTheme:
      themeName*: string
    of cmrLspLog:
      discard
    of cmrLspFormat:
      discard
    of cmrLspRestart:
      discard
    of cmrLspFold:
      discard
    of cmrLspExecuteCommand:
      lspCommand*: string
      lspCommandArgs*: seq[string]
    of cmrLspCallHierarchyIncoming:
      discard
    of cmrLspCallHierarchyOutgoing:
      discard
    of cmrSubstitute:
      substitutePattern*: string
      substituteReplacement*: string
      substituteGlobal*: bool # true for /g flag
      substituteCount*: int # number of replacements made
    of cmrDeleteLines:
      deletedText*: string # deleted content for register storage
      deletedLineCount*: int # number of lines deleted
    of cmrTerminal:
      terminalCommand*: string # Optional command (empty = default shell)
    of cmrMapAdd:
      mapAddLhs*: string
      mapAddRhs*: string
      mapAddModes*: seq[EditorMode]
    of cmrMapRemove:
      mapRemoveLhs*: string
      mapRemoveModes*: seq[EditorMode]
    of cmrMapClear:
      mapClearModes*: seq[EditorMode]
    of cmrMapList:
      mapListModes*: seq[EditorMode]
    of cmrOnlyWindow:
      discard
    of cmrFileTree:
      fileTreePath*: Option[string]
    of cmrCquit:
      discard
    of cmrError:
      errorMessage*: string

proc newCommandModeHandler*(
    parser: CommandLineParser, config: CommandConfig, commandRegistry: CommandRegistry
): CommandModeHandler =
  ## Create a new Command mode handler
  CommandModeHandler(parser: parser, config: config, commandRegistry: commandRegistry)

proc executeQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    isSharedBuffer: bool = false,
): CommandModeResult =
  ## Execute quit command (:q, :q!) - now closes current window
  ## If isSharedBuffer is true, skip the isModified check since buffer is shared across windows
  if not force and not isSharedBuffer:
    # Check if there are unsaved changes
    if buffer.isModified:
      return CommandModeResult(
        kind: cmrError, errorMessage: "No write since last change (add ! to override)"
      )

  return CommandModeResult(kind: cmrCloseWindow, forceClose: force)

proc executeSave*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): CommandModeResult =
  ## Execute save command (:w, :w!)
  ## Returns cmrSave to signal that the file should be saved
  ## The actual save operation is performed by the editor
  return CommandModeResult(kind: cmrSave, saveFilename: filename, forceSave: force)

proc executeSaveAll*(handler: CommandModeHandler, force: bool): CommandModeResult =
  ## Execute save all command (:wa, :wa!)
  ## Returns cmrSaveAll to signal that every modified buffer should be saved.
  ## The actual save operation is performed by the editor.
  return CommandModeResult(kind: cmrSaveAll, forceSaveAll: force)

proc executeSaveAndQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): CommandModeResult =
  ## Execute save and quit command (:wq, :x)
  ## Returns cmrSaveAndQuit to signal that the file should be saved and editor should quit
  ## The actual save operation is performed by the editor
  return CommandModeResult(
    kind: cmrSaveAndQuit, saveAndQuitFilename: filename, forceSaveAndQuit: force
  )

proc executeSaveAllAndQuit*(
    handler: CommandModeHandler, force: bool
): CommandModeResult =
  ## Execute save all and quit command (:wqa, :xa, :wqa!)
  ## Returns cmrSaveAllAndQuit to signal that every modified buffer should be
  ## saved and then the editor should quit. The actual save and quit operations
  ## are performed by the editor.
  return CommandModeResult(kind: cmrSaveAllAndQuit, forceSaveAllAndQuit: force)

proc executeQuitAll*(
    handler: CommandModeHandler, buffer: TextBuffer, force: bool
): CommandModeResult =
  ## Execute quit all command (:qa, :qa!) - closes all windows and quits
  if not force:
    # Check if there are unsaved changes
    if buffer.isModified:
      return CommandModeResult(
        kind: cmrError, errorMessage: "No write since last change (add ! to override)"
      )

  # Return cmrQuit to signal immediate editor quit
  return CommandModeResult(kind: cmrQuit, forceQuit: force)

proc executeEdit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): CommandModeResult =
  ## Execute edit command (:e/:e! with optional filename)
  if filename.isSome:
    let expanded = expandTilde(filename.get)
    # If path is a directory, open in Filer mode
    if dirExists(expanded):
      return CommandModeResult(kind: cmrFiler, filerPath: some(absolutePath(expanded)))
    # Open the file in the current window
    return CommandModeResult(
      kind: cmrEdit, editFilename: some(absolutePath(expanded)), forceEdit: force
    )
  else:
    # No filename: reload current buffer
    if not force and buffer.isModified:
      return CommandModeResult(
        kind: cmrError, errorMessage: "No write since last change (add ! to override)"
      )
    return
      CommandModeResult(kind: cmrEdit, editFilename: none(string), forceEdit: force)

proc executeGotoLine*(
    handler: CommandModeHandler, buffer: TextBuffer, lineNumber: int
): CommandModeResult =
  ## Execute goto line command (:123)
  if lineNumber <= 0:
    return CommandModeResult(kind: cmrError, errorMessage: "Invalid line number")

  # Clamp to last line if lineNumber exceeds buffer length
  let clampedLine = min(lineNumber, buffer.len)

  return CommandModeResult(kind: cmrGotoLine, lineNumber: clampedLine)

proc parseSetIntValue(spec: SetOptionSpec, value: Option[string]): CommandModeResult =
  ## Validate and dispatch an integer-typed `:set X=N` option.
  doAssert spec.kind == sokInt, "parseSetIntValue called with non-int spec"
  if value.isNone:
    return CommandModeResult(
      kind: cmrError,
      errorMessage:
        spec.longName & " requires a value (e.g., " & spec.longName & "=" &
        $spec.intExample & ")",
    )
  try:
    let intVal = parseInt(value.get)
    if intBoundOk(spec.intBound, intVal):
      return CommandModeResult(
        kind: cmrSetIntOption, intOption: spec.intOption, intValue: intVal
      )
    return CommandModeResult(
      kind: cmrError, errorMessage: spec.longName & " " & intBoundError(spec.intBound)
    )
  except ValueError:
    return CommandModeResult(
      kind: cmrError, errorMessage: "Invalid value for " & spec.longName
    )

proc parseSetFloatValue(spec: SetOptionSpec, value: Option[string]): CommandModeResult =
  ## Validate and dispatch a float-typed `:set X=N.N` option.
  doAssert spec.kind == sokFloat, "parseSetFloatValue called with non-float spec"
  if value.isNone:
    return CommandModeResult(
      kind: cmrError,
      errorMessage:
        spec.longName & " requires a value (e.g., " & spec.longName & "=" &
        $spec.floatExample & ")",
    )
  try:
    let floatVal = parseFloat(value.get)
    if floatVal >= 0:
      return CommandModeResult(
        kind: cmrSetFloatOption, floatOption: spec.floatOption, floatValue: floatVal
      )
    return CommandModeResult(
      kind: cmrError, errorMessage: spec.longName & " must be non-negative"
    )
  except ValueError:
    return CommandModeResult(
      kind: cmrError, errorMessage: "Invalid value for " & spec.longName
    )

proc executeSet*(
    handler: CommandModeHandler, option: string, value: Option[string]
): CommandModeResult =
  ## Execute set command (:set option=value). Dispatches via `SetOptionTable`
  ## so each `:set` option lives in exactly one place (setting_options.nim).
  let opt = option.toLower
  for spec in SetOptionTable:
    case spec.kind
    of sokBool:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return CommandModeResult(
          kind: cmrSetBoolOption, boolOption: spec.boolOption, boolValue: true
        )
      let noLong = "no" & spec.longName
      if opt == noLong:
        return CommandModeResult(
          kind: cmrSetBoolOption, boolOption: spec.boolOption, boolValue: false
        )
      if spec.shortName.len > 0 and opt == "no" & spec.shortName:
        return CommandModeResult(
          kind: cmrSetBoolOption, boolOption: spec.boolOption, boolValue: false
        )
    of sokInt:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return parseSetIntValue(spec, value)
    of sokFloat:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return parseSetFloatValue(spec, value)
  return CommandModeResult(kind: cmrError, errorMessage: "Unknown option: " & option)

proc executeHelp*(
    handler: CommandModeHandler, topic: Option[string]
): CommandModeResult =
  ## Execute help command (:help, :help topic)
  # Open the help viewer
  return CommandModeResult(kind: cmrHelpViewer)

proc executeVSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute vertical split command (:vs, :vs filename)
  return CommandModeResult(kind: cmrVSplit, vsplitFilename: filename)

proc executeHSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute horizontal split command (:sp, :sp filename)
  return CommandModeResult(kind: cmrHSplit, hsplitFilename: filename)

proc executeNew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute new command (:new) - create new empty buffer in horizontal split
  return CommandModeResult(kind: cmrNew)

proc executeVnew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute vnew command (:vnew) - create new empty buffer in vertical split
  return CommandModeResult(kind: cmrVnew)

proc executeEnew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute enew command (:ene, :enew) - create new empty buffer
  return CommandModeResult(kind: cmrEnew)

proc executeBufferNext*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bnext command (:bn, :bnext) - switch to next buffer
  return CommandModeResult(kind: cmrBufferNext)

proc executeBufferPrev*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bprev command (:bp, :bprev) - switch to previous buffer
  return CommandModeResult(kind: cmrBufferPrev)

proc executeBufferFirst*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bfirst command (:bf, :bfirst) - switch to first buffer
  return CommandModeResult(kind: cmrBufferFirst)

proc executeBufferLast*(handler: CommandModeHandler): CommandModeResult =
  ## Execute blast command (:bl, :blast) - switch to last buffer
  return CommandModeResult(kind: cmrBufferLast)

proc executeBuffer*(handler: CommandModeHandler, arg: string): CommandModeResult =
  ## Execute buffer command (:b N or :b name) - switch to buffer by number or name
  return CommandModeResult(kind: cmrBuffer, bufferArg: arg)

proc executeBufferDelete*(
    handler: CommandModeHandler, buffer: TextBuffer, force: bool
): CommandModeResult =
  ## Execute bdelete command (:bd, :bdelete) - delete current buffer
  if not force and buffer.isModified:
    return CommandModeResult(
      kind: cmrError, errorMessage: "No write since last change (add ! to override)"
    )
  return CommandModeResult(kind: cmrBufferDelete, forceBufferDelete: force)

proc executeStripWhitespace*(
    handler: CommandModeHandler, buffer: TextBuffer
): CommandModeResult =
  ## Execute stripwhitespace command (:stripwhitespace, :stripws)
  ## Removes trailing whitespace from all lines
  var strippedCount = 0
  discard buffer.beginTransaction("stripwhitespace")
  for lineIdx in 0 ..< buffer.len:
    let line = buffer.getLine(lineIdx)
    let trimmed = line.strip(leading = false, trailing = true)
    if trimmed != line:
      discard buffer.replaceLine(lineIdx, trimmed)
      strippedCount.inc
  discard buffer.commitTransaction()
  return CommandModeResult(kind: cmrStripWhitespace, strippedLineCount: strippedCount)

proc executeQuickRun*(handler: CommandModeHandler): CommandModeResult =
  ## Execute quickrun command (:run, :quickrun, :qr)
  return CommandModeResult(kind: cmrQuickRun)

proc executeSubstitute*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    pattern: string,
    replacement: string,
    flags: string,
    hasRange: bool = false,
    isGlobalRange: bool = false,
    startLine: int = 0,
    endLine: int = 0,
    currentLine: int = 0,
): CommandModeResult =
  ## Execute substitute command (:s, :%s/pattern/replacement/flags)
  ## flags: "g" for global replacement (all occurrences), otherwise first only
  ## hasRange: true if a line range was specified (e.g., :1,10s/...)
  ## isGlobalRange: true if % prefix was used (all lines)
  ## startLine/endLine: line range (1-based, 0 means current line)
  ## currentLine: current cursor line (0-based)
  if pattern.len == 0:
    return CommandModeResult(kind: cmrError, errorMessage: "Pattern required")

  let isGlobal = "g" in flags
  var replaceCount = 0

  # Process escape sequences in replacement string using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Determine line range
  var rangeStart, rangeEnd: int
  if isGlobalRange:
    # % means all lines
    rangeStart = 0
    rangeEnd = buffer.len - 1
  elif hasRange:
    # Explicit range specified
    # Convert 1-based to 0-based, 0 means current line
    rangeStart =
      if startLine == 0:
        currentLine
      else:
        startLine - 1
    rangeEnd =
      if endLine == 0:
        currentLine
      else:
        endLine - 1
    # Validate range
    if rangeStart < 0:
      rangeStart = 0
    if rangeEnd >= buffer.len:
      rangeEnd = buffer.len - 1
    if rangeStart > rangeEnd:
      return CommandModeResult(
        kind: cmrError, errorMessage: "Invalid range: start line > end line"
      )
  else:
    # No range - current line only
    rangeStart = currentLine
    rangeEnd = currentLine

  # Begin transaction for all changes
  discard buffer.beginTransaction("substitute")

  # Search and replace in specified range
  for lineIdx in rangeStart .. rangeEnd:
    var line = buffer.getLine(lineIdx)
    var modified = false
    var newLine = ""
    var searchPos = 0

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        # No more matches - add rest of line
        newLine.add(line[searchPos ..^ 1])
        break

      # Add text before match
      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      # Add replacement
      newLine.add(processedReplacement)
      replaceCount.inc
      modified = true

      # Move past the match
      searchPos = idx + pattern.len

      # If not global, only replace first occurrence per line
      if not isGlobal:
        newLine.add(line[searchPos ..^ 1])
        break

    # Update the line if modified
    if modified:
      discard buffer.replaceLine(lineIdx, newLine)

  discard buffer.commitTransaction()

  if replaceCount == 0:
    return
      CommandModeResult(kind: cmrError, errorMessage: "Pattern not found: " & pattern)

  return CommandModeResult(
    kind: cmrSubstitute,
    substitutePattern: pattern,
    substituteReplacement: processedReplacement,
    substituteGlobal: isGlobal,
    substituteCount: replaceCount,
  )

proc executeDelete*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    hasRange: bool = false,
    isGlobalRange: bool = false,
    startLine: int = 0,
    endLine: int = 0,
    currentLine: int = 0,
): CommandModeResult =
  ## Execute delete command (:d, :%d, :1,10d)
  ## hasRange: true if a line range was specified
  ## isGlobalRange: true if % prefix was used (all lines)
  ## startLine/endLine: line range (1-based, 0 means current line)
  ## currentLine: current cursor line (0-based)

  # Determine line range
  var rangeStart, rangeEnd: int
  if isGlobalRange:
    rangeStart = 0
    rangeEnd = buffer.len - 1
  elif hasRange:
    rangeStart =
      if startLine == 0:
        currentLine
      else:
        startLine - 1
    rangeEnd =
      if endLine == 0:
        currentLine
      else:
        endLine - 1
    if rangeStart < 0:
      rangeStart = 0
    if rangeEnd < 0:
      rangeEnd = 0
    if rangeEnd >= buffer.len:
      rangeEnd = buffer.len - 1
    if rangeStart > rangeEnd:
      return CommandModeResult(
        kind: cmrError, errorMessage: "Invalid range: start line > end line"
      )
  else:
    # No range - current line only
    rangeStart = currentLine
    rangeEnd = currentLine

  if rangeStart >= buffer.len:
    return CommandModeResult(kind: cmrError, errorMessage: "Line out of range")

  # Collect text from all lines in range
  var text = ""
  for lineIdx in rangeStart .. rangeEnd:
    if lineIdx > rangeStart:
      text.add("\n")
    text.add(buffer.getLine(lineIdx))
  text.add("\n")

  let lineCount = rangeEnd - rangeStart + 1
  let deletingAll = rangeStart == 0 and rangeEnd == buffer.len - 1

  discard buffer.beginTransaction("delete lines")

  if deletingAll:
    # Delete all lines except the first, then clear the first
    for i in countdown(buffer.len - 1, 1):
      discard buffer.deleteLine(i)
    discard buffer.replaceLine(0, "")
  else:
    # Delete lines from bottom to top to avoid index shifting
    for i in countdown(rangeEnd, rangeStart):
      discard buffer.deleteLine(i)

  discard buffer.commitTransaction()

  return CommandModeResult(
    kind: cmrDeleteLines, deletedText: text, deletedLineCount: lineCount
  )

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
): CommandModeResult =
  ## Main entry point for handling Command mode input
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  ## currentLine: current cursor line (0-based), used for range substitution with '.'

  if commandText.len <= 1: # Just ":"
    return CommandModeResult(kind: cmrModeSwitch, targetMode: EditorMode.Normal)

  # Parse and execute the command
  let cmdResult = handler.parser.parseAndExecute(commandText)

  case cmdResult.kind
  of claQuit:
    return handler.executeQuit(buffer, cmdResult.forceQuit, isSharedBuffer)
  of claQuitAll:
    return handler.executeQuitAll(buffer, cmdResult.forceQuitAll)
  of claSave:
    return handler.executeSave(buffer, cmdResult.filename, cmdResult.forceSave)
  of claSaveAll:
    return handler.executeSaveAll(cmdResult.forceSaveAll)
  of claSaveAndQuit:
    return handler.executeSaveAndQuit(
      buffer, cmdResult.saveFilename, cmdResult.forceSaveAndQuit
    )
  of claSaveAllAndQuit:
    return handler.executeSaveAllAndQuit(cmdResult.forceSaveAllAndQuit)
  of claEdit:
    return handler.executeEdit(buffer, cmdResult.editFilename, cmdResult.forceEdit)
  of claEnew:
    return handler.executeEnew()
  of claGoto:
    return handler.executeGotoLine(buffer, cmdResult.lineNumber)
  of claSet:
    return handler.executeSet(cmdResult.option, cmdResult.value)
  of claHelp:
    return handler.executeHelp(cmdResult.topic)
  of claVSplit:
    return handler.executeVSplit(cmdResult.vsplitFilename)
  of claHSplit:
    return handler.executeHSplit(cmdResult.hsplitFilename)
  of claNew:
    return handler.executeNew()
  of claVnew:
    return handler.executeVnew()
  of claBufferNext:
    return handler.executeBufferNext()
  of claBufferPrev:
    return handler.executeBufferPrev()
  of claBufferFirst:
    return handler.executeBufferFirst()
  of claBufferLast:
    return handler.executeBufferLast()
  of claBufferDelete:
    return handler.executeBufferDelete(buffer, cmdResult.forceBufferDelete)
  of claBuffer:
    return handler.executeBuffer(cmdResult.bufferArg)
  of claStripWhitespace:
    return handler.executeStripWhitespace(buffer)
  of claFiler:
    return CommandModeResult(kind: cmrFiler, filerPath: cmdResult.filerPath)
  of claLogViewer:
    return CommandModeResult(kind: cmrLogViewer)
  of claQuickRun:
    return handler.executeQuickRun()
  of claBufferManager:
    return CommandModeResult(kind: cmrBufferManager)
  of claBackupManager:
    return CommandModeResult(kind: cmrBackupManager)
  of claRecentFile:
    when defined(macosx):
      return CommandModeResult(
        kind: cmrError, errorMessage: ":recent is not supported on macOS"
      )
    else:
      return CommandModeResult(kind: cmrRecentFile)
  of claClearSearchHighlight:
    return CommandModeResult(kind: cmrClearSearchHighlight)
  of claShellCommand:
    return
      CommandModeResult(kind: cmrShellCommand, shellCommand: cmdResult.shellCommand)
  of claBackground:
    return CommandModeResult(kind: cmrBackground)
  of claJumpList:
    return CommandModeResult(kind: cmrJumpList)
  of claChanges:
    return CommandModeResult(kind: cmrChanges)
  of claBookmarks:
    return CommandModeResult(kind: cmrBookmarks)
  of claConflictNext:
    return CommandModeResult(kind: cmrConflictNext)
  of claConflictPrev:
    return CommandModeResult(kind: cmrConflictPrev)
  of claBuild:
    return CommandModeResult(kind: cmrBuild)
  of claDebug:
    return CommandModeResult(kind: cmrDebug)
  of claConfig:
    return CommandModeResult(kind: cmrConfig)
  of claPutConfigFile:
    return CommandModeResult(kind: cmrPutConfigFile)
  of claMan:
    return CommandModeResult(kind: cmrMan, manPage: cmdResult.manPage)
  of claTheme:
    return CommandModeResult(kind: cmrTheme, themeName: cmdResult.themeName)
  of claLspLog:
    return CommandModeResult(kind: cmrLspLog)
  of claLspFormat:
    return CommandModeResult(kind: cmrLspFormat)
  of claLspRestart:
    return CommandModeResult(kind: cmrLspRestart)
  of claLspFold:
    return CommandModeResult(kind: cmrLspFold)
  of claLspExecuteCommand:
    return CommandModeResult(
      kind: cmrLspExecuteCommand,
      lspCommand: cmdResult.lspCommand,
      lspCommandArgs: cmdResult.lspCommandArgs,
    )
  of claLspCallHierarchyIncoming:
    return CommandModeResult(kind: cmrLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    return CommandModeResult(kind: cmrLspCallHierarchyOutgoing)
  of claTerminal:
    return
      CommandModeResult(kind: cmrTerminal, terminalCommand: cmdResult.terminalCommand)
  of claSubstitute:
    return handler.executeSubstitute(
      buffer, cmdResult.pattern, cmdResult.replacement, cmdResult.substituteFlags,
      cmdResult.hasRange, cmdResult.isGlobal, cmdResult.startLine, cmdResult.endLine,
      currentLine,
    )
  of claDeleteLines:
    return handler.executeDelete(
      buffer, cmdResult.deleteHasRange, cmdResult.deleteIsGlobal,
      cmdResult.deleteStartLine, cmdResult.deleteEndLine, currentLine,
    )
  of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
    let modes =
      case cmdResult.kind
      of claNmap:
        @[EditorMode.Normal]
      of claImap:
        @[EditorMode.Insert]
      of claVmap:
        @[EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]
      of claRmap:
        @[EditorMode.Replace]
      of claCmap:
        @[EditorMode.Command]
      else:
        # claMap: all editable modes
        @[
          EditorMode.Normal, EditorMode.Insert, EditorMode.Visual,
          EditorMode.VisualBlock, EditorMode.VisualLine, EditorMode.Replace,
        ]
    if cmdResult.mapLhs == "":
      # No arguments: list mappings
      return CommandModeResult(kind: cmrMapList, mapListModes: modes)
    return CommandModeResult(
      kind: cmrMapAdd,
      mapAddLhs: cmdResult.mapLhs,
      mapAddRhs: cmdResult.mapRhs,
      mapAddModes: modes,
    )
  of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
    let modes =
      case cmdResult.kind
      of claNunmap:
        @[EditorMode.Normal]
      of claIunmap:
        @[EditorMode.Insert]
      of claVunmap:
        @[EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]
      of claRunmap:
        @[EditorMode.Replace]
      of claCunmap:
        @[EditorMode.Command]
      else:
        @[
          EditorMode.Normal, EditorMode.Insert, EditorMode.Visual,
          EditorMode.VisualBlock, EditorMode.VisualLine, EditorMode.Replace,
        ]
    return CommandModeResult(
      kind: cmrMapRemove, mapRemoveLhs: cmdResult.unmapLhs, mapRemoveModes: modes
    )
  of claMapclear, claNmapclear, claImapclear, claVmapclear, claRmapclear, claCmapclear:
    let modes =
      case cmdResult.kind
      of claNmapclear:
        @[EditorMode.Normal]
      of claImapclear:
        @[EditorMode.Insert]
      of claVmapclear:
        @[EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]
      of claRmapclear:
        @[EditorMode.Replace]
      of claCmapclear:
        @[EditorMode.Command]
      else:
        @[
          EditorMode.Normal, EditorMode.Insert, EditorMode.Visual,
          EditorMode.VisualBlock, EditorMode.VisualLine, EditorMode.Replace,
        ]
    return CommandModeResult(kind: cmrMapClear, mapClearModes: modes)
  of claOnlyWindow:
    return CommandModeResult(kind: cmrOnlyWindow)
  of claEditConfigFile:
    let configPath = getConfigPath()
    return
      CommandModeResult(kind: cmrEdit, editFilename: some(configPath), forceEdit: false)
  of claFileTree:
    return CommandModeResult(
      kind: cmrFileTree,
      fileTreePath:
        if cmdResult.kind == claFileTree:
          cmdResult.fileTreePath
        else:
          none(string),
    )
  of claCquit:
    return CommandModeResult(kind: cmrCquit)
  of claUnknown:
    return CommandModeResult(kind: cmrError, errorMessage: cmdResult.errorMessage)

proc shouldQuit*(cmdResult: CommandModeResult): bool =
  ## Check if the application should quit
  cmdResult.kind in {cmrQuit, cmrCquit}

proc shouldSwitchMode*(cmdResult: CommandModeResult): bool =
  ## Check if mode should be switched
  cmdResult.kind == cmrModeSwitch

proc getTargetMode*(cmdResult: CommandModeResult): EditorMode =
  ## Get the target mode for switching
  if cmdResult.kind == cmrModeSwitch:
    cmdResult.targetMode
  else:
    EditorMode.Normal # Default fallback

proc hasError*(cmdResult: CommandModeResult): bool =
  ## Check if there was an error
  cmdResult.kind == cmrError

proc getMessage*(cmdResult: CommandModeResult): string =
  ## Get message or error message
  case cmdResult.kind
  of cmrMessage: cmdResult.message
  of cmrError: cmdResult.errorMessage
  else: ""
