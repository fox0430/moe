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

import modes

import config_macros
export config_macros

const DefaultBackupDir* = "~/.cache/moe/backups"
  ## Effective default for `AutoBackupConfig.backupDir` when the field is
  ## `none`. Lives here (not in `backup.nim`) so it can be referenced by
  ## `cfgDocDefault` on the field without introducing a config → backup
  ## cycle.

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

  BufferBackendKind* = enum
    bbcAuto = "auto"
    bbcGapBuffer = "gapBuffer"
    bbcSqrtDecomp = "sqrtDecomp"
    bbcRope = "rope"
    bbcPieceTable = "pieceTable"

  BracketSplitMode* = enum
    bsmDisable = "disable" ## Existing behavior: no special handling on Enter
    bsmNoIndent = "noIndent" ## Split pair onto 3 lines without indenting
    bsmIndent = "indent" ## Split pair and indent the middle line one step deeper

  # Standard settings
  StandardConfig* {.cfgSection: "Standard".} = object
    number* {.cfg, cfgDocDescription: "Display line numbers".}: bool
    relativeNumber* {.cfg, cfgDocDescription: "Display relative line numbers".}: bool
    statusLine* {.cfg, cfgDocDescription: "Display status lines".}: bool
    syntax* {.cfg, cfgDocDescription: "Enable syntax highlighting".}: bool
    indentationLines* {.cfg, cfgDocDescription: "Enable indentation lines".}: bool
    tabStop* {.cfg, cfgMin: 1, cfgMax: 16, cfgDocDescription: "Tab width".}: int
    shiftWidth* {.
      cfg, cfgMin: 0, cfgMax: 16, cfgDocDescription: "Indent width (0 = use tabStop)"
    .}: int ## Indent width, 0 = use tabStop (Vim compatible)
    softTabStop* {.
      cfg,
      cfgMin: 0,
      cfgMax: 16,
      cfgDocDescription: "Tab/Backspace width in insert mode (0 = use tabStop)"
    .}: int ## Tab/Backspace width in insert mode, 0 = use tabStop (Vim compatible)
    expandTab* {.cfg, cfgDocDescription: "Expand tabs to spaces".}: bool
    sidebar* {.cfg, cfgDocDescription: "Enable Sidebars for editor views".}: bool
    scrollbar* {.
      cfg, cfgDocDescription: "Enable scrollbar on the right edge of windows"
    .}: bool
    scrollbarWidth* {.
      cfg,
      cfgMin: 0,
      cfgMax: 5,
      cfgDocDescription: "Scrollbar width in characters (0 = hidden)"
    .}: int
    bookmarkMarker* {.cfg, cfgDocDescription: "Bookmark indicator symbol in sidebars".}:
      string
    showModifiedLines* {.
      cfg, cfgDocDescription: "Show modified/inserted line indicators in sidebars"
    .}: bool
    autoCloseParen* {.cfg, cfgDocDescription: "Automatic closing brackets".}: bool
    autoIndent* {.cfg, cfgDocDescription: "Automatic indentation".}: bool
    smartIndent* {.
      cfg,
      cfgDocDescription:
        "Language-aware extra indent on Enter " &
        "(Nim: var/let/const/type, trailing or/and/object/tuple/enum, " &
        "trailing `:` or `=`, unclosed brackets)"
    .}: bool
    ignorecase* {.cfg, cfgDocDescription: "Enable ignorecase when searching".}: bool
    smartcase* {.cfg, cfgDocDescription: "Enable smartcase when searching".}: bool
    disableChangeCursor* {.
      cfg, cfgDocDescription: "Disable change of the cursor shape"
    .}: bool
    defaultCursor* {.
      cfg, cfgDocDescription: "The cursor shape of the terminal emulator you are using"
    .}: CursorType
    normalModeCursor* {.cfg, cfgDocDescription: "The cursor shape in Normal mode".}:
      CursorType
    insertModeCursor* {.cfg, cfgDocDescription: "The cursor shape in insert mode".}:
      CursorType
    liveReloadOfConf* {.
      cfg, cfgDocDescription: "Enable live reload of the configuration file"
    .}: bool
    incrementalSearch* {.cfg, cfgDocDescription: "Enable incremental search".}: bool
    popupWindowInExmode* {.
      cfg, cfgDocDescription: "Show Pop-up window in Command mode"
    .}: bool
    autoDeleteParen* {.cfg, cfgDocDescription: "Automatic delete brackets".}: bool
    liveReloadOfFile* {.cfg, cfgDocDescription: "Enable live reload of opening files".}:
      bool
    colorMode* {.cfg, cfgDocDescription: "Terminal color mode".}: ColorMode
    mouse* {.cfg, cfgDocDescription: "Enable mouse cursor movement".}: bool
    lineWrap* {.cfg, cfgDocDescription: "Enable line wrapping".}: bool
    timeoutlen* {.
      cfg,
      cfgMin: 0,
      cfgMax: 10000,
      cfgDocDescription: "Key mapping timeout in milliseconds (0 = no timeout)"
    .}: int ## Key mapping timeout in ms (0 = no timeout)
    bracketSplit* {.
      cfg,
      cfgDocDescription:
        "Behavior when pressing Enter between matching bracket pairs " &
        "(disable/noIndent/indent)"
    .}: BracketSplitMode

  # Buffer backend settings
  BufferBackendConfig* {.cfgSection: "BufferBackend".} = object
    kind* {.
      cfg,
      cfgDocDescription:
        "Buffer data structure. \"auto\" selects backend based on file size"
    .}: BufferBackendKind

  # Clipboard settings
  ClipboardConfig* {.cfgSection: "Clipboard".} = object
    enable* {.cfg, cfgDocDescription: "Enable system clipboard".}: bool
    tool* {.
      cfg, cfgDocDefault: cbtXsel, cfgDocDescription: "The clipboard tool for Linux"
    .}: ClipboardTool
      ## Runtime default is system-dependent (detectClipboardTool()); the doc
      ## fixes it to "xsel" via cfgDocDefault for stability across environments.

  # Build on save settings
  BuildOnSaveConfig* {.cfgSection: "BuildOnSave".} = object
    enable* {.cfg, cfgDocDescription: "Enable build on save".}: bool
    workspaceRoot* {.
      cfg, cfgDirPath, cfgNoUi, cfgDocDescription: "Project root directory"
    .}: Option[string]
    command* {.cfg, cfgNoUi, cfgDocDescription: "Override commands executed at build".}:
      Option[string]

  # Tab line settings
  TabLineConfig* {.cfgSection: "TabLine".} = object
    enable* {.cfg, cfgDocDescription: "Enable tab line".}: bool

  # Status line settings
  StatusLineConfig* {.cfgSection: "StatusLine".} = object
    multipleStatusLine* {.cfg, cfgDocDescription: "Show multiple status lines".}: bool
    merge* {.
      cfg, cfgDocDescription: "Enable merge the status line with the command line"
    .}: bool
    mode* {.cfg, cfgDocDescription: "Display the current mode".}: bool
    filename* {.cfg, cfgDocDescription: "Display the filename".}: bool
    changedMark* {.cfg, cfgDocDescription: "Display the buffer changed mark".}: bool
    directory* {.cfg, cfgDocDescription: "Display the directory of the path".}: bool
    gitChangedLines* {.cfg, cfgDocDescription: "Display number of changed lines".}: bool
    gitBranchName* {.cfg, cfgDocDescription: "Display the current git branch name".}:
      bool
    showGitInactive* {.
      cfg,
      cfgDocDescription:
        "Display the git branch name on the status line in inactive windows"
    .}: bool
    showModeInactive* {.
      cfg, cfgDocDescription: "Display the mode on the status line in inactive windows"
    .}: bool
    setupText* {.
      cfg,
      cfgNoUi,
      cfgDocDescription:
        "Text to customize the items displayed in the status line. Please check StatusLineItem"
    .}: string

  # Highlight settings
  HighlightConfig* {.cfgSection: "Highlight".} = object
    currentLine* {.cfg, cfgDocDescription: "Highlight the current line background".}:
      bool
    currentColumn* {.cfg, cfgDocDescription: "Highlight the current column background".}:
      bool
    reservedWord* {.cfg, cfgNoUi, cfgDocDescription: "Highlight any words".}:
      seq[string]
    replaceText* {.cfg, cfgDocDescription: "Highlight replacement text".}: bool
    pairOfParen* {.cfg, cfgDocDescription: "Highlight a pair of brackets".}: bool
    fullWidthSpace* {.cfg, cfgDocDescription: "Highlight full-width spaces".}: bool
    trailingSpaces* {.cfg, cfgDocDescription: "Highlight trailing spaces".}: bool
    currentWord* {.
      cfg,
      cfgDocDescription: "Highlight other uses of the current word under the cursor"
    .}: bool
    findCharHighlight* {.cfg, cfgDocDescription: "Highlight f/F/t/T matches".}: bool
    colorCodeHighlight* {.
      cfg,
      cfgDocDescription:
        "Highlight inline color codes (#RRGGBB, #RGB) with their actual color"
    .}: bool
    gitConflict* {.
      cfg,
      cfgDocDescription:
        "Highlight git merge conflict blocks (`<<<<<<<` / `=======` / `>>>>>>>`)"
    .}: bool
    gitConflictTwoColor* {.
      cfg,
      cfgDocDescription:
        "Use GitHub-style two-color scheme (ours / theirs distinct); false for single red background"
    .}: bool
    maxHighlightLineLength* {.
      cfg,
      cfgMin: 0,
      cfgDocDescription:
        "Stop syntax highlighting a line past this many characters (0 = unlimited). Bounds frame time on very long lines such as minified code"
    .}: int

  # Auto backup settings
  AutoBackupConfig* {.cfgSection: "AutoBackup".} = object
    enable* {.cfg, cfgDocDescription: "Enable automatic backups".}: bool
    backupDir* {.
      cfg,
      cfgDirPath,
      cfgNoUi,
      cfgDocDescription: "Directory to save backup files",
      cfgDocDefault: some(DefaultBackupDir)
    .}: Option[string]
    idleTime* {.
      cfg,
      cfgMin: 1,
      cfgMax: 3600,
      cfgDocDescription: "Start backup when there is no operation times (seconds)"
    .}: int
    interval* {.
      cfg, cfgMin: 1, cfgMax: 3600, cfgDocDescription: "Backup interval (minutes)"
    .}: int
    dirToExclude* {.
      cfg,
      cfgNoUi,
      cfgDocDescription:
        "Exclude dirs for where you don't want to produce automatic backups"
    .}: seq[string]

  # Quick run settings
  QuickRunConfig* {.cfgSection: "QuickRun".} = object
    saveBufferWhenQuickRun* {.cfg, cfgDocDescription: "Save buffer when run QuickRun".}:
      bool
    command* {.cfg, cfgNoUi, cfgDocDescription: "Commands to be executed by quick run".}:
      Option[string]
    timeout* {.cfg, cfgMin: 1, cfgDocDescription: "Command timeout (seconds)".}: int
    nimAdvancedCommand* {.
      cfg, cfgNoUi, cfgDocDescription: "Nim compiler advanced args"
    .}: Option[string]
    clangOptions* {.
      cfg,
      cfgKey: "ClangOptions",
      cfgNoUi,
      cfgDocDescription: "C lang compiler options. The default compiler is gcc"
    .}: Option[string]
    cppOptions* {.
      cfg,
      cfgKey: "CppOptions",
      cfgNoUi,
      cfgDocDescription: "C++ compiler options. The default compiler is gcc"
    .}: Option[string]
    nimOptions* {.
      cfg, cfgKey: "NimOptions", cfgNoUi, cfgDocDescription: "Nim compiler options"
    .}: Option[string]
    shOptions* {.cfg, cfgNoUi, cfgDocDescription: "sh options".}: Option[string]
    bashOptions* {.cfg, cfgNoUi, cfgDocDescription: "bash options".}: Option[string]

  # Notification settings
  NotificationConfig* {.cfgSection: "Notification".} = object
    screenNotifications* {.
      cfg, cfgDocDescription: "Show all messages/notifications in the command line"
    .}: bool
    logNotifications* {.
      cfg, cfgDocDescription: "Record all messages/notifications to the log"
    .}: bool
    autoBackupScreenNotify* {.
      cfg, cfgDocDescription: "Auto backups messages/notifications in the command line"
    .}: bool
    autoBackupLogNotify* {.
      cfg, cfgDocDescription: "Auto backups messages/notifications to the log"
    .}: bool
    autoSaveScreenNotify* {.
      cfg, cfgDocDescription: "Auto save messages/notifications in the command line"
    .}: bool
    autoSaveLogNotify* {.
      cfg, cfgDocDescription: "Auto save messages/notifications to the log"
    .}: bool
    yankScreenNotify* {.
      cfg, cfgDocDescription: "Yank messages/notifications in the command line"
    .}: bool
    yankLogNotify* {.cfg, cfgDocDescription: "Yank messages/notifications to the log".}:
      bool
    deleteScreenNotify* {.
      cfg, cfgDocDescription: "Delete buffer messages/notifications in the command line"
    .}: bool
    deleteLogNotify* {.
      cfg, cfgDocDescription: "Delete buffer messages/notifications to the log"
    .}: bool
    saveScreenNotify* {.
      cfg, cfgDocDescription: "Save messages/notifications in the command line"
    .}: bool
    saveLogNotify* {.cfg, cfgDocDescription: "Save messages/notifications to the log".}:
      bool
    quickRunScreenNotify* {.
      cfg, cfgDocDescription: "QuickRun messages/notifications in the command line"
    .}: bool
    quickRunLogNotify* {.
      cfg, cfgDocDescription: "QuickRun messages/notifications to the log"
    .}: bool
    buildOnSaveScreenNotify* {.
      cfg, cfgDocDescription: "Build on save messages/notifications in the command line"
    .}: bool
    buildOnSaveLogNotify* {.
      cfg, cfgDocDescription: "Build on save messages/notifications to the log"
    .}: bool
    filerScreenNotify* {.
      cfg, cfgDocDescription: "Filer messages/notifications in the command line"
    .}: bool
    filerLogNotify* {.
      cfg, cfgDocDescription: "Filer messages/notifications to the log"
    .}: bool
    restoreScreenNotify* {.
      cfg, cfgDocDescription: "Restore messages/notifications in the command line"
    .}: bool
    restoreLogNotify* {.
      cfg, cfgDocDescription: "Restore messages/notifications to the log"
    .}: bool
    lspScreenNotify* {.
      cfg, cfgDocDescription: "Lsp messages/notifications in the command line"
    .}: bool
    lspLogNotify* {.cfg, cfgDocDescription: "Lsp messages/notifications to the log".}:
      bool
    lspForcePopup* {.
      cfg,
      cfgDocDescription:
        "Force all LSP messages (including logs) to popup notifications"
    .}: bool
    popupNotifications* {.
      cfg,
      cfgDocDescription:
        "Show notifications as floating popups instead of the command line"
    .}: bool
    popupPosition* {.
      cfg,
      cfgEnumStrings: ["bottomRight", "topRight", "topLeft", "bottomLeft"],
      cfgDocDescription:
        "Popup position: \"topRight\", \"topLeft\", \"bottomRight\", \"bottomLeft\""
    .}: string
    popupTimeoutMs* {.
      cfg,
      cfgMin: 100,
      cfgDocDescription: "Auto-dismiss timeout in milliseconds (minimum: 100)"
    .}: int
    popupMaxVisible* {.
      cfg,
      cfgMin: 1,
      cfgDocDescription:
        "Maximum number of simultaneous popup notifications (minimum: 1)"
    .}: int
    popupMaxWidth* {.
      cfg,
      cfgMin: 10,
      cfgDocDescription: "Maximum popup width in characters (minimum: 10)"
    .}: int
    popupBorder* {.cfg, cfgDocDescription: "Show border around popup notifications".}:
      bool

  # Filer settings
  FilerConfig* {.cfgSection: "Filer".} = object
    showIcons* {.cfg, cfgDocDescription: "Show/Hidden file type icons".}: bool

  # FileTree settings
  FileTreeConfig* {.cfgSection: "FileTree".} = object
    width* {.
      cfg, cfgMin: 1, cfgDocDescription: "Width of the FileTree sidebar in columns"
    .}: int

  # Autocomplete settings
  AutocompleteConfig* {.cfgSection: "Autocomplete".} = object
    enable* {.cfg, cfgDocDescription: "Enable/Disable General-purpose autocompletion".}:
      bool
    windowBorder* {.cfg, cfgDocDescription: "Show borderline on completion window".}:
      bool

  # Auto save settings
  AutoSaveConfig* {.cfgSection: "AutoSave".} = object
    enable* {.cfg, cfgDocDescription: "Auto save".}: bool
    interval* {.
      cfg, cfgMin: 1, cfgMax: 3600, cfgDocDescription: "Auto save interval (minutes)"
    .}: int

  # Persist settings
  PersistConfig* {.cfgSection: "Persist".} = object
    commandHistory* {.cfg, cfgDocDescription: "Saving Command mode command history".}:
      bool
    commandHistoryLimit* {.
      cfg,
      cfgMin: 1,
      cfgDocDescription: "The maximum entries of Command mode command history to save"
    .}: int
    search* {.cfg, cfgDocDescription: "Saving search history".}: bool
    searchHistoryLimit* {.
      cfg, cfgMin: 1, cfgDocDescription: "The maximum entries of search history to save"
    .}: int
    cursorPosition* {.cfg, cfgDocDescription: "Saving last cursor position".}: bool
    bookmarks* {.cfg, cfgDocDescription: "Saving bookmarks".}: bool

  # Git settings
  GitConfig* {.cfgSection: "Git".} = object
    showChangedLine* {.cfg, cfgDocDescription: "Line changes on sidebars".}: bool
    updateInterval* {.
      cfg,
      cfgMin: 100,
      cfgMax: 60000,
      cfgDocDescription: "Interval for updating Git information. (Milli seconds)"
    .}: int

  # Syntax checker settings
  SyntaxCheckerConfig* {.cfgSection: "SyntaxChecker".} = object
    enable* {.cfg, cfgDocDescription: "Syntax checker".}: bool

  # Smooth scroll settings (physics-based, compatible with vim comfortable-motion)
  SmoothScrollConfig* {.cfgSection: "SmoothScroll".} = object
    enable* {.cfg, cfgDocDescription: "Enable smooth scrolling".}: bool
    friction* {.
      cfg,
      cfgMin: 0.0,
      cfgMax: 500.0,
      cfgStep: 10.0,
      cfgDocDescription: "Friction coefficient (velocity decay rate)"
    .}: float
    airDrag* {.
      cfg,
      cfgMin: 0.0,
      cfgMax: 20.0,
      cfgStep: 0.5,
      cfgDocDescription: "Air drag coefficient (velocity resistance)"
    .}: float

  # EditorConfig settings
  EditorConfigSettings* {.cfgSection: "EditorConfig".} = object
    enable* {.
      cfg, cfgDocDescription: "[EditorConfig](https://editorconfig.org) support"
    .}: bool

  # Startup file open settings
  StartUpFileOpenConfig* {.cfgSection: "StartUp.FileOpen".} = object
    autoSplit* {.
      cfg,
      cfgDocDescription:
        "Display all buffers in multiple views if multiple paths are received when starting the editor"
    .}: bool
    splitType* {.
      cfg, cfgDocDescription: "The split type for `StartUp.FileOpen.autoSplit`"
    .}: SplitType

  # Startup file tree settings
  StartUpFileTreeConfig* {.cfgSection: "StartUp.FileTree".} = object
    enable* {.
      cfg, cfgDocDescription: "Open the fileTree sidebar automatically on startup"
    .}: bool

  # Debug window node settings
  DebugWindowNodeConfig* {.cfgSection: "Debug.WindowNode".} = object
    enable* {.cfg, cfgDocDescription: "All WindowNode info".}: bool
    currentWindow* {.cfg, cfgDocDescription: "Whether the current window or not".}: bool
    index* {.cfg, cfgDocDescription: "WindowNode.index".}: bool
    windowIndex* {.cfg, cfgDocDescription: "WindowNode.windowIndex".}: bool
    bufferIndex* {.cfg, cfgDocDescription: "WindowNode.bufferIndex".}: bool
    parentIndex* {.cfg, cfgDocDescription: "Parent node's WindowNode.index".}: bool
    childLen* {.cfg, cfgDocDescription: "WindowNode.child.len".}: bool
    splitType* {.cfg, cfgDocDescription: "WindowNode.splitType".}: bool
    haveCursesWin* {.
      cfg, cfgDocDescription: "Whether windowNode have cursesWindow or not"
    .}: bool
    y* {.cfg, cfgDocDescription: "WindowNode.y".}: bool
    x* {.cfg, cfgDocDescription: "WindowNode.x".}: bool
    h* {.cfg, cfgDocDescription: "WindowNode.h".}: bool
    w* {.cfg, cfgDocDescription: "WindowNode.w".}: bool
    currentLine* {.cfg, cfgDocDescription: "WindowNode.currentLine".}: bool
    currentColumn* {.cfg, cfgDocDescription: "WindowNode.currentColumn".}: bool
    expandedColumn* {.cfg, cfgDocDescription: "WindowNode.expandedColumn".}: bool
    cursor* {.cfg, cfgDocDescription: "WindowNode.cursor".}: bool

  # Debug editor view settings
  DebugEditorViewConfig* {.cfgSection: "Debug.EditorView".} = object
    enable* {.cfg, cfgDocDescription: "All Editorview info".}: bool
    widthOfLineNum* {.cfg, cfgDocDescription: "Editorview.widthOfLineNum".}: bool
    height* {.cfg, cfgDocDescription: "Editorview.height".}: bool
    width* {.cfg, cfgDocDescription: "Editorview.width".}: bool
    originalLine* {.cfg, cfgDocDescription: "Editorview.originalLine".}: bool
    start* {.cfg, cfgDocDescription: "Editorview.start".}: bool
    length* {.cfg, cfgDocDescription: "Editorview.length".}: bool

  # Debug buffer status settings
  DebugBufferStatusConfig* {.cfgSection: "Debug.BufferStatus".} = object
    enable* {.cfg, cfgDocDescription: "All BufStatus info".}: bool
    bufferIndex* {.cfg, cfgDocDescription: "The index of BufStatus".}: bool
    path* {.cfg, cfgDocDescription: "BufStatus.path".}: bool
    openDir* {.cfg, cfgDocDescription: "BufStatus.openDir".}: bool
    currentMode* {.cfg, cfgDocDescription: "BufStatus.mode".}: bool
    prevMode* {.cfg, cfgDocDescription: "BufStatus.prevMode".}: bool
    language* {.cfg, cfgDocDescription: "BufStatus.language".}: bool
    encoding* {.cfg, cfgDocDescription: "BufStatus.characterEncoding".}: bool
    countChange* {.cfg, cfgDocDescription: "BufStatus.countChange".}: bool
    cmdLoop* {.cfg, cfgDocDescription: "BufStatus.cmdLoop".}: bool
    lastSaveTime* {.cfg, cfgDocDescription: "BufStatus.lastSaveTime".}: bool
    bufferLen* {.cfg, cfgDocDescription: "BufStatus.buffer.len".}: bool

  # Debug search settings
  DebugSearchConfig* {.cfgSection: "Debug.Search".} = object
    enable* {.cfg, cfgDocDescription: "Search debug info".}: bool

  # Debug macro settings
  DebugMacroConfig* {.cfgSection: "Debug.MacroState".} = object
    enable* {.cfg, cfgDocDescription: "Macro state debug info".}: bool

  # Debug visual selection settings
  DebugVisualConfig* {.cfgSection: "Debug.Visual".} = object
    enable* {.cfg, cfgDocDescription: "Visual selection debug info".}: bool

  # Debug jump list settings
  DebugJumpListConfig* {.cfgSection: "Debug.JumpList".} = object
    enable* {.cfg, cfgDocDescription: "Jump list debug info".}: bool

  # Debug LSP settings
  DebugLspConfig* {.cfgSection: "Debug.Lsp".} = object
    enable* {.cfg, cfgDocDescription: "LSP debug info".}: bool

  # Log settings
  LogConfig* {.cfgSection: "Log".} = object
    clearOnStart* {.
      cfg, cfgDocDescription: "Clear existing log file when starting with debug mode"
    .}: bool

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
  KeyMappingEntry* = object
    ## A single [KeyMapping] right-hand side. A bare TOML string maps to
    ## `KeyMappingEntry(rhs: s, noremap: true)`; an inline table can additionally
    ## carry args, force a key sequence, and toggle noremap.
    rhs*: string ## Command name, key sequence, or "mode_switch <mode>" etc.
    args*: seq[string] ## Explicit args (may contain spaces); empty resolves rhs as-is.
    forceKeySeq*: bool ## true skips command-name resolution (verbatim key sequence).
    noremap*: bool ## true replays verbatim (Vim :noremap); false expands recursively.

  KeyMappingConfig* = object
    ## `perMode` is indexed by EditorMode; `all`/`visualAll` are meta sections
    ## expanded at apply time (all modes but Command / the three visual modes).
    perMode*: array[EditorMode, OrderedTable[string, KeyMappingEntry]]
    all*: OrderedTable[string, KeyMappingEntry]
    visualAll*: OrderedTable[string, KeyMappingEntry]

  # Main configuration
  EditorConfig* = ref object
    standard*: StandardConfig
    bufferBackend*: BufferBackendConfig
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
      smartIndent: false,
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
      bracketSplit: bsmDisable,
    ),
    bufferBackend: BufferBackendConfig(kind: bbcAuto),
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
      # Keep in sync with highlight.DefaultMaxHighlightLineLength. Not referenced
      # directly: config.nim must not import the highlight engine (keeps its
      # dependency closure small).
      maxHighlightLineLength: 3000,
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
      timeout: 30000,
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
    keyMapping: KeyMappingConfig(),
    shellCommands: initTable[string, UserCommandEntry](),
    commandAliases: initTable[string, UserCommandEntry](),
  )
