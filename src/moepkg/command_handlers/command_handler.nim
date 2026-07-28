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
## Parses `:cmd` input and produces a `HandlerResult` directly.  Each execute*
## helper corresponds to a specific `CommandLineAction` (cla*) and returns the
## same `HandlerResult` variant that `processResult` consumes, so no
## intermediate cmr layer is required.

import std/[options, os, strutils]

import ../[modes, command_line, command_config, command_registry, config_loader]
import ../buffer/[core, edit, fold, undo]
import ../setting_options
import handler_types, handler_result
export setting_options, handler_types

proc newCommandModeHandler*(
    parser: CommandLineParser, config: CommandConfig, commandRegistry: CommandRegistry
): CommandModeHandler =
  ## Create a new Command mode handler
  CommandModeHandler(parser: parser, config: config, commandRegistry: commandRegistry)

const AllEditableModes = @[
  EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
  EditorMode.VisualLine, EditorMode.Replace,
]

proc unsavedChangesErr(): HandlerResult =
  ## Error returned when a destructive command runs on a modified buffer without
  ## the ! override.
  HandlerResult(
    kind: hrError, errorMessage: "No write since last change (add ! to override)"
  )

proc modesForMapAction(kind: CommandLineAction): seq[EditorMode] =
  ## Resolve the target modes for a :map/:unmap/:mapclear-family action. The
  ## letter prefix (n/i/v/r/c) picks a single mode; the bare form (:map,
  ## :unmap, :mapclear) covers all editable modes.
  case kind
  of claNmap, claNnoremap, claNunmap, claNmapclear:
    @[EditorMode.Normal]
  of claImap, claInoremap, claIunmap, claImapclear:
    @[EditorMode.Insert]
  of claVmap, claVnoremap, claVunmap, claVmapclear:
    @[EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]
  of claRmap, claRunmap, claRmapclear:
    @[EditorMode.Replace]
  of claCmap, claCnoremap, claCunmap, claCmapclear:
    @[EditorMode.Command]
  else:
    AllEditableModes

proc executeQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    isSharedBuffer: bool = false,
): HandlerResult =
  ## Execute quit command (:q, :q!) - closes current window.
  ## isSharedBuffer=true skips the isModified check for shared buffers.
  if not force and not isSharedBuffer:
    if buffer.isModified:
      return unsavedChangesErr()
  return HandlerResult(kind: hrCloseWindow, forceClose: force)

proc executeSave*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute save command (:w, :w!)
  HandlerResult(kind: hrSave, saveFilename: filename, forceSave: force)

proc executeSaveAll*(handler: CommandModeHandler, force: bool): HandlerResult =
  ## Execute save all command (:wa, :wa!)
  HandlerResult(kind: hrSaveAll, forceSaveAll: force)

proc executeSaveAndQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute save and quit command (:wq, :x)
  HandlerResult(
    kind: hrSaveAndQuit, saveAndQuitFilename: filename, forceQuitAfterSave: force
  )

proc executeSaveAllAndQuit*(handler: CommandModeHandler, force: bool): HandlerResult =
  ## Execute save all and quit command (:wqa, :xa, :wqa!)
  HandlerResult(kind: hrSaveAllAndQuit, forceSaveAllAndQuitAfter: force)

proc executeQuitAll*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Execute :qa / :qa!. `otherModifiedCount` covers buffers other than `buffer`.
  if not force:
    let total = (if buffer.isModified: 1 else: 0) + otherModifiedCount
    if total > 0:
      if total == 1:
        return unsavedChangesErr()
      return HandlerResult(
        kind: hrError,
        errorMessage:
          "No write since last change: " & $total &
          " buffers modified (add ! to override)",
      )
  HandlerResult(kind: hrQuit)

proc executeEdit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): HandlerResult =
  ## Execute edit command (:e/:e! with optional filename).
  ## Opens a directory in Filer mode; reloads the current buffer when no
  ## filename is given.
  if filename.isSome:
    let expanded = expandTilde(filename.get)
    if dirExists(expanded):
      return
        HandlerResult(kind: hrEnterFiler, enterFilerPath: some(absolutePath(expanded)))
    return HandlerResult(
      kind: hrEdit, editFilename: some(absolutePath(expanded)), forceEdit: force
    )
  if not force and buffer.isModified:
    return unsavedChangesErr()
  HandlerResult(kind: hrEdit, editFilename: none(string), forceEdit: force)

proc executeGotoLine*(
    handler: CommandModeHandler, buffer: TextBuffer, lineNumber: int
): HandlerResult =
  ## Execute goto line command (:123)
  if lineNumber <= 0:
    return HandlerResult(kind: hrError, errorMessage: "Invalid line number")
  # Clamp to last line if lineNumber exceeds buffer length
  let clampedLine = min(lineNumber, buffer.len)
  HandlerResult(kind: hrGotoLine, lineNumber: clampedLine)

proc parseSetIntValue(spec: SetOptionSpec, value: Option[string]): HandlerResult =
  ## Validate and dispatch an integer-typed `:set X=N` option.
  doAssert spec.kind == sokInt, "parseSetIntValue called with non-int spec"
  if value.isNone:
    return HandlerResult(
      kind: hrError,
      errorMessage:
        spec.longName & " requires a value (e.g., " & spec.longName & "=" &
        $spec.intExample & ")",
    )
  try:
    let intVal = parseInt(value.get)
    if intBoundOk(spec.intBound, intVal):
      return
        HandlerResult(kind: hrSetIntOption, intOption: spec.intOption, intValue: intVal)
    HandlerResult(
      kind: hrError, errorMessage: spec.longName & " " & intBoundError(spec.intBound)
    )
  except ValueError:
    HandlerResult(kind: hrError, errorMessage: "Invalid value for " & spec.longName)

proc parseSetFloatValue(spec: SetOptionSpec, value: Option[string]): HandlerResult =
  ## Validate and dispatch a float-typed `:set X=N.N` option.
  doAssert spec.kind == sokFloat, "parseSetFloatValue called with non-float spec"
  if value.isNone:
    return HandlerResult(
      kind: hrError,
      errorMessage:
        spec.longName & " requires a value (e.g., " & spec.longName & "=" &
        $spec.floatExample & ")",
    )
  try:
    let floatVal = parseFloat(value.get)
    if floatVal >= 0:
      return HandlerResult(
        kind: hrSetFloatOption, floatOption: spec.floatOption, floatValue: floatVal
      )
    HandlerResult(kind: hrError, errorMessage: spec.longName & " must be non-negative")
  except ValueError:
    HandlerResult(kind: hrError, errorMessage: "Invalid value for " & spec.longName)

proc executeSet*(
    handler: CommandModeHandler, option: string, value: Option[string]
): HandlerResult =
  ## Execute set command (:set option=value). Dispatches via `SetOptionTable`
  ## so each `:set` option lives in exactly one place (setting_options.nim).
  let opt = option.toLower
  for spec in SetOptionTable:
    case spec.kind
    of sokBool:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return HandlerResult(
          kind: hrSetBoolOption, boolOption: spec.boolOption, boolValue: true
        )
      let noLong = "no" & spec.longName
      if opt == noLong:
        return HandlerResult(
          kind: hrSetBoolOption, boolOption: spec.boolOption, boolValue: false
        )
      if spec.shortName.len > 0 and opt == "no" & spec.shortName:
        return HandlerResult(
          kind: hrSetBoolOption, boolOption: spec.boolOption, boolValue: false
        )
    of sokInt:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return parseSetIntValue(spec, value)
    of sokFloat:
      if opt == spec.longName or (spec.shortName.len > 0 and opt == spec.shortName):
        return parseSetFloatValue(spec, value)
  HandlerResult(kind: hrError, errorMessage: "Unknown option: " & option)

proc executeHelp*(handler: CommandModeHandler, topic: Option[string]): HandlerResult =
  ## Execute help command (:help, :help topic) - opens the help viewer.
  HandlerResult(kind: hrEnterHelpViewer)

proc executeVSplit*(
    handler: CommandModeHandler, filename: Option[string]
): HandlerResult =
  ## Execute vertical split command (:vs, :vs filename)
  HandlerResult(kind: hrVSplit, vsplitFilename: filename)

proc executeHSplit*(
    handler: CommandModeHandler, filename: Option[string]
): HandlerResult =
  ## Execute horizontal split command (:sp, :sp filename)
  HandlerResult(kind: hrHSplit, hsplitFilename: filename)

proc executeNew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrNew)

proc executeVnew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrVnew)

proc executeEnew*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrEnew)

proc executeBufferNext*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferNext)

proc executeBufferPrev*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferPrev)

proc executeBufferFirst*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferFirst)

proc executeBufferLast*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrBufferLast)

proc executeBuffer*(handler: CommandModeHandler, arg: string): HandlerResult =
  HandlerResult(kind: hrBuffer, bufferArg: arg)

proc executeBufferDelete*(
    handler: CommandModeHandler, buffer: TextBuffer, force: bool
): HandlerResult =
  ## Execute bdelete command (:bd, :bdelete)
  if not force and buffer.isModified:
    return unsavedChangesErr()
  HandlerResult(kind: hrBufferDelete, forceBufferDelete: force)

proc executeStripWhitespace*(
    handler: CommandModeHandler, buffer: TextBuffer
): HandlerResult =
  ## Execute stripwhitespace command (:stripwhitespace, :stripws)
  ## Removes trailing whitespace from all lines.
  if buffer.readOnly:
    return HandlerResult(kind: hrError, errorMessage: "Buffer is read-only")
  var strippedCount = 0
  discard withTransaction(buffer, "stripwhitespace"):
    for lineIdx in 0 ..< buffer.len:
      let line = buffer.getLine(lineIdx)
      let trimmed = line.strip(leading = false, trailing = true)
      if trimmed != line:
        # Reveal the line if it is hidden inside a collapsed fold.
        discard buffer.foldState.openFoldsInRange(lineIdx, lineIdx)
        discard buffer.replaceLine(lineIdx, trimmed)
        strippedCount.inc
  HandlerResult(kind: hrStripWhitespace, strippedLineCount: strippedCount)

proc executeQuickRun*(handler: CommandModeHandler): HandlerResult =
  HandlerResult(kind: hrQuickRun)

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
): HandlerResult =
  ## Execute substitute command (:s, :%s/pattern/replacement/flags)
  if buffer.readOnly:
    return HandlerResult(kind: hrError, errorMessage: "Buffer is read-only")
  if pattern.len == 0:
    return HandlerResult(kind: hrError, errorMessage: "Pattern required")

  let isGlobal = "g" in flags
  var replaceCount = 0

  let processedReplacement = processEscapeSequences(replacement)

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
    if rangeEnd >= buffer.len:
      rangeEnd = buffer.len - 1
    if rangeStart > rangeEnd:
      return HandlerResult(
        kind: hrError, errorMessage: "Invalid range: start line > end line"
      )
  else:
    rangeStart = currentLine
    rangeEnd = currentLine

  discard withTransaction(buffer, "substitute"):
    for lineIdx in rangeStart .. rangeEnd:
      var line = buffer.getLine(lineIdx)
      var modified = false
      var newLine = ""
      var searchPos = 0

      while searchPos <= line.len:
        let idx = line.find(pattern, searchPos)
        if idx < 0:
          newLine.add(line[searchPos ..^ 1])
          break

        if idx > searchPos:
          newLine.add(line[searchPos ..< idx])

        newLine.add(processedReplacement)
        replaceCount.inc
        modified = true

        searchPos = idx + pattern.len

        if not isGlobal:
          newLine.add(line[searchPos ..^ 1])
          break

      if modified:
        discard buffer.foldState.openFoldsInRange(lineIdx, lineIdx)
        discard buffer.replaceLine(lineIdx, newLine)

  if replaceCount == 0:
    return HandlerResult(kind: hrError, errorMessage: "Pattern not found: " & pattern)

  HandlerResult(kind: hrSubstitute, hrSubstituteCount: replaceCount)

proc executeDelete*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    hasRange: bool = false,
    isGlobalRange: bool = false,
    startLine: int = 0,
    endLine: int = 0,
    currentLine: int = 0,
): HandlerResult =
  ## Execute delete command (:d, :%d, :1,10d)
  if buffer.readOnly:
    return HandlerResult(kind: hrError, errorMessage: "Buffer is read-only")
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
      return HandlerResult(
        kind: hrError, errorMessage: "Invalid range: start line > end line"
      )
  else:
    rangeStart = currentLine
    rangeEnd = currentLine

  if rangeStart >= buffer.len:
    return HandlerResult(kind: hrError, errorMessage: "Line out of range")

  var text = ""
  for lineIdx in rangeStart .. rangeEnd:
    if lineIdx > rangeStart:
      text.add("\n")
    text.add(buffer.getLine(lineIdx))
  text.add("\n")

  let lineCount = rangeEnd - rangeStart + 1
  let deletingAll = rangeStart == 0 and rangeEnd == buffer.len - 1

  discard buffer.foldState.openFoldsInRange(rangeStart, rangeEnd)

  discard withTransaction(buffer, "delete lines"):
    if deletingAll:
      for i in countdown(buffer.len - 1, 1):
        discard buffer.deleteLine(i)
      discard buffer.replaceLine(0, "")
    else:
      for i in countdown(rangeEnd, rangeStart):
        discard buffer.deleteLine(i)

  HandlerResult(kind: hrDeleteLines, hrDeletedText: text, hrDeletedLineCount: lineCount)

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Main entry point for handling Command mode input.
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  ## currentLine: 0-based cursor line, used for range substitution with '.'
  ## otherModifiedCount: modified buffers other than `buffer` (for :qa)

  if commandText.len <= 1: # Just ":"
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: ""
    )

  let cmdResult = handler.parser.parseAndExecute(commandText)

  case cmdResult.kind
  of claQuit:
    handler.executeQuit(buffer, cmdResult.forceQuit, isSharedBuffer)
  of claQuitAll:
    handler.executeQuitAll(buffer, cmdResult.forceQuitAll, otherModifiedCount)
  of claSave:
    handler.executeSave(buffer, cmdResult.filename, cmdResult.forceSave)
  of claSaveAll:
    handler.executeSaveAll(cmdResult.forceSaveAll)
  of claSaveAndQuit:
    handler.executeSaveAndQuit(
      buffer, cmdResult.saveFilename, cmdResult.forceSaveAndQuit
    )
  of claSaveAllAndQuit:
    handler.executeSaveAllAndQuit(cmdResult.forceSaveAllAndQuit)
  of claEdit:
    handler.executeEdit(buffer, cmdResult.editFilename, cmdResult.forceEdit)
  of claEnew:
    handler.executeEnew()
  of claGoto:
    handler.executeGotoLine(buffer, cmdResult.lineNumber)
  of claSet:
    handler.executeSet(cmdResult.option, cmdResult.value)
  of claHelp:
    handler.executeHelp(cmdResult.topic)
  of claVSplit:
    handler.executeVSplit(cmdResult.vsplitFilename)
  of claHSplit:
    handler.executeHSplit(cmdResult.hsplitFilename)
  of claNew:
    handler.executeNew()
  of claVnew:
    handler.executeVnew()
  of claBufferNext:
    handler.executeBufferNext()
  of claBufferPrev:
    handler.executeBufferPrev()
  of claBufferFirst:
    handler.executeBufferFirst()
  of claBufferLast:
    handler.executeBufferLast()
  of claBufferDelete:
    handler.executeBufferDelete(buffer, cmdResult.forceBufferDelete)
  of claBuffer:
    handler.executeBuffer(cmdResult.bufferArg)
  of claStripWhitespace:
    handler.executeStripWhitespace(buffer)
  of claFiler:
    HandlerResult(kind: hrEnterFiler, enterFilerPath: cmdResult.filerPath)
  of claLogViewer:
    HandlerResult(kind: hrEnterLogViewer)
  of claQuickRun:
    handler.executeQuickRun()
  of claBufferManager:
    HandlerResult(kind: hrEnterBufferManager)
  of claBackupManager:
    HandlerResult(kind: hrEnterBackupManager)
  of claRecentFile:
    when defined(macosx):
      HandlerResult(kind: hrError, errorMessage: ":recent is not supported on macOS")
    else:
      HandlerResult(kind: hrRecentFile)
  of claClearSearchHighlight:
    HandlerResult(kind: hrClearSearchHighlight)
  of claShellCommand:
    HandlerResult(kind: hrShellCommand, shellCommand: cmdResult.shellCommand)
  of claBackground:
    HandlerResult(kind: hrBackground)
  of claJumpList:
    HandlerResult(kind: hrJumpList)
  of claChanges:
    HandlerResult(kind: hrChanges)
  of claBookmarks:
    HandlerResult(kind: hrEnterBookmarkManager)
  of claConflictNext:
    HandlerResult(kind: hrConflictNext)
  of claConflictPrev:
    HandlerResult(kind: hrConflictPrev)
  of claBuild:
    HandlerResult(kind: hrBuild)
  of claDebug:
    HandlerResult(kind: hrDebug)
  of claConfig:
    HandlerResult(kind: hrConfig)
  of claPutConfigFile:
    HandlerResult(kind: hrPutConfigFile)
  of claMan:
    HandlerResult(kind: hrMan, hrManPage: cmdResult.manPage)
  of claTheme:
    HandlerResult(kind: hrTheme, hrThemeName: cmdResult.themeName)
  of claLspLog:
    HandlerResult(kind: hrLspLog)
  of claLspFormat:
    HandlerResult(kind: hrLspFormat)
  of claLspRestart:
    HandlerResult(kind: hrLspRestart)
  of claLspFold:
    HandlerResult(kind: hrLspFold)
  of claLspExecuteCommand:
    HandlerResult(
      kind: hrLspExecuteCommand,
      hrLspCommand: cmdResult.lspCommand,
      hrLspCommandArgs: cmdResult.lspCommandArgs,
    )
  of claLspCallHierarchyIncoming:
    HandlerResult(kind: hrLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    HandlerResult(kind: hrLspCallHierarchyOutgoing)
  of claTerminal:
    HandlerResult(
      kind: hrEnterTerminal, enterTerminalCommand: cmdResult.terminalCommand
    )
  of claSubstitute:
    handler.executeSubstitute(
      buffer, cmdResult.pattern, cmdResult.replacement, cmdResult.substituteFlags,
      cmdResult.hasRange, cmdResult.isGlobal, cmdResult.startLine, cmdResult.endLine,
      currentLine,
    )
  of claDeleteLines:
    handler.executeDelete(
      buffer, cmdResult.deleteHasRange, cmdResult.deleteIsGlobal,
      cmdResult.deleteStartLine, cmdResult.deleteEndLine, currentLine,
    )
  of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
    let modes = modesForMapAction(cmdResult.kind)
    if cmdResult.mapRhs == "":
      # No rhs: list mappings. mapLhs (if any) filters by prefix.
      HandlerResult(
        kind: hrMapList, mapListModes: modes, mapListPrefix: cmdResult.mapLhs
      )
    else:
      HandlerResult(
        kind: hrMapAdd,
        mapAddLhs: cmdResult.mapLhs,
        mapAddRhs: cmdResult.mapRhs,
        mapAddModes: modes,
        mapAddNoremap: cmdResult.noremap,
      )
  of claNoremap, claNnoremap, claInoremap, claVnoremap, claCnoremap:
    # Unreachable: the executor folds these onto the base map kind (carrying
    # noremap=true). Present only to keep the case exhaustive.
    HandlerResult(kind: hrError, errorMessage: "internal: unfolded noremap action")
  of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
    HandlerResult(
      kind: hrMapRemove,
      mapRemoveLhs: cmdResult.unmapLhs,
      mapRemoveModes: modesForMapAction(cmdResult.kind),
    )
  of claMapclear, claNmapclear, claImapclear, claVmapclear, claRmapclear, claCmapclear:
    HandlerResult(kind: hrMapClear, mapClearModes: modesForMapAction(cmdResult.kind))
  of claOnlyWindow:
    HandlerResult(kind: hrOnlyWindow)
  of claEditConfigFile:
    let configPath = getConfigPath()
    HandlerResult(kind: hrEdit, editFilename: some(configPath), forceEdit: false)
  of claFileTree:
    HandlerResult(
      kind: hrEnterFileTree,
      enterFileTreePath:
        if cmdResult.kind == claFileTree:
          cmdResult.fileTreePath
        else:
          none(string),
    )
  of claCquit:
    HandlerResult(kind: hrCquit)
  of claUnknown:
    HandlerResult(kind: hrError, errorMessage: cmdResult.errorMessage)
