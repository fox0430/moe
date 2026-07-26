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

## Lightweight configuration type definitions.
##
## Split out from `config` so modules that only need the config types
## (notably `types/editor_types` for the `Editor.config` field) do not
## transitively pull in `std/os` / `std/osproc` and the `newEditorConfig`
## defaults builder. The tool-detection and defaults procs stay in `config`.

import std/[options, tables]

import ../modes

import ../config_macros
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
    timeout* {.
      cfg, cfgMin: 0, cfgDocDescription: "Build timeout (seconds, 0 = no timeout)"
    .}: int

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
    timeout* {.
      cfg, cfgMin: 0, cfgDocDescription: "Command timeout (seconds, 0 = no timeout)"
    .}: int
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
    timeout* {.
      cfg,
      cfgMin: 0,
      cfgDocDescription: "Syntax check timeout (seconds, 0 = no timeout)"
    .}: int

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
    enable* {.cfg, cfgDocDescription: "Enable {}".}: bool

  # LSP diagnostics config
  LspDiagnosticsConfig* = object
    enable* {.cfg, cfgDocDescription: "Enable {}".}: bool
    autoHover* {.
      cfg,
      cfgDocDescription:
        "Automatically show diagnostic messages in hover popup when cursor is on a diagnostic"
    .}: bool
    autoHoverDelay* {.
      cfg,
      cfgMin: 0,
      cfgDocDescription: "Delay in milliseconds before auto hover shows (0 = no delay)"
    .}: int

  # LSP feature with openWindow option
  LspOpenWindowConfig* = object
    enable* {.cfg, cfgDocDescription: "Enable {}".}: bool
    openWindow* {.cfg, cfgDocDescription: "Open a new window and jump".}: bool

  # LSP language server config
  LspServerConfig* = object
    extensions*: seq[string]
    command*: string
    trace*: LspTraceLevel
    settings*: string
      ## Serialized JSON for workspace/didChangeConfiguration and
      ## workspace/configuration responses ("" = none).
    # Rust-analyzer specific options
    rustAnalyzerRunSingle*: bool
    rustAnalyzerDebugSingle*: bool

  # LSP settings. A section group: loader, known-key list, serializer, UI and
  # docs are all derived from this declaration; `servers` absorbs the dynamic
  # [Lsp.<languageId>] space and is the only hand-written part.
  LspConfig* {.cfgGroup: "Lsp".} = object
    enable* {.cfg, cfgDocDescription: "LSP (Language Server Protocol) Client".}: bool
    timeout* {.
      cfg, cfgMin: 1, cfgDocDescription: "Timeout in milliseconds for LSP requests"
    .}: int
      ## Deliberately unbounded above: only correctness matters, so a
      ## non-positive value is rejected and a long wait is the user's call.
    # Feature configs
    completion* {.cfgSubSection: "Completion", cfgDocDescription: "LSP Completion".}:
      LspFeatureConfig
    declaration* {.
      cfgSubSection: "Declaration", cfgDocDescription: "LSP Goto Declaration"
    .}: LspOpenWindowConfig
    definition* {.
      cfgSubSection: "Definition", cfgDocDescription: "LSP Goto Definition"
    .}: LspOpenWindowConfig
    typeDefinition* {.
      cfgSubSection: "TypeDefinition", cfgDocDescription: "LSP Type Definition"
    .}: LspOpenWindowConfig
    implementation* {.
      cfgSubSection: "Implementation", cfgDocDescription: "LSP Implementation"
    .}: LspOpenWindowConfig
    diagnostics* {.cfgSubSection: "Diagnostics", cfgDocDescription: "LSP Diagnostics".}:
      LspDiagnosticsConfig
    signatureHelp* {.
      cfgSubSection: "SignatureHelp", cfgDocDescription: "LSP Signature Help"
    .}: LspFeatureConfig
    documentFormatting* {.
      cfgSubSection: "DocumentFormatting", cfgDocDescription: "LSP Document Formatting"
    .}: LspFeatureConfig
    foldingRange* {.
      cfgSubSection: "FoldingRange", cfgDocDescription: "LSP Folding Range"
    .}: LspFeatureConfig
    selectionRange* {.
      cfgSubSection: "SelectionRange", cfgDocDescription: "LSP Selection Range"
    .}: LspFeatureConfig
    documentSymbol* {.
      cfgSubSection: "DocumentSymbol", cfgDocDescription: "LSP Document Symbol"
    .}: LspFeatureConfig
    hover* {.cfgSubSection: "Hover", cfgDocDescription: "LSP Hover".}: LspFeatureConfig
    inlayHint* {.cfgSubSection: "InlayHint", cfgDocDescription: "LSP Inlay Hint".}:
      LspFeatureConfig
    references* {.
      cfgSubSection: "References", cfgDocDescription: "LSP Find References"
    .}: LspFeatureConfig
    callHierarchy* {.
      cfgSubSection: "CallHierarchy", cfgDocDescription: "LSP Call Hierarchy"
    .}: LspFeatureConfig
    documentHighlight* {.
      cfgSubSection: "DocumentHighlight", cfgDocDescription: "LSP Document Highlight"
    .}: LspFeatureConfig
    documentLink* {.
      cfgSubSection: "DocumentLink", cfgDocDescription: "LSP Document Link"
    .}: LspFeatureConfig
    codeLens* {.cfgSubSection: "CodeLens", cfgDocDescription: "LSP Code Lens".}:
      LspFeatureConfig
    rename* {.cfgSubSection: "Rename", cfgDocDescription: "LSP Rename".}:
      LspFeatureConfig
    semanticTokens* {.
      cfgSubSection: "SemanticTokens", cfgDocDescription: "LSP Semantic Tokens"
    .}: LspFeatureConfig
    executeCommand* {.
      cfgSubSection: "ExecuteCommand", cfgDocDescription: "LSP Execute Command"
    .}: LspFeatureConfig
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
    disabledCommandAliases*: seq[string] ## Built-in command aliases disabled by the user
