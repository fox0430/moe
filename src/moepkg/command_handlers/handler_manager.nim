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

## Unified handler manager
##
## This module provides a unified interface for all mode-specific handlers,
## maintaining the shared infrastructure while delegating to specialized handlers.

import std/[options, unicode]

import pkg/[results, celina]

import
  ../[
    types, buffer, cursor, modes, motion, keybindings, commandline, commandconfig,
    commandregistry, config, stringbuilder, filer,
  ]
import
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler

export
  normal_handler, insert_handler, command_handler, visual_handler, replace_handler,
  filer_handler

type
  HandlerResultKind* = enum
    hrHandled # Command was handled successfully
    hrQuit # Application should quit
    hrCloseWindow # Close current window
    hrGotoLine # Jump to specific line
    hrVSplit # Vertical split window
    hrHSplit # Horizontal split window
    hrEnew # Create new empty buffer
    hrEdit # Edit/open file in current window
    hrSetMultiStatusLine # Set multi status line
    hrSetIgnoreCase # Set ignorecase option
    hrSetSmartCase # Set smartcase option
    hrSetIncSearch # Set incsearch option
    hrSetHlSearch # Set hlsearch option
    hrSave # Save file
    hrSaveAndQuit # Save file and quit
    hrBufferNext # Switch to next buffer
    hrBufferPrev # Switch to previous buffer
    hrBufferFirst # Switch to first buffer
    hrBufferLast # Switch to last buffer
    hrBufferDelete # Delete current buffer
    hrStripWhitespace # Remove trailing whitespace
    hrFilerOpenFile # Open file from filer
    hrFilerOpenFileVSplit # Open file from filer in vertical split
    hrFilerOpenFileHSplit # Open file from filer in horizontal split
    hrFilerQuit # Close filer and return to previous mode
    hrEnterFiler # Enter filer mode with optional path
    hrQuickRun # Run the current buffer
    hrLspGotoDefinition # Execute LSP goto definition
    hrLspFindReferences # Execute LSP find references
    hrUnhandled # Command was not handled
    hrError # Error occurred

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    filerHandler*: FilerHandler
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
    of hrEnew:
      discard
    of hrEdit:
      editFilename*: string
    of hrSetMultiStatusLine:
      enabled*: bool
    of hrSetIgnoreCase:
      ignorecaseEnabled*: bool
    of hrSetSmartCase:
      smartcaseEnabled*: bool
    of hrSetIncSearch:
      incsearchEnabled*: bool
    of hrSetHlSearch:
      hlsearchEnabled*: bool
    of hrSave:
      saveFilename*: Option[string]
    of hrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceQuitAfterSave*: bool
    of hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast:
      discard
    of hrBufferDelete:
      forceBufferDelete*: bool
    of hrStripWhitespace:
      strippedLineCount*: int
    of hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit:
      filerFilePath*: string
    of hrFilerQuit:
      discard
    of hrEnterFiler:
      enterFilerPath*: Option[string]
    of hrQuickRun:
      discard
    of hrLspGotoDefinition:
      discard
    of hrLspFindReferences:
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
      SmoothScrollConfig(enable: true, baseDurationMs: 350, maxDurationMs: 650),
): HandlerManager =
  ## Create a new handler manager with all mode handlers

  let normalHandler = newNormalModeHandler(
    motionController, keyBindingRegistry, commandRegistry, clipboardConfig,
    smoothScrollConfig,
  )
  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)
  let visualHandler = newVisualModeHandler(keyBindingRegistry, commandRegistry)
  let replaceHandler =
    newReplaceModeHandler(keyBindingRegistry, motionController, commandRegistry)
  let filerHandler = newFilerHandler()

  HandlerManager(
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
    filerHandler: filerHandler,
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
        state.insertModeStartPos = some(state.cursor)
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
        state.replaceHistory = @[]
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
  of nmrLspFindReferences:
    # Signal to editor to execute LSP find references
    return HandlerResult(kind: hrLspFindReferences)

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
      if buffer.currentTransaction.isSome and state.insertModeStartPos.isSome:
        let transaction = buffer.currentTransaction.get
        let insertedText = extractInsertedText(transaction)

        # Record the insert command for repeat (.) if text was actually inserted
        if insertedText.len > 0:
          # Check if we entered Insert mode via substitute command (s/S/cc)
          if state.substituteContext.isSome:
            let subCtx = state.substituteContext.get
            state.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecSubstitute,
                substituteText: insertedText,
                substituteCount: subCtx.deleteCount,
                substituteKind: subCtx.kind,
              )
            )
          else:
            # Normal insert (i, a, o, O)
            state.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecInsertText,
                insertedText: insertedText,
                insertPosition: state.insertModeStartPos.get,
              )
            )

        # Clear insert position tracking and substitute context
        state.insertModeStartPos = none(BufferPosition)
        state.substituteContext = none(types.SubstituteContext)

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
): HandlerResult =
  ## Handle Command mode input (when Enter is pressed)
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  let r =
    manager.commandHandler.handleCommandModeInput(buffer, commandText, isSharedBuffer)

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
  of cmrEnew:
    return HandlerResult(kind: hrEnew)
  of cmrEdit:
    return HandlerResult(kind: hrEdit, editFilename: r.editFilename)
  of cmrSetMultiStatusLine:
    return HandlerResult(kind: hrSetMultiStatusLine, enabled: r.enabled)
  of cmrSetIgnoreCase:
    return HandlerResult(kind: hrSetIgnoreCase, ignorecaseEnabled: r.ignorecaseEnabled)
  of cmrSetSmartCase:
    return HandlerResult(kind: hrSetSmartCase, smartcaseEnabled: r.smartcaseEnabled)
  of cmrSetIncSearch:
    return HandlerResult(kind: hrSetIncSearch, incsearchEnabled: r.incsearchEnabled)
  of cmrSetHlSearch:
    return HandlerResult(kind: hrSetHlSearch, hlsearchEnabled: r.hlsearchEnabled)
  of cmrSave:
    return HandlerResult(kind: hrSave, saveFilename: r.saveFilename)
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
  of cmrStripWhitespace:
    return
      HandlerResult(kind: hrStripWhitespace, strippedLineCount: r.strippedLineCount)
  of cmrFiler:
    # Switch to Filer mode with optional path
    return HandlerResult(kind: hrEnterFiler, enterFilerPath: r.filerPath)
  of cmrQuickRun:
    return HandlerResult(kind: hrQuickRun)
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
  if state.isRecordingMacro:
    state.recordedKeys.add(keyComboToString(keyCombo))

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
      return manager.handleCommandMode(buffer, commandText, false)
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
  if state.isRecordingMacro:
    state.recordedKeys.add(keyComboToString(keyCombo))

  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      # Cancel search mode and restore cursor
      state.searchText = ""
      state.cursor = state.searchStartPos
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
      if state.searchText.len > 0:
        var runes = state.searchText.toRunes
        if runes.len > 0:
          runes.setLen(runes.len - 1)
          state.searchText = $runes
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    else:
      return HandlerResult(kind: hrUnhandled)
  else:
    # Regular character - append to search text
    if keyCombo.modifiers == {} and keyCombo.char.len > 0:
      state.searchText.add(keyCombo.char)
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
  of frQuit:
    return HandlerResult(kind: hrFilerQuit)
  of frUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of frError:
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
    let (completed, cursorLine, topLine) =
      completeScrollAnimation(state.scrollAnimation)
    if completed:
      state.cursor.line = cursorLine
      manager.motionController.viewportManager.viewport.topLine = topLine

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
  if state.macroPlaybackDepth >= MaxMacroRecursionDepth:
    return HandlerResult(
      kind: hrError,
      errorMessage:
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")",
    )

  # Increment recursion depth
  state.macroPlaybackDepth += 1

  # Clear any pending key sequences before starting playback
  manager.keyBindingRegistry.clearSequence()

  # Temporarily disable macro recording to avoid recording during playback
  let wasRecording = state.isRecordingMacro
  state.isRecordingMacro = false

  for keyStr in keys:
    let keyComboOpt = stringToKeyCombo(keyStr)
    if keyComboOpt.isNone:
      state.isRecordingMacro = wasRecording
      state.macroPlaybackDepth -= 1
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
      state.isRecordingMacro = wasRecording
      state.macroPlaybackDepth -= 1
      return keyResult

  # Restore recording state and decrement recursion depth
  state.isRecordingMacro = wasRecording
  state.macroPlaybackDepth -= 1

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
    hrHandled, hrQuit, hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrEnew, hrSave,
    hrSaveAndQuit, hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast,
    hrBufferDelete, hrStripWhitespace, hrFilerOpenFile, hrFilerOpenFileVSplit,
    hrFilerOpenFileHSplit, hrFilerQuit, hrLspGotoDefinition, hrLspFindReferences,
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

proc shouldEdit*(hrResult: HandlerResult): bool =
  ## Check if we should edit/open a file
  hrResult.kind == hrEdit

proc getEditFilename*(hrResult: HandlerResult): string =
  ## Get the filename for edit command
  if hrResult.kind == hrEdit: hrResult.editFilename else: ""

proc shouldSetMultiStatusLine*(hrResult: HandlerResult): bool =
  ## Check if we should set multi status line mode
  hrResult.kind == hrSetMultiStatusLine

proc shouldSetIgnoreCase*(hrResult: HandlerResult): bool =
  ## Check if we should set ignorecase option
  hrResult.kind == hrSetIgnoreCase

proc shouldSetSmartCase*(hrResult: HandlerResult): bool =
  ## Check if we should set smartcase option
  hrResult.kind == hrSetSmartCase

proc shouldSetIncSearch*(hrResult: HandlerResult): bool =
  ## Check if we should set incsearch option
  hrResult.kind == hrSetIncSearch

proc shouldSetHlSearch*(hrResult: HandlerResult): bool =
  ## Check if we should set hlsearch option
  hrResult.kind == hrSetHlSearch

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

proc shouldQuickRun*(hrResult: HandlerResult): bool =
  ## Check if we should run QuickRun
  hrResult.kind == hrQuickRun

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

proc getMultiStatusLineEnabled*(hrResult: HandlerResult): bool =
  ## Get multi status line enabled setting
  if hrResult.kind == hrSetMultiStatusLine: hrResult.enabled else: false

proc getIgnoreCaseEnabled*(hrResult: HandlerResult): bool =
  ## Get ignorecase enabled setting
  if hrResult.kind == hrSetIgnoreCase: hrResult.ignorecaseEnabled else: false

proc getSmartCaseEnabled*(hrResult: HandlerResult): bool =
  ## Get smartcase enabled setting
  if hrResult.kind == hrSetSmartCase: hrResult.smartcaseEnabled else: false

proc getIncSearchEnabled*(hrResult: HandlerResult): bool =
  ## Get incsearch enabled setting
  if hrResult.kind == hrSetIncSearch: hrResult.incsearchEnabled else: false

proc getHlSearchEnabled*(hrResult: HandlerResult): bool =
  ## Get hlsearch enabled setting
  if hrResult.kind == hrSetHlSearch: hrResult.hlsearchEnabled else: false

proc getSaveFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for save operation
  if hrResult.kind == hrSave:
    hrResult.saveFilename
  else:
    none(string)

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

proc shouldLspFindReferences*(hrResult: HandlerResult): bool =
  ## Check if we should execute LSP find references
  hrResult.kind == hrLspFindReferences
