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

## Configuration system for moe editor
##
## This module defines all configuration structures and provides functionality
## for loading settings from TOML files.

import std/[options, tables, os, osproc]

import config_macros
export config_macros

type
  UserCommandEntry* = object
    command*: string ## The command to execute (command name or shell command)
    description*: string ## Optional user-provided description

  ColorMode* = enum
    cm8color = "8" ## 8 basic ANSI colors (0-7)
    cm16color = "16" ## 16 ANSI colors (0-15, includes bright)
    cm256color = "256" ## 256-color palette
    cm24bit = "24bit" ## True color (24-bit RGB)
    cmNone = "none" ## No colors (terminal defaults only)

  CursorType* = enum
    ctTerminalDefault = "terminalDefault"
    ctBlinkBlock = "blinkBlock"
    ctBlinkIbeam = "blinkIbeam"
    ctNonBlinkBlock = "nonBlinkBlock"
    ctNonBlinkIbeam = "nonBlinkIbeam"

  ThemeKind* = enum
    tkDefault = "default"
    tkConfig = "config"
    tkVscode = "vscode"

  ClipboardTool* = enum
    cbtXsel = "xsel"
    cbtXclip = "xclip"
    cbtWlClipboard = "wl-clipboard"
    cbtWin32yank = "win32yank"
    cbtPbcopy = "pbcopy"

  SplitType* = enum
    stHorizontal = "horizontal"
    stVertical = "vertical"

  BufferBackendConfig* = enum
    bbcAuto = "auto"
    bbcGapBuffer = "gapBuffer"
    bbcSqrtDecomp = "sqrtDecomp"
    bbcRope = "rope"
    bbcPieceTable = "pieceTable"

  # Standard settings
  StandardConfig* {.cfgSection: "Standard".} = object
    number* {.cfg.}: bool
    relativeNumber* {.cfg.}: bool
    statusLine* {.cfg.}: bool
    syntax* {.cfg.}: bool
    indentationLines* {.cfg.}: bool
    tabStop* {.cfg, cfgMin: 1, cfgMax: 16.}: int
    shiftWidth* {.cfg, cfgMin: 0, cfgMax: 16.}: int
      ## Indent width, 0 = use tabStop (Vim compatible)
    softTabStop* {.cfg, cfgMin: 0, cfgMax: 16.}: int
      ## Tab/Backspace width in insert mode, 0 = use tabStop (Vim compatible)
    expandTab* {.cfg.}: bool
    sidebar* {.cfg.}: bool
    scrollbar* {.cfg.}: bool
    scrollbarWidth* {.cfg, cfgMin: 0, cfgMax: 5.}: int
    bookmarkMarker* {.cfg.}: string
    showModifiedLines* {.cfg.}: bool
    autoCloseParen* {.cfg.}: bool
    autoIndent* {.cfg.}: bool
    ignorecase* {.cfg.}: bool
    smartcase* {.cfg.}: bool
    disableChangeCursor* {.cfg.}: bool
    defaultCursor* {.cfg.}: CursorType
    normalModeCursor* {.cfg.}: CursorType
    insertModeCursor* {.cfg.}: CursorType
    liveReloadOfConf* {.cfg.}: bool
    incrementalSearch* {.cfg.}: bool
    popupWindowInExmode* {.cfg.}: bool
    autoDeleteParen* {.cfg.}: bool
    liveReloadOfFile* {.cfg.}: bool
    colorMode* {.cfg.}: ColorMode
    mouse* {.cfg.}: bool
    lineWrap* {.cfg.}: bool
    timeoutlen* {.cfg, cfgMin: 0, cfgMax: 10000.}: int
      ## Key mapping timeout in ms (0 = no timeout)
    bufferBackend* {.cfg.}: BufferBackendConfig

  # Clipboard settings
  ClipboardConfig* {.cfgSection: "Clipboard".} = object
    enable* {.cfg.}: bool
    tool* {.cfg.}: ClipboardTool

  # Build on save settings
  BuildOnSaveConfig* {.cfgSection: "BuildOnSave".} = object
    enable* {.cfg.}: bool
    workspaceRoot* {.cfg, cfgDirPath, cfgNoUi.}: Option[string]
    command* {.cfg, cfgNoUi.}: Option[string]

  # Tab line settings
  TabLineConfig* {.cfgSection: "TabLine".} = object
    enable* {.cfg.}: bool

  # Status line settings
  StatusLineConfig* {.cfgSection: "StatusLine".} = object
    multipleStatusLine* {.cfg.}: bool
    merge* {.cfg.}: bool
    mode* {.cfg.}: bool
    filename* {.cfg.}: bool
    changedMark* {.cfg.}: bool
    directory* {.cfg.}: bool
    gitChangedLines* {.cfg.}: bool
    gitBranchName* {.cfg.}: bool
    showGitInactive* {.cfg.}: bool
    showModeInactive* {.cfg.}: bool
    setupText* {.cfg, cfgNoUi.}: string

  # Highlight settings
  HighlightConfig* {.cfgSection: "Highlight".} = object
    currentLine* {.cfg.}: bool
    currentColumn* {.cfg.}: bool
    reservedWord* {.cfg, cfgNoUi.}: seq[string]
    replaceText* {.cfg.}: bool
    pairOfParen* {.cfg.}: bool
    fullWidthSpace* {.cfg.}: bool
    trailingSpaces* {.cfg.}: bool
    currentWord* {.cfg.}: bool
    findCharHighlight* {.cfg.}: bool
    colorCodeHighlight* {.cfg.}: bool
    gitConflict* {.cfg.}: bool
    gitConflictTwoColor* {.cfg.}: bool

  # Auto backup settings
  AutoBackupConfig* {.cfgSection: "AutoBackup".} = object
    enable* {.cfg.}: bool
    backupDir* {.cfg, cfgDirPath, cfgNoUi.}: Option[string]
    idleTime* {.cfg, cfgMin: 1, cfgMax: 3600.}: int
    interval* {.cfg, cfgMin: 1, cfgMax: 3600.}: int
    dirToExclude* {.cfg, cfgNoUi.}: seq[string]

  # Quick run settings
  QuickRunConfig* {.cfgSection: "QuickRun".} = object
    saveBufferWhenQuickRun* {.cfg.}: bool
    command* {.cfg, cfgNoUi.}: Option[string]
    timeout* {.cfg, cfgMin: 1.}: int
    nimAdvancedCommand* {.cfg, cfgNoUi.}: Option[string]
    clangOptions* {.cfg, cfgKey: "ClangOptions", cfgNoUi.}: Option[string]
    cppOptions* {.cfg, cfgKey: "CppOptions", cfgNoUi.}: Option[string]
    nimOptions* {.cfg, cfgKey: "NimOptions", cfgNoUi.}: Option[string]
    shOptions* {.cfg, cfgNoUi.}: Option[string]
    bashOptions* {.cfg, cfgNoUi.}: Option[string]

  # Notification settings
  NotificationConfig* {.cfgSection: "Notification".} = object
    screenNotifications* {.cfg.}: bool
    logNotifications* {.cfg.}: bool
    autoBackupScreenNotify* {.cfg.}: bool
    autoBackupLogNotify* {.cfg.}: bool
    autoSaveScreenNotify* {.cfg.}: bool
    autoSaveLogNotify* {.cfg.}: bool
    yankScreenNotify* {.cfg.}: bool
    yankLogNotify* {.cfg.}: bool
    deleteScreenNotify* {.cfg.}: bool
    deleteLogNotify* {.cfg.}: bool
    saveScreenNotify* {.cfg.}: bool
    saveLogNotify* {.cfg.}: bool
    quickRunScreenNotify* {.cfg.}: bool
    quickRunLogNotify* {.cfg.}: bool
    buildOnSaveScreenNotify* {.cfg.}: bool
    buildOnSaveLogNotify* {.cfg.}: bool
    filerScreenNotify* {.cfg.}: bool
    filerLogNotify* {.cfg.}: bool
    restoreScreenNotify* {.cfg.}: bool
    restoreLogNotify* {.cfg.}: bool
    lspScreenNotify* {.cfg.}: bool
    lspLogNotify* {.cfg.}: bool
    lspForcePopup* {.cfg.}: bool
    popupNotifications* {.cfg.}: bool
    popupPosition* {.
      cfg, cfgEnumStrings: ["bottomRight", "topRight", "topLeft", "bottomLeft"]
    .}: string
    popupTimeoutMs* {.cfg, cfgMin: 100.}: int
    popupMaxVisible* {.cfg, cfgMin: 1.}: int
    popupMaxWidth* {.cfg, cfgMin: 10.}: int
    popupBorder* {.cfg.}: bool

  # Filer settings
  FilerConfig* {.cfgSection: "Filer".} = object
    showIcons* {.cfg.}: bool

  # FileTree settings
  FileTreeConfig* {.cfgSection: "FileTree".} = object
    width* {.cfg, cfgMin: 1.}: int

  # Autocomplete settings
  AutocompleteConfig* {.cfgSection: "Autocomplete".} = object
    enable* {.cfg.}: bool
    windowBorder* {.cfg.}: bool

  # Auto save settings
  AutoSaveConfig* {.cfgSection: "AutoSave".} = object
    enable* {.cfg.}: bool
    interval* {.cfg, cfgMin: 1, cfgMax: 3600.}: int

  # Persist settings
  PersistConfig* {.cfgSection: "Persist".} = object
    commandHistory* {.cfg.}: bool
    commandHistoryLimit* {.cfg, cfgMin: 1.}: int
    search* {.cfg.}: bool
    searchHistoryLimit* {.cfg, cfgMin: 1.}: int
    cursorPosition* {.cfg.}: bool
    bookmarks* {.cfg.}: bool

  # Git settings
  GitConfig* {.cfgSection: "Git".} = object
    showChangedLine* {.cfg.}: bool
    updateInterval* {.cfg, cfgMin: 100, cfgMax: 60000.}: int

  # Syntax checker settings
  SyntaxCheckerConfig* {.cfgSection: "SyntaxChecker".} = object
    enable* {.cfg.}: bool

  # Smooth scroll settings (physics-based, compatible with vim comfortable-motion)
  SmoothScrollConfig* {.cfgSection: "SmoothScroll".} = object
    enable* {.cfg.}: bool
    friction* {.cfg, cfgMin: 0.0, cfgMax: 500.0, cfgStep: 10.0.}: float
      # Friction coefficient (velocity decay rate). Default: 80.0
    airDrag* {.cfg, cfgMin: 0.0, cfgMax: 20.0, cfgStep: 0.5.}: float
      # Air drag coefficient (velocity resistance). Default: 2.0

  # EditorConfig settings
  EditorConfigSettings* {.cfgSection: "EditorConfig".} = object
    enable* {.cfg.}: bool

  # Startup file open settings
  StartUpFileOpenConfig* {.cfgSection: "StartUp.FileOpen".} = object
    autoSplit* {.cfg.}: bool
    splitType* {.cfg.}: SplitType

  # Startup file tree settings
  StartUpFileTreeConfig* {.cfgSection: "StartUp.FileTree".} = object
    enable* {.cfg.}: bool

  # Debug window node settings
  DebugWindowNodeConfig* {.cfgSection: "Debug.WindowNode".} = object
    enable* {.cfg.}: bool
    currentWindow* {.cfg.}: bool
    index* {.cfg.}: bool
    windowIndex* {.cfg.}: bool
    bufferIndex* {.cfg.}: bool
    parentIndex* {.cfg.}: bool
    childLen* {.cfg.}: bool
    splitType* {.cfg.}: bool
    haveCursesWin* {.cfg.}: bool
    y* {.cfg.}: bool
    x* {.cfg.}: bool
    h* {.cfg.}: bool
    w* {.cfg.}: bool
    currentLine* {.cfg.}: bool
    currentColumn* {.cfg.}: bool
    expandedColumn* {.cfg.}: bool
    cursor* {.cfg.}: bool

  # Debug editor view settings
  DebugEditorViewConfig* {.cfgSection: "Debug.EditorView".} = object
    enable* {.cfg.}: bool
    widthOfLineNum* {.cfg.}: bool
    height* {.cfg.}: bool
    width* {.cfg.}: bool
    originalLine* {.cfg.}: bool
    start* {.cfg.}: bool
    length* {.cfg.}: bool

  # Debug buffer status settings
  DebugBufferStatusConfig* {.cfgSection: "Debug.BufferStatus".} = object
    enable* {.cfg.}: bool
    bufferIndex* {.cfg.}: bool
    path* {.cfg.}: bool
    openDir* {.cfg.}: bool
    currentMode* {.cfg.}: bool
    prevMode* {.cfg.}: bool
    language* {.cfg.}: bool
    encoding* {.cfg.}: bool
    countChange* {.cfg.}: bool
    cmdLoop* {.cfg.}: bool
    lastSaveTime* {.cfg.}: bool
    bufferLen* {.cfg.}: bool

  # Debug search settings
  DebugSearchConfig* {.cfgSection: "Debug.Search".} = object
    enable* {.cfg.}: bool

  # Debug macro settings
  DebugMacroConfig* {.cfgSection: "Debug.MacroState".} = object
    enable* {.cfg.}: bool

  # Debug visual selection settings
  DebugVisualConfig* {.cfgSection: "Debug.Visual".} = object
    enable* {.cfg.}: bool

  # Debug jump list settings
  DebugJumpListConfig* {.cfgSection: "Debug.JumpList".} = object
    enable* {.cfg.}: bool

  # Debug LSP settings
  DebugLspConfig* {.cfgSection: "Debug.Lsp".} = object
    enable* {.cfg.}: bool

  # Log settings
  LogConfig* {.cfgSection: "Log".} = object
    clearOnStart* {.cfg.}: bool ## Clear existing log file when starting with debug mode

  # Debug settings
  DebugConfig* = object
    windowNode*: DebugWindowNodeConfig
    editorView*: DebugEditorViewConfig
    bufferStatus*: DebugBufferStatusConfig
    search*: DebugSearchConfig
    macroState*: DebugMacroConfig
    visual*: DebugVisualConfig
    jumpList*: DebugJumpListConfig
    lsp*: DebugLspConfig

  # Theme settings
  ThemeConfig* = object
    kind*: ThemeKind
    path*: string

  # LSP trace level
  LspTraceLevel* = enum
    ltOff = "off"
    ltMessages = "messages"
    ltVerbose = "verbose"

  # LSP feature config (enable only)
  LspFeatureConfig* = object
    enable*: bool

  # LSP diagnostics config
  LspDiagnosticsConfig* = object
    enable*: bool
    autoHover*: bool
    autoHoverDelay*: int # Debounce delay in milliseconds

  # LSP feature with openWindow option
  LspOpenWindowConfig* = object
    enable*: bool
    openWindow*: bool

  # LSP language server config
  LspServerConfig* = object
    extensions*: seq[string]
    command*: string
    trace*: LspTraceLevel
    # Rust-analyzer specific options
    rustAnalyzerRunSingle*: bool
    rustAnalyzerDebugSingle*: bool

  # LSP settings
  LspConfig* = object
    enable*: bool
    timeout*: int
    # Feature configs
    completion*: LspFeatureConfig
    declaration*: LspOpenWindowConfig
    definition*: LspOpenWindowConfig
    typeDefinition*: LspOpenWindowConfig
    implementation*: LspOpenWindowConfig
    diagnostics*: LspDiagnosticsConfig
    signatureHelp*: LspFeatureConfig
    documentFormatting*: LspFeatureConfig
    foldingRange*: LspFeatureConfig
    selectionRange*: LspFeatureConfig
    documentSymbol*: LspFeatureConfig
    hover*: LspFeatureConfig
    inlayHint*: LspFeatureConfig
    inlineValue*: LspFeatureConfig
    references*: LspFeatureConfig
    callHierarchy*: LspFeatureConfig
    documentHighlight*: LspFeatureConfig
    documentLink*: LspFeatureConfig
    codeLens*: LspFeatureConfig
    rename*: LspFeatureConfig
    semanticTokens*: LspFeatureConfig
    executeCommand*: LspFeatureConfig
    # Language server configs (language name -> config)
    servers*: Table[string, LspServerConfig]

  # Key mapping settings
  KeyMappingConfig* = object
    all*: OrderedTable[string, string]
    normal*: OrderedTable[string, string]
    insert*: OrderedTable[string, string]
    visual*: OrderedTable[string, string]
    visualAll*: OrderedTable[string, string]
    visualLine*: OrderedTable[string, string]
    visualBlock*: OrderedTable[string, string]
    replace*: OrderedTable[string, string]
    command*: OrderedTable[string, string]
    filer*: OrderedTable[string, string]
    logViewer*: OrderedTable[string, string]
    help*: OrderedTable[string, string]
    bufferManager*: OrderedTable[string, string]
    backupManager*: OrderedTable[string, string]
    diffViewer*: OrderedTable[string, string]
    config*: OrderedTable[string, string]
    references*: OrderedTable[string, string]
    documentSymbol*: OrderedTable[string, string]
    callHierarchy*: OrderedTable[string, string]
    recentFile*: OrderedTable[string, string]
    debug*: OrderedTable[string, string]
    terminal*: OrderedTable[string, string]

  # Main configuration
  EditorConfig* = ref object
    standard*: StandardConfig
    clipboard*: ClipboardConfig
    buildOnSave*: BuildOnSaveConfig
    tabLine*: TabLineConfig
    statusLine*: StatusLineConfig
    highlight*: HighlightConfig
    autoBackup*: AutoBackupConfig
    quickRun*: QuickRunConfig
    notification*: NotificationConfig
    filer*: FilerConfig
    fileTree*: FileTreeConfig
    autocomplete*: AutocompleteConfig
    autoSave*: AutoSaveConfig
    persist*: PersistConfig
    git*: GitConfig
    syntaxChecker*: SyntaxCheckerConfig
    smoothScroll*: SmoothScrollConfig
    startUpFileOpen*: StartUpFileOpenConfig
    startUpFileTree*: StartUpFileTreeConfig
    editorConfig*: EditorConfigSettings
    log*: LogConfig
    debug*: DebugConfig
    theme*: ThemeConfig
    lsp*: LspConfig
    keyMapping*: KeyMappingConfig
    shellCommands*: Table[string, UserCommandEntry] ## Shell command definitions
    commandAliases*: Table[string, UserCommandEntry] ## User-defined command aliases

proc isToolAvailable(toolCommand: string): bool =
  ## Check if a command-line tool is available in PATH
  let checkResult = execCmdEx("command -v " & toolCommand)
  return checkResult.exitCode == 0

proc isWaylandSession(): bool =
  ## Check if running in a Wayland session
  getEnv("WAYLAND_DISPLAY").len > 0 or getEnv("XDG_SESSION_TYPE") == "wayland"

proc detectClipboardTool*(): ClipboardTool =
  ## Detect the best available clipboard tool for the current environment
  ## Prioritizes Wayland tools on Wayland, then X11 tools, then platform-specific
  if isWaylandSession():
    # Wayland: prefer wl-clipboard
    if isToolAvailable("wl-copy"):
      return cbtWlClipboard
  # X11 or Wayland fallback: try xsel, then xclip
  if isToolAvailable("xsel"):
    return cbtXsel
  if isToolAvailable("xclip"):
    return cbtXclip
  # macOS
  if isToolAvailable("pbcopy"):
    return cbtPbcopy
  # WSL/Windows
  if isToolAvailable("win32yank.exe"):
    return cbtWin32yank
  # Default fallback
  return cbtXsel

proc newEditorConfig*(): EditorConfig =
  ## Create a new configuration with default values
  EditorConfig(
    standard: StandardConfig(
      number: true,
      relativeNumber: false,
      statusLine: true,
      syntax: true,
      indentationLines: true,
      tabStop: 2,
      shiftWidth: 0, # 0 = use tabStop (Vim compatible)
      softTabStop: 0, # 0 = use tabStop (Vim compatible)
      expandTab: false, # Match example/moerc.toml default
      sidebar: true,
      scrollbar: false,
      scrollbarWidth: 1,
      bookmarkMarker: "♥ ",
      showModifiedLines: true,
      autoCloseParen: true,
      autoIndent: true,
      ignorecase: true,
      smartcase: true,
      disableChangeCursor: false,
      defaultCursor: ctTerminalDefault,
      normalModeCursor: ctBlinkBlock,
      insertModeCursor: ctBlinkIbeam,
      liveReloadOfConf: false,
      incrementalSearch: true,
      popupWindowInExmode: true,
      autoDeleteParen: true,
      liveReloadOfFile: true,
      colorMode: cm256color,
      mouse: false,
      lineWrap: true,
      timeoutlen: 1000,
      bufferBackend: bbcAuto,
    ),
    clipboard: ClipboardConfig(enable: true, tool: detectClipboardTool()),
    buildOnSave: BuildOnSaveConfig(
      enable: false, workspaceRoot: none(string), command: none(string)
    ),
    tabLine: TabLineConfig(enable: true),
    statusLine: StatusLineConfig(
      multipleStatusLine: true,
      merge: false,
      mode: true,
      filename: true,
      changedMark: true,
      directory: true,
      gitChangedLines: true,
      gitBranchName: true,
      showGitInactive: false,
      showModeInactive: false,
      setupText:
        "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {lineEnding} {fileType}",
    ),
    highlight: HighlightConfig(
      currentLine: true,
      reservedWord: @["TODO", "WIP", "NOTE"],
      replaceText: true,
      pairOfParen: true,
      fullWidthSpace: true,
      trailingSpaces: true,
      currentWord: true,
      findCharHighlight: true,
      colorCodeHighlight: true,
      gitConflict: true,
      gitConflictTwoColor: true,
    ),
    autoBackup: AutoBackupConfig(
      enable: false,
      backupDir: none(string),
      idleTime: 10,
      interval: 5,
      dirToExclude: @["/etc"],
    ),
    quickRun: QuickRunConfig(
      saveBufferWhenQuickRun: true,
      command: none(string),
      timeout: 30,
      nimAdvancedCommand: none(string),
      clangOptions: none(string),
      cppOptions: none(string),
      nimOptions: none(string),
      shOptions: none(string),
      bashOptions: none(string),
    ),
    notification: NotificationConfig(
      screenNotifications: true,
      logNotifications: true,
      autoBackupScreenNotify: true,
      autoBackupLogNotify: true,
      autoSaveScreenNotify: true,
      autoSaveLogNotify: true,
      yankScreenNotify: true,
      yankLogNotify: true,
      deleteScreenNotify: true,
      deleteLogNotify: true,
      saveScreenNotify: true,
      saveLogNotify: true,
      quickRunScreenNotify: true,
      quickRunLogNotify: true,
      buildOnSaveScreenNotify: true,
      buildOnSaveLogNotify: true,
      filerScreenNotify: true,
      filerLogNotify: true,
      restoreScreenNotify: true,
      restoreLogNotify: true,
      lspScreenNotify: true,
      lspLogNotify: true,
      lspForcePopup: true,
      popupNotifications: false,
      popupPosition: "bottomRight",
      popupTimeoutMs: 3000,
      popupMaxVisible: 3,
      popupMaxWidth: 60,
      popupBorder: false,
    ),
    filer: FilerConfig(showIcons: true),
    fileTree: FileTreeConfig(width: 30),
    autocomplete: AutocompleteConfig(enable: true, windowBorder: true),
    autoSave: AutoSaveConfig(enable: true, interval: 5),
    persist: PersistConfig(
      commandHistory: true,
      commandHistoryLimit: 1000,
      search: true,
      searchHistoryLimit: 1000,
      cursorPosition: true,
      bookmarks: true,
    ),
    git: GitConfig(showChangedLine: true, updateInterval: 1000),
    syntaxChecker: SyntaxCheckerConfig(enable: false),
    smoothScroll: SmoothScrollConfig(enable: true, friction: 80.0, airDrag: 2.0),
    startUpFileOpen: StartUpFileOpenConfig(autoSplit: true, splitType: stVertical),
    startUpFileTree: StartUpFileTreeConfig(enable: false),
    editorConfig: EditorConfigSettings(enable: true),
    log: LogConfig(clearOnStart: false),
    debug: DebugConfig(
      windowNode: DebugWindowNodeConfig(
        enable: true,
        currentWindow: true,
        index: true,
        windowIndex: true,
        bufferIndex: true,
        parentIndex: true,
        childLen: true,
        splitType: true,
        haveCursesWin: true,
        y: true,
        x: true,
        h: true,
        w: true,
        currentLine: true,
        currentColumn: true,
        expandedColumn: true,
        cursor: true,
      ),
      editorView: DebugEditorViewConfig(
        enable: true,
        widthOfLineNum: true,
        height: true,
        width: true,
        originalLine: false,
        start: false,
        length: false,
      ),
      bufferStatus: DebugBufferStatusConfig(
        enable: true,
        bufferIndex: true,
        path: true,
        openDir: true,
        currentMode: true,
        prevMode: true,
        language: true,
        encoding: true,
        countChange: true,
        cmdLoop: true,
        lastSaveTime: true,
        bufferLen: true,
      ),
      search: DebugSearchConfig(enable: true),
      macroState: DebugMacroConfig(enable: true),
      visual: DebugVisualConfig(enable: true),
      jumpList: DebugJumpListConfig(enable: true),
      lsp: DebugLspConfig(enable: true),
    ),
    theme: ThemeConfig(kind: tkConfig, path: "~/.config/moe/themes/dark.toml"),
    lsp: LspConfig(
      enable: false,
      timeout: 5000,
      completion: LspFeatureConfig(enable: true),
      declaration: LspOpenWindowConfig(enable: true, openWindow: false),
      definition: LspOpenWindowConfig(enable: true, openWindow: false),
      typeDefinition: LspOpenWindowConfig(enable: true, openWindow: false),
      implementation: LspOpenWindowConfig(enable: true, openWindow: false),
      diagnostics:
        LspDiagnosticsConfig(enable: true, autoHover: true, autoHoverDelay: 300),
      signatureHelp: LspFeatureConfig(enable: true),
      documentFormatting: LspFeatureConfig(enable: true),
      foldingRange: LspFeatureConfig(enable: true),
      selectionRange: LspFeatureConfig(enable: true),
      documentSymbol: LspFeatureConfig(enable: true),
      hover: LspFeatureConfig(enable: true),
      inlayHint: LspFeatureConfig(enable: true),
      inlineValue: LspFeatureConfig(enable: false),
      references: LspFeatureConfig(enable: true),
      callHierarchy: LspFeatureConfig(enable: true),
      documentHighlight: LspFeatureConfig(enable: true),
      documentLink: LspFeatureConfig(enable: true),
      codeLens: LspFeatureConfig(enable: false),
      rename: LspFeatureConfig(enable: true),
      semanticTokens: LspFeatureConfig(enable: true),
      executeCommand: LspFeatureConfig(enable: true),
      servers: initTable[string, LspServerConfig](),
    ),
    keyMapping: KeyMappingConfig(
      all: initOrderedTable[string, string](),
      normal: initOrderedTable[string, string](),
      insert: initOrderedTable[string, string](),
      visual: initOrderedTable[string, string](),
      visualAll: initOrderedTable[string, string](),
      visualLine: initOrderedTable[string, string](),
      visualBlock: initOrderedTable[string, string](),
      replace: initOrderedTable[string, string](),
      command: initOrderedTable[string, string](),
      filer: initOrderedTable[string, string](),
      logViewer: initOrderedTable[string, string](),
      help: initOrderedTable[string, string](),
      bufferManager: initOrderedTable[string, string](),
      backupManager: initOrderedTable[string, string](),
      diffViewer: initOrderedTable[string, string](),
      config: initOrderedTable[string, string](),
      references: initOrderedTable[string, string](),
      documentSymbol: initOrderedTable[string, string](),
      callHierarchy: initOrderedTable[string, string](),
      recentFile: initOrderedTable[string, string](),
      debug: initOrderedTable[string, string](),
      terminal: initOrderedTable[string, string](),
    ),
    shellCommands: initTable[string, UserCommandEntry](),
    commandAliases: initTable[string, UserCommandEntry](),
  )
