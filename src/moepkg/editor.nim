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

import std/[strformat, strutils, sequtils, options, monotimes, times, os, tables]

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
  viewer_mode,
  editor_reload,
  editor_config_reload,
  editor_frame,
  editor_init,
  emergency

import
  render_utils, git_conflict, logger, config_loader, search_utils, hover_popup,
  command_completion, color, message_log, recent_file_mode, registers, persist,
  command_line, command_config, key_router, config, window_manager, lsp_integration

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
  ## Add a new command alias.
  ## Updates the runtime command config, the parser, and the persisted
  ## config ([CommandAliases]) so the alias survives save/reload.
  let
    commandName = canonicalCommandName(action)
    key = alias.toLowerAscii()
  if commandName.isNone:
    return err fmt"Unknown command action: {action}"
  e.commandConfig.addAlias(key, action)
  e.commandConfig.applyToParser(e.commandLineParser)
  e.config.commandAliases[key] = UserCommandEntry(command: commandName.get)
  # Re-adding an alias lifts any persisted disable of the same name.
  e.config.disabledCommandAliases.keepItIf(it != key)
  ok(())

proc removeCommandAlias*(e: Editor, alias: string): Result[(), string] =
  ## Remove a command alias.
  ## Updates the runtime command config, the parser, and the persisted
  ## config ([CommandAliases] / [DisabledCommandAliases]) so the removal
  ## survives save/reload. Removing a built-in default alias is persisted
  ## as a [DisabledCommandAliases] entry.
  let key = alias.toLowerAscii()
  if not e.commandLineParser.aliases.hasKey(key):
    return err fmt"Alias not found: {alias}"
  e.commandConfig.removeAlias(key)
  e.commandConfig.applyToParser(e.commandLineParser)
  e.config.commandAliases.del(key)
  if isDefaultCommandAlias(key) and key notin e.config.disabledCommandAliases:
    e.config.disabledCommandAliases.add(key)
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
  case editorConfig.bufferBackend.kind
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
  logDebug("editor", "Buffer backend: " & $editorConfig.bufferBackend.kind)

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
    lastLspContentVersions: initTable[BufferId, int](),
    state: EditorState(
      # activeWindow will be set after window creation below
      cursorVisible: true,
      display: DisplaySettings(
        showLineCount: true,
        showLinePercentage: true,
        showEncoding: true,
        showLineEnding: true,
      ),
      config: editorConfig,
      windowDisplay: WindowDisplayState(
        viewportReservedLines: steadyBottomAreaHeight(), # Status+command share same row
        savedViewportTopLine: 0, # Saved viewport position for operators
      ),
      # Timing state (grouped in TimingState)
      timing: TimingState(
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
      # Command-line/search input state (grouped in InputState)
      input: InputState(
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
      ),
      pendingInput: PendingInputState(
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
        pendingOperator: none(PendingOperator),
        pendingTextObject: none(PendingTextObject),
        pendingRegister: none(char),
      ),
      lastKeyWasEscape: false,
      editState: EditState(
        lastEditCommand: none(LastEditCommand),
        substituteContext: none(SubstituteContext),
        replaceHistory: @[],
        insertModeStartPos: none(BufferPosition),
        visualBlockInsertContext: none(VisualBlockInsertContext),
      ),
      registers: initRegisters(),
      # Jump list (grouped in JumpListState)
      jumpList: JumpListState(
        list: @[], # Empty jump list initially
        index: -1, # Not navigating jump list initially
      ),
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
        codeLensPoll: initDebouncedLspPoll(1000),
        documentHighlightPoll: initDebouncedLspPoll(200),
        semanticTokensPoll: initDebouncedLspPoll(500),
        semanticTokensPendingExtras: PendingSemanticTokensRequest(
          rangeFirst: -1,
          rangeLast: -1,
          legend: SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[]),
          viewportTopLine: -1,
          viewportBottomLine: -1,
        ),
        inlayHintPoll: initDebouncedLspPoll(500),
        inlayHintCache: InlayHintCache(isValid: false),
        signatureHelpPoll: initDebouncedLspPoll(100),
        # The interval is refreshed from config on every check.
        autoHoverPoll: initDebouncedLspPoll(0),
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

  # Add initial buffer to buffer list
  result.addBuffer(initialBuffer)
  logDebug("editor", "Initial buffer added, buffers.len: " & $result.buffers.len)

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

  result.motionController =
    newMotionController(initialBuffer, result.state, initialViewport)

  result.handlerManager = newHandlerManager(
    result.motionController, keyRegistry, cmdLineParser, cmdConfig, cmdRegistry,
    result.lsp,
  )

  # Route the initial config push through the reload path so the two lists
  # can't drift.
  result.applyConfigSettings(editorConfig)

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

  # Deprecation notices are not errors: the loader accepted the value. Log
  # them, and surface the first one only if no error already claimed the
  # status message.
  if configVr.hasDeprecations:
    let deprecationMessages = configVr.toDeprecationMessages
    if result.state.statusMessage.len == 0:
      result.state.statusMessage = "Config notice: " & deprecationMessages[0]
    for msg in deprecationMessages:
      addMessageLog("Config notice: " & msg)

  # Check for crash recovery files from a previous crash
  if hasCrashRecoveryFiles():
    let msg = "Crash recovery files found. See " & getCrashRecoveryBaseDir()
    if result.state.statusMessage.len == 0:
      result.state.statusMessage = msg
    addMessageLog(msg)

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
  e.enterViewerMode(
    EditorMode.RecentFile,
    ModeState(kind: mskRecentFile, recentFile: state),
    state.createRecentFileTextBuffer(),
    vpVSplit,
  )
