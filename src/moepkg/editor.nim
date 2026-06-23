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

import std/[strformat, options, monotimes, times, os]

import pkg/[results, chronos]

import
  types/editor_types,
  editor_window,
  editor_file,
  editor_lsp,
  editor_codelens,
  editor_selectionrange,
  editor_documentsymbol,
  editor_documentlink,
  editor_signaturehelp,
  editor_hover,
  editor_callhierarchy,
  editor_navigation,
  editor_render,
  editor_display,
  editor_substitute,
  editor_buffers,
  editor_reload,
  editor_config_reload,
  editor_frame,
  editor_init,
  emergency

import
  status_line, render_utils, git_conflict, logger, config_loader, search_utils,
  hover_popup, command_completion, color, message_log, sidebar, recent_file_mode

import command_handlers/handler_manager

export
  editor_types, editor_window, editor_file, editor_lsp, editor_codelens,
  editor_selectionrange, editor_documentsymbol, editor_documentlink,
  editor_signaturehelp, editor_hover, editor_callhierarchy, editor_navigation,
  editor_render, editor_display, editor_substitute, editor_buffers, editor_reload,
  editor_config_reload, editor_frame

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

  # Accumulator for validation errors discovered during initialization.
  var configVr = vr

  # Initialize theme from configuration. Invalid keys/values in the user theme
  # file are recorded in configVr so they surface in the startup status message.
  initTheme(editorConfig, configVr)

  # Create the command/keybinding registries and load all config-driven
  # built-in commands, default bindings, [KeyMapping] overrides, command
  # aliases, and shell commands (see editor_init.nim).
  let (cmdRegistry, keyRegistry, cmdConfig, cmdLineParser) =
    newEditorRegistries(editorConfig, configVr)

  # Set buffer backend from configuration
  case editorConfig.standard.bufferBackend
  of bbcAuto:
    setAutoBackendMode(true)
    setConfiguredBackend(GapBuffer)
  of bbcGapBuffer:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)
  of bbcSqrtDecomp:
    setAutoBackendMode(false)
    setConfiguredBackend(SqrtDecomp)
  of bbcRope:
    setAutoBackendMode(false)
    setConfiguredBackend(Rope)
  of bbcPieceTable:
    setAutoBackendMode(false)
    setConfiguredBackend(PieceTable)
  logDebug("editor", "Buffer backend: " & $editorConfig.standard.bufferBackend)

  # Initialize LSP integration with current working directory as workspace root
  let lspIntegration = newLspIntegration(getCurrentDir())

  # The initial buffer and viewport are owned by the default window created
  # below; the editor has no separate buffer/viewport field, so keep local
  # handles for the setup wiring.
  let initialBuffer = newTextBuffer()
  let initialViewport =
    ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0)

  result = Editor(
    lsp: lspIntegration,
    lastLspChangeSeqs: initTable[BufferId, int](),
    state: EditorState(
      # activeWindow will be set after window creation below
      cursorVisible: true,
      # Display settings (grouped in DisplaySettings)
      display: DisplaySettings(
        showTabLine: editorConfig.tabLine.enable,
        showStatusLine: editorConfig.standard.statusLine,
        multiStatusLine: editorConfig.statusLine.multipleStatusLine,
        showLineCount: true,
        showLinePercentage: true,
        showEncoding: true,
        showLineEnding: true,
        showLineNumbers: editorConfig.standard.number,
        relativeLineNumbers: editorConfig.standard.relativeNumber,
        showCursorLine: editorConfig.highlight.currentLine,
        showCursorColumn: editorConfig.highlight.currentColumn,
        showSyntax: editorConfig.standard.syntax,
        showIndentationLines: editorConfig.standard.indentationLines,
        showSidebar: editorConfig.standard.sidebar,
        scrollbar: editorConfig.standard.scrollbar,
        scrollbarWidth: editorConfig.standard.scrollbarWidth,
        showModifiedLines: editorConfig.standard.showModifiedLines,
        showGitDiff: editorConfig.git.showChangedLine,
        showSyntaxChecker: editorConfig.syntaxChecker.enable,
        showCodeLens: editorConfig.lsp.codeLens.enable,
        showDocumentHighlight: editorConfig.lsp.documentHighlight.enable,
        showInlayHint: editorConfig.lsp.inlayHint.enable,
        lineWrap: editorConfig.standard.lineWrap,
        tabStop: editorConfig.standard.tabStop,
        shiftWidth: editorConfig.standard.shiftWidth,
        softTabStop: editorConfig.standard.softTabStop,
        expandTab: editorConfig.standard.expandTab,
        autoIndent: editorConfig.standard.autoIndent,
        smartIndent: editorConfig.standard.smartIndent,
        autoCloseParen: editorConfig.standard.autoCloseParen,
        autoDeleteParen: editorConfig.standard.autoDeleteParen,
        bracketSplit: editorConfig.standard.bracketSplit,
      ),
      windowDisplay: WindowDisplayState(
        viewportReservedLines: steadyBottomAreaHeight(), # Status+command share same row
        savedViewportTopLine: 0, # Saved viewport position for operators
      ),
      # Timing state (grouped in TimingState)
      timing: TimingState(
        lastResizeTime: getMonoTime(),
        gitDiffUpdateInterval: editorConfig.git.updateInterval,
        lastConflictScan: getMonoTime(),
        lastConflictScanSeq: -1,
        conflictScanInterval: DefaultConflictScanIntervalMs,
        lastAutoSave: getMonoTime(),
        lastAutoBackup: getMonoTime(),
        lastInputTime: getMonoTime(),
        lastFileModCheck: getMonoTime(),
        fileModCheckInterval: 1000, # Check file modification every 1 second
        lastConfigCheck: getMonoTime(),
        lastConfigModTime: times.Time(), # Will be set properly after initialization
        configCheckInterval: 2000, # Check config modification every 2 seconds
        lastLspCleanup: getMonoTime(),
        lspCleanupInterval: 1000, # Sweep timed-out LSP requests every 1 second
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
          if editorConfig.persist.commandHistory:
            loadCommandHistory(editorConfig.persist.commandHistoryLimit)
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
        lastEditCommand: none(LastEditCommand),
        pendingOperator: none(PendingOperator),
        pendingTextObject: none(PendingTextObject),
        substituteContext: none(SubstituteContext),
        replaceHistory: @[],
        insertModeStartPos: none(BufferPosition),
        visualBlockInsertContext: none(VisualBlockInsertContext),
      ),
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
        inlayHintCache: InlayHintCache(isValid: false),
        lastInlayHintUpdate: getMonoTime(),
        inlayHintUpdateInterval: 500, # 500ms debounce for inlay hints
        signatureHelp: SignatureHelpRequestState(
          lastUpdate: getMonoTime(),
          interval: 100, # 100ms debounce for signature help
          cursorLine: -1,
          cursorColumn: -1,
          changeSeq: -1,
          consecutiveErrors: 0,
        ),
      ),
      notificationPopup: newNotificationPopupManager(),
    ),
    screenSize: ScreenSize(width: 80, height: 20),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    keyRouter: newKeyRouter(
      keyRegistry,
      TimeoutPolicy(timeoutlen: editorConfig.standard.timeoutlen, enabled: true),
    ),
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
    savedBookmarks:
      if editorConfig.persist.bookmarks:
        loadBookmarks()
      else:
        initTable[string, seq[int]](),
  )

  # Apply sidebar bookmark marker from config
  setBookmarkMarker(editorConfig.standard.bookmarkMarker)

  # Sync notification popup settings from config
  result.state.notificationPopup.timeoutMs = editorConfig.notification.popupTimeoutMs
  result.state.notificationPopup.maxVisible = editorConfig.notification.popupMaxVisible
  result.state.notificationPopup.maxWidth = editorConfig.notification.popupMaxWidth
  result.state.notificationPopup.showBorder = editorConfig.notification.popupBorder
  case editorConfig.notification.popupPosition
  of "topRight":
    result.state.notificationPopup.position = nppTopRight
  of "topLeft":
    result.state.notificationPopup.position = nppTopLeft
  of "bottomLeft":
    result.state.notificationPopup.position = nppBottomLeft
  else:
    result.state.notificationPopup.position = nppBottomRight

  # Add initial buffer to buffer list
  result.addBuffer(initialBuffer)
  logDebug("editor", "Initial buffer added, buffers.len: " & $result.buffers.len)

  # Set reserved words for syntax highlighting on initial buffer
  initialBuffer.setReservedWords(toReservedWords(editorConfig.highlight.reservedWord))

  # Create default window (always have at least one window)
  result.windowManager.windows.add(
    EditorWindow(
      buffer: initialBuffer,
      bufferIds: @[initialBuffer.id],
        # Initialize per-window tabs with the initial buffer
      viewport: initialViewport,
      cursor: BufferPosition(line: 0, column: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      preferredColumn: -1,
      screenCursor: CursorPosition(x: 0, y: 0),
      active: true,
      wrapCountCache: WrapCountCache(),
    )
  )
  result.windowManager.activeWindowIndex = 0
  result.state.activeWindow = result.windowManager.windows[0]
  result.state.windowDisplay.currentBufferId = initialBuffer.id
  logDebug(
    "editor",
    "Default window created, windows.len: " & $result.windowManager.windows.len,
  )

  result.executer = newCommandExecutor(
    initialBuffer,
    result.state,
    initialViewport,
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
    result.config.lsp.completion.enable,
  )

  # Set clipboard tool for register system
  if result.config.clipboard.enable:
    result.state.registers.setClipboardTool(result.config.clipboard.tool)

  # Apply LSP enable setting from config
  result.lsp.setEnabled(result.config.lsp.enable)

  # Apply the user-configured LSP request timeout (config.lsp.timeout, ms).
  result.lsp.service.setRequestTimeout(result.config.lsp.timeout)

  # Propagate per-language server settings from the config ([Lsp.<lang>])
  # into the LSP service. Without this, user overrides for command,
  # extensions, or trace were ignored and only the hardcoded defaults ran.
  # The command string may include arguments; the worker splits it, so args
  # is cleared when a custom command is given. trace=verbose enables raw
  # JSON-RPC logging (off by default to avoid the per-keystroke cost).
  for langId, serverCfg in result.config.lsp.servers:
    let existing = result.lsp.service.getConfig(langId)
    if existing.isSome:
      var c = existing.get
      if serverCfg.command.len > 0:
        c.command = serverCfg.command
        c.args = @[]
      if serverCfg.extensions.len > 0:
        c.extensions = serverCfg.extensions
      if serverCfg.trace == LspTraceLevel.ltVerbose:
        c.rawJsonLog = true
      if langId == "rust":
        # Drive rust-analyzer's run/debug CodeLenses from the user settings.
        # Sent explicitly (including false) so the lenses are suppressed when
        # disabled, instead of relying on rust-analyzer's on-by-default lens.
        c.initializationOptions =
          "{\"lens\":{\"run\":{\"enable\":" & $serverCfg.rustAnalyzerRunSingle &
          "},\"debug\":{\"enable\":" & $serverCfg.rustAnalyzerDebugSingle & "}}}"
      result.lsp.service.setConfig(langId, c)
    elif serverCfg.command.len > 0:
      # A language with no built-in default: register it from the user config
      result.lsp.service.setConfig(
        langId,
        LanguageServerConfig(
          command: serverCfg.command,
          args: @[],
          extensions: serverCfg.extensions,
          enabled: true,
          rawJsonLog: serverCfg.trace == LspTraceLevel.ltVerbose,
        ),
      )

  # Initialize config file modification time for liveReloadOfConf
  let configPath = getConfigPath()
  if fileExists(configPath):
    try:
      result.state.timing.lastConfigModTime = getFileInfo(configPath).lastWriteTime
    except OSError:
      discard

  # Display validation errors in status message if any
  if configVr.hasErrors:
    let errorMessages = configVr.toErrorMessages
    result.state.statusMessage = "Config error: " & errorMessages[0]
    # Log all errors
    for msg in errorMessages:
      addMessageLog("Config error: " & msg)

  # Check for crash recovery files from a previous crash
  if hasCrashRecoveryFiles():
    let msg = "Crash recovery files found. See " & getCrashRecoveryBaseDir()
    if result.state.statusMessage.len == 0:
      result.state.statusMessage = msg
    addMessageLog(msg)

  # Propagate the configured git diff refresh cadence into the status-line
  # cache's module global. applyConfigSettings does this on config reload;
  # without an initial call here the cache would run at the hardcoded
  # default until the first reload.
  setGitDiffRefreshInterval(editorConfig.git.updateInterval.int64)

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
  e.activeWindow.modeState = ModeState(kind: mskRecentFile, recentFile: state)
  ok()
