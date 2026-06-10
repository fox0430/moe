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

## Mode-specific dispatchers
##
## Houses the per-mode dispatchers that translate sub-handler results into
## HandlerResult values. These are the non-recursive part of the dispatcher
## layer: each proc here calls into a single sub-handler and converts its
## result kind to a HandlerResult. The recursive cluster (Normal mode +
## handleKeyCombo + playbackMacro + checkRuntimeKeySeqMapping) lives in
## handler_manager.nim.
##
## dispatchSubStateMode is also kept here because it only forwards to the
## sub-state-mode dispatchers in this file.

import std/[options, strutils, unicode]

import pkg/[results, celina]

import
  ../[
    types, buffer, modes, key_bindings, string_builder, filer, filetree, diff_viewer,
    recent_file_mode,
  ]
import ../lsp/protocol/types as lspTypes
import ../types/editor_types
import handler_types, handler_result
import
  insert_handler, insert_commands, command_handler, visual_handler, replace_handler,
  filer_handler, filetree_handler, log_viewer_handler, help_handler,
  buffer_manager_handler, bookmark_manager_handler, backup_manager_handler,
  diff_viewer_handler, recent_file_mode_handler, config_handler, references_handler,
  documentsymbol_handler, callhierarchy_handler, terminal_handler

proc extractInsertedText*(transaction: buffer.BufferTransaction): string =
  ## Extract net inserted text from a transaction
  ## Handles insertions and deletions (backspace during insert mode)
  ## Optimized with StringBuilder for O(n) instead of O(n²) performance
  var sb = newStringBuilder()
  for change in transaction.changes:
    case change.kind
    of buffer.ckInsertText:
      sb.add(change.insertText)
    of buffer.ckDeleteText:
      # Backspace - remove from end of accumulated text
      sb.removeLast(change.deletedText.len)
    of buffer.ckInsertLine:
      # Line insertion - add the line text
      sb.add(change.insertLineText)
      # Ensure it ends with newline if it doesn't already
      if change.insertLineText.len == 0 or change.insertLineText[^1] != '\n':
        sb.add("\n")
    of buffer.ckDeleteLine:
      # Line deletion during insert mode (rare, but handle it)
      # We can't easily track which line was deleted, so clear accumulated text
      sb.clear()
    of buffer.ckDeleteRange:
      # Range deletion - remove from end of accumulated text
      sb.removeLast(change.deletedRangeText.len)
    of buffer.ckReplaceLine:
      discard # Line replacement doesn't contribute to inserted text tracking
    of buffer.ckSnapshot:
      discard # Snapshots don't contribute to inserted text tracking
    of buffer.ckTransaction:
      # Nested transaction - recursively extract text
      let nestedTransaction = buffer.BufferTransaction(
        changes: change.transactionChanges,
        description: change.transactionDescription,
        startSeq: 0,
      )
      sb.add(extractInsertedText(nestedTransaction))
  return sb.toString()

proc handleInsertMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
      # Ctrl-o (insert-normal mode): skip transaction commit/cleanup,
      # keep insert state intact so we can resume after one Normal command
      if state.insertNormalMode:
        return HandlerResult(
          kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
        )

      clearAutoIndentIfUnedited(buffer, state)

      # Extract inserted text before committing transaction
      if buffer.currentTransaction.isSome and state.editState.insertModeStartPos.isSome:
        let transaction = buffer.currentTransaction.get
        let insertedText = extractInsertedText(transaction)

        # Visual Block insert replication: replicate inserted text to all block lines
        if state.editState.visualBlockInsertContext.isSome:
          if insertedText.len > 0:
            let ctx = state.editState.visualBlockInsertContext.get
            for lineNum in (ctx.startLine + 1) .. min(ctx.endLine, buffer.len - 1):
              let lineCharLen = buffer.getLine(lineNum).runeLen
              let col = ctx.insertColumn
              # Pad with spaces if line is shorter than the target column
              if col > lineCharLen:
                let padding = ' '.repeat(col - lineCharLen)
                discard buffer.insertText(
                  BufferPosition(line: lineNum, column: lineCharLen), padding
                )
              discard buffer.insertText(
                BufferPosition(line: lineNum, column: col), insertedText
              )
          # Always clear context when leaving insert mode
          state.editState.visualBlockInsertContext =
            none(types.VisualBlockInsertContext)

        # Record the insert command for repeat (.) if text was actually inserted
        if insertedText.len > 0:
          # Check if we entered Insert mode via substitute command (s/S/cc)
          if state.editState.substituteContext.isSome:
            let subCtx = state.editState.substituteContext.get
            state.editState.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecSubstitute,
                substituteText: insertedText,
                substituteCount: subCtx.deleteCount,
                substituteKind: subCtx.kind,
              )
            )
          else:
            # Normal insert (i, a, o, O)
            state.editState.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecInsertText,
                insertedText: insertedText,
                insertPosition: state.editState.insertModeStartPos.get,
              )
            )

        # Clear insert position tracking and substitute context
        state.editState.insertModeStartPos = none(BufferPosition)
        state.editState.substituteContext = none(types.SubstituteContext)

      # Commit the transaction when leaving Insert mode
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        # Even if commit fails, allow mode transition so user isn't stuck in Insert mode
        return HandlerResult(
          kind: hrHandled,
          modeTransition: r.modeTransition,
          statusMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of imrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of imrExecCommand:
    # Command mode command alias bridge fired from Insert mode (e.g.
    # `imap K = "bdelete"`). Commit any in-progress insert transaction first
    # so the Command mode command sees a consistent buffer state — otherwise
    # an open transaction could be left dangling across buffer switches
    # performed by `:bdelete` / `:bnext`.
    if buffer.inTransaction:
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        return HandlerResult(
          kind: hrError,
          errorMessage: "Failed to commit transaction: " & transactionResult.error,
        )
      state.editState.insertModeStartPos = none(BufferPosition)
    return HandlerResult(
      kind: hrExecCommand, execCommandText: r.execCommandText, execCommandCount: 1
    )
  of imrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
): HandlerResult =
  ## Handle Command mode input (when Enter is pressed)
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  ## currentLine: current cursor line (0-based), used for range substitution with '.'
  let r = manager.commandHandler.handleCommandModeInput(
    buffer, commandText, isSharedBuffer, currentLine
  )

  case r.kind
  of cmrQuit:
    return HandlerResult(kind: hrQuit)
  of cmrCquit:
    return HandlerResult(kind: hrCquit)
  of cmrCloseWindow:
    return HandlerResult(kind: hrCloseWindow, forceClose: r.forceClose)
  of cmrModeSwitch:
    return HandlerResult(
      kind: hrHandled, modeTransition: some(r.targetMode), statusMessage: ""
    )
  of cmrMessage:
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: r.message
    )
  of cmrGotoLine:
    return HandlerResult(kind: hrGotoLine, lineNumber: r.lineNumber)
  of cmrVSplit:
    return HandlerResult(kind: hrVSplit, vsplitFilename: r.vsplitFilename)
  of cmrHSplit:
    return HandlerResult(kind: hrHSplit, hsplitFilename: r.hsplitFilename)
  of cmrNew:
    return HandlerResult(kind: hrNew)
  of cmrVnew:
    return HandlerResult(kind: hrVnew)
  of cmrEnew:
    return HandlerResult(kind: hrEnew)
  of cmrEdit:
    return
      HandlerResult(kind: hrEdit, editFilename: r.editFilename, forceEdit: r.forceEdit)
  of cmrSetBoolOption:
    return HandlerResult(
      kind: hrSetBoolOption, boolOption: r.boolOption, boolValue: r.boolValue
    )
  of cmrSetIntOption:
    return
      HandlerResult(kind: hrSetIntOption, intOption: r.intOption, intValue: r.intValue)
  of cmrSetFloatOption:
    return HandlerResult(
      kind: hrSetFloatOption, floatOption: r.floatOption, floatValue: r.floatValue
    )
  of cmrClearSearchHighlight:
    return HandlerResult(kind: hrClearSearchHighlight)
  of cmrShellCommand:
    return HandlerResult(kind: hrShellCommand, shellCommand: r.shellCommand)
  of cmrBackground:
    return HandlerResult(kind: hrBackground)
  of cmrSave:
    return
      HandlerResult(kind: hrSave, saveFilename: r.saveFilename, forceSave: r.forceSave)
  of cmrSaveAll:
    return HandlerResult(kind: hrSaveAll, forceSaveAll: r.forceSaveAll)
  of cmrSaveAndQuit:
    return HandlerResult(
      kind: hrSaveAndQuit,
      saveAndQuitFilename: r.saveAndQuitFilename,
      forceQuitAfterSave: r.forceSaveAndQuit,
    )
  of cmrSaveAllAndQuit:
    return HandlerResult(
      kind: hrSaveAllAndQuit, forceSaveAllAndQuitAfter: r.forceSaveAllAndQuit
    )
  of cmrBufferNext:
    return HandlerResult(kind: hrBufferNext)
  of cmrBufferPrev:
    return HandlerResult(kind: hrBufferPrev)
  of cmrBufferFirst:
    return HandlerResult(kind: hrBufferFirst)
  of cmrBufferLast:
    return HandlerResult(kind: hrBufferLast)
  of cmrBufferDelete:
    return HandlerResult(kind: hrBufferDelete, forceBufferDelete: r.forceBufferDelete)
  of cmrBuffer:
    return HandlerResult(kind: hrBuffer, bufferArg: r.bufferArg)
  of cmrStripWhitespace:
    return
      HandlerResult(kind: hrStripWhitespace, strippedLineCount: r.strippedLineCount)
  of cmrFiler:
    # Switch to Filer mode with optional path
    return HandlerResult(kind: hrEnterFiler, enterFilerPath: r.filerPath)
  of cmrLogViewer:
    # Switch to LogViewer mode
    return HandlerResult(kind: hrEnterLogViewer)
  of cmrHelpViewer:
    # Switch to HelpViewer mode
    return HandlerResult(kind: hrEnterHelpViewer)
  of cmrQuickRun:
    return HandlerResult(kind: hrQuickRun)
  of cmrBufferManager:
    return HandlerResult(kind: hrEnterBufferManager)
  of cmrBackupManager:
    return HandlerResult(kind: hrEnterBackupManager)
  of cmrRecentFile:
    return HandlerResult(kind: hrRecentFile)
  of cmrJumpList:
    return HandlerResult(kind: hrJumpList)
  of cmrChanges:
    return HandlerResult(kind: hrChanges)
  of cmrBookmarks:
    return HandlerResult(kind: hrEnterBookmarkManager)
  of cmrConflictNext:
    return HandlerResult(kind: hrConflictNext)
  of cmrConflictPrev:
    return HandlerResult(kind: hrConflictPrev)
  of cmrBuild:
    return HandlerResult(kind: hrBuild)
  of cmrDebug:
    return HandlerResult(kind: hrDebug)
  of cmrConfig:
    return HandlerResult(kind: hrConfig)
  of cmrPutConfigFile:
    return HandlerResult(kind: hrPutConfigFile)
  of cmrMan:
    return HandlerResult(kind: hrMan, hrManPage: r.manPage)
  of cmrTheme:
    return HandlerResult(kind: hrTheme, hrThemeName: r.themeName)
  of cmrLspLog:
    return HandlerResult(kind: hrLspLog)
  of cmrLspFormat:
    return HandlerResult(kind: hrLspFormat)
  of cmrLspRestart:
    return HandlerResult(kind: hrLspRestart)
  of cmrLspFold:
    return HandlerResult(kind: hrLspFold)
  of cmrLspExecuteCommand:
    return HandlerResult(
      kind: hrLspExecuteCommand,
      hrLspCommand: r.lspCommand,
      hrLspCommandArgs: r.lspCommandArgs,
    )
  of cmrLspCallHierarchyIncoming:
    return HandlerResult(kind: hrLspCallHierarchyIncoming)
  of cmrLspCallHierarchyOutgoing:
    return HandlerResult(kind: hrLspCallHierarchyOutgoing)
  of cmrSubstitute:
    return HandlerResult(kind: hrSubstitute, hrSubstituteCount: r.substituteCount)
  of cmrDeleteLines:
    return HandlerResult(
      kind: hrDeleteLines,
      hrDeletedText: r.deletedText,
      hrDeletedLineCount: r.deletedLineCount,
    )
  of cmrTerminal:
    return HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: r.terminalCommand)
  of cmrMapList:
    var lines: seq[string] = @[]
    for mode in r.mapListModes:
      let mappings = manager.keyBindingRegistry.listRuntimeMappings(mode)
      for m in mappings:
        lines.add(modeLabel(mode) & "  " & m)
    let msg =
      if lines.len > 0:
        lines.join("\n")
      else:
        "No mapping"
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of cmrMapAdd:
    var firstError = ""
    var modeNames: seq[string] = @[]
    for mode in r.mapAddModes:
      let err =
        manager.keyBindingRegistry.addRuntimeMapping(mode, r.mapAddLhs, r.mapAddRhs)
      if err.len > 0:
        if firstError.len == 0:
          firstError = err
      else:
        modeNames.add(modeLabel(mode))
    if firstError.len > 0:
      return HandlerResult(kind: hrError, errorMessage: firstError)
    let msg =
      "Mapped in " & modeNames.join(", ") & ": " & r.mapAddLhs & " -> " & r.mapAddRhs
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of cmrMapRemove:
    var firstError = ""
    var modeNames: seq[string] = @[]
    for mode in r.mapRemoveModes:
      let err = manager.keyBindingRegistry.removeRuntimeMapping(mode, r.mapRemoveLhs)
      if err.len > 0:
        if firstError.len == 0:
          firstError = err
      else:
        modeNames.add(modeLabel(mode))
    if firstError.len > 0:
      return HandlerResult(kind: hrError, errorMessage: firstError)
    let msg = "Unmapped in " & modeNames.join(", ") & ": " & r.mapRemoveLhs
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of cmrMapClear:
    var modeNames: seq[string] = @[]
    for mode in r.mapClearModes:
      manager.keyBindingRegistry.clearRuntimeMappings(mode)
      modeNames.add(modeLabel(mode))
    let msg = "Cleared " & modeNames.join(", ") & " mode mappings"
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of cmrOnlyWindow:
    return HandlerResult(kind: hrOnlyWindow)
  of cmrFileTree:
    return HandlerResult(kind: hrEnterFileTree, enterFileTreePath: r.fileTreePath)
  of cmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Command mode key events (for macro playback)
  ## This builds up the command text character by character

  # Record key for macro if recording is active
  if state.macroState.isRecording:
    state.macroState.recordedKeys.add(keyComboToString(keyCombo))

  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      # Cancel command mode
      state.commandText = ""
      state.commandCursor = 0
      return HandlerResult(
        kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: ""
      )
    of skEnter:
      # Execute the command
      let commandText = state.commandText
      state.commandText = ""
      state.commandCursor = 0
      return manager.handleCommandMode(buffer, commandText, false, state.cursor.line)
    of skBackspace:
      # Delete character (rune) before cursor - handles unicode properly
      if state.commandCursor > 1: # Keep the ":" prefix
        let beforeCursor = state.commandText[0 ..< state.commandCursor]
        let afterCursor = state.commandText[state.commandCursor ..^ 1]
        # Convert to runes and remove last one
        var runes = beforeCursor.toRunes
        if runes.len > 1: # Keep the ":" prefix
          runes.setLen(runes.len - 1)
          let newBefore = $runes
          state.commandText = newBefore & afterCursor
          state.commandCursor = newBefore.len
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    of skLeft:
      # Move cursor left by one rune (handles unicode properly)
      if state.commandCursor > 1:
        let beforeCursor = state.commandText[0 ..< state.commandCursor]
        let runes = beforeCursor.toRunes
        if runes.len > 1: # Keep cursor after ":"
          state.commandCursor = ($runes[0 ..< runes.len - 1]).len
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    of skRight:
      # Move cursor right by one rune (handles unicode properly)
      if state.commandCursor < state.commandText.len:
        let afterCursor = state.commandText[state.commandCursor ..^ 1]
        let runes = afterCursor.toRunes
        if runes.len > 0:
          state.commandCursor += ($runes[0]).len
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    of skHome:
      state.commandCursor = 1 # After ":"
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    of skEnd:
      state.commandCursor = state.commandText.len
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    else:
      return HandlerResult(kind: hrUnhandled)
  else:
    # Regular character - insert at cursor position
    if keyCombo.modifiers == {} and keyCombo.char.len > 0:
      state.commandText =
        state.commandText[0 ..< state.commandCursor] & keyCombo.char &
        state.commandText[state.commandCursor ..^ 1]
      state.commandCursor += keyCombo.char.len
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    else:
      return HandlerResult(kind: hrUnhandled)

proc handleSearchMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Search mode key events (for macro playback)
  ## This builds up the search text character by character

  # Record key for macro if recording is active
  if state.macroState.isRecording:
    state.macroState.recordedKeys.add(keyComboToString(keyCombo))

  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      # Cancel search mode and restore cursor
      state.search.text = ""
      state.cursor = state.search.startPos
      return HandlerResult(
        kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: ""
      )
    of skEnter:
      # Confirm search and switch to Normal mode
      # The search result is already applied via incremental search
      return HandlerResult(
        kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: ""
      )
    of skBackspace:
      # Delete last character (rune) - handles unicode properly
      if state.search.text.len > 0:
        var runes = state.search.text.toRunes
        if runes.len > 0:
          runes.setLen(runes.len - 1)
          state.search.text = $runes
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    else:
      return HandlerResult(kind: hrUnhandled)
  else:
    # Regular character - append to search text
    if keyCombo.modifiers == {} and keyCombo.char.len > 0:
      state.search.text.add(keyCombo.char)
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    else:
      return HandlerResult(kind: hrUnhandled)

proc handleVisualMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Visual mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  let r =
    manager.visualHandler.handleVisualModeKey(buffer, state, editor.viewport, keyCombo)
  case r.kind
  of vmrHandled:
    # Check if we're entering Insert mode (e.g., visual block I command)
    if r.modeTransition.isSome and r.modeTransition.get == EditorMode.Insert:
      # Begin a transaction so commitTransaction() succeeds when leaving Insert mode
      # Guard: visualChange already commits its delete transaction, so don't double-begin
      if not buffer.inTransaction:
        let transactionResult = buffer.beginTransaction(
          "Visual to insert mode", cursorPos = some(state.cursor)
        )
        if transactionResult.isErr:
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
      state.editState.insertModeStartPos = some(state.cursor)
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of vmrWaitingForInput:
    # Waiting for additional character input (e.g., visual replace char)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of vmrLspSelectionRange:
    # Execute LSP selection range
    return HandlerResult(kind: hrLspSelectionRange)
  of vmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of vmrExecCommand:
    # Command mode command alias bridge fired from a Visual mode
    # (`xnoremap K = "bdelete"`). Visual mode has no buffer transaction; just
    # forward the alias.
    return HandlerResult(
      kind: hrExecCommand, execCommandText: r.execCommandText, execCommandCount: 1
    )
  of vmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReplaceMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Replace mode input
  let buffer = editor.activeBuffer
  let r = manager.replaceHandler.handleReplaceModeKey(buffer, editor.state, keyCombo)
  case r.kind
  of rmrHandled:
    # Check if we're leaving Replace mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Replace:
      # Commit the transaction when leaving Replace mode
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        # Even if commit fails, allow mode transition so user isn't stuck in Replace mode
        return HandlerResult(
          kind: hrHandled,
          modeTransition: r.modeTransition,
          statusMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleFilerMode*(
    manager: HandlerManager,
    filerState: FilerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Filer mode input
  let r = handleFilerModeKey(filerState, viewportHeight, keyCombo)
  case r.kind
  of frHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of frOpenFile:
    return HandlerResult(kind: hrFilerOpenFile, filerFilePath: r.filePath)
  of frOpenFileVSplit:
    return HandlerResult(kind: hrFilerOpenFileVSplit, filerFilePath: r.filePath)
  of frOpenFileHSplit:
    return HandlerResult(kind: hrFilerOpenFileHSplit, filerFilePath: r.filePath)
  of frOpenDirectory:
    # Directory navigation is handled within the filer state
    discard filerState.enterDirectory(r.dirPath)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of frEnterCommand:
    # Enter command mode from filer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of frDeleteFile:
    return HandlerResult(kind: hrFilerDeleteFile, filerDeletePath: r.deletePath)
  of frShowInfo:
    return HandlerResult(kind: hrFilerShowInfo, filerFileInfo: r.fileInfo)
  of frUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of frError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleFileTreeMode*(
    manager: HandlerManager,
    fileTreeState: FileTreeState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle FileTree mode input
  let r = handleFileTreeModeKey(fileTreeState, viewportHeight, keyCombo)

  # Transfer any error from fileTree operations to the status message
  if fileTreeState.lastError.len > 0:
    state.statusMessage = fileTreeState.lastError
    fileTreeState.lastError = ""

  # Display search prompt or status message
  if fileTreeState.isSearching:
    state.statusMessage = "/" & fileTreeState.searchText
  else:
    state.statusMessage = r.statusMessage

  case r.kind
  of ftrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of ftrOpenFile:
    return HandlerResult(kind: hrFileTreeOpenFile, fileTreeFilePath: r.filePath)
  of ftrEnterCommand:
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of ftrNextWindow:
    return HandlerResult(kind: hrNextWindow)
  of ftrPrevWindow:
    return HandlerResult(kind: hrPrevWindow)
  of ftrIncreaseWindowWidth:
    return HandlerResult(kind: hrIncreaseWindowWidth)
  of ftrDecreaseWindowWidth:
    return HandlerResult(kind: hrDecreaseWindowWidth)
  of ftrClearSearchHighlight:
    # Double-Escape: clear the persisted search highlight. FileTree search is
    # self-contained (its own match list, not the global hlsearch gate), so the
    # clear is applied here rather than through state.search.
    fileTreeState.clearSearch()
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of ftrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of ftrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleLogViewerMode*(
    manager: HandlerManager,
    logState: LogViewerState,
    buffer: TextBuffer,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Log Viewer mode input
  let r = handleLogViewerModeKey(logState, buffer, state, viewportHeight, keyCombo)
  case r.kind
  of lvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrEnterCommand:
    # Enter command mode from log viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of lvrEnterSearchForward:
    # Enter search overlay (forward) from log viewer
    state.enterSearchOverlay(Forward)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrEnterSearchBackward:
    # Enter search overlay (backward) from log viewer
    state.enterSearchOverlay(Backward)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrQuit:
    return HandlerResult(kind: hrLogViewerQuit)
  of lvrRefresh:
    return HandlerResult(kind: hrLogViewerRefresh)
  of lvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of lvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReferencesMode*(
    manager: HandlerManager,
    refState: ReferencesViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle References Viewer mode input
  let r = handleReferencesModeKey(refState, viewportHeight, keyCombo)
  case r.kind
  of rvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of rvrEnterCommand:
    # Enter command mode from references viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of rvrJumpToReference:
    return HandlerResult(
      kind: hrReferencesJumpTo,
      jumpToPath: r.targetItem.path,
      jumpToLine: r.targetItem.line,
      jumpToColumn: r.targetItem.column,
    )
  of rvrQuit:
    return HandlerResult(kind: hrReferencesQuit)
  of rvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleDocumentSymbolMode*(
    manager: HandlerManager,
    symState: DocumentSymbolViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Document Symbol Viewer mode input
  let r = handleDocumentSymbolModeKey(symState, viewportHeight, keyCombo)
  case r.kind
  of dsvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of dsvrEnterCommand:
    # Enter command mode from document symbol viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of dsvrQuit:
    return HandlerResult(kind: hrDocumentSymbolQuit)
  of dsvrJumpToSymbol:
    return HandlerResult(
      kind: hrDocumentSymbolJumpTo,
      symbolLine: r.targetItem.line,
      symbolColumn: r.targetItem.column,
    )
  of dsvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of dsvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCallHierarchyMode*(
    manager: HandlerManager,
    chState: CallHierarchyViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Call Hierarchy Viewer mode input
  let r = handleCallHierarchyModeKey(chState, viewportHeight, keyCombo)
  case r.kind
  of chvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of chvrEnterCommand:
    # Enter command mode from call hierarchy viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of chvrQuit:
    return HandlerResult(kind: hrCallHierarchyQuit)
  of chvrJumpToItem:
    return HandlerResult(
      kind: hrCallHierarchyJumpTo,
      callHierarchyJumpUri: r.targetItem.uri,
      callHierarchyJumpLine: r.targetItem.selectionRange.start.line,
      callHierarchyJumpColumn: r.targetItem.selectionRange.start.character,
    )
  of chvrRequestIncoming:
    return HandlerResult(
      kind: hrCallHierarchyRequestIncoming, callHierarchyIncomingItem: r.targetItem
    )
  of chvrRequestOutgoing:
    return HandlerResult(
      kind: hrCallHierarchyRequestOutgoing, callHierarchyOutgoingItem: r.targetItem
    )
  of chvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of chvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleHelpViewerMode*(
    manager: HandlerManager,
    helpState: HelpViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Help Viewer mode input
  let r = handleHelpViewerModeKey(helpState, viewportHeight, keyCombo)
  case r.kind
  of hvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrEnterCommand:
    # Enter command mode from help viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of hvrEnterSearch:
    # Enter search mode (forward) from help viewer.
    # historyIndex/text/etc. are reset by enterSearchOverlay on transition.
    state.search.direction = Forward
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of hvrEnterSearchBackward:
    # Enter search mode (backward) from help viewer
    state.search.direction = Backward
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of hvrRepeatSearch:
    # n/N jumped to a match: re-enable the global hlsearch gate (like Vim's n
    # after :noh) so the highlight comes back across all windows/modes.
    state.search.hlsearchTempDisabled = false
    state.windowDisplay.needsFullRedraw = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrClearSearchHighlight:
    # Double-Escape: clear search highlight in help viewer
    state.search.hlsearchTempDisabled = true
    state.windowDisplay.needsFullRedraw = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrQuit:
    return HandlerResult(kind: hrHelpViewerQuit)
  of hvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of hvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBufferManagerMode*(
    manager: HandlerManager,
    bmState: BufferManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Buffer Manager mode input
  let r = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)
  case r.kind
  of bmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bmrSelectBuffer:
    return
      HandlerResult(kind: hrBufferManagerSelectBuffer, selectBufferIndex: r.bufferIndex)
  of bmrDeleteBuffer:
    return HandlerResult(
      kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: r.deleteBufferIndex
    )
  of bmrEnterCommand:
    # Enter command mode from buffer manager
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bmrQuit:
    return HandlerResult(kind: hrBufferManagerQuit)
  of bmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBookmarkManagerMode*(
    manager: HandlerManager,
    bmState: BookmarkManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Bookmark Manager mode input
  let r = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)
  case r.kind
  of bkmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bkmrJumpToBookmark:
    return HandlerResult(
      kind: hrBookmarkManagerJump,
      bookmarkJumpBufferIndex: r.jumpBufferIndex,
      bookmarkJumpLine: r.jumpLine,
    )
  of bkmrDeleteBookmark:
    return HandlerResult(
      kind: hrBookmarkManagerDelete, bookmarkDeleteEntryIndex: r.deleteEntryIndex
    )
  of bkmrEnterCommand:
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bkmrQuit:
    return HandlerResult(kind: hrBookmarkManagerQuit)
  of bkmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bkmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBackupManagerMode*(
    manager: HandlerManager,
    bkState: BackupManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Backup Manager mode input
  let r = handleBackupManagerModeKey(bkState, viewportHeight, keyCombo)
  case r.kind
  of bkmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bkmrRestore:
    return
      HandlerResult(kind: hrBackupManagerRestore, restoreBackupIndex: r.restoreIndex)
  of bkmrDelete:
    return HandlerResult(kind: hrBackupManagerDelete, deleteBackupIndex: r.deleteIndex)
  of bkmrOpenDiff:
    return HandlerResult(kind: hrBackupManagerOpenDiff, diffBackupIndex: r.diffIndex)
  of bkmrRefresh:
    return HandlerResult(kind: hrBackupManagerRefresh)
  of bkmrEnterCommand:
    # Enter command mode from backup manager
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bkmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bkmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleDiffViewerMode*(
    manager: HandlerManager,
    diffState: DiffViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Diff Viewer mode input
  let r = handleDiffViewerModeKey(diffState, viewportHeight, keyCombo)
  case r.kind
  of dvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of dvrEnterCommand:
    # Enter command mode from diff viewer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of dvrQuit:
    return HandlerResult(kind: hrDiffViewerQuit)
  of dvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of dvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleConfigMode*(
    manager: HandlerManager,
    configState: ConfigModeState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Configuration mode input
  let r = handleConfigModeKey(configState, viewportHeight, keyCombo)
  case r.kind
  of cmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrEnterCommand:
    # Enter command mode from config mode
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of cmrEnterSearch:
    # Enter search mode (forward) from config mode.
    # historyIndex/text/etc. are reset by enterSearchOverlay on transition;
    # searchStartIndex is the config-specific anchor for the upcoming search.
    state.search.direction = Forward
    configState.searchStartIndex = configState.selectedIndex
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of cmrEnterSearchBackward:
    # Enter search mode (backward) from config mode
    state.search.direction = Backward
    configState.searchStartIndex = configState.selectedIndex
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of cmrRepeatSearch:
    # n/N jumped to a match: re-enable the global hlsearch gate (like Vim's n
    # after :noh) so the highlight comes back across all windows/modes.
    state.search.hlsearchTempDisabled = false
    state.windowDisplay.needsFullRedraw = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrClearSearchHighlight:
    # Double-Escape: clear search highlight. Disable the global hlsearch gate
    # so every window/mode (buffers, Help, other Config windows) hides matches.
    state.search.hlsearchTempDisabled = true
    state.windowDisplay.needsFullRedraw = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrSaveConfig:
    return HandlerResult(kind: hrConfigSaveConfig)
  of cmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of cmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleRecentFileMode*(
    manager: HandlerManager,
    state: RecentFileModeState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Recent File mode input
  let r = handleRecentFileModeKey(state, viewportHeight, keyCombo)
  case r.kind
  of rfmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rfmrOpenFile:
    return HandlerResult(kind: hrRecentFileOpenFile, recentFilePath: r.filePath)
  of rfmrEnterCommand:
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of rfmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rfmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleTerminalMode*(
    manager: HandlerManager,
    termState: TerminalState,
    state: EditorState,
    keyCombo: KeyCombo,
    window: EditorWindow,
): HandlerResult =
  ## Handle Terminal mode input
  let r = handleTerminalModeKey(termState, keyCombo)
  case r.kind
  of trHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of trSwitchToNormal:
    # Switch to Terminal-Normal sub-mode: snapshot grid to TextBuffer
    let snapshotBuffer = termState.enterNormalSubMode()
    window.buffer = snapshotBuffer
    window.cursor = BufferPosition(line: max(0, snapshotBuffer.len - 1), column: 0)
    window.viewport.topLine = max(0, snapshotBuffer.len - window.viewport.height)
    return HandlerResult(
      kind: hrHandled,
      modeTransition: none(EditorMode),
      statusMessage: "-- TERMINAL NORMAL --",
    )
  of trReturnToInput:
    # Return to Terminal-Input sub-mode: restore placeholder buffer
    termState.exitNormalSubMode()
    window.buffer = newTextBuffer("")
    window.cursor = BufferPosition(line: 0, column: 0)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of trEnterCommand:
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of trQuit:
    return HandlerResult(kind: hrTerminalQuit)
  of trUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of trError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

template dispatchSubState(
    variantKind: ModeStateKind,
    variantField: untyped,
    handlerProc: untyped,
    modeName: string,
): untyped {.dirty.} =
  ## Sub-state mode dispatcher helper. Expands to an early-return in the
  ## caller: forwards to `manager.handlerProc(...)` when the active
  ## window's ModeState variant matches `variantKind`, otherwise returns
  ## an `hrError` HandlerResult with the message
  ## "<modeName> state not initialized".
  ## Requires `manager`, `activeWindow`, `state`, `viewport`, `keyCombo`
  ## to be bound in the caller's scope. Marked `{.dirty.}` so that those
  ## names are resolved at the call site (avoids clashes with same-named
  ## procs such as `editor_types.activeWindow` and `worker.state`).
  if activeWindow.modeState.kind == variantKind:
    return manager.handlerProc(
      activeWindow.modeState.variantField, state, viewport.height, keyCombo
    )
  else:
    return
      HandlerResult(kind: hrError, errorMessage: modeName & " state not initialized")

proc dispatchSubStateMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Dispatch sub-state modes — modes that carry their own per-window state
  ## object on `EditorWindow` (via the `modeState` variant). Called from the
  ## Editor-based handleKeyCombo for any mode it does not handle directly.
  ##
  ## 11 sub-state modes (Filer, FileTree, Help, BufferManager, BookmarkManager,
  ## BackupManager, DiffViewer, Config, References, DocumentSymbol,
  ## CallHierarchy) share the same dispatch shape and use the
  ## `dispatchSubState` template. LogViewer and Terminal have non-standard
  ## handler signatures and remain as explicit branches.
  let buffer = editor.activeBuffer
  let state = editor.state
  let viewport = editor.viewport
  let activeWindow = editor.activeWindow

  case state.mode
  of EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
      EditorMode.VisualLine, EditorMode.Replace:
    # Migrated modes are handled by the Editor-based handleKeyCombo and
    # never reach this dispatcher.
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.Filer:
    dispatchSubState(mskFiler, filer, handleFilerMode, "Filer")
  of EditorMode.FileTree:
    dispatchSubState(mskFileTree, fileTree, handleFileTreeMode, "FileTree")
  of EditorMode.LogViewer:
    # Non-standard handler signature: takes the buffer directly because log
    # content lives in the TextBuffer. LogViewerState is threaded for the
    # per-window key-sequence flags (waitingForG).
    if activeWindow.modeState.kind == mskLogViewer:
      return manager.handleLogViewerMode(
        activeWindow.modeState.logViewer, buffer, state, viewport.height, keyCombo
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Log viewer state not initialized")
  of EditorMode.Help:
    dispatchSubState(mskHelp, help, handleHelpViewerMode, "Help viewer")
  of EditorMode.BufferManager:
    dispatchSubState(
      mskBufferManager, bufferManager, handleBufferManagerMode, "Buffer manager"
    )
  of EditorMode.BookmarkManager:
    dispatchSubState(
      mskBookmarkManager, bookmarkManager, handleBookmarkManagerMode, "Bookmark manager"
    )
  of EditorMode.BackupManager:
    dispatchSubState(
      mskBackupManager, backupManager, handleBackupManagerMode, "Backup manager"
    )
  of EditorMode.DiffViewer:
    dispatchSubState(mskDiffViewer, diffViewer, handleDiffViewerMode, "Diff viewer")
  of EditorMode.Config:
    dispatchSubState(mskConfig, config, handleConfigMode, "Config mode")
  of EditorMode.References:
    dispatchSubState(
      mskReferences, references, handleReferencesMode, "References viewer"
    )
  of EditorMode.DocumentSymbol:
    dispatchSubState(
      mskDocumentSymbol, documentSymbol, handleDocumentSymbolMode,
      "Document symbol viewer",
    )
  of EditorMode.CallHierarchy:
    dispatchSubState(
      mskCallHierarchy, callHierarchy, handleCallHierarchyMode, "Call hierarchy viewer"
    )
  of EditorMode.Terminal:
    # Non-standard handler signature: takes `window` instead of viewport height.
    if activeWindow.modeState.kind == mskTerminal:
      return manager.handleTerminalMode(
        activeWindow.modeState.terminal, state, keyCombo, activeWindow
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Terminal state not initialized")
  of EditorMode.Command, EditorMode.RecentFile, EditorMode.Debug, EditorMode.QuickRun:
    # Command: handled via overlay in handler.nim.
    # RecentFile: requires its own state, handled at a higher level.
    # Debug: handled at a higher level in handler.nim.
    # QuickRun: not interactive, handled through command mode.
    return HandlerResult(kind: hrUnhandled)
