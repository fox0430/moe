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

import std/[options, unicode]

import pkg/[results, celina]

import
  ../[
    types, buffer, cursor, modes, motion, keybindings, commandline, commandconfig,
    commandregistry, config, stringbuilder, filer, recentfilemode, lspintegration,
  ]
import ../lsp/protocol/types as lspTypes
import
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler, logviewer_handler, help_handler, buffermanager_handler,
  backupmanager_handler, diffviewer_handler, recentfilemode_handler, debug_handler,
  config_handler, references_handler, documentsymbol_handler, callhierarchy_handler

export
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler, logviewer_handler, help_handler, buffermanager_handler,
  backupmanager_handler, diffviewer_handler, recentfilemode_handler, debug_handler,
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
  var sb = stringbuilder.newStringBuilder()
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
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
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
        # This should not happen in normal operation, but handle it gracefully
        return HandlerResult(
          kind: hrError,
          errorMessage: "Failed to commit transaction: " & transactionResult.error,
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
        # This should not happen in normal operation, but handle it gracefully
        return HandlerResult(
          kind: hrError,
          errorMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleFilerMode*(
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Filer mode input
  let r = manager.filerHandler.handleFilerModeKey(state, viewportHeight, keyCombo)
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
    if state.filerState.isSome:
      discard state.filerState.get.enterDirectory(r.dirPath)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of frEnterCommand:
    # Enter command mode from filer
    state.commandText = ":"
    state.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of frDeleteFile:
    return HandlerResult(kind: hrFilerDeleteFile, filerDeletePath: r.deletePath)
  of frShowInfo:
    return HandlerResult(kind: hrFilerShowInfo, filerFileInfo: r.fileInfo)
  of frQuit:
    return HandlerResult(kind: hrFilerQuit)
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of lvrEnterSearchForward:
    # Enter search mode (forward) from log viewer
    state.previousMode = EditorMode.LogViewer
    state.search.text = ""
    state.search.startPos = state.cursor
    state.search.direction = Forward
    state.search.historyIndex = -1
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Search), statusMessage: ""
    )
  of lvrEnterSearchBackward:
    # Enter search mode (backward) from log viewer
    state.previousMode = EditorMode.LogViewer
    state.search.text = ""
    state.search.startPos = state.cursor
    state.search.direction = Backward
    state.search.historyIndex = -1
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Search), statusMessage: ""
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
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle References Viewer mode input
  let r =
    manager.referencesHandler.handleReferencesModeKey(state, viewportHeight, keyCombo)
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of rvrQuit:
    return HandlerResult(kind: hrReferencesQuit)
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
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Document Symbol Viewer mode input
  let r = manager.documentSymbolHandler.handleDocumentSymbolModeKey(
    state, viewportHeight, keyCombo
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
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
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Call Hierarchy Viewer mode input
  let r = manager.callHierarchyHandler.handleCallHierarchyModeKey(
    state, viewportHeight, keyCombo
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
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
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Help Viewer mode input
  let r =
    manager.helpViewerHandler.handleHelpViewerModeKey(state, viewportHeight, keyCombo)
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of hvrQuit:
    return HandlerResult(kind: hrHelpViewerQuit)
  of hvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of hvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBufferManagerMode*(
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Buffer Manager mode input
  let r = manager.bufferManagerHandler.handleBufferManagerModeKey(
    state, viewportHeight, keyCombo
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of bmrQuit:
    return HandlerResult(kind: hrBufferManagerQuit)
  of bmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBackupManagerMode*(
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Backup Manager mode input
  let r = manager.backupManagerHandler.handleBackupManagerModeKey(
    state, viewportHeight, keyCombo
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of bkmrQuit:
    return HandlerResult(kind: hrBackupManagerQuit)
  of bkmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bkmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleDiffViewerMode*(
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Diff Viewer mode input
  let r =
    manager.diffViewerHandler.handleDiffViewerModeKey(state, viewportHeight, keyCombo)
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of dvrQuit:
    return HandlerResult(kind: hrDiffViewerQuit)
  of dvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of dvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleConfigMode*(
    manager: HandlerManager, state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Configuration mode input
  let r = manager.configModeHandler.handleConfigModeKey(state, viewportHeight, keyCombo)
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of cmrQuit:
    return HandlerResult(kind: hrConfigQuit)
  of cmrSaveConfig:
    return HandlerResult(kind: hrConfigSaveConfig)
  of cmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of cmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleRecentFileMode*(
    manager: HandlerManager,
    state: recentfilemode.RecentFileModeState,
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
      kind: hrHandled, modeTransition: some(EditorMode.Command), statusMessage: ""
    )
  of rfmrQuit:
    return HandlerResult(kind: hrRecentFileQuit)
  of rfmrNextWindow:
    return HandlerResult(kind: hrNextWindow)
  of rfmrPrevWindow:
    return HandlerResult(kind: hrPrevWindow)
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
): HandlerResult =
  ## Handle a KeyCombo by dispatching to the appropriate mode handler
  ## This is used for macro playback where we have KeyCombo directly

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
  of EditorMode.Command:
    # Handle Command mode key events for macro playback
    return manager.handleCommandMode(buffer, state, viewport, keyCombo)
  of EditorMode.Search:
    # Handle Search mode key events for macro playback
    return manager.handleSearchMode(buffer, state, viewport, keyCombo)
  of EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine:
    return manager.handleVisualMode(buffer, state, viewport, keyCombo)
  of EditorMode.Replace:
    return manager.handleReplaceMode(buffer, state, keyCombo)
  of EditorMode.Filer:
    return manager.handleFilerMode(state, viewport.height, keyCombo)
  of EditorMode.LogViewer:
    return manager.handleLogViewerMode(buffer, state, viewport.height, keyCombo)
  of EditorMode.Help:
    return manager.handleHelpViewerMode(state, viewport.height, keyCombo)
  of EditorMode.BufferManager:
    return manager.handleBufferManagerMode(state, viewport.height, keyCombo)
  of EditorMode.BackupManager:
    return manager.handleBackupManagerMode(state, viewport.height, keyCombo)
  of EditorMode.DiffViewer:
    return manager.handleDiffViewerMode(state, viewport.height, keyCombo)
  of EditorMode.Config:
    return manager.handleConfigMode(state, viewport.height, keyCombo)
  of EditorMode.References:
    return manager.handleReferencesMode(state, viewport.height, keyCombo)
  of EditorMode.DocumentSymbol:
    return manager.handleDocumentSymbolMode(state, viewport.height, keyCombo)
  of EditorMode.CallHierarchy:
    return manager.handleCallHierarchyMode(state, viewport.height, keyCombo)
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
  of EditorMode.Rename:
    # Rename mode is handled at a higher level in handler.nim
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
): HandlerResult =
  ## Main entry point for handling events across all modes

  if event.kind != EventKind.Key:
    return HandlerResult(kind: hrUnhandled)

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return HandlerResult(kind: hrUnhandled)

  return manager.handleKeyCombo(buffer, state, viewport, keyComboOpt.get)

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

proc shouldQuit*(hrResult: HandlerResult): bool =
  ## Check if the application should quit
  if hrResult.kind == hrQuit: hrResult.shouldQuit else: false

proc shouldCloseWindow*(hrResult: HandlerResult): bool =
  ## Check if we should close the current window
  hrResult.kind == hrCloseWindow

proc shouldGotoLine*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a line
  hrResult.kind == hrGotoLine

proc shouldVSplit*(hrResult: HandlerResult): bool =
  ## Check if we should create a vertical split
  hrResult.kind == hrVSplit

proc shouldHSplit*(hrResult: HandlerResult): bool =
  ## Check if we should create a horizontal split
  hrResult.kind == hrHSplit

proc shouldEnew*(hrResult: HandlerResult): bool =
  ## Check if we should create a new empty buffer
  hrResult.kind == hrEnew

proc shouldNew*(hrResult: HandlerResult): bool =
  ## Check if we should create a new empty buffer in horizontal split
  hrResult.kind == hrNew

proc shouldVnew*(hrResult: HandlerResult): bool =
  ## Check if we should create a new empty buffer in vertical split
  hrResult.kind == hrVnew

proc shouldEdit*(hrResult: HandlerResult): bool =
  ## Check if we should edit/open a file
  hrResult.kind == hrEdit

proc getEditFilename*(hrResult: HandlerResult): string =
  ## Get the filename for edit command
  if hrResult.kind == hrEdit: hrResult.editFilename else: ""

proc shouldSetBoolOption*(hrResult: HandlerResult): bool =
  ## Check if we should set a boolean option
  hrResult.kind == hrSetBoolOption

proc shouldSetIntOption*(hrResult: HandlerResult): bool =
  ## Check if we should set an integer option
  hrResult.kind == hrSetIntOption

proc shouldClearSearchHighlight*(hrResult: HandlerResult): bool =
  ## Check if we should clear search highlighting
  hrResult.kind == hrClearSearchHighlight

proc shouldShellCommand*(hrResult: HandlerResult): bool =
  ## Check if we should execute a shell command
  hrResult.kind == hrShellCommand

proc getShellCommand*(hrResult: HandlerResult): string =
  ## Get the shell command to execute
  if hrResult.kind == hrShellCommand: hrResult.shellCommand else: ""

proc shouldBackground*(hrResult: HandlerResult): bool =
  ## Check if we should pause editor and show terminal (:bg)
  hrResult.kind == hrBackground

proc getBoolOption*(hrResult: HandlerResult): BoolSettingOption =
  ## Get the boolean option to set
  if hrResult.kind == hrSetBoolOption: hrResult.boolOption else: bsoNumber

proc getBoolValue*(hrResult: HandlerResult): bool =
  ## Get the boolean value to set
  if hrResult.kind == hrSetBoolOption: hrResult.boolValue else: false

proc getIntOption*(hrResult: HandlerResult): IntSettingOption =
  ## Get the integer option to set
  if hrResult.kind == hrSetIntOption: hrResult.intOption else: isoTabStop

proc getIntValue*(hrResult: HandlerResult): int =
  ## Get the integer value to set
  if hrResult.kind == hrSetIntOption: hrResult.intValue else: 0

proc shouldSetFloatOption*(hrResult: HandlerResult): bool =
  ## Check if we should set a float option
  hrResult.kind == hrSetFloatOption

proc getFloatOption*(hrResult: HandlerResult): FloatSettingOption =
  ## Get the float option to set
  if hrResult.kind == hrSetFloatOption: hrResult.floatOption else: fsoScrollFriction

proc getFloatValue*(hrResult: HandlerResult): float =
  ## Get the float value to set
  if hrResult.kind == hrSetFloatOption: hrResult.floatValue else: 0.0

proc shouldSave*(hrResult: HandlerResult): bool =
  ## Check if we should save the file
  hrResult.kind == hrSave

proc shouldSaveAndQuit*(hrResult: HandlerResult): bool =
  ## Check if we should save the file and quit
  hrResult.kind == hrSaveAndQuit

proc shouldBufferNext*(hrResult: HandlerResult): bool =
  ## Check if we should switch to next buffer
  hrResult.kind == hrBufferNext

proc shouldBufferPrev*(hrResult: HandlerResult): bool =
  ## Check if we should switch to previous buffer
  hrResult.kind == hrBufferPrev

proc shouldBufferFirst*(hrResult: HandlerResult): bool =
  ## Check if we should switch to first buffer
  hrResult.kind == hrBufferFirst

proc shouldBufferLast*(hrResult: HandlerResult): bool =
  ## Check if we should switch to last buffer
  hrResult.kind == hrBufferLast

proc shouldBuffer*(hrResult: HandlerResult): bool =
  ## Check if we should switch to buffer by number or name
  hrResult.kind == hrBuffer

proc getBufferArg*(hrResult: HandlerResult): string =
  ## Get the buffer argument (number or name)
  if hrResult.kind == hrBuffer: hrResult.bufferArg else: ""

proc shouldJumpToBuffer*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a specific buffer and position
  hrResult.kind == hrJumpToBuffer

proc getJumpBufferIndex*(hrResult: HandlerResult): int =
  ## Get the target buffer index for jump
  if hrResult.kind == hrJumpToBuffer: hrResult.jumpBufferIndex else: -1

proc getJumpLine*(hrResult: HandlerResult): int =
  ## Get the target line for jump
  if hrResult.kind == hrJumpToBuffer: hrResult.jumpLine else: 0

proc getJumpColumn*(hrResult: HandlerResult): int =
  ## Get the target column for jump
  if hrResult.kind == hrJumpToBuffer: hrResult.jumpColumn else: 0

proc shouldBufferDelete*(hrResult: HandlerResult): bool =
  ## Check if we should delete the current buffer
  hrResult.kind == hrBufferDelete

proc getForceBufferDelete*(hrResult: HandlerResult): bool =
  ## Get force flag for buffer delete
  if hrResult.kind == hrBufferDelete: hrResult.forceBufferDelete else: false

proc shouldStripWhitespace*(hrResult: HandlerResult): bool =
  ## Check if we should strip trailing whitespace
  hrResult.kind == hrStripWhitespace

proc getStrippedLineCount*(hrResult: HandlerResult): int =
  ## Get number of lines that had whitespace stripped
  if hrResult.kind == hrStripWhitespace: hrResult.strippedLineCount else: 0

proc shouldEnterFiler*(hrResult: HandlerResult): bool =
  ## Check if we should enter filer mode
  hrResult.kind == hrEnterFiler

proc getEnterFilerPath*(hrResult: HandlerResult): Option[string] =
  ## Get the path for filer mode
  if hrResult.kind == hrEnterFiler:
    hrResult.enterFilerPath
  else:
    none(string)

proc shouldFilerDeleteFile*(hrResult: HandlerResult): bool =
  ## Check if we should delete a file/directory from filer
  hrResult.kind == hrFilerDeleteFile

proc getFilerDeletePath*(hrResult: HandlerResult): string =
  ## Get the path to delete from filer
  if hrResult.kind == hrFilerDeleteFile: hrResult.filerDeletePath else: ""

proc shouldEnterLogViewer*(hrResult: HandlerResult): bool =
  ## Check if we should enter log viewer mode
  hrResult.kind == hrEnterLogViewer

proc shouldLogViewerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close log viewer
  hrResult.kind == hrLogViewerQuit

proc shouldLspLog*(hrResult: HandlerResult): bool =
  ## Check if we should open LSP log viewer
  hrResult.kind == hrLspLog

proc shouldEnterReferences*(hrResult: HandlerResult): bool =
  ## Check if we should enter references viewer mode
  hrResult.kind == hrEnterReferences

proc shouldReferencesQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close references viewer
  hrResult.kind == hrReferencesQuit

proc shouldReferencesJumpTo*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a reference
  hrResult.kind == hrReferencesJumpTo

proc getReferencesJumpTarget*(
    hrResult: HandlerResult
): tuple[path: string, line: int, column: int] =
  ## Get the jump target for references
  if hrResult.kind == hrReferencesJumpTo:
    (hrResult.jumpToPath, hrResult.jumpToLine, hrResult.jumpToColumn)
  else:
    ("", 0, 0)

proc shouldEnterDocumentSymbol*(hrResult: HandlerResult): bool =
  ## Check if we should enter document symbol viewer mode
  hrResult.kind == hrEnterDocumentSymbol

proc shouldDocumentSymbolQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close document symbol viewer
  hrResult.kind == hrDocumentSymbolQuit

proc shouldDocumentSymbolJumpTo*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a symbol
  hrResult.kind == hrDocumentSymbolJumpTo

proc getDocumentSymbolJumpTarget*(
    hrResult: HandlerResult
): tuple[line: int, column: int] =
  ## Get the jump target for document symbol
  if hrResult.kind == hrDocumentSymbolJumpTo:
    (hrResult.symbolLine, hrResult.symbolColumn)
  else:
    (0, 0)

proc shouldEnterCallHierarchy*(hrResult: HandlerResult): bool =
  ## Check if we should enter call hierarchy viewer mode
  hrResult.kind == hrEnterCallHierarchy

proc shouldCallHierarchyQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close call hierarchy viewer
  hrResult.kind == hrCallHierarchyQuit

proc shouldCallHierarchyJumpTo*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a call hierarchy item
  hrResult.kind == hrCallHierarchyJumpTo

proc getCallHierarchyJumpTarget*(
    hrResult: HandlerResult
): tuple[uri: string, line: int, column: int] =
  ## Get the jump target for call hierarchy
  if hrResult.kind == hrCallHierarchyJumpTo:
    (
      hrResult.callHierarchyJumpUri, hrResult.callHierarchyJumpLine,
      hrResult.callHierarchyJumpColumn,
    )
  else:
    ("", 0, 0)

proc shouldCallHierarchyRequestIncoming*(hrResult: HandlerResult): bool =
  ## Check if we should request incoming calls
  hrResult.kind == hrCallHierarchyRequestIncoming

proc getCallHierarchyIncomingItem*(
    hrResult: HandlerResult
): Option[lspTypes.CallHierarchyItem] =
  ## Get the item for incoming calls request
  if hrResult.kind == hrCallHierarchyRequestIncoming:
    some(hrResult.callHierarchyIncomingItem)
  else:
    none(lspTypes.CallHierarchyItem)

proc shouldCallHierarchyRequestOutgoing*(hrResult: HandlerResult): bool =
  ## Check if we should request outgoing calls
  hrResult.kind == hrCallHierarchyRequestOutgoing

proc getCallHierarchyOutgoingItem*(
    hrResult: HandlerResult
): Option[lspTypes.CallHierarchyItem] =
  ## Get the item for outgoing calls request
  if hrResult.kind == hrCallHierarchyRequestOutgoing:
    some(hrResult.callHierarchyOutgoingItem)
  else:
    none(lspTypes.CallHierarchyItem)

proc shouldEnterHelpViewer*(hrResult: HandlerResult): bool =
  ## Check if we should enter help viewer mode
  hrResult.kind == hrEnterHelpViewer

proc shouldHelpViewerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close help viewer
  hrResult.kind == hrHelpViewerQuit

proc shouldQuickRun*(hrResult: HandlerResult): bool =
  ## Check if we should run QuickRun
  hrResult.kind == hrQuickRun

proc shouldBuild*(hrResult: HandlerResult): bool =
  ## Check if we should run Build
  hrResult.kind == hrBuild

proc hasError*(hrResult: HandlerResult): bool =
  ## Check if there was an error
  hrResult.kind == hrError

proc getModeTransition*(hrResult: HandlerResult): Option[EditorMode] =
  ## Get mode transition if any
  if hrResult.kind == hrHandled:
    hrResult.modeTransition
  else:
    none(EditorMode)

proc getStatusMessage*(hrResult: HandlerResult): string =
  ## Get status message if any
  case hrResult.kind
  of hrHandled: hrResult.statusMessage
  of hrError: hrResult.errorMessage
  else: ""

proc getLineNumber*(hrResult: HandlerResult): int =
  ## Get line number for goto
  if hrResult.kind == hrGotoLine: hrResult.lineNumber else: 0

proc getVSplitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for vertical split
  if hrResult.kind == hrVSplit:
    hrResult.vsplitFilename
  else:
    none(string)

proc getHSplitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for horizontal split
  if hrResult.kind == hrHSplit:
    hrResult.hsplitFilename
  else:
    none(string)

proc getSaveFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for save operation
  if hrResult.kind == hrSave:
    hrResult.saveFilename
  else:
    none(string)

proc getForceSave*(hrResult: HandlerResult): bool =
  ## Get force save flag for save operation
  if hrResult.kind == hrSave: hrResult.forceSave else: false

proc getSaveAndQuitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for save and quit operation
  if hrResult.kind == hrSaveAndQuit:
    hrResult.saveAndQuitFilename
  else:
    none(string)

proc getForceQuitAfterSave*(hrResult: HandlerResult): bool =
  ## Get force quit flag for save and quit operation
  if hrResult.kind == hrSaveAndQuit: hrResult.forceQuitAfterSave else: false

proc shouldLspGotoDefinition*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP goto definition
  hrResult.kind == hrLspGotoDefinition

proc shouldLspGotoDeclaration*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP goto declaration
  hrResult.kind == hrLspGotoDeclaration

proc shouldLspFindReferences*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP find references
  hrResult.kind == hrLspFindReferences

proc shouldLspCodeLensExecute*(hrResult: HandlerResult): bool =
  ## Check if we should execute CodeLens on current line
  hrResult.kind == hrLspCodeLensExecute

proc shouldLspCallHierarchyIncoming*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP incoming calls
  hrResult.kind == hrLspCallHierarchyIncoming

proc shouldLspCallHierarchyOutgoing*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP outgoing calls
  hrResult.kind == hrLspCallHierarchyOutgoing

proc shouldLspTypeDefinition*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP goto type definition
  hrResult.kind == hrLspTypeDefinition

proc shouldLspImplementation*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP goto implementation
  hrResult.kind == hrLspImplementation

proc shouldLspHover*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP hover
  hrResult.kind == hrLspHover

proc shouldLspRename*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP rename
  hrResult.kind == hrLspRename

proc getLspRenameNewName*(hrResult: HandlerResult): string =
  ## Get the new name for LSP rename
  if hrResult.kind == hrLspRename: hrResult.hrLspNewName else: ""

proc shouldLspSelectionRange*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP selection range
  hrResult.kind == hrLspSelectionRange

proc shouldLspDocumentLink*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP document link
  hrResult.kind == hrLspDocumentLink

proc shouldLspFormat*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP document formatting
  hrResult.kind == hrLspFormat

proc shouldLspFold*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP folding range
  hrResult.kind == hrLspFold

proc shouldEnterBufferManager*(hrResult: HandlerResult): bool =
  ## Check if we should enter buffer manager mode
  hrResult.kind == hrEnterBufferManager

proc shouldBufferManagerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close buffer manager
  hrResult.kind == hrBufferManagerQuit

proc shouldBufferManagerSelectBuffer*(hrResult: HandlerResult): bool =
  ## Check if we should select a buffer
  hrResult.kind == hrBufferManagerSelectBuffer

proc getBufferManagerSelectBufferIndex*(hrResult: HandlerResult): int =
  ## Get the buffer index to select
  if hrResult.kind == hrBufferManagerSelectBuffer: hrResult.selectBufferIndex else: -1

proc shouldBufferManagerDeleteBuffer*(hrResult: HandlerResult): bool =
  ## Check if we should delete a buffer
  hrResult.kind == hrBufferManagerDeleteBuffer

proc getBufferManagerDeleteBufferIndex*(hrResult: HandlerResult): int =
  ## Get the buffer index to delete
  if hrResult.kind == hrBufferManagerDeleteBuffer: hrResult.deleteBufferIdx else: -1

proc shouldEnterBackupManager*(hrResult: HandlerResult): bool =
  ## Check if we should enter backup manager mode
  hrResult.kind == hrEnterBackupManager

proc shouldBackupManagerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close backup manager
  hrResult.kind == hrBackupManagerQuit

proc shouldBackupManagerRestore*(hrResult: HandlerResult): bool =
  ## Check if we should restore a backup
  hrResult.kind == hrBackupManagerRestore

proc getBackupManagerRestoreIndex*(hrResult: HandlerResult): int =
  ## Get the backup index to restore
  if hrResult.kind == hrBackupManagerRestore: hrResult.restoreBackupIndex else: -1

proc shouldBackupManagerDelete*(hrResult: HandlerResult): bool =
  ## Check if we should delete a backup
  hrResult.kind == hrBackupManagerDelete

proc getBackupManagerDeleteIndex*(hrResult: HandlerResult): int =
  ## Get the backup index to delete
  if hrResult.kind == hrBackupManagerDelete: hrResult.deleteBackupIndex else: -1

proc shouldBackupManagerOpenDiff*(hrResult: HandlerResult): bool =
  ## Check if we should open diff viewer for a backup
  hrResult.kind == hrBackupManagerOpenDiff

proc getBackupManagerDiffIndex*(hrResult: HandlerResult): int =
  ## Get the backup index for diff viewer
  if hrResult.kind == hrBackupManagerOpenDiff: hrResult.diffBackupIndex else: -1

proc shouldBackupManagerRefresh*(hrResult: HandlerResult): bool =
  ## Check if we should refresh backup list
  hrResult.kind == hrBackupManagerRefresh

proc shouldDiffViewerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close diff viewer
  hrResult.kind == hrDiffViewerQuit

proc shouldEnterDiffViewer*(hrResult: HandlerResult): bool =
  ## Check if we should enter diff viewer mode
  hrResult.kind == hrEnterDiffViewer

proc getDiffViewerSourcePath*(hrResult: HandlerResult): string =
  ## Get the source file path for diff viewer
  if hrResult.kind == hrEnterDiffViewer: hrResult.diffSourcePath else: ""

proc getDiffViewerBackupPath*(hrResult: HandlerResult): string =
  ## Get the backup file path for diff viewer
  if hrResult.kind == hrEnterDiffViewer: hrResult.diffBackupPath else: ""

proc shouldEnterRecentFileMode*(hrResult: HandlerResult): bool =
  ## Check if we should enter Recent File mode
  hrResult.kind == hrRecentFile

proc shouldOpenRecentFile*(hrResult: HandlerResult): bool =
  ## Check if we should open a file from Recent File mode
  hrResult.kind == hrRecentFileOpenFile

proc shouldQuitRecentFileMode*(hrResult: HandlerResult): bool =
  ## Check if we should quit Recent File mode
  hrResult.kind == hrRecentFileQuit

proc getRecentFilePath*(hrResult: HandlerResult): string =
  ## Get the file path to open from Recent File mode
  if hrResult.kind == hrRecentFileOpenFile: hrResult.recentFilePath else: ""

proc shouldNextWindow*(hrResult: HandlerResult): bool =
  ## Check if we should move to next window
  hrResult.kind == hrNextWindow

proc shouldPrevWindow*(hrResult: HandlerResult): bool =
  ## Check if we should move to previous window
  hrResult.kind == hrPrevWindow

proc shouldJumpList*(hrResult: HandlerResult): bool =
  ## Check if we should show jump list
  hrResult.kind == hrJumpList

proc shouldEnterDebugViewer*(hrResult: HandlerResult): bool =
  ## Check if we should enter debug viewer mode
  hrResult.kind == hrDebug

proc shouldDebugViewerQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close debug viewer
  hrResult.kind == hrDebugViewerQuit

proc shouldEnterConfigMode*(hrResult: HandlerResult): bool =
  ## Check if we should enter config mode
  hrResult.kind == hrConfig

proc shouldConfigQuit*(hrResult: HandlerResult): bool =
  ## Check if we should close config mode
  hrResult.kind == hrConfigQuit

proc shouldConfigSaveConfig*(hrResult: HandlerResult): bool =
  ## Check if we should save config
  hrResult.kind == hrConfigSaveConfig

proc shouldPutConfigFile*(hrResult: HandlerResult): bool =
  ## Check if we should write current config to file (:putConfigFile)
  hrResult.kind == hrPutConfigFile

proc shouldLspRestart*(hrResult: HandlerResult): bool =
  ## Check if we should restart LSP server
  hrResult.kind == hrLspRestart

proc shouldLspExecuteCommand*(hrResult: HandlerResult): bool =
  ## Check if we should execute an LSP command
  hrResult.kind == hrLspExecuteCommand

proc getLspExecuteCommand*(hrResult: HandlerResult): string =
  ## Get the LSP command to execute
  if hrResult.kind == hrLspExecuteCommand: hrResult.hrLspCommand else: ""

proc getLspExecuteCommandArgs*(hrResult: HandlerResult): seq[string] =
  ## Get the LSP command arguments
  if hrResult.kind == hrLspExecuteCommand:
    hrResult.hrLspCommandArgs
  else:
    @[]

proc shouldMan*(hrResult: HandlerResult): bool =
  ## Check if we should show a man page
  hrResult.kind == hrMan

proc getManPage*(hrResult: HandlerResult): string =
  ## Get the man page to show
  if hrResult.kind == hrMan: hrResult.hrManPage else: ""
