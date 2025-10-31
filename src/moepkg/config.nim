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

## Configuration system for moe editor
##
## This module defines all configuration structures and provides functionality
## for loading settings from TOML files.

import std/options

type
  ColorMode* = enum
    cm8bit = "8bit"
    cm24bit = "24bit"
    cmNone = "none"

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
    ctXsel = "xsel"
    ctXclip = "xclip"
    ctWlClipboard = "wl-clipboard"
    ctWin32yank = "win32yank"
    ctPbcopy = "pbcopy"

  SplitType* = enum
    stHorizontal = "horizontal"
    stVertical = "vertical"

  # Standard settings
  StandardConfig* = object
    number*: bool
    currentNumber*: bool
    cursorLine*: bool
    statusLine*: bool
    tabLine*: bool
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
    allBuffer*: bool

  # Status line settings
  StatusLineConfig* = object
    multipleStatusLine*: bool
    merge*: bool
    mode*: bool
    filename*: bool
    chanedMark*: bool
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

  # Smooth scroll settings
  SmoothScrollConfig* = object
    enable*: bool
    minDelay*: int
    maxDelay*: int

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

  # Debug settings
  DebugConfig* = object
    windowNode*: DebugWindowNodeConfig
    editorView*: DebugEditorViewConfig
    bufferStatus*: DebugBufferStatusConfig

  # Theme settings
  ThemeConfig* = object
    kind*: ThemeKind
    path*: string

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

proc newEditorConfig*(): EditorConfig =
  ## Create a new configuration with default values
  EditorConfig(
    standard: StandardConfig(
      number: true,
      currentNumber: true,
      cursorLine: false,
      statusLine: true,
      tabLine: true,
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
      liveReloadOfFile: false,
      colorMode: cm24bit,
    ),
    clipboard: ClipboardConfig(enable: true, tool: ctXsel),
    buildOnSave: BuildOnSaveConfig(
      enable: false, workspaceRoot: none(string), command: none(string)
    ),
    tabLine: TabLineConfig(allBuffer: false),
    statusLine: StatusLineConfig(
      multipleStatusLine: true,
      merge: false,
      mode: true,
      filename: true,
      chanedMark: true,
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
    smoothScroll: SmoothScrollConfig(enable: true, minDelay: 5, maxDelay: 20),
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
    ),
    theme: ThemeConfig(kind: tkConfig, path: "~/.config/moe/themes/dark.toml"),
  )
