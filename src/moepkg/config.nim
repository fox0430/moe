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

type
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

  # Standard settings
  StandardConfig* = object
    number*: bool
    statusLine*: bool
    syntax*: bool
    indentationLines*: bool
    tabStop*: int
    expandTab*: bool
    sidebar*: bool
    autoCloseParen*: bool
    autoIndent*: bool
    ignorecase*: bool
    smartcase*: bool
    disableChangeCursor*: bool
    defaultCursor*: CursorType
    normalModeCursor*: CursorType
    insertModeCursor*: CursorType
    liveReloadOfConf*: bool
    incrementalSearch*: bool
    popupWindowInExmode*: bool
    autoDeleteParen*: bool
    liveReloadOfFile*: bool
    colorMode*: ColorMode
    mouse*: bool
    lineWrap*: bool
    timeoutlen*: int ## Key mapping timeout in ms (0 = no timeout)

  # Clipboard settings
  ClipboardConfig* = object
    enable*: bool
    tool*: ClipboardTool

  # Build on save settings
  BuildOnSaveConfig* = object
    enable*: bool
    workspaceRoot*: Option[string]
    command*: Option[string]

  # Tab line settings
  TabLineConfig* = object
    enable*: bool

  # Status line settings
  StatusLineConfig* = object
    multipleStatusLine*: bool
    merge*: bool
    mode*: bool
    filename*: bool
    changedMark*: bool
    directory*: bool
    gitChangedLines*: bool
    gitBranchName*: bool
    showGitInactive*: bool
    showModeInactive*: bool
    setupText*: string

  # Highlight settings
  HighlightConfig* = object
    currentLine*: bool
    reservedWord*: seq[string]
    replaceText*: bool
    pairOfParen*: bool
    fullWidthSpace*: bool
    trailingSpaces*: bool
    currentWord*: bool
    currentColumn*: bool

  # Auto backup settings
  AutoBackupConfig* = object
    enable*: bool
    backupDir*: Option[string]
    idleTime*: int
    interval*: int
    dirToExclude*: seq[string]

  # Quick run settings
  QuickRunConfig* = object
    saveBufferWhenQuickRun*: bool
    command*: Option[string]
    timeout*: int
    nimAdvancedCommand*: Option[string]
    clangOptions*: Option[string]
    cppOptions*: Option[string]
    nimOptions*: Option[string]
    shOptions*: Option[string]
    bashOptions*: Option[string]

  # Notification settings
  NotificationConfig* = object
    screenNotifications*: bool
    logNotifications*: bool
    autoBackupScreenNotify*: bool
    autoBackupLogNotify*: bool
    autoSaveScreenNotify*: bool
    autoSaveLogNotify*: bool
    yankScreenNotify*: bool
    yankLogNotify*: bool
    deleteScreenNotify*: bool
    deleteLogNotify*: bool
    saveScreenNotify*: bool
    saveLogNotify*: bool
    quickRunScreenNotify*: bool
    quickRunLogNotify*: bool
    buildOnSaveScreenNotify*: bool
    buildOnSaveLogNotify*: bool
    filerScreenNotify*: bool
    filerLogNotify*: bool
    restoreScreenNotify*: bool
    restoreLogNotify*: bool
    lspScreenNotify*: bool
    lspLogNotify*: bool

  # Filer settings
  FilerConfig* = object
    showIcons*: bool

  # Autocomplete settings
  AutocompleteConfig* = object
    enable*: bool
    windowBorder*: bool

  # Auto save settings
  AutoSaveConfig* = object
    enable*: bool
    interval*: int

  # Persist settings
  PersistConfig* = object
    exCommand*: bool
    exCommandHistoryLimit*: int
    search*: bool
    searchHistoryLimit*: int
    cursorPosition*: bool

  # Git settings
  GitConfig* = object
    showChangedLine*: bool
    updateInterval*: int

  # Syntax checker settings
  SyntaxCheckerConfig* = object
    enable*: bool

  # Smooth scroll settings (physics-based, compatible with vim comfortable-motion)
  SmoothScrollConfig* = object
    enable*: bool
    friction*: float # Friction coefficient (velocity decay rate). Default: 80.0
    airDrag*: float # Air drag coefficient (velocity resistance). Default: 2.0

  # Startup file open settings
  StartUpFileOpenConfig* = object
    autoSplit*: bool
    splitType*: SplitType

  # Debug window node settings
  DebugWindowNodeConfig* = object
    enable*: bool
    currentWindow*: bool
    index*: bool
    windowIndex*: bool
    bufferIndex*: bool
    parentIndex*: bool
    childLen*: bool
    splitType*: bool
    haveCursesWin*: bool
    y*: bool
    x*: bool
    h*: bool
    w*: bool
    currentLine*: bool
    currentColumn*: bool
    expandedColumn*: bool
    cursor*: bool

  # Debug editor view settings
  DebugEditorViewConfig* = object
    enable*: bool
    widthOfLineNum*: bool
    height*: bool
    width*: bool
    originalLine*: bool
    start*: bool
    length*: bool

  # Debug buffer status settings
  DebugBufferStatusConfig* = object
    enable*: bool
    bufferIndex*: bool
    path*: bool
    openDir*: bool
    currentMode*: bool
    prevMode*: bool
    language*: bool
    encoding*: bool
    countChange*: bool
    cmdLoop*: bool
    lastSaveTime*: bool
    bufferLen*: bool

  # Debug search settings
  DebugSearchConfig* = object
    enable*: bool

  # Debug macro settings
  DebugMacroConfig* = object
    enable*: bool

  # Debug visual selection settings
  DebugVisualConfig* = object
    enable*: bool

  # Debug jump list settings
  DebugJumpListConfig* = object
    enable*: bool

  # Debug LSP settings
  DebugLspConfig* = object
    enable*: bool

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
    diagnostics*: LspFeatureConfig
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
    autocomplete*: AutocompleteConfig
    autoSave*: AutoSaveConfig
    persist*: PersistConfig
    git*: GitConfig
    syntaxChecker*: SyntaxCheckerConfig
    smoothScroll*: SmoothScrollConfig
    startUpFileOpen*: StartUpFileOpenConfig
    debug*: DebugConfig
    theme*: ThemeConfig
    lsp*: LspConfig
    keyMapping*: KeyMappingConfig

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
      statusLine: true,
      syntax: true,
      indentationLines: true,
      tabStop: 2,
      expandTab: false, # Match example/moerc.toml default
      sidebar: true,
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
      colorMode: cm24bit,
      mouse: false,
      lineWrap: true,
      timeoutlen: 1000,
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
        "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}",
    ),
    highlight: HighlightConfig(
      currentLine: true,
      reservedWord: @["TODO", "WIP", "NOTE"],
      replaceText: true,
      pairOfParen: true,
      fullWidthSpace: true,
      trailingSpaces: true,
      currentWord: true,
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
    ),
    filer: FilerConfig(showIcons: true),
    autocomplete: AutocompleteConfig(enable: true, windowBorder: true),
    autoSave: AutoSaveConfig(enable: true, interval: 5),
    persist: PersistConfig(
      exCommand: true,
      exCommandHistoryLimit: 1000,
      search: true,
      searchHistoryLimit: 1000,
      cursorPosition: true,
    ),
    git: GitConfig(showChangedLine: true, updateInterval: 1000),
    syntaxChecker: SyntaxCheckerConfig(enable: false),
    smoothScroll: SmoothScrollConfig(enable: true, friction: 80.0, airDrag: 2.0),
    startUpFileOpen: StartUpFileOpenConfig(autoSplit: true, splitType: stVertical),
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
      diagnostics: LspFeatureConfig(enable: true),
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
  )
