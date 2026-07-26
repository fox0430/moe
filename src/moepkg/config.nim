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
## Runtime helpers over the config types defined in `types/config_types.nim`
## (tool detection + `newEditorConfig` factory). Type definitions and the
## `config_macros` re-export live in `types/config_types.nim`.

import std/[options, tables, os, osproc]

import types/config_types
export config_types

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
      enable: false, workspaceRoot: none(string), command: none(string), timeout: 300
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
    syntaxChecker: SyntaxCheckerConfig(enable: false, timeout: 60),
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
    disabledCommandAliases: @[],
  )
