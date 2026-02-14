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

## Unified handler manager
##
## This module provides a unified interface for all mode-specific handlers,
## maintaining the shared infrastructure while delegating to specialized handlers.

import std/[options, strutils, unicode]

import pkg/[results, celina]

import
  ../[
    types, buffer, modes, motion, key_bindings, command_line, command_config,
    command_registry, config, string_builder, filer, recent_file_mode, lsp_integration,
  ]
import ../lsp/protocol/types as lspTypes
import
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler, log_viewer_handler, help_handler, buffer_manager_handler,
  backup_manager_handler, diff_viewer_handler, recent_file_mode_handler, debug_handler,
  config_handler, references_handler, documentsymbol_handler, callhierarchy_handler

export
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler, log_viewer_handler, help_handler, buffer_manager_handler,
  backup_manager_handler, diff_viewer_handler, recent_file_mode_handler, debug_handler,
  config_handler, references_handler, documentsymbol_handler, callhierarchy_handler

type
  HandlerResultKind* = enum
    hrHandled # Command was handled successfully
    hrQuit # Application should quit
    hrCloseWindow # Close current window
    hrGotoLine # Jump to specific line
    hrVSplit # Vertical split window
    hrHSplit # Horizontal split window
    hrNew # Create new empty buffer in horizontal split
    hrVnew # Create new empty buffer in vertical split
    hrEnew # Create new empty buffer
    hrEdit # Edit/open file in current window
    hrSetBoolOption # Set boolean option
    hrSetIntOption # Set integer option
    hrSetFloatOption # Set float option
    hrClearSearchHighlight # Clear search highlighting
    hrSave # Save file
    hrSaveAndQuit # Save file and quit
    hrBufferNext # Switch to next buffer
    hrBufferPrev # Switch to previous buffer
    hrBufferFirst # Switch to first buffer
    hrBufferLast # Switch to last buffer
    hrBuffer # Switch to buffer by number or name
    hrJumpToBuffer # Jump to specific buffer and position (Ctrl-o/Ctrl-i)
    hrBufferDelete # Delete current buffer
    hrStripWhitespace # Remove trailing whitespace
    hrFilerOpenFile # Open file from filer
    hrFilerOpenFileVSplit # Open file from filer in vertical split
    hrFilerOpenFileHSplit # Open file from filer in horizontal split
    hrFilerDeleteFile # Delete file/directory from filer
    hrFilerShowInfo # Show file information
    hrFilerQuit # Close filer and return to previous mode
    hrEnterFiler # Enter filer mode with optional path
    hrLogViewerQuit # Close log viewer window
    hrLogViewerRefresh # Refresh log viewer content
    hrEnterLogViewer # Enter log viewer mode
    hrHelpViewerQuit # Close help viewer and return to previous mode
    hrEnterHelpViewer # Enter help viewer mode
    hrQuickRun # Run the current buffer
    hrBufferManagerSelectBuffer # Select and switch to a buffer
    hrBufferManagerDeleteBuffer # Delete a buffer
    hrBufferManagerQuit # Close buffer manager and return to previous mode
    hrEnterBufferManager # Enter buffer manager mode
    hrBackupManagerRestore # Restore a backup file
    hrBackupManagerDelete # Delete a backup file
    hrBackupManagerOpenDiff # Open diff viewer for a backup
    hrBackupManagerRefresh # Refresh backup list
    hrBackupManagerQuit # Close backup manager and return to previous mode
    hrEnterBackupManager # Enter backup manager mode
    hrDiffViewerQuit # Close diff viewer and return to previous mode
    hrEnterDiffViewer # Enter diff viewer mode
    hrRecentFile # Enter recent file selection mode
    hrRecentFileOpenFile # Open file from recent file mode
    hrRecentFileQuit # Quit recent file mode
    hrNextWindow # Move to next window
    hrPrevWindow # Move to previous window
    hrLspGotoDefinition # Execute LSP goto definition
    hrLspGotoDeclaration # Execute LSP goto declaration
    hrLspFindReferences # Execute LSP find references
    hrLspCodeLensExecute # Execute CodeLens on current line
    hrLspCallHierarchyIncoming # Execute LSP incoming calls
    hrLspCallHierarchyOutgoing # Execute LSP outgoing calls
    hrLspTypeDefinition # Execute LSP goto type definition
    hrLspImplementation # Execute LSP goto implementation
    hrLspHover # Execute LSP hover
    hrLspRename # Execute LSP rename
    hrLspSelectionRange # Execute LSP selection range
    hrLspDocumentLink # Execute LSP document link
    hrShellCommand # Execute shell command
    hrBackground # Pause editor and show terminal (:bg)
    hrJumpList # Show jump list (:ju, :jump)
    hrBuild # Build current buffer (:build)
    hrDebug # Open debug mode (:debug)
    hrDebugViewerQuit # Close debug viewer
    hrConfig # Open configuration mode (:conf)
    hrConfigQuit # Close config mode and return to previous mode
    hrConfigSaveConfig # Save configuration to file
    hrPutConfigFile # Write sample config file (:putConfigFile)
    hrMan # Show manual page (:man)
    hrTheme # Change color theme (:theme)
    hrLspLog # Open LSP log viewer (:lspLog)
    hrLspFormat # LSP document formatting (:lspFormat)
    hrLspRestart # Restart LSP server (:lspRestart)
    hrLspFold # LSP folding range (:lspFold)
    hrLspExecuteCommand # LSP execute command (:lspExeCommand)
    hrSubstitute # Search and replace (:s)
    hrReferencesQuit # Close references viewer and return to previous mode
    hrReferencesJumpTo # Jump to the selected reference
    hrEnterReferences # Enter references viewer mode
    hrDocumentSymbolQuit # Close document symbol viewer and return to previous mode
    hrDocumentSymbolJumpTo # Jump to the selected symbol
    hrEnterDocumentSymbol # Enter document symbol viewer mode
    hrCallHierarchyQuit # Close call hierarchy viewer and return to previous mode
    hrCallHierarchyJumpTo # Jump to the selected call hierarchy item
    hrCallHierarchyRequestIncoming # Request incoming calls for selected item
    hrCallHierarchyRequestOutgoing # Request outgoing calls for selected item
    hrEnterCallHierarchy # Enter call hierarchy viewer mode
    hrUnhandled # Command was not handled
    hrError # Error occurred

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    filerHandler*: FilerHandler
    logViewerHandler*: LogViewerHandler
    helpViewerHandler*: HelpViewerHandler
    bufferManagerHandler*: BufferManagerHandler
    backupManagerHandler*: BackupManagerHandler
    diffViewerHandler*: DiffViewerHandler
    recentFileModeHandler*: RecentFileModeHandler
    configModeHandler*: ConfigModeHandler
    referencesHandler*: ReferencesHandler
    documentSymbolHandler*: DocumentSymbolHandler
    callHierarchyHandler*: CallHierarchyHandler
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    commandRegistry*: CommandRegistry

  HandlerResult* = object ## Unified result type for all handlers
    case kind*: HandlerResultKind
    of hrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
      statusMessage*: string
    of hrQuit:
      shouldQuit*: bool
    of hrCloseWindow:
      forceClose*: bool
    of hrGotoLine:
      lineNumber*: int
    of hrVSplit:
      vsplitFilename*: Option[string]
    of hrHSplit:
      hsplitFilename*: Option[string]
    of hrNew:
      discard
    of hrVnew:
      discard
    of hrEnew:
      discard
    of hrEdit:
      editFilename*: string
    of hrSetBoolOption:
      boolOption*: BoolSettingOption
      boolValue*: bool
    of hrSetIntOption:
      intOption*: IntSettingOption
      intValue*: int
    of hrSetFloatOption:
      floatOption*: FloatSettingOption
      floatValue*: float
    of hrClearSearchHighlight:
      discard
    of hrSave:
      saveFilename*: Option[string]
      forceSave*: bool
    of hrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceQuitAfterSave*: bool
    of hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast:
      discard
    of hrBuffer:
      bufferArg*: string # Buffer number or name
    of hrJumpToBuffer:
      jumpBufferIndex*: int # Target buffer index
      jumpLine*: int # Target line number
      jumpColumn*: int # Target column number
    of hrBufferDelete:
      forceBufferDelete*: bool
    of hrStripWhitespace:
      strippedLineCount*: int
    of hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit:
      filerFilePath*: string
    of hrFilerDeleteFile:
      filerDeletePath*: string
    of hrFilerShowInfo:
      filerFileInfo*: string
    of hrFilerQuit:
      discard
    of hrEnterFiler:
      enterFilerPath*: Option[string]
    of hrLogViewerQuit:
      discard
    of hrLogViewerRefresh:
      discard
    of hrEnterLogViewer:
      discard
    of hrHelpViewerQuit:
      discard
    of hrEnterHelpViewer:
      discard
    of hrQuickRun:
      discard
    of hrBufferManagerSelectBuffer:
      selectBufferIndex*: int
    of hrBufferManagerDeleteBuffer:
      deleteBufferIdx*: int
    of hrBufferManagerQuit:
      discard
    of hrEnterBufferManager:
      discard
    of hrBackupManagerRestore:
      restoreBackupIndex*: int
    of hrBackupManagerDelete:
      deleteBackupIndex*: int
    of hrBackupManagerOpenDiff:
      diffBackupIndex*: int
    of hrBackupManagerRefresh:
      discard
    of hrBackupManagerQuit:
      discard
    of hrEnterBackupManager:
      discard
    of hrDiffViewerQuit:
      discard
    of hrEnterDiffViewer:
      diffSourcePath*: string
      diffBackupPath*: string
    of hrRecentFile:
      discard
    of hrRecentFileOpenFile:
      recentFilePath*: string
    of hrRecentFileQuit:
      discard
    of hrNextWindow, hrPrevWindow:
      discard
    of hrLspGotoDefinition:
      discard
    of hrLspGotoDeclaration:
      discard
    of hrLspFindReferences:
      discard
    of hrLspCodeLensExecute:
      discard
    of hrLspCallHierarchyIncoming:
      discard
    of hrLspCallHierarchyOutgoing:
      discard
    of hrLspTypeDefinition:
      discard
    of hrLspImplementation:
      discard
    of hrLspHover:
      discard
    of hrLspRename:
      hrLspNewName*: string
    of hrLspSelectionRange:
      discard
    of hrLspDocumentLink:
      discard
    of hrShellCommand:
      shellCommand*: string
    of hrBackground:
      discard
    of hrJumpList:
      discard
    of hrBuild:
      discard
    of hrDebug:
      discard
    of hrDebugViewerQuit:
      discard
    of hrConfig:
      discard
    of hrConfigQuit:
      discard
    of hrConfigSaveConfig:
      discard
    of hrPutConfigFile:
      discard
    of hrMan:
      hrManPage*: string
    of hrTheme:
      hrThemeName*: string
    of hrLspLog:
      discard
    of hrLspFormat:
      discard
    of hrLspRestart:
      discard
    of hrLspFold:
      discard
    of hrLspExecuteCommand:
      hrLspCommand*: string
      hrLspCommandArgs*: seq[string]
    of hrSubstitute:
      hrSubstituteCount*: int
    of hrReferencesQuit:
      discard
    of hrReferencesJumpTo:
      jumpToPath*: string
      jumpToLine*: int
      jumpToColumn*: int
    of hrEnterReferences:
      discard
    of hrDocumentSymbolQuit:
      discard
    of hrDocumentSymbolJumpTo:
      symbolLine*: int
      symbolColumn*: int
    of hrEnterDocumentSymbol:
      discard
    of hrCallHierarchyQuit:
      discard
    of hrCallHierarchyJumpTo:
      callHierarchyJumpUri*: string
      callHierarchyJumpLine*: int
      callHierarchyJumpColumn*: int
    of hrCallHierarchyRequestIncoming:
      callHierarchyIncomingItem*: lspTypes.CallHierarchyItem
    of hrCallHierarchyRequestOutgoing:
      callHierarchyOutgoingItem*: lspTypes.CallHierarchyItem
    of hrEnterCallHierarchy:
      discard
    of hrUnhandled:
      discard
    of hrError:
      errorMessage*: string

proc newHandlerManager*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandLineParser: CommandLineParser,
    commandConfig: CommandConfig,
    commandRegistry: CommandRegistry,
    clipboardConfig: ClipboardConfig,
    smoothScrollConfig: SmoothScrollConfig =
      SmoothScrollConfig(enable: true, friction: 80.0, airDrag: 2.0),
    notificationConfig: NotificationConfig = NotificationConfig(),
    lsp: LspIntegration = nil,
    autocompleteEnabled: bool = true,
): HandlerManager =
  ## Create a new handler manager with all mode handlers

  let normalHandler = newNormalModeHandler(
    motionController, keyBindingRegistry, commandRegistry, clipboardConfig,
    smoothScrollConfig, notificationConfig,
  )
  let insertHandler = newInsertModeHandler(
    keyBindingRegistry, motionController, commandRegistry, lsp, autocompleteEnabled,
    notificationConfig,
  )
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)
  let visualHandler = newVisualModeHandler(
    keyBindingRegistry, commandRegistry, motionController, notificationConfig
  )
  let replaceHandler =
    newReplaceModeHandler(keyBindingRegistry, motionController, commandRegistry)
  let filerHandler = newFilerHandler()
  let logViewerHandler = newLogViewerHandler()
  let helpViewerHandler = newHelpViewerHandler()
  let bufferManagerHandler = newBufferManagerHandler()
  let backupManagerHandler = newBackupManagerHandler()
  let diffViewerHandler = newDiffViewerHandler()
  let recentFileModeHandler = newRecentFileModeHandler()
  let configModeHandler = newConfigModeHandler()
  let referencesHandler = newReferencesHandler()
  let documentSymbolHandler = newDocumentSymbolHandler()
  let callHierarchyHandler = newCallHierarchyHandler()

  HandlerManager(
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
    filerHandler: filerHandler,
    logViewerHandler: logViewerHandler,
    helpViewerHandler: helpViewerHandler,
    bufferManagerHandler: bufferManagerHandler,
    backupManagerHandler: backupManagerHandler,
    diffViewerHandler: diffViewerHandler,
    recentFileModeHandler: recentFileModeHandler,
    configModeHandler: configModeHandler,
    referencesHandler: referencesHandler,
    documentSymbolHandler: documentSymbolHandler,
    callHierarchyHandler: callHierarchyHandler,
    motionController: motionController,
    keyBindingRegistry: keyBindingRegistry,
    commandLineParser: commandLineParser,
    commandConfig: commandConfig,
    commandRegistry: commandRegistry,
  )

proc extractInsertedText(transaction: buffer.BufferTransaction): string =
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
    of buffer.ckTransaction:
      # Nested transaction - recursively extract text
      let nestedTransaction = buffer.BufferTransaction(
        changes: change.transactionChanges,
        description: change.transactionDescription,
        startSeq: 0,
      )
      sb.add(extractInsertedText(nestedTransaction))
  return sb.toString()

# Forward declaration for playbackMacro
proc playbackMacro*(
  manager: HandlerManager,
  buffer: TextBuffer,
  state: EditorState,
  viewport: ViewPort,
  keys: seq[string],
): HandlerResult

proc handleNormalMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Normal mode input
  let r = manager.normalHandler.handleNormalModeKey(buffer, state, viewport, keyCombo)
  case r.kind
  of nmrHandled:
    # Check if we're entering Insert or Replace mode
    if r.modeTransition.isSome:
      let targetMode = r.modeTransition.get
      if targetMode == EditorMode.Insert:
        # Begin a transaction when entering Insert mode
        let transactionResult = buffer.beginTransaction("Insert mode edit")
        if transactionResult.isErr:
          # This should not happen in normal operation, but handle it gracefully
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
        # Record insert start position for text tracking
        state.editState.insertModeStartPos = some(state.cursor)
      elif targetMode == EditorMode.Replace:
        # Begin a transaction when entering Replace mode
        let transactionResult = buffer.beginTransaction("Replace mode edit")
        if transactionResult.isErr:
          # This should not happen in normal operation, but handle it gracefully
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
        # Clear replace history when entering Replace mode
        state.editState.replaceHistory = @[]
    return HandlerResult(
      kind: hrHandled,
      modeTransition: r.modeTransition,
      overlayTransition: r.overlayTransition,
      statusMessage: "",
    )
  of nmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of nmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)
  of nmrSaveAndQuit:
    # ZZ command - Save and quit
    return HandlerResult(
      kind: hrSaveAndQuit, saveAndQuitFilename: none(string), forceQuitAfterSave: false
    )
  of nmrQuitWithoutSave:
    # ZQ command - Quit without saving (force quit)
    return HandlerResult(kind: hrQuit, shouldQuit: true)
  of nmrCloseWindow:
    # Ctrl-W c command - Close current window
    return HandlerResult(kind: hrCloseWindow, forceClose: false)
  of nmrPlaybackMacro:
    # Playback the macro through handler_manager which can dispatch to any mode
    # Loop for the specified count (e.g., 3@a plays macro 3 times)
    let count = if r.macroCount > 0: r.macroCount else: 1
    for i in 0 ..< count:
      let playbackResult = manager.playbackMacro(buffer, state, viewport, r.macroKeys)
      if playbackResult.kind == hrError or playbackResult.kind == hrQuit:
        return playbackResult
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of nmrLspGotoDefinition:
    # Signal to editor to execute LSP goto definition
    return HandlerResult(kind: hrLspGotoDefinition)
  of nmrLspGotoDeclaration:
    # Signal to editor to execute LSP goto declaration
    return HandlerResult(kind: hrLspGotoDeclaration)
  of nmrLspFindReferences:
    # Signal to editor to execute LSP find references
    return HandlerResult(kind: hrLspFindReferences)
  of nmrLspCodeLensExecute:
    # Signal to editor to execute CodeLens on current line
    return HandlerResult(kind: hrLspCodeLensExecute)
  of nmrLspCallHierarchyIncoming:
    # Signal to editor to execute LSP incoming calls
    return HandlerResult(kind: hrLspCallHierarchyIncoming)
  of nmrLspCallHierarchyOutgoing:
    # Signal to editor to execute LSP outgoing calls
    return HandlerResult(kind: hrLspCallHierarchyOutgoing)
  of nmrLspTypeDefinition:
    # Signal to editor to execute LSP goto type definition
    return HandlerResult(kind: hrLspTypeDefinition)
  of nmrLspImplementation:
    # Signal to editor to execute LSP goto implementation
    return HandlerResult(kind: hrLspImplementation)
  of nmrLspHover:
    # Signal to editor to execute LSP hover
    return HandlerResult(kind: hrLspHover)
  of nmrLspRename:
    # Signal to editor to execute LSP rename
    return HandlerResult(kind: hrLspRename, hrLspNewName: r.nmrLspNewName)
  of nmrLspSelectionRange:
    # Signal to editor to execute LSP selection range
    return HandlerResult(kind: hrLspSelectionRange)
  of nmrLspDocumentLink:
    # Signal to editor to execute LSP document link
    return HandlerResult(kind: hrLspDocumentLink)
  of nmrJumpToBuffer:
    # Signal to editor to jump to a specific buffer and position
    return HandlerResult(
      kind: hrJumpToBuffer,
      jumpBufferIndex: r.nmrJumpBufferIndex,
      jumpLine: r.nmrJumpLine,
      jumpColumn: r.nmrJumpColumn,
    )
  of nmrBufferNext:
    return HandlerResult(kind: hrBufferNext)
  of nmrBufferPrev:
    return HandlerResult(kind: hrBufferPrev)

proc handleInsertMode*(
    manager: HandlerManager, buffer: TextBuffer, state: EditorState, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
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
    return HandlerResult(kind: hrQuit, shouldQuit: true)
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
    return HandlerResult(kind: hrEdit, editFilename: r.editFilename)
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
  of cmrSaveAndQuit:
    return HandlerResult(
      kind: hrSaveAndQuit,
      saveAndQuitFilename: r.saveAndQuitFilename,
      forceQuitAfterSave: r.forceSaveAndQuit,
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
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Visual mode input
  let r = manager.visualHandler.handleVisualModeKey(buffer, state, viewport, keyCombo)
  case r.kind
  of vmrHandled:
    # Check if we're entering Insert mode (e.g., visual block I command)
    if r.modeTransition.isSome and r.modeTransition.get == EditorMode.Insert:
      # Begin a transaction so commitTransaction() succeeds when leaving Insert mode
      # Guard: visualChange already commits its delete transaction, so don't double-begin
      if not buffer.inTransaction:
        let transactionResult = buffer.beginTransaction("Visual to insert mode")
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
  of vmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReplaceMode*(
    manager: HandlerManager, buffer: TextBuffer, state: EditorState, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Replace mode input
  let r = manager.replaceHandler.handleReplaceModeKey(buffer, state, keyCombo)
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
  let r = manager.filerHandler.handleFilerModeKey(filerState, viewportHeight, keyCombo)
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

proc handleLogViewerMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Log Viewer mode input
  let r = manager.logViewerHandler.handleLogViewerModeKey(
    buffer, state, viewportHeight, keyCombo
  )
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
  let r = manager.referencesHandler.handleReferencesModeKey(
    refState, viewportHeight, keyCombo
  )
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
  let r = manager.documentSymbolHandler.handleDocumentSymbolModeKey(
    symState, viewportHeight, keyCombo
  )
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
  let r = manager.callHierarchyHandler.handleCallHierarchyModeKey(
    chState, viewportHeight, keyCombo
  )
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
  let r = manager.helpViewerHandler.handleHelpViewerModeKey(
    helpState, viewportHeight, keyCombo
  )
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
    # Enter search mode (forward) from help viewer
    state.search.direction = Forward
    state.search.historyIndex = -1
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of hvrEnterSearchBackward:
    # Enter search mode (backward) from help viewer
    state.search.direction = Backward
    state.search.historyIndex = -1
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
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
  let r = manager.bufferManagerHandler.handleBufferManagerModeKey(
    bmState, viewportHeight, keyCombo
  )
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

proc handleBackupManagerMode*(
    manager: HandlerManager,
    bkState: BackupManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Backup Manager mode input
  let r = manager.backupManagerHandler.handleBackupManagerModeKey(
    bkState, viewportHeight, keyCombo
  )
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
  let r = manager.diffViewerHandler.handleDiffViewerModeKey(
    diffState, viewportHeight, keyCombo
  )
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
  let r =
    manager.configModeHandler.handleConfigModeKey(configState, viewportHeight, keyCombo)
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
  let r = manager.recentFileModeHandler.handleRecentFileModeKey(
    state, viewportHeight, keyCombo
  )
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

const MaxMacroRecursionDepth = 100
  ## Maximum macro recursion depth to prevent infinite loops

proc handleKeyCombo*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
    window: Option[EditorWindow] = none(EditorWindow),
): HandlerResult =
  ## Handle a KeyCombo by dispatching to the appropriate mode handler
  ## This is used for macro playback where we have KeyCombo directly
  ## window is required for special modes (Filer, etc.) that store state in EditorWindow

  # Complete any active scroll animation on key input (instant jump to target)
  if state.scrollAnimation.active:
    let (completed, cursorLine) = completeScrollAnimation(state.scrollAnimation)
    if completed:
      state.cursor.line = cursorLine
      # Viewport will be updated by updateViewport after cursor is set

  # Delegate to appropriate mode handler
  case state.mode
  of EditorMode.Normal:
    return manager.handleNormalMode(buffer, state, viewport, keyCombo)
  of EditorMode.Insert:
    return manager.handleInsertMode(buffer, state, keyCombo)
  of EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine:
    return manager.handleVisualMode(buffer, state, viewport, keyCombo)
  of EditorMode.Replace:
    return manager.handleReplaceMode(buffer, state, keyCombo)
  of EditorMode.Filer:
    if window.isSome and window.get.filerState.isSome:
      return manager.handleFilerMode(
        window.get.filerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(kind: hrError, errorMessage: "Filer state not initialized")
  of EditorMode.LogViewer:
    return manager.handleLogViewerMode(buffer, state, viewport.height, keyCombo)
  of EditorMode.Help:
    if window.isSome and window.get.helpViewerState.isSome:
      return manager.handleHelpViewerMode(
        window.get.helpViewerState.get, state, viewport.height, keyCombo
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Help viewer state not initialized")
  of EditorMode.BufferManager:
    if window.isSome and window.get.bufferManagerState.isSome:
      return manager.handleBufferManagerMode(
        window.get.bufferManagerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(
        kind: hrError, errorMessage: "Buffer manager state not initialized"
      )
  of EditorMode.BackupManager:
    if window.isSome and window.get.backupManagerState.isSome:
      return manager.handleBackupManagerMode(
        window.get.backupManagerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(
        kind: hrError, errorMessage: "Backup manager state not initialized"
      )
  of EditorMode.DiffViewer:
    if window.isSome and window.get.diffViewerState.isSome:
      return manager.handleDiffViewerMode(
        window.get.diffViewerState.get, state, viewport.height, keyCombo
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Diff viewer state not initialized")
  of EditorMode.Config:
    if window.isSome and window.get.configModeState.isSome:
      return manager.handleConfigMode(
        window.get.configModeState.get, state, viewport.height, keyCombo
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Config mode state not initialized")
  of EditorMode.References:
    if window.isSome and window.get.referencesViewerState.isSome:
      return manager.handleReferencesMode(
        window.get.referencesViewerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(
        kind: hrError, errorMessage: "References viewer state not initialized"
      )
  of EditorMode.DocumentSymbol:
    if window.isSome and window.get.documentSymbolViewerState.isSome:
      return manager.handleDocumentSymbolMode(
        window.get.documentSymbolViewerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(
        kind: hrError, errorMessage: "Document symbol viewer state not initialized"
      )
  of EditorMode.CallHierarchy:
    if window.isSome and window.get.callHierarchyViewerState.isSome:
      return manager.handleCallHierarchyMode(
        window.get.callHierarchyViewerState.get, state, viewport.height, keyCombo
      )
    else:
      return HandlerResult(
        kind: hrError, errorMessage: "Call hierarchy viewer state not initialized"
      )
  of EditorMode.RecentFile:
    # Recent File mode requires its own state, not EditorState
    # This should be handled at a higher level with RecentFileModeState
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.Debug:
    # Debug mode is handled at a higher level in handler.nim
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.QuickRun:
    # QuickRun mode is not interactive - handled through command mode
    return HandlerResult(kind: hrUnhandled)

proc playbackMacro*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keys: seq[string],
): HandlerResult =
  ## Play back a recorded macro, handling mode transitions properly
  ## This dispatches each key to the appropriate mode handler based on current mode

  # Check for recursion depth limit
  if state.macroState.playbackDepth >= MaxMacroRecursionDepth:
    return HandlerResult(
      kind: hrError,
      errorMessage:
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")",
    )

  # Increment recursion depth
  state.macroState.playbackDepth += 1

  # Clear any pending key sequences before starting playback
  manager.keyBindingRegistry.clearSequence()

  # Temporarily disable macro recording to avoid recording during playback
  let wasRecording = state.macroState.isRecording
  state.macroState.isRecording = false

  for keyStr in keys:
    let keyComboOpt = stringToKeyCombo(keyStr)
    if keyComboOpt.isNone:
      state.macroState.isRecording = wasRecording
      state.macroState.playbackDepth -= 1
      return
        HandlerResult(kind: hrError, errorMessage: "Invalid key in macro: " & keyStr)

    let keyCombo = keyComboOpt.get

    # Dispatch to appropriate mode handler based on current state.mode
    let keyResult = manager.handleKeyCombo(buffer, state, viewport, keyCombo)

    # Handle mode transitions from keyResult
    if keyResult.kind == hrHandled and keyResult.modeTransition.isSome:
      state.mode = keyResult.modeTransition.get

    # If error or quit, stop playback
    if keyResult.kind == hrError or keyResult.kind == hrQuit:
      state.macroState.isRecording = wasRecording
      state.macroState.playbackDepth -= 1
      return keyResult

  # Restore recording state and decrement recursion depth
  state.macroState.isRecording = wasRecording
  state.macroState.playbackDepth -= 1

  # Clear any pending sequences after playback
  manager.keyBindingRegistry.clearSequence()
  return
    HandlerResult(kind: hrHandled, modeTransition: none(EditorMode), statusMessage: "")

proc handleEvent*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    event: Event,
    window: Option[EditorWindow] = none(EditorWindow),
): HandlerResult =
  ## Main entry point for handling events across all modes

  if event.kind != EventKind.Key:
    return HandlerResult(kind: hrUnhandled)

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return HandlerResult(kind: hrUnhandled)

  return manager.handleKeyCombo(buffer, state, viewport, keyComboOpt.get, window)

# Utility functions for HandlerResult
proc wasHandled*(hrResult: HandlerResult): bool =
  ## Check if the event was handled
  hrResult.kind in {
    hrHandled, hrQuit, hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrNew, hrVnew,
    hrEnew, hrSave, hrSaveAndQuit, hrBufferNext, hrBufferPrev, hrBufferFirst,
    hrBufferLast, hrBuffer, hrJumpToBuffer, hrBufferDelete, hrStripWhitespace,
    hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit, hrFilerDeleteFile,
    hrFilerShowInfo, hrFilerQuit, hrEnterFiler, hrLogViewerQuit, hrEnterLogViewer,
    hrHelpViewerQuit, hrEnterHelpViewer, hrReferencesQuit, hrReferencesJumpTo,
    hrEnterReferences, hrDocumentSymbolQuit, hrDocumentSymbolJumpTo,
    hrEnterDocumentSymbol, hrCallHierarchyQuit, hrCallHierarchyJumpTo,
    hrCallHierarchyRequestIncoming, hrCallHierarchyRequestOutgoing,
    hrEnterCallHierarchy, hrBufferManagerSelectBuffer, hrBufferManagerDeleteBuffer,
    hrBufferManagerQuit, hrEnterBufferManager, hrBackupManagerRestore,
    hrBackupManagerDelete, hrBackupManagerOpenDiff, hrBackupManagerRefresh,
    hrBackupManagerQuit, hrEnterBackupManager, hrDiffViewerQuit, hrRecentFile,
    hrRecentFileOpenFile, hrRecentFileQuit, hrNextWindow, hrPrevWindow,
    hrEnterDiffViewer, hrLspGotoDefinition, hrLspGotoDeclaration, hrLspFindReferences,
    hrLspCodeLensExecute, hrLspCallHierarchyIncoming, hrLspCallHierarchyOutgoing,
    hrLspTypeDefinition, hrLspImplementation, hrLspHover, hrLspRename,
    hrLspSelectionRange, hrLspDocumentLink, hrJumpList, hrLspLog,
  }

proc hasError*(hrResult: HandlerResult): bool =
  ## Check if there was an error
  hrResult.kind == hrError

proc getModeTransition*(hrResult: HandlerResult): Option[EditorMode] =
  ## Get mode transition if any
  if hrResult.kind == hrHandled:
    hrResult.modeTransition
  else:
    none(EditorMode)

proc getOverlayTransition*(hrResult: HandlerResult): Option[OverlayKind] =
  ## Get overlay transition if any
  if hrResult.kind == hrHandled:
    hrResult.overlayTransition
  else:
    none(OverlayKind)

proc getStatusMessage*(hrResult: HandlerResult): string =
  ## Get status message if any
  case hrResult.kind
  of hrHandled: hrResult.statusMessage
  of hrError: hrResult.errorMessage
  else: ""
