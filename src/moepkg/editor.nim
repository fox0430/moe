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

import std/[strutils, strformat, options, monotimes, times, os]

import pkg/[results, chronos]

import
  editor_types, editor_window, editor_file, editor_lsp, editor_codelens, editor_render

import
  status_line, render_utils, git_diff, logger, config_loader, keybind_config,
  search_utils, completion, signature_help, hover_popup, command_completion, motion,
  color, gap_buffer, debug_viewer, message_log, unicode_utils
import key_bindings except Command
import command_handlers/insert_handler

export
  editor_types, editor_window, editor_file, editor_lsp, editor_codelens, editor_render

proc findBufferByPath*(e: Editor, path: string): int =
  ## Find a buffer in the buffer list by its file path
  ## Returns the buffer index (0-based) or -1 if not found
  let absPath = absolutePath(path)
  for i, buf in e.buffers:
    if buf.filePath.isSome and absolutePath(buf.filePath.get) == absPath:
      return i
  return -1

proc addBufferToWindowList*(e: Editor, buffer: TextBuffer) =
  ## Add a buffer to the active window's bufferList if not already present
  var found = false
  for buf in e.activeWindow.bufferList:
    if buf == buffer:
      found = true
      break
  if not found:
    e.activeWindow.bufferList.add(buffer)
    logDebug(
      "editor",
      "Added buffer to window bufferList, len: " & $e.activeWindow.bufferList.len,
    )

proc switchToBufferByIndex*(e: Editor, index: int) =
  ## Switch the current window to display the buffer at the given index
  logDebug("editor", "switchToBufferByIndex called with index: " & $index)
  logDebug("editor", "windows.len: " & $e.windowManager.windows.len)

  if index < 0 or index >= e.buffers.len:
    logDebug("editor", "Invalid index, returning")
    return

  let targetBuffer = e.buffers[index]
  let targetPath =
    if targetBuffer.filePath.isSome: targetBuffer.filePath.get else: "No Name"
  logDebug("editor", "Target buffer path: " & targetPath)

  # Don't switch if already on this buffer
  if e.activeWindow.buffer == targetBuffer:
    logDebug("editor", "Already on this buffer")
    return

  # Add buffer to window's bufferList if not already there
  e.addBufferToWindowList(targetBuffer)

  e.activeWindow.buffer = targetBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.topLine = 0
  e.activeWindow.viewport.leftColumn = 0

  # Sync the executor and motion controller
  e.syncActiveWindow()

  # Update screen cursor
  e.setActiveWindowScreenCursor(e.activeWindow)
  logDebug("editor", "Switched buffer in window")

  # Update current buffer index in state (for jump list)
  e.state.currentBufferIndex = index

proc currentBufferIndex*(e: Editor): int =
  ## Get the index of the current buffer in the buffer list
  ## Returns -1 if not found
  logDebug(
    "editor",
    "currentBufferIndex: windows.len=" & $e.windowManager.windows.len &
      " activeWindowIndex=" & $e.windowManager.activeWindowIndex,
  )
  let currentBuffer = e.activeBuffer()
  let currentPath =
    if currentBuffer.filePath.isSome: currentBuffer.filePath.get else: "[No Name]"
  logDebug("editor", "currentBufferIndex: activeBuffer path=" & currentPath)
  for i, buf in e.buffers:
    if buf == currentBuffer:
      logDebug("editor", "currentBufferIndex: found match at index " & $i)
      return i
  logDebug("editor", "currentBufferIndex: no match found, returning -1")
  return -1

proc windowBufferIndex*(e: Editor): int =
  ## Get the index of the current buffer in the window's bufferList
  ## Returns -1 if not found
  let currentBuffer = e.activeWindow.buffer
  for i, buf in e.activeWindow.bufferList:
    if buf == currentBuffer:
      return i
  return -1

proc switchToWindowBuffer*(e: Editor, windowIndex: int) =
  ## Switch to a buffer in the window's bufferList by index
  if windowIndex < 0 or windowIndex >= e.activeWindow.bufferList.len:
    return

  let targetBuffer = e.activeWindow.bufferList[windowIndex]

  # Don't switch if already on this buffer
  if e.activeWindow.buffer == targetBuffer:
    return

  e.activeWindow.buffer = targetBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.topLine = 0
  e.activeWindow.viewport.leftColumn = 0

  # Sync the executor and motion controller
  e.syncActiveWindow()

  # Update screen cursor
  e.setActiveWindowScreenCursor(e.activeWindow)
  logDebug("editor", "Switched to window buffer at index: " & $windowIndex)

proc switchToNextBuffer*(e: Editor) =
  ## Switch to the next buffer in the window's bufferList (:bnext)
  if e.activeWindow.bufferList.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  let currentIdx = e.windowBufferIndex()
  let nextIdx = (currentIdx + 1) mod e.activeWindow.bufferList.len
  e.switchToWindowBuffer(nextIdx)
  e.state.statusMessage = ""

proc switchToPrevBuffer*(e: Editor) =
  ## Switch to the previous buffer in the window's bufferList (:bprev)
  if e.activeWindow.bufferList.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  let currentIdx = e.windowBufferIndex()
  let prevIdx =
    if currentIdx == 0:
      e.activeWindow.bufferList.len - 1
    else:
      currentIdx - 1
  e.switchToWindowBuffer(prevIdx)
  e.state.statusMessage = ""

proc switchToFirstBuffer*(e: Editor) =
  ## Switch to the first buffer in the window's bufferList (:bfirst)
  if e.activeWindow.bufferList.len <= 1:
    e.state.statusMessage = "Already at first buffer"
    return

  let currentIdx = e.windowBufferIndex()
  if currentIdx == 0:
    e.state.statusMessage = "Already at first buffer"
    return

  e.switchToWindowBuffer(0)
  e.state.statusMessage = ""

proc switchToLastBuffer*(e: Editor) =
  ## Switch to the last buffer in the window's bufferList (:blast)
  if e.activeWindow.bufferList.len <= 1:
    e.state.statusMessage = "Already at last buffer"
    return

  let lastIdx = e.activeWindow.bufferList.len - 1
  let currentIdx = e.windowBufferIndex()
  if currentIdx == lastIdx:
    e.state.statusMessage = "Already at last buffer"
    return

  e.switchToWindowBuffer(lastIdx)
  e.state.statusMessage = ""

proc switchToBuffer*(e: Editor, arg: string): bool =
  ## Switch to a buffer by number or name (:b N or :b name)
  ## Returns true if successful, false otherwise
  ## Uses the buffer list (not windows) like Vim

  logDebug("editor", "switchToBuffer called with arg: " & arg)
  logDebug("editor", "buffers.len: " & $e.buffers.len)
  # Log each buffer's path for debugging
  for i, buf in e.buffers:
    let path = if buf.filePath.isSome: buf.filePath.get else: "[No Name]"
    logDebug("editor", "  buffer[" & $i & "]: " & path)

  # Try to parse as a number first
  try:
    let bufNum = parseInt(arg)
    # Buffer numbers are 1-indexed in Vim
    let targetIndex = bufNum - 1

    logDebug(
      "editor", "Parsed buffer number: " & $bufNum & ", targetIndex: " & $targetIndex
    )

    if targetIndex < 0 or targetIndex >= e.buffers.len:
      e.state.statusMessage = "E86: Buffer " & $bufNum & " does not exist"
      logDebug("editor", "Buffer does not exist")
      return false

    let currentIdx = e.currentBufferIndex()
    logDebug("editor", "currentIdx: " & $currentIdx)
    if targetIndex == currentIdx:
      # Already at this buffer
      logDebug("editor", "Already at this buffer")
      return true

    # Switch to the buffer
    logDebug("editor", "Switching to buffer at index: " & $targetIndex)
    e.switchToBufferByIndex(targetIndex)
    e.state.statusMessage = ""
    return true
  except ValueError:
    discard # Not a number, try matching by name

  # Try to match by file name in buffer list
  for i, buf in e.buffers:
    if buf.filePath.isSome:
      let bufferPath = buf.filePath.get
      # Match against full path, file name, or partial match
      if bufferPath == arg or bufferPath.extractFilename == arg or
          bufferPath.contains(arg):
        let currentIdx = e.currentBufferIndex()
        if i == currentIdx:
          # Already at this buffer
          return true

        # Switch to the buffer
        e.switchToBufferByIndex(i)
        e.state.statusMessage = ""
        return true

  e.state.statusMessage = "E94: No matching buffer for " & arg
  return false

proc isBufferShared*(e: Editor, buffer: TextBuffer): bool =
  ## Check if the given buffer is shared across multiple windows
  ## Returns true if the buffer is open in more than one window
  for window in e.windowManager.windows:
    if window.buffer == buffer:
      if result:
        return true
      else:
        result = true

  # Buffer is not shared across multiple windows (0 or 1 window)
  return false

proc addCommandAlias*(
    e: Editor, alias: string, action: CommandLineAction
): Result[(), string] =
  ## Add a new command alias
  e.commandConfig.addAlias(alias, action)
  e.commandConfig.applyToParser(e.commandLineParser)
  ok(())

proc removeCommandAlias*(e: Editor, alias: string): Result[(), string] =
  ## Remove a command alias
  if e.commandLineParser.aliases.hasKey(alias):
    e.commandLineParser.removeAlias(alias)
    # Note: This doesn't remove from config until save is called
    ok(())
  else:
    err fmt"Alias not found: {alias}"

proc toggleStatusLine*(e: Editor) =
  ## Toggle the visibility of the status line
  e.state.toggleStatusLine()

proc setStatusLineVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the status line
  e.state.setStatusLineVisible(visible)

proc toggleLineCount*(e: Editor) =
  ## Toggle the visibility of line count in status line
  e.state.toggleLineCount()

proc setLineCountVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line count in status line
  e.state.setLineCountVisible(visible)

proc toggleLinePercentage*(e: Editor) =
  ## Toggle the visibility of line percentage in status line
  e.state.toggleLinePercentage()

proc setLinePercentageVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line percentage in status line
  e.state.setLinePercentageVisible(visible)

proc toggleEncoding*(e: Editor) =
  ## Toggle the visibility of encoding in status line
  e.state.toggleEncoding()

proc setEncodingVisible*(e: Editor, visible: bool) =
  ## Set the visibility of encoding in status line
  e.state.setEncodingVisible(visible)

proc toggleLineWrap*(e: Editor) =
  ## Toggle line wrapping
  e.state.display.lineWrap = not e.state.display.lineWrap
  e.state.needsFullRedraw = true

proc setLineWrap*(e: Editor, enabled: bool) =
  ## Set line wrapping
  e.state.display.lineWrap = enabled
  e.state.needsFullRedraw = true

proc toggleMultiStatusLine*(e: Editor) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  e.state.display.multiStatusLine = not e.state.display.multiStatusLine
  e.state.needsFullRedraw = true

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  ## Set multi status line mode
  e.state.display.multiStatusLine = enabled
  e.state.needsFullRedraw = true

proc toggleSidebar*(e: Editor) =
  ## Toggle the visibility of the sidebar
  e.state.display.showSidebar = not e.state.display.showSidebar
  e.state.needsFullRedraw = true

proc setSidebarVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the sidebar
  e.state.display.showSidebar = visible
  e.state.needsFullRedraw = true

proc toggleGitDiff*(e: Editor) =
  ## Toggle git diff indicators in sidebar
  e.state.display.showGitDiff = not e.state.display.showGitDiff

  # Update git diff information when enabled
  if e.state.display.showGitDiff:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc setGitDiffVisible*(e: Editor, visible: bool) =
  ## Set git diff indicators visibility in sidebar
  e.state.display.showGitDiff = visible

  # Update git diff information when enabled
  if visible:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc toggleSyntaxChecker*(e: Editor) =
  ## Toggle syntax checker results in sidebar
  e.state.display.showSyntaxChecker = not e.state.display.showSyntaxChecker
  e.state.needsFullRedraw = true

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  ## Set syntax checker results visibility in sidebar
  e.state.display.showSyntaxChecker = visible
  e.state.needsFullRedraw = true

proc editFile*(e: Editor, path: string): Result[(), string] =
  ## Load a file and switch to it (like :e in Vim)
  ## If the buffer already exists in the buffer list, switch to it
  ## If the file doesn't exist, create an empty buffer with the path set (new file)

  logDebug("editor", "editFile called with path: " & path)
  logDebug("editor", "Current buffers.len: " & $e.buffers.len)

  # Check if buffer already exists in the global buffer list
  let existingIndex = e.findBufferByPath(path)
  if existingIndex >= 0:
    # Buffer already exists, switch to it (also adds to window's bufferList)
    logDebug("editor", "Buffer already exists at index: " & $existingIndex)
    e.switchToBufferByIndex(existingIndex)
    return ok(())

  # Create new buffer
  let newBuffer = newTextBuffer()

  if fileExists(path):
    # Load existing file
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      return err(loadResult.error)
  else:
    # New file: set the path for saving later
    newBuffer.filePath = some(path)

  # Add new buffer to the global buffer list
  e.buffers.add(newBuffer)
  logDebug("editor", "Added new buffer, buffers.len now: " & $e.buffers.len)

  # Add new buffer to the active window's bufferList
  e.addBufferToWindowList(newBuffer)

  # Switch to the new buffer (sets active window's buffer)
  e.switchToBufferByIndex(e.buffers.len - 1)
  ok(())

proc newEditor*(editorConfig: EditorConfig, vr: ValidationResult): Editor =
  ## Create a new Editor with the given configuration and validation result.
  ## If validation errors exist, they will be displayed in the status message.
  # Set color mode from configuration with fallback
  let requestedColorMode =
    case editorConfig.standard.colorMode
    of cm8color: cmk8color
    of cm16color: cmk16color
    of cm256color: cmk256color
    of cm24bit: cmk24bit
    of cmNone: cmkNone
  globalColorMode = applyColorModeFallback(requestedColorMode)

  if requestedColorMode != globalColorMode:
    editorConfig.standard.colorMode =
      case globalColorMode
      of cmk8color: cm8color
      of cmk16color: cm16color
      of cmk256color: cm256color
      of cmk24bit: cm24bit
      of cmkNone: cmNone

  # Initialize theme from configuration
  initTheme(editorConfig)

  # Create registries and configuration first
  let
    cmdRegistry = newCommandRegistry()
    keyRegistry = newKeyBindingRegistry()
    cmdConfig = newCommandConfig()
    cmdLineParser = newCommandLineParser()

  # Register built-in commands and default bindings
  cmdRegistry.registerBuiltinCommands
  keyRegistry.setupDefaultBindings

  # Load custom key_bindings from TOML
  keyRegistry.loadDefaultKeybindings()

  # Apply key mappings from config (moerc.toml [KeyMapping] section)
  # Apply "All" mappings to every mode first (mode-specific mappings can override)
  for lhs, rhs in editorConfig.keyMapping.all:
    for mode in EditorMode:
      if mode == EditorMode.QuickRun:
        continue
      let err = keyRegistry.addRuntimeMapping(mode, lhs, rhs)
      if err.len > 0:
        logWarn("editor", "KeyMapping.All error (" & $mode & "): " & err)

  for lhs, rhs in editorConfig.keyMapping.normal:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Normal, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Normal error: " & err)
  for lhs, rhs in editorConfig.keyMapping.insert:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Insert, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Insert error: " & err)
  for lhs, rhs in editorConfig.keyMapping.visualAll:
    for mode in [EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]:
      let err = keyRegistry.addRuntimeMapping(mode, lhs, rhs)
      if err.len > 0:
        logWarn("editor", "KeyMapping.VisualAll error (" & $mode & "): " & err)
  for lhs, rhs in editorConfig.keyMapping.visual:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Visual, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Visual error: " & err)
  for lhs, rhs in editorConfig.keyMapping.visualLine:
    let err = keyRegistry.addRuntimeMapping(EditorMode.VisualLine, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.VisualLine error: " & err)
  for lhs, rhs in editorConfig.keyMapping.visualBlock:
    let err = keyRegistry.addRuntimeMapping(EditorMode.VisualBlock, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.VisualBlock error: " & err)
  for lhs, rhs in editorConfig.keyMapping.replace:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Replace, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Replace error: " & err)
  for lhs, rhs in editorConfig.keyMapping.commandLine:
    let err = keyRegistry.addRuntimeMapping(EditorMode.CommandLine, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.CommandLine error: " & err)

  for lhs, rhs in editorConfig.keyMapping.filer:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Filer, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Filer error: " & err)
  for lhs, rhs in editorConfig.keyMapping.logViewer:
    let err = keyRegistry.addRuntimeMapping(EditorMode.LogViewer, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.LogViewer error: " & err)
  for lhs, rhs in editorConfig.keyMapping.help:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Help, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Help error: " & err)
  for lhs, rhs in editorConfig.keyMapping.bufferManager:
    let err = keyRegistry.addRuntimeMapping(EditorMode.BufferManager, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.BufferManager error: " & err)
  for lhs, rhs in editorConfig.keyMapping.backupManager:
    let err = keyRegistry.addRuntimeMapping(EditorMode.BackupManager, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.BackupManager error: " & err)
  for lhs, rhs in editorConfig.keyMapping.diffViewer:
    let err = keyRegistry.addRuntimeMapping(EditorMode.DiffViewer, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.DiffViewer error: " & err)
  for lhs, rhs in editorConfig.keyMapping.config:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Config, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Config error: " & err)
  for lhs, rhs in editorConfig.keyMapping.references:
    let err = keyRegistry.addRuntimeMapping(EditorMode.References, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.References error: " & err)
  for lhs, rhs in editorConfig.keyMapping.documentSymbol:
    let err = keyRegistry.addRuntimeMapping(EditorMode.DocumentSymbol, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.DocumentSymbol error: " & err)
  for lhs, rhs in editorConfig.keyMapping.callHierarchy:
    let err = keyRegistry.addRuntimeMapping(EditorMode.CallHierarchy, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.CallHierarchy error: " & err)
  for lhs, rhs in editorConfig.keyMapping.recentFile:
    let err = keyRegistry.addRuntimeMapping(EditorMode.RecentFile, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.RecentFile error: " & err)
  for lhs, rhs in editorConfig.keyMapping.debug:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Debug, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Debug error: " & err)
  for lhs, rhs in editorConfig.keyMapping.terminal:
    let err = keyRegistry.addRuntimeMapping(EditorMode.Terminal, lhs, rhs)
    if err.len > 0:
      logWarn("editor", "KeyMapping.Terminal error: " & err)

  # Load command configuration
  cmdConfig.loadDefaultConfig

  # Apply configuration to parser
  cmdConfig.applyToParser(cmdLineParser)

  # Initialize LSP integration with current working directory as workspace root
  let lspIntegration = newLspIntegration(getCurrentDir())

  result = Editor(
    textBuffer: newTextBuffer(),
    lsp: lspIntegration,
    lastLspChangeSeq: 0,
    state: EditorState(
      cursor: BufferPosition(line: 0, column: 0),
      preferredColumn: -1,
        # -1 means not set, will be initialized on first vertical move
      screenCursor: CursorPosition(x: 0, y: 0),
      cursorVisible: true,
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      # Display settings (grouped in DisplaySettings)
      display: DisplaySettings(
        showTabLine: editorConfig.tabLine.enable,
        showStatusLine: editorConfig.standard.statusLine,
        multiStatusLine: editorConfig.statusLine.multipleStatusLine,
        showLineCount: true,
        showLinePercentage: true,
        showEncoding: true,
        showLineNumbers: editorConfig.standard.number,
        showCursorLine: editorConfig.highlight.currentLine,
        showSyntax: editorConfig.standard.syntax,
        showIndentationLines: editorConfig.standard.indentationLines,
        showSidebar: editorConfig.standard.sidebar,
        showGitDiff: editorConfig.git.showChangedLine,
        showSyntaxChecker: editorConfig.syntaxChecker.enable,
        showCodeLens: true,
        showDocumentHighlight: true,
        lineWrap: editorConfig.standard.lineWrap,
        tabStop: editorConfig.standard.tabStop,
        expandTab: editorConfig.standard.expandTab,
        autoIndent: editorConfig.standard.autoIndent,
        autoCloseParen: editorConfig.standard.autoCloseParen,
        autoDeleteParen: editorConfig.standard.autoDeleteParen,
      ),
      needsFullRedraw: true, # Initial render needs full draw
      viewportReservedLines: StatusAndCommandReserve, # Status+command share same row
      # Timing state (grouped in TimingState)
      timing: TimingState(
        lastResizeTime: getMonoTime(),
        lastGitDiffUpdate: getMonoTime(),
        lastGitDiffChangeSeq: 0,
        gitDiffUpdateInterval: editorConfig.git.updateInterval,
        lastAutoSave: getMonoTime(),
        lastAutoBackup: getMonoTime(),
        lastInputTime: getMonoTime(),
        lastFileModCheck: getMonoTime(),
        fileModCheckInterval: 1000, # Check file modification every 1 second
        lastConfigCheck: getMonoTime(),
        lastConfigModTime: times.Time(), # Will be set properly after initialization
        configCheckInterval: 2000, # Check config modification every 2 seconds
      ),
      # Search state (grouped in SearchState)
      search: SearchState(
        text: "",
        lastText: "",
        direction: Forward,
        history:
          if editorConfig.persist.search:
            loadSearchHistory(editorConfig.persist.searchHistoryLimit)
          else:
            @[],
        historyIndex: -1,
        startPos: BufferPosition(line: 0, column: 0),
        ignorecase: editorConfig.standard.ignorecase,
        smartcase: editorConfig.standard.smartcase,
        incsearch: editorConfig.standard.incrementalSearch,
        hlsearch: true,
        hlsearchTempDisabled: false,
      ),
      # Command state (grouped in CommandState)
      commandState: CommandState(
        history:
          if editorConfig.persist.exCommand:
            loadCommandHistory(editorConfig.persist.exCommandHistoryLimit)
          else:
            @[],
        historyIndex: -1,
      ),
      # Macro state (grouped in MacroState)
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 1,
        playbackDepth: 0,
      ),
      lastKeyWasEscape: false, # Track double-Escape for clearing highlight
      # Edit operation state (grouped in EditState)
      editState: EditState(
        lastMotion: none(Motion),
        lastEditCommand: none(LastEditCommand),
        pendingOperator: none(PendingOperator),
        pendingTextObject: none(PendingTextObject),
        substituteContext: none(SubstituteContext),
        replaceHistory: @[],
        insertModeStartPos: none(BufferPosition),
        visualBlockInsertContext: none(VisualBlockInsertContext),
      ),
      savedViewportTopLine: 0, # Saved viewport position for operators
      # Yank register (internal clipboard) - DEPRECATED
      yankRegister: "", # Empty initially
      yankIsLine: false, # Not linewise initially
      # Full register system
      registers: initRegisters(),
      pendingRegister: none(char),
      # Jump list
      jumpList: @[], # Empty jump list initially
      jumpListIndex: -1, # Not navigating jump list initially
      # Command mode completion
      commandCompletionManager: newCommandCompletionManager(),
      # LSP cache state (grouped in LspCacheState)
      lspCache: LspCacheState(
        codeLensCache: CodeLensCache(isValid: false),
        codeLensPicker: CodeLensPicker(isActive: false),
        documentHighlightCache: DocumentHighlightCache(isValid: false),
        semanticTokensCache: SemanticTokensCache(isValid: false),
        hoverPopup: newHoverPopupManager(),
        locations: none(LspLocationsResult),
        lastCodeLensUpdate: getMonoTime(),
        codeLensUpdateInterval: 1000, # 1 second debounce
        lastDocumentHighlightUpdate: getMonoTime(),
        documentHighlightUpdateInterval: 200, # 200ms debounce
        lastSemanticTokensUpdate: getMonoTime(),
        semanticTokensUpdateInterval: 500, # 500ms debounce for semantic tokens
      ),
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0),
    screenSize: ScreenSize(width: 80, height: 20),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
    windowManager: newEditorWindowManager(),
    buffers: @[], # Will be initialized below
    config: editorConfig, # Store configuration
    cursorPositions:
      if editorConfig.persist.cursorPosition:
        loadCursorPositions()
      else:
        initTable[string, CursorPositionEntry](),
  )

  # Add initial buffer to buffer list
  result.buffers.add(result.textBuffer)
  logDebug("editor", "Initial buffer added, buffers.len: " & $result.buffers.len)

  # Set reserved words for syntax highlighting on initial buffer
  result.textBuffer.setReservedWords(
    toReservedWords(editorConfig.highlight.reservedWord)
  )

  # Create default window (always have at least one window)
  result.windowManager.windows.add(
    EditorWindow(
      buffer: result.textBuffer,
      bufferList: @[result.textBuffer], # Initialize with initial buffer
      viewport: result.viewport,
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )
  )
  result.windowManager.activeWindowIndex = 0
  logDebug(
    "editor",
    "Default window created, windows.len: " & $result.windowManager.windows.len,
  )

  result.executer = newCommandExecutor(
    result.textBuffer,
    result.state,
    result.viewport,
    result.config.clipboard,
    result.config.notification,
    some(cmdRegistry),
    some(keyRegistry),
  )

  # Create handler manager after executer (which creates motion controller)
  result.handlerManager = newHandlerManager(
    result.executer.motionController, keyRegistry, cmdLineParser, cmdConfig,
    cmdRegistry, result.config.clipboard, result.config.smoothScroll,
    result.config.notification, result.lsp, result.config.autocomplete.enable,
  )

  # Set clipboard tool for register system
  if result.config.clipboard.enable:
    result.state.registers.setClipboardTool(result.config.clipboard.tool)

  # Apply LSP enable setting from config
  result.lsp.setEnabled(result.config.lsp.enable)

  # Initialize config file modification time for liveReloadOfConf
  let configPath = getConfigPath()
  if fileExists(configPath):
    try:
      result.state.timing.lastConfigModTime = getFileInfo(configPath).lastWriteTime
    except OSError:
      discard

  # Display validation errors in status message if any
  if vr.hasErrors:
    let errorMessages = vr.toErrorMessages
    result.state.statusMessage = "Config error: " & errorMessages[0]
    # Log all errors
    for msg in errorMessages:
      addMessageLog("Config error: " & msg)

proc newEditor*(editorConfig: EditorConfig): Editor =
  ## Create a new Editor with the given configuration.
  result = newEditor(editorConfig, newValidationResult())

proc newEditor*(): Editor =
  ## Create a new Editor, loading configuration from default path.
  # Load TOML configuration
  let loadResult = loadConfig()
  var
    editorConfig: EditorConfig
    vr = newValidationResult()
  if loadResult.isOk:
    (editorConfig, vr) = loadResult.get
  else:
    vr.addError("config", loadResult.error, "valid TOML file")
    editorConfig = newEditorConfig()

  result = newEditor(editorConfig, vr)

proc maybeReloadExternallyModifiedFile*(e: Editor) =
  ## Check if files were modified externally and reload them if:
  ##   - liveReloadOfFile is enabled in config
  ##   - Buffer has no unsaved changes (if modified, just show a message)
  ##   - Enough time has passed since last check (debouncing)

  if not e.config.standard.liveReloadOfFile:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastFileModCheck
  let threshold = initDuration(milliseconds = e.state.timing.fileModCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastFileModCheck = now

  # Check the active buffer
  let activeBuffer = e.activeBuffer()
  if not activeBuffer.isExternallyModified():
    return

  let filePath =
    if activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      return

  # If buffer has unsaved changes, warn the user instead of reloading
  if activeBuffer.isModified:
    if not activeBuffer.externalModWarned:
      e.state.statusMessage =
        "Warning: " & filePath & " changed on disk (buffer has unsaved changes)"
      activeBuffer.externalModWarned = true
    return

  # Reload the file
  logInfo("editor", "File externally modified, reloading: " & filePath)
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isOk:
    e.state.statusMessage = "File reloaded: " & filePath
    e.state.needsFullRedraw = true
    # Update git diff after reload
    e.refreshGitDiff(useBuffer = false)
  else:
    e.state.statusMessage = "Failed to reload file: " & reloadResult.error

proc applyConfigSettings*(e: Editor, newConfig: EditorConfig) =
  ## Apply configuration settings to the editor
  ## Updates display settings, search settings, and other runtime state
  ## Note: Some settings require editor restart to take effect

  # Update display settings from config
  e.state.display.showTabLine = newConfig.tabLine.enable
  e.state.display.showStatusLine = newConfig.standard.statusLine
  e.state.display.multiStatusLine = newConfig.statusLine.multipleStatusLine
  e.state.display.showLineNumbers = newConfig.standard.number
  e.state.display.showCursorLine = newConfig.highlight.currentLine
  e.state.display.showSyntax = newConfig.standard.syntax
  e.state.display.showIndentationLines = newConfig.standard.indentationLines
  e.state.display.showSidebar = newConfig.standard.sidebar
  e.state.display.showGitDiff = newConfig.git.showChangedLine
  e.state.display.showSyntaxChecker = newConfig.syntaxChecker.enable
  e.state.display.tabStop = newConfig.standard.tabStop
  e.state.display.expandTab = newConfig.standard.expandTab
  e.state.display.autoIndent = newConfig.standard.autoIndent
  e.state.display.autoCloseParen = newConfig.standard.autoCloseParen
  e.state.display.autoDeleteParen = newConfig.standard.autoDeleteParen

  # Update search settings
  e.state.search.ignorecase = newConfig.standard.ignorecase
  e.state.search.smartcase = newConfig.standard.smartcase
  e.state.search.incsearch = newConfig.standard.incrementalSearch

  # Update timing intervals
  e.state.timing.gitDiffUpdateInterval = newConfig.git.updateInterval

  # Update color mode with fallback
  let requestedColorMode =
    case newConfig.standard.colorMode
    of cm8color: cmk8color
    of cm16color: cmk16color
    of cm256color: cmk256color
    of cm24bit: cmk24bit
    of cmNone: cmkNone
  globalColorMode = applyColorModeFallback(requestedColorMode)

  # Update clipboard tool if enabled
  if newConfig.clipboard.enable:
    e.state.registers.setClipboardTool(newConfig.clipboard.tool)

  # Update reserved words on all buffers
  let reservedWords = toReservedWords(newConfig.highlight.reservedWord)
  for buf in e.buffers:
    buf.setReservedWords(reservedWords)

  # Reload theme if configured
  initTheme(newConfig)

  # Update LSP enable/disable
  e.lsp.setEnabled(newConfig.lsp.enable)

  # Store the new config
  e.config = newConfig

proc maybeReloadConfig*(e: Editor) =
  ## Check if config file was modified and reload if:
  ##   - liveReloadOfConf is enabled in config
  ##   - Enough time has passed since last check (debouncing)
  ##   - Config file modification time has changed

  if not e.config.standard.liveReloadOfConf:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastConfigCheck
  let threshold = initDuration(milliseconds = e.state.timing.configCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastConfigCheck = now

  # Check if config file exists and has been modified
  let configPath = getConfigPath()
  if not fileExists(configPath):
    return

  var currentModTime: times.Time
  try:
    currentModTime = getFileInfo(configPath).lastWriteTime
  except OSError:
    return

  # Compare modification times
  if currentModTime == e.state.timing.lastConfigModTime:
    return

  # Config file was modified, reload it
  logInfo("editor", "Config file modified, reloading: " & configPath)
  let loadResult = loadConfigFromToml(configPath)
  if loadResult.isErr:
    logError("editor", "Failed to reload config: " & loadResult.error)
    return

  let (newConfig, vr) = loadResult.get
  if vr.hasErrors:
    for msg in vr.toErrorMessages:
      logWarn("editor", "Config warning: " & msg)

  # Apply the new settings
  e.applyConfigSettings(newConfig)

  # Update last known modification time
  e.state.timing.lastConfigModTime = currentModTime

  e.state.statusMessage = "Configuration reloaded"
  e.state.needsFullRedraw = true

proc maybeUpdateGitDiff*(e: Editor) =
  ## Update git diff if buffer was modified and enough time has passed (debouncing)
  ## This should be called after buffer modifications to provide real-time updates

  if not e.state.display.showGitDiff:
    return

  let activeBuffer = e.activeBuffer()

  # Only update if buffer has changed since last update
  if activeBuffer.changeSeq == e.state.timing.lastGitDiffChangeSeq:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastGitDiffUpdate

  # Compare with threshold duration (500ms)
  let threshold = initDuration(milliseconds = e.state.timing.gitDiffUpdateInterval)

  if elapsed >= threshold:
    e.refreshGitDiff(useBuffer = true)

proc enterRecentFileMode*(e: Editor): Result[void, string] =
  ## Enter Recent File mode in a vertical split window
  let state = newRecentFileModeState()
  let loadResult = state.loadRecentFiles()
  if loadResult.isErr:
    return err(loadResult.error)
  let recentBuffer = state.createRecentFileTextBuffer()
  let splitResult = e.vsplitWithBuffer(recentBuffer)
  if splitResult.isErr:
    return err(splitResult.error)
  e.activeWindow.recentFileModeState = some(state)
  ok()

proc startSubstitutePreview*(e: Editor) =
  ## Start substitute preview by saving the current buffer content
  if e.state.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  e.state.substitutePreview.originalLines = @[]
  for i in 0 ..< buffer.len:
    e.state.substitutePreview.originalLines.add(buffer.getLine(i))
  e.state.substitutePreview.isActive = true
  e.state.substitutePreview.lastPattern = ""
  e.state.substitutePreview.lastReplacement = ""

proc restoreFromPreview(e: Editor) =
  ## Restore buffer content from preview snapshot
  if not e.state.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  # Restore all lines from snapshot
  for i in 0 ..< e.state.substitutePreview.originalLines.len:
    if i < buffer.len:
      buffer.gapBuffer.replaceLine(i, e.state.substitutePreview.originalLines[i])

  # Handle line count differences
  while buffer.len > e.state.substitutePreview.originalLines.len:
    buffer.gapBuffer.deleteLine(buffer.len - 1)
  while buffer.len < e.state.substitutePreview.originalLines.len:
    buffer.gapBuffer.insertLine(
      buffer.len, e.state.substitutePreview.originalLines[buffer.len]
    )

  buffer.highlightNeedsUpdate = true

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.state.substitutePreview.isActive = false
  e.state.substitutePreview.originalLines = @[]
  e.state.needsFullRedraw = true

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (discard snapshot, keep current changes)
  e.state.substitutePreview.isActive = false
  e.state.substitutePreview.originalLines = @[]

proc updateSubstitutePreview*(
    e: Editor, pattern: string, replacement: string, isGlobalFlag: bool = true
) =
  ## Update substitute preview with new pattern and replacement
  ## isGlobalFlag: if true, replace all occurrences per line; if false, only first occurrence
  if not e.state.substitutePreview.isActive:
    return

  # Skip if nothing changed
  if pattern == e.state.substitutePreview.lastPattern and
      replacement == e.state.substitutePreview.lastReplacement:
    return

  e.state.substitutePreview.lastPattern = pattern
  e.state.substitutePreview.lastReplacement = replacement

  # Restore from snapshot first
  e.restoreFromPreview()

  if pattern.len == 0:
    e.state.needsFullRedraw = true
    return

  # Process escape sequences in replacement using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Apply substitute to buffer
  let buffer = e.activeBuffer()
  for lineIdx in 0 ..< buffer.len:
    var line = buffer.getLine(lineIdx)
    var newLine = ""
    var searchPos = 0
    var modified = false

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        newLine.add(line[searchPos ..^ 1])
        break

      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      newLine.add(processedReplacement)
      modified = true
      searchPos = idx + pattern.len

      # If not global flag, only replace first occurrence per line
      if not isGlobalFlag:
        newLine.add(line[searchPos ..^ 1])
        break

    if modified:
      buffer.gapBuffer.replaceLine(lineIdx, newLine)

  buffer.highlightNeedsUpdate = true
  e.state.needsFullRedraw = true

proc shutdown*(e: Editor) =
  ## Shutdown editor and clean up resources (including LSP servers)
  e.lsp.shutdown()

proc maybeUpdateDebugBuffer*(e: Editor) =
  ## Update debug buffer content periodically if it's displayed in a window
  ## This provides auto-refresh functionality for the debug viewer
  if e.state.debugBuffer == nil:
    return

  # Check if the debug buffer is still displayed in a window
  var foundWindow: EditorWindow = nil
  for window in e.windowManager.windows:
    if window.buffer == e.state.debugBuffer:
      foundWindow = window
      break

  if foundWindow == nil:
    # Debug buffer is no longer displayed, clear the reference
    e.state.debugBuffer = nil
    return

  # Check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastDebugUpdate
  let threshold = initDuration(milliseconds = e.state.timing.debugUpdateInterval)

  if elapsed < threshold:
    return

  # Generate fresh debug info based on config settings
  var debugLines: seq[string] = @[]
  let debugConfig = e.config.debug

  for i, window in e.windowManager.windows:
    generateWindowInfo(
      debugLines,
      i,
      i == e.windowManager.activeWindowIndex,
      e.buffers.find(window.buffer),
      window.viewport.x,
      window.viewport.y,
      window.viewport.width,
      window.viewport.height,
      window.viewport.topLine,
      window.viewport.leftColumn,
      window.cursor.line,
      window.cursor.column,
      debugConfig.windowNode.enable,
    )

  for i, buf in e.buffers:
    generateBufferInfo(
      debugLines,
      i,
      buf.filePath,
      buf.isModified,
      buf.readOnly,
      $buf.language,
      $buf.encoding,
      buf.len,
      buf.changeSeq,
      debugConfig.bufferStatus.enable,
    )

  generateEditorStateInfo(
    debugLines, e.state.mode, e.state.previousMode, e.activeWindow.cursor.line,
    e.cursor.column, e.state.commandText, e.state.statusMessage,
    debugConfig.editorView.enable,
  )

  generateSearchInfo(
    debugLines,
    e.state.search.text,
    e.state.search.lastText,
    $e.state.search.direction,
    e.state.search.history.len,
    e.state.search.ignorecase,
    e.state.search.smartcase,
    e.state.search.incsearch,
    e.state.search.hlsearch,
    debugConfig.search.enable,
  )

  generateDisplayInfo(
    debugLines, e.state.display.showStatusLine, e.state.display.multiStatusLine,
    e.state.display.showLineNumbers, e.state.display.showCursorLine,
    e.state.display.showSyntax, e.state.display.showIndentationLines,
    e.state.display.showSidebar, e.state.display.lineWrap, e.state.display.tabStop,
    debugConfig.editorView.enable,
  )

  generateMacroInfo(
    debugLines, e.state.macroState.isRecording, e.state.macroState.register,
    e.state.macroState.registers.len, e.state.macroState.playbackDepth,
    debugConfig.macroState.enable,
  )

  generateVisualInfo(
    debugLines,
    e.state.visualSelection.active,
    $e.state.visualSelection.kind,
    e.state.visualSelection.start.line,
    e.state.visualSelection.start.column,
    e.state.visualSelection.current.line,
    e.state.visualSelection.current.column,
    debugConfig.visual.enable,
  )

  generateJumpListInfo(
    debugLines, e.state.jumpList.len, e.state.jumpListIndex, debugConfig.jumpList.enable
  )

  generateLspInfo(
    debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
    e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
    debugConfig.lsp.enable,
  )

  # Update debug viewer state and create new buffer
  if foundWindow.debugViewerState.isSome:
    let debugState = foundWindow.debugViewerState.get
    debugState.lines = debugLines
    let newDebugBuffer = debugState.createDebugTextBuffer()

    # Preserve scroll position
    let savedTopLine = foundWindow.viewport.topLine
    let savedLeftColumn = foundWindow.viewport.leftColumn

    # Replace buffer in the window
    foundWindow.buffer = newDebugBuffer

    # Restore scroll position (clamped to valid range)
    foundWindow.viewport.topLine = min(savedTopLine, max(0, newDebugBuffer.len - 1))
    foundWindow.viewport.leftColumn = savedLeftColumn

    # Update the reference in state
    e.state.debugBuffer = newDebugBuffer
  e.state.timing.lastDebugUpdate = now
  e.state.needsFullRedraw = true

proc tick*(e: Editor) =
  ## Background processing: LSP, file watching, autosave, etc.
  ## Should be called each frame before rendering.

  # Poll LSP for messages (non-blocking)
  e.lsp.poll(0)

  # Cleanup stale progress entries (handles missing 'end' notifications)
  e.lsp.cleanupStaleProgress()

  # Update LSP progress display
  let progressOpt = e.lsp.getLatestActiveProgress()
  if progressOpt.isSome:
    e.state.lspProgressText = getProgressText(progressOpt.get)
  else:
    e.state.lspProgressText = ""

  # Display any pending LSP status messages
  let lspMessages = e.lsp.getAndClearMessages()
  if lspMessages.len > 0:
    # Store LSP messages for the log viewer
    addLspMessageLog(lspMessages)
    if e.config.notification.screenNotifications and
        e.config.notification.lspScreenNotify:
      e.state.statusMessage = lspMessages[^1]
    if e.config.notification.logNotifications and e.config.notification.lspLogNotify:
      for msg in lspMessages:
        logInfo("lsp", msg)

  # Update LSP if buffer was modified
  e.maybeUpdateLsp()

  # Update LSP caches
  e.updateCodeLensCache()
  e.updateDocumentHighlightCache()
  # Note: updateSemanticTokensCache is called in prepareFrame after updateHighlight
  e.requestSignatureHelpFromLsp()
  e.pollLspCompletion()
  e.pollLspHover()
  e.pollLspLocationRequest()
  e.pollLspCallHierarchy()
  e.pollLspSelectionRange()
  e.pollLspDocumentSymbols()
  e.pollLspDocumentLinks()
  e.pollLspDocumentLinkResolve()

  # File and config monitoring
  e.maybeReloadExternallyModifiedFile()
  e.maybeReloadConfig()

  # Git and debug updates
  e.maybeUpdateGitDiff()
  e.maybeUpdateDebugBuffer()

  # Auto save/backup
  e.autoSave()
  e.autoBackup()

proc prepareFrame(e: Editor, buffer: var Buffer): bool =
  ## Prepare for rendering: clear buffer, update animations, prepare highlights.
  ## Returns true if viewport was resized.

  clearBuffer(buffer)

  # Update smooth scroll animation
  if e.state.scrollAnimation.active:
    let reservedLines =
      if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve
    let bufferLen = e.activeBuffer().len
    let (_, cursorLine) = e.executer.motionController.viewportManager.updateScrollAnimation(
      e.state.scrollAnimation, e.config.smoothScroll, reservedLines, bufferLen
    )
    e.activeWindow.cursor.line = cursorLine

  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update highlight state (skip for debug buffer)
  let isDebugBuffer =
    e.state.debugBuffer != nil and e.activeBuffer() == e.state.debugBuffer

  if e.config.highlight.pairOfParen and not isDebugBuffer:
    e.state.matchingParenPos = findMatchingParenPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.matchingParenPos = none(BufferPosition)

  if e.config.highlight.currentWord and not isDebugBuffer:
    e.state.currentWord = getWordAtPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.currentWord = ""

  # Update syntax highlight before rendering (so semantic tokens can be applied on top)
  if not isDebugBuffer:
    let activeBuffer = e.activeBuffer()
    let needsHighlightUpdate = activeBuffer.highlightNeedsUpdate
    activeBuffer.updateHighlight()
    # If highlight was regenerated, we need to re-apply semantic tokens
    if needsHighlightUpdate:
      e.invalidateSemanticTokensCache()
    # Apply semantic tokens after local highlight is ready
    e.updateSemanticTokensCache()

  result = e.updateViewportSize(buffer)

proc renderMainContent(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render the main editor view (always uses split view since we always have at least one window).
  e.renderSplitView(buffer, wasResized)
  e.renderBottomLines(buffer)
  e.renderTempMessages(buffer)

proc renderOverlays(e: Editor, buffer: var Buffer) =
  ## Render overlay popups (completion, signature help, CodeLens picker, hover popup).

  if e.state.mode == EditorMode.Insert:
    let completionMgr = e.handlerManager.insertHandler.completionManager
    if completionMgr.isActive():
      # Anchor the popup to the start of the word being completed, not the
      # current cursor position. This prevents the popup from shifting when
      # cycling through candidates of different lengths.
      let anchorX = e.state.screenCursor.x - displayWidth(completionMgr.menu.prefix)
      let popupPos = calculatePopupPosition(
        anchorX, e.state.screenCursor.y, buffer.area.width, buffer.area.height,
        completionMgr.menu.entries, completionMgr.menu.maxVisible,
        e.config.autocomplete.windowBorder,
      )
      renderCompletionPopup(
        buffer, completionMgr.menu, popupPos, e.config.autocomplete.windowBorder
      )

    let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
    if sigHelpMgr.isActive():
      let popupPos = calculateSignatureHelpPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, sigHelpMgr.display.signature.len,
      )
      renderSignatureHelpPopup(buffer, sigHelpMgr.display, popupPos, true)

  if e.state.lspCache.codeLensPicker.isActive:
    e.renderCodeLensPicker(buffer)

  # Render hover popup (Normal mode)
  if e.state.lspCache.hoverPopup.isActive():
    let hoverMgr = e.state.lspCache.hoverPopup
    let popupPos = calculateHoverPopupPosition(
      e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
      buffer.area.height, hoverMgr,
    )
    renderHoverPopup(buffer, hoverMgr, popupPos, true)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components.
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  e.tick()
  let wasResized = e.prepareFrame(buffer)

  # Always use split view rendering - each window renders based on its own mode
  e.renderMainContent(buffer, wasResized)

  e.renderOverlays(buffer)
