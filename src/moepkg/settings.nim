#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[os, json, macros, options, strformat, osproc, strutils]
import pkg/[parsetoml, results]
import ui, color, unicodeext, highlight, platform, independentutils, rgb

export TomlError

type
  VsCodeFlavor = enum
    # CodeOss is an Official Arch Linux open-source release.
    # https://archlinux.org/packages/?name=code
    CodeOss
    VSCodium
    VSCode

  ClipboardToolOnLinux* = enum
    none
    xsel
    xclip
    wlClipboard

  DebugWindowNodeSettings* = object
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

  DebugBufferStatusSettings* = object
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

  DebugEditorViewSettings* = object
    enable*: bool
    widthOfLineNum*: bool
    height*: bool
    width*: bool
    originalLine*: bool
    start*: bool
    length*: bool

  DebugModeSettings* = object
    windowNode*: DebugWindowNodeSettings
    editorview*: DebugEditorViewSettings
    bufStatus*: DebugBufferStatusSettings

  NotificationSettings* = object
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

  BuildOnSaveSettings* = object
    enable*: bool
    workspaceRoot*: seq[Rune]
    command*: seq[Rune]

  QuickRunSettings* = object
    saveBufferWhenQuickRun*: bool
    command*: string
    timeout*: int # seconds
    nimAdvancedCommand*: string
    clangOptions*: string
    cppOptions*: string
    nimOptions*: string
    shOptions*: string
    bashOptions*: string

  AutoBackupSettings* = object
    enable*: bool
    idleTime*: int # seconds
    interval*: int # minutes
    backupDir*: seq[Rune]
    dirToExclude*: seq[seq[Rune]]

  FilerSettings* = object
    showIcons*: bool

  StatusLineSettings* = object
    enable*: bool
    merge*: bool
    mode*: bool
    filename*: bool
    chanedMark*: bool
    line*: bool
    column*: bool
    characterEncoding*: bool
    language*: bool
    directory*: bool
    multipleStatusLine*: bool
    gitbranchName*: bool
    showGitInactive*: bool
    showModeInactive*: bool

  TabLineSettings* = object
    enable*: bool
    allBuffer*: bool

  EditorViewSettings* = object
    highlightCurrentLine*: bool
    lineNumber*: bool
    currentLineNumber*: bool
    cursorLine*: bool
    indentationLines*: bool
    tabStop*: int
    sidebar*: bool

  AutocompleteSettings* = object
    enable*: bool

  HighlightSettings* = object
    replaceText*: bool
    pairOfParen*: bool
    currentWord*: bool
    fullWidthSpace*: bool
    trailingSpaces*: bool
    reservedWords*: seq[ReservedWord]

  PersistSettings* = object
    exCommand*: bool
    exCommandHistoryLimit*: int
    search*: bool
    searchHistoryLimit*: int
    cursorPosition*: bool

  ClipboardSettings* = object
    enable*: bool
    toolOnLinux*: ClipboardToolOnLinux

  GitSettings* = object
    showChangedLine*: bool

  SyntaxCheckerSettings* = object
    enable*: bool

  EditorSettings* = object
    editorColorTheme*: ColorTheme
    statusLine*: StatusLineSettings
    tabLine*: TabLineSettings
    view*: EditorViewSettings
    syntax*: bool
    autoCloseParen*: bool
    autoIndent*: bool
    tabStop*: int
    ignorecase*: bool
    smartcase*: bool
    disableChangeCursor*: bool
    defaultCursor*: CursorType
    normalModeCursor*: CursorType
    insertModeCursor*: CursorType
    autoSave*: bool
    autoSaveInterval*: int # minutes
    liveReloadOfConf*: bool
    incrementalSearch*: bool
    popupWindowInExmode*: bool
    autoDeleteParen*: bool
    smoothScroll*: bool
    smoothScrollSpeed*: int
    liveReloadOfFile*: bool
    clipboard*: ClipboardSettings
    buildOnSave*: BuildOnSaveSettings
    filer*: FilerSettings
    autocomplete*: AutocompleteSettings
    autoBackup*: AutoBackupSettings
    quickRun*: QuickRunSettings
    notification*: NotificationSettings
    debugMode*: DebugModeSettings
    highlight*: HighlightSettings
    persist*: PersistSettings
    git*: GitSettings
    syntaxChecker*: SyntaxCheckerSettings

  InvalidItem = object
    name: string
    val: string

  # Warning: inherit from a more precise exception type like ValueError, IOError or OSError.
  # If these don't suit, inherit from CatchableError or Defect. [InheritFromException]
  InvalidItemError* = object of ValueError

proc initDebugModeSettings(): DebugModeSettings =
  result.windowNode = DebugWindowNodeSettings(
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
    cursor: true)

  result.editorview = DebugEditorViewSettings(
    enable: true,
    widthOfLineNum: true,
    height: true,
    width: true)

  result.bufStatus = DebugBufferStatusSettings(
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
    bufferLen: true)

proc initNotificationSettings(): NotificationSettings =
  result.screenNotifications = true
  result.logNotifications = true
  result.autoBackupScreenNotify = true
  result.autoBackupLogNotify = true
  result.autoSaveScreenNotify = true
  result.autoSaveLogNotify = true
  result.yankScreenNotify = true
  result.yankLogNotify = true
  result.deleteScreenNotify = true
  result.deleteLogNotify = true
  result.saveScreenNotify = true
  result.saveLogNotify = true
  result.quickRunScreenNotify = true
  result.quickRunLogNotify = true
  result.buildOnSaveScreenNotify = true
  result.buildOnSaveLogNotify = true
  result.filerScreenNotify = true
  result.filerLogNotify = true
  result.restoreScreenNotify = true
  result.restoreLogNotify = true

proc initQuickRunSettings(): QuickRunSettings =
  result.saveBufferWhenQuickRun = true
  result.nimAdvancedCommand = "c"
  result.timeout = 30

proc initAutoBackupSettings(): AutoBackupSettings =
  result.interval = 5 # 5 minutes
  result.idleTime = 10 # 10 seconds
  result.backupDir = (getCacheDir() / "/moe/backups").toRunes
  result.dirToExclude = @[ru"/etc"]

proc initFilerSettings(): FilerSettings {.inline.} =
  result.showIcons = true

proc initAutocompleteSettings*(): AutocompleteSettings {.inline.} =
  result.enable = true

proc initTabBarSettings*(): TabLineSettings {.inline.} =
  result.enable = true

proc initStatusLineSettings*(): StatusLineSettings =
  result.enable = true
  result.mode = true
  result.filename = true
  result.chanedMark = true
  result.line = true
  result.column = true
  result.characterEncoding = true
  result.language = true
  result.directory = true
  result.multipleStatusLine = true
  result.gitbranchName = true

proc initEditorViewSettings*(): EditorViewSettings =
  result.highlightCurrentLine = true
  result.lineNumber = true
  result.currentLineNumber = true
  result.indentationLines = true
  result.tabStop = 2
  result.sidebar = true

proc initReservedWords*(): seq[ReservedWord] =
  result = @[
    ReservedWord(word: "TODO", color: EditorColorPairIndex.reservedWord),
    ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord),
    ReservedWord(word: "NOTE", color: EditorColorPairIndex.reservedWord),
  ]

proc initHighlightSettings(): HighlightSettings =
  result.replaceText = true
  result.pairOfParen = true
  result.currentWord = true
  result.fullWidthSpace = true
  result.trailingSpaces = true
  result.reservedWords =  initReservedWords()

proc initPersistSettings(): PersistSettings =
  result.exCommand = true
  result.exCommandHistoryLimit = 1000
  result.search = true
  result.searchHistoryLimit = 1000
  result.cursorPosition = true

# Automatically set the clipboard tool on GNU/Linux
proc autoSetClipboardTool(): ClipboardToolOnLinux =
  result = ClipboardToolOnLinux.none

  case currentPlatform:
    of linux:
      ## Check if X server is running
      if execCmdExNoOutput("xset q") == 0:

        if execCmdExNoOutput("xsel --version") == 0:
          result = ClipboardToolOnLinux.xsel
        elif execCmdExNoOutput("xclip -version") == 0:
          let (output, _) = execCmdEx("xclip -version")
          # Check xclip version
          let
            lines = output.splitLines
            versionStr = (strutils.splitWhitespace(lines[0]))[2]
          if parseFloat(versionStr) >= 0.13:
            result = ClipboardToolOnLinux.xclip
        elif execCmdExNoOutput("wl-copy -v") == 0:
          result = ClipboardToolOnLinux.wlClipboard
    else:
      discard

proc initClipboardSettings(): ClipboardSettings =
  result.toolOnLinux = autoSetClipboardTool()

  if ClipboardToolOnLinux.none != result.toolOnLinux:
    result.enable = true

proc initGitSettings(): GitSettings =
  result.showChangedLine = true

proc initSyntaxCheckerSettings(): SyntaxCheckerSettings =
  result.enable = false

proc initEditorSettings*(): EditorSettings =
  result.editorColorTheme = ColorTheme.dark
  result.statusLine = initStatusLineSettings()
  result.tabLine = initTabBarSettings()
  result.view = initEditorViewSettings()
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.ignorecase = true
  result.smartcase = true
  result.defaultCursor = CursorType.terminalDefault
  result.normalModeCursor = CursorType.blinkBlock
  result.insertModeCursor = CursorType.blinkIbeam
  result.autoSaveInterval = 5
  result.incrementalSearch = true
  result.popupWindowInExmode = true
  result.smoothScroll = true
  result.smoothScrollSpeed = 15
  result.clipboard = initClipboardSettings()
  result.buildOnSave = BuildOnSaveSettings()
  result.filer = initFilerSettings()
  result.autocomplete = initAutocompleteSettings()
  result.autoBackup = initAutoBackupSettings()
  result.quickRun = initQuickRunSettings()
  result.notification = initNotificationSettings()
  result.debugMode = initDebugModeSettings()
  result.highlight = initHighlightSettings()
  result.persist = initPersistSettings()
  result.git = initGitSettings()
  result.syntaxChecker = initSyntaxCheckerSettings()

proc toColorTheme(theme: string): Result[ColorTheme, string] =
  case theme:
    of "dark": Result[ColorTheme, string].ok ColorTheme.dark
    of "light": Result[ColorTheme, string].ok ColorTheme.light
    of "vivid": Result[ColorTheme, string].ok ColorTheme.vivid
    of "config": Result[ColorTheme, string].ok ColorTheme.config
    of "vscode": Result[ColorTheme, string].ok ColorTheme.vscode
    else: Result[ColorTheme, string].err fmt"Invalid value {theme}"

proc colorFromNode(node: JsonNode): Rgb =
  if node == nil:
    return TerminalDefaultRgb

  var asString = node.getStr
  if asString.len >= 7 and asString[0] == '#':
    # Indexes above 6 are cut.
    return asString[1 .. 6].hexToRgb.get
  else:
    return TerminalDefaultRgb

proc makeColorThemeFromVSCodeThemeFile(jsonNode: JsonNode): ThemeColors =
  # Load the theme file of VSCode and adapt it as the theme of moe.
  # Reproduce the original theme as much as possible.

  # The base theme is dark.
  result = ColorThemeTable[ColorTheme.dark]

  let colorsNode =
    if jsonNode.contains("colors"):
      jsonNode["colors"]
    else:
      %* {}

  var tokenNodes = initTable[string, JsonNode]()
  for node in jsonNode{"tokenColors"}:
    var scope = node{"scope"}
    let settings = node{"settings"}
    if scope == nil:
      scope = parseJson("\"unnamedScope\"")
    if settings == nil:
      continue
    if scope.len() > 0:
      for item in scope:
        tokenNodes[item.getStr()] = settings
    else:
      tokenNodes[scope.getStr()] = settings

  proc isKey(key: string): bool {.inline.} = tokenNodes.hasKey(key)

  if jsonNode["colors"].contains("editor.foreground"):
    result[EditorColorPairIndex.default].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.commandLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.currentWord].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.replaceText].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.currentFile].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.searchResult].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

    result[EditorColorPairIndex.visualMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editor.foreground"})

  if jsonNode["colors"].contains("editor.background"):

    result[EditorColorPairIndex.default].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.keyword].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.functionName].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.typeName].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.boolean].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.stringLit].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.specialVar].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.binNumber].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.decNumber].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.floatNumber].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.hexNumber].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.octNumber].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.commandLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.errorMessage].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.currentLineNum].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.file].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.dir].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.pcLink].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.diffViewerAddedLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.diffViewerDeletedLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.backupManagerCurrentLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.configModeCurrentLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.preprocessor].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.pragma].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.background"})

  if tokenNodes.hasKey("keyword"):
    result[EditorColorPairIndex.keyword].foreground.rgb =
      colorFromNode(tokenNodes["keyword"]{"foreground"})

  if tokenNodes.hasKey("entity"):
    result[EditorColorPairIndex.functionName].foreground.rgb =
      colorFromNode(tokenNodes["entity"]{"foreground"})

    result[EditorColorPairIndex.typeName].foreground.rgb =
      colorFromNode(tokenNodes["entity"]{"foreground"})

    result[EditorColorPairIndex.boolean].foreground.rgb =
      colorFromNode(tokenNodes["entity"]{"foreground"})

    result[EditorColorPairIndex.builtin].foreground.rgb =
      colorFromNode(tokenNodes["entity"]{"foreground"})

  if tokenNodes.hasKey("string"):
    result[EditorColorPairIndex.stringLit].foreground.rgb =
      colorFromNode(tokenNodes["string"]{"foreground"})

  if tokenNodes.hasKey("variable"):
    result[EditorColorPairIndex.specialVar].foreground.rgb =
      colorFromNode(tokenNodes["variable"]{"foreground"})

  if tokenNodes.hasKey("constant"):
    result[EditorColorPairIndex.binNumber].foreground.rgb =
      colorFromNode(tokenNodes["constant"]{"foreground"})

    result[EditorColorPairIndex.decNumber].foreground.rgb =
      colorFromNode(tokenNodes["constant"]{"foreground"})

    result[EditorColorPairIndex.floatNumber].foreground.rgb =
      colorFromNode(tokenNodes["constant"]{"foreground"})

    result[EditorColorPairIndex.hexNumber].foreground.rgb =
      colorFromNode(tokenNodes["constant"]{"foreground"})

    result[EditorColorPairIndex.octNumber].foreground.rgb =
      colorFromNode(tokenNodes["constant"]{"foreground"})

  if tokenNodes.hasKey("comment"):
    result[EditorColorPairIndex.comment].foreground.rgb =
      colorFromNode(tokenNodes["comment"]{"foreground"})

    result[EditorColorPairIndex.longComment].foreground.rgb =
      colorFromNode(tokenNodes["comment"]{"foreground"})

  if jsonNode["colors"].contains("editorWhitespace.foreground"):
    result[EditorColorPairIndex.whitespace].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorWhitespace.foreground"})

  if jsonNode.contains("semanticTokenColors"):
    result[EditorColorPairIndex.preprocessor].foreground.rgb =
      colorFromNode(jsonNode{"colors", "semanticTokenColors.parameter.label"})

    result[EditorColorPairIndex.pragma].foreground.rgb =
      colorFromNode(jsonNode{"colors", "semanticTokenColors.parameter.label"})

  if jsonNode["colors"].contains("statusBar.foreground"):
    result[EditorColorPairIndex.statusLineNormalMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeNormalMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineNormalModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeInsertMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeInsertMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineVisualMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeVisualMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineVisualModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineReplaceMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeReplaceMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineReplaceModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineFilerMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeFilerMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineFilerModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineExMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineModeExMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineExModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineGitBranch].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

  if jsonNode["colors"].contains("statusBar.background"):
    result[EditorColorPairIndex.statusLineNormalMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeNormalMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineNormalModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeInsertMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeInsertMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineVisualMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeVisualMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineVisualModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineReplaceMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeReplaceMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineReplaceModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineFilerMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeFilerMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineFilerModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineExMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineModeExMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineExModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineGitBranch].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

  if tokenNodes.hasKey("console.error"):
    result[EditorColorPairIndex.errorMessage].foreground.rgb =
      colorFromNode(jsonNode{"console.error", "foreground"})

  if jsonNode["colors"].contains("tab.foreground"):
    result[EditorColorPairIndex.tab].foreground.rgb =
      colorFromNode(jsonNode{"colors", "tab.foreground"})

    result[EditorColorPairIndex.currentTab].foreground.rgb =
      colorFromNode(jsonNode{"colors", "tab.foreground"})

  if jsonNode["colors"].contains("tab.inactiveBackground"):
    result[EditorColorPairIndex.tab].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.inactiveBackground"})

  if jsonNode["colors"].contains("tab.activeBackground"):
    result[EditorColorPairIndex.currentTab].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBackground"})

  if jsonNode["colors"].contains("editorLineNumber.foreground"):
    result[EditorColorPairIndex.lineNum].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorLineNumber.foreground"})

  if jsonNode["colors"].contains("editorLineNumber.background"):
    result[EditorColorPairIndex.lineNum].background.rgb =
      colorFromNode(jsonNode{"colors", "editorLineNumber.background"})

  if jsonNode["colors"].contains("editorCursor.foreground"):
    result[EditorColorPairIndex.currentLineNum].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})

    result[EditorColorPairIndex.backupManagerCurrentLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})

    result[EditorColorPairIndex.diffViewerDeletedLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})

    result[EditorColorPairIndex.configModeCurrentLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})

  if jsonNode["colors"].contains("editor.selectionBackground"):
    result[EditorColorPairIndex.currentWord].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})

  if jsonNode["colors"].contains("editorSuggestWidget.foreground"):
    result[EditorColorPairIndex.popupWindow].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorSuggestWidget.foreground"})

  if jsonNode["colors"].contains("editorSuggestWidget.selectionBackground"):
    result[EditorColorPairIndex.popupWindow].background.rgb =
      colorFromNode(jsonNode{"colors", "editorSuggestWidget.selectedBackground"})

  if jsonNode["colors"].contains("editorSuggestWidget.highlightForeground"):
    result[EditorColorPairIndex.popupWinCurrentLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "editorSuggestWidget.highlightForeground"})

  if jsonNode["colors"].contains("editorSuggestWidget.selectedBackground"):
    result[EditorColorPairIndex.popupWinCurrentLine].background.rgb =
      colorFromNode(jsonNode{"colors", "editorSuggestWidget.selectedBackground"})

  if tokenNodes.hasKey("unnamedScope"):
    result[EditorColorPairIndex.parenPair].foreground.rgb =
      colorFromNode(tokenNodes["unnamedScope"]{"bracketsForeground"})

  if jsonNode["colors"].contains("editor.selectionBackground"):
    result[EditorColorPairIndex.parenPair].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})

    result[EditorColorPairIndex.currentFile].background.rgb =
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})

  if jsonNode["colors"].contains("gitDecoration.conflictingResourceForeground"):
    result[EditorColorPairIndex.replaceText].background.rgb =
      colorFromNode(jsonNode{"colors", "gitDecoration.conflictingResourceForeground"})

  if tokenNodes.hasKey("hyperlink"):
    result[EditorColorPairIndex.file].foreground.rgb =
      colorFromNode(tokenNodes["hyperlink"]{"foreground"})

    result[EditorColorPairIndex.dir].foreground.rgb =
      colorFromNode(tokenNodes["hyperlink"]{"foreground"})

    result[EditorColorPairIndex.pcLink].foreground.rgb =
      colorFromNode(tokenNodes["hyperlink"]{"foreground"})

  if jsonNode["colors"].contains("tab.activeBorder"):
    result[EditorColorPairIndex.highlightFullWidthSpace].foreground.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

    result[EditorColorPairIndex.highlightFullWidthSpace].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

    result[EditorColorPairIndex.highlightTrailingSpaces].foreground.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

    result[EditorColorPairIndex.highlightTrailingSpaces].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

    result[EditorColorPairIndex.searchResult].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

    result[EditorColorPairIndex.visualMode].background.rgb =
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

  if jsonNode["colors"].contains("dir.inserted"):
    result[EditorColorPairIndex.diffViewerAddedLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "dir.inserted"})

  if jsonNode["colors"].contains("dir.deleted"):
    result[EditorColorPairIndex.diffViewerDeletedLine].foreground.rgb =
      colorFromNode(jsonNode{"colors", "dir.deleted"})

proc codeOssUserSettingsFilePath(): string {.inline.} =
  getConfigDir() / "Code - OSS/User/settings.json"

proc vsCodiumUserSettingsFilePath(): string {.inline.} =
  getConfigDir() / "VSCodium/User/settings.json"

proc vsCodeUserSettingsFilePath(): string {.inline.} =
  getConfigDir() / "Code/User/settings.json"

proc codeOssDefaultExtensionsDir(): string {.inline.} =
  "/usr/lib/code/extensions"

proc vSCodiumDefaultExtensionsDir(): string {.inline.} =
  # TODO: Add support for non-Linux systems.

  "/opt/vscodium-bin/resources/app/extensions"

proc vsCodeDefaultExtensionsDir(): string {.inline.} =
  # TODO: Add support for non-Linux systems.

  "/opt/visual-studio-code/resources/app/extensions"

proc codeOssUserExtensionsDir(): string {.inline.} =
  getHomeDir() / ".vscode-oss/extensions"

proc vsCodiumUserExtensionsDir(): string {.inline.} =
  # Same as the code-oss.
  codeOssUserExtensionsDir()

proc vsCodeUserExtensionsDir(): string  {.inline.} =
  getHomeDir() / ".vscode/extensions"

proc vsCodeSettingsFilePath(flavor: VsCodeFlavor): string =
  case flavor:
    of VsCodeFlavor.VSCodium:
      return vsCodiumUserSettingsFilePath()
    of VsCodeFlavor.CodeOss:
      return codeOssUserSettingsFilePath()
    of VsCodeFlavor.VSCode:
      return vsCodeUserSettingsFilePath()

proc vsCodeUserExtensionsDir(flavor: VsCodeFlavor): string =
  case flavor:
    of VsCodeFlavor.VSCodium:
      return vsCodiumUserExtensionsDir()
    of VsCodeFlavor.CodeOss:
      return codeOssUserExtensionsDir()
    of VsCodeFlavor.VSCode:
      return vsCodeUserExtensionsDir()

proc vsCodeDefaultExtensionsDir(flavor: VsCodeFlavor): string =
  case flavor:
    of VsCodeFlavor.VSCodium:
      return vSCodiumDefaultExtensionsDir()
    of VsCodeFlavor.CodeOss:
      return codeOssDefaultExtensionsDir()
    of VsCodeFlavor.VSCode:
      return vsCodeDefaultExtensionsDir()

proc detectVsCodeFlavor(): Option[VsCodeFlavor] =
  # Check settings dirs in the following order.
  # vscodium -> code-oss -> vscode

  if fileExists(vsCodiumUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCodium)
  elif fileExists(codeOssUserSettingsFilePath()):
    return some(VsCodeFlavor.CodeOss)
  elif fileExists(vsCodeUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCode)

proc isCurrentVsCodeThemePackage(json: JsonNode, themeName: string): bool =
  # Return true if `json` is the current VSCode theme.

  if json{"contributes", "themes"} != nil:
    let themes = json{"contributes", "themes"}
    if themes != nil and themes.kind == JArray:
      for t in themes:
        if t{"label"} != nil and t{"label"}.getStr == themeName:
          return true

proc parseVsCodeThemeJson(
  packageJson: JsonNode,
  themeName, extensionDir: string): Option[JsonNode] =

    let themesJson = packageJson{"contributes", "themes"}
    if themesJson != nil and themesJson.kind == JArray:
      for theme in themesJson:
        if theme{"label"} != nil and theme{"label"}.getStr == themeName:
          let themePath = theme{"path"}

          if themePath != nil and themePath.kind == JString:
            let themeFilePath = parentDir(extensionDir) / themePath.getStr()

            if fileExists(themeFilePath):
              result =
                try: some(json.parseFile(themeFilePath))
                except CatchableError: none(JsonNode)

proc loadVSCodeTheme*(): Result[ColorTheme, string] =
  # If no vscode theme can be found, this defaults to the dark theme.
  # Hopefully other contributors will come and add support for Windows,
  # and other systems.

  let vsCodeFlavor = detectVsCodeFlavor()
  if vsCodeFlavor.isNone:
    return Result[ColorTheme, string].err fmt"Failed to load VSCode theme: Could not find VSCode"

  let
    # load the VSCode user settings json
    settingsFilePath = vsCodeSettingsFilePath(vsCodeFlavor.get)
    settingsJson =
      try:
        json.parseFile(settingsFilePath)
      except CatchableError as e:
        return Result[ColorTheme, string].err fmt"Failed to load VSCode theme: {e.msg}"

  # The current theme name
  if settingsJson{"workbench.colorTheme"} == nil or
     settingsJson{"workbench.colorTheme"}.getStr == "":
       return Result[ColorTheme, string].err fmt"Failed to load VSCode theme: Failed to get the current theme"

  let
    currentThemeName = settingsJson{"workbench.colorTheme"}.getStr

    extensionDirs = [
      # Build in themes.
      vsCodeDefaultExtensionsDir(vsCodeFlavor.get),
      # User themes.
      vsCodeUserExtensionsDir(vsCodeFlavor.get)]

  for dir in extensionDirs:
    if dirExists(dir):
      for file in walkPattern(dir / "*/package.json" ):
        let packageJson =
          try: json.parseFile(file)
          except CatchableError: continue

        if isCurrentVsCodeThemePackage(packageJson, currentThemeName):
          let themeJson = parseVsCodeThemeJson(
            packageJson,
            currentThemeName,
            file)
          if themeJson.isSome:
            ColorThemeTable[ColorTheme.vscode] =
              makecolorThemeFromVSCodeThemeFile(themeJson.get)

            return Result[ColorTheme, string].ok ColorTheme.vscode

  return Result[ColorTheme, string].err fmt"Failed to load VSCode theme: Could not find files for the current theme"

proc parseSettingsFile*(settings: TomlValueRef): EditorSettings =
  result = initEditorSettings()

  if settings.contains("Standard"):
    template cursorType(str: string): untyped =
      parseEnum[CursorType](str)

    if settings["Standard"].contains("theme"):
      let themeString = settings["Standard"]["theme"].getStr()
      result.editorColorTheme = themeString.toColorTheme.get

    if settings["Standard"].contains("number"):
      result.view.lineNumber = settings["Standard"]["number"].getBool()

    if settings["Standard"].contains("currentNumber"):
      result.view.currentLineNumber = settings["Standard"]["currentNumber"].getBool()

    if settings["Standard"].contains("cursorLine"):
      result.view.cursorLine = settings["Standard"]["cursorLine"].getBool()

    if settings["Standard"].contains("statusLine"):
      result.statusLine.enable = settings["Standard"]["statusLine"].getBool()

    if settings["Standard"].contains("tabLine"):
      result.tabLine.enable = settings["Standard"]["tabLine"].getBool()

    if settings["Standard"].contains("syntax"):
      result.syntax = settings["Standard"]["syntax"].getBool()

    if settings["Standard"].contains("tabStop"):
      result.tabStop      = settings["Standard"]["tabStop"].getInt()
      result.view.tabStop = settings["Standard"]["tabStop"].getInt()

    if settings["Standard"].contains("sidebar"):
      result.view.sidebar = settings["Standard"]["sidebar"].getBool

    if settings["Standard"].contains("autoCloseParen"):
      result.autoCloseParen = settings["Standard"]["autoCloseParen"].getBool()

    if settings["Standard"].contains("autoIndent"):
      result.autoIndent = settings["Standard"]["autoIndent"].getBool()

    if settings["Standard"].contains("ignorecase"):
      result.ignorecase = settings["Standard"]["ignorecase"].getBool()

    if settings["Standard"].contains("smartcase"):
      result.smartcase = settings["Standard"]["smartcase"].getBool()

    if settings["Standard"].contains("disableChangeCursor"):
      result.disableChangeCursor = settings["Standard"]["disableChangeCursor"].getBool()

    if settings["Standard"].contains("defaultCursor"):
      let str = settings["Standard"]["defaultCursor"].getStr()
      result.defaultCursor = cursorType(str)

    if settings["Standard"].contains("normalModeCursor"):
      let str = settings["Standard"]["normalModeCursor"].getStr()
      result.normalModeCursor = cursorType(str)

    if settings["Standard"].contains("insertModeCursor"):
      let str = settings["Standard"]["insertModeCursor"].getStr()
      result.insertModeCursor = cursorType(str)

    if settings["Standard"].contains("autoSave"):
      result.autoSave = settings["Standard"]["autoSave"].getBool()

    if settings["Standard"].contains("autoSaveInterval"):
      result.autoSaveInterval = settings["Standard"]["autoSaveInterval"].getInt()

    if settings["Standard"].contains("liveReloadOfConf"):
      result.liveReloadOfConf = settings["Standard"]["liveReloadOfConf"].getBool()

    if settings["Standard"].contains("incrementalSearch"):
      result.incrementalSearch = settings["Standard"]["incrementalSearch"].getBool()

    if settings["Standard"].contains("popupWindowInExmode"):
      result.popupWindowInExmode = settings["Standard"]["popupWindowInExmode"].getBool()

    if settings["Standard"].contains("autoDeleteParen"):
      result.autoDeleteParen =  settings["Standard"]["autoDeleteParen"].getBool()

    if settings["Standard"].contains("smoothScroll"):
      result.smoothScroll =  settings["Standard"]["smoothScroll"].getBool()

    if settings["Standard"].contains("smoothScrollSpeed"):
      result.smoothScrollSpeed = settings["Standard"]["smoothScrollSpeed"].getInt()

    if settings["Standard"].contains("liveReloadOfFile"):
      result.liveReloadOfFile = settings["Standard"]["liveReloadOfFile"].getBool()

    if settings["Standard"].contains("indentationLines"):
      result.view.indentationLines = settings["Standard"]["indentationLines"].getBool()

  if settings.contains("Clipboard"):
    if settings["Clipboard"].contains("enable"):
      result.clipboard.enable = settings["Clipboard"]["enable"].getBool()

    if settings["Clipboard"].contains("toolOnLinux"):
      let str = settings["Clipboard"]["toolOnLinux"].getStr
      case str:
        of "xsel":
          result.clipboard.toolOnLinux = ClipboardToolOnLinux.xsel
        of "xclip":
          result.clipboard.toolOnLinux = ClipboardToolOnLinux.xclip
        of "wl-clipboard":
          result.clipboard.toolOnLinux = ClipboardToolOnLinux.wlClipboard
        else:
          result.clipboard.toolOnLinux = ClipboardToolOnLinux.xsel

  if settings.contains("TabLine"):
    if settings["TabLine"].contains("allBuffer"):
        result.tabLine.allBuffer = settings["TabLine"]["allBuffer"].getBool()

  if settings.contains("StatusLine"):
    if settings["StatusLine"].contains("multipleStatusLine"):
        result.statusLine.multipleStatusLine = settings["StatusLine"]["multipleStatusLine"].getBool()

    if settings["StatusLine"].contains("merge"):
        result.statusLine.merge = settings["StatusLine"]["merge"].getBool()

    if settings["StatusLine"].contains("mode"):
        result.statusLine.mode= settings["StatusLine"]["mode"].getBool()

    if settings["StatusLine"].contains("filename"):
        result.statusLine.filename = settings["StatusLine"]["filename"].getBool()

    if settings["StatusLine"].contains("chanedMark"):
        result.statusLine.chanedMark = settings["StatusLine"]["chanedMark"].getBool()

    if settings["StatusLine"].contains("line"):
        result.statusLine.line = settings["StatusLine"]["line"].getBool()

    if settings["StatusLine"].contains("column"):
        result.statusLine.column = settings["StatusLine"]["column"].getBool()

    if settings["StatusLine"].contains("encoding"):
        result.statusLine.characterEncoding = settings["StatusLine"]["encoding"].getBool()

    if settings["StatusLine"].contains("language"):
        result.statusLine.language = settings["StatusLine"]["language"].getBool()

    if settings["StatusLine"].contains("directory"):
        result.statusLine.directory = settings["StatusLine"]["directory"].getBool()

    if settings["StatusLine"].contains("gitbranchName"):
        result.statusLine.gitbranchName = settings["StatusLine"]["gitbranchName"].getBool()

    if settings["StatusLine"].contains("showGitInactive"):
        result.statusLine.showGitInactive = settings["StatusLine"]["showGitInactive"].getBool()

    if settings["StatusLine"].contains("showModeInactive"):
        result.statusLine.showModeInactive = settings["StatusLine"]["showModeInactive"].getBool()

  if settings.contains("BuildOnSave"):
    if settings["BuildOnSave"].contains("enable"):
      result.buildOnSave.enable = settings["BuildOnSave"]["enable"].getBool()

    if settings["BuildOnSave"].contains("workspaceRoot"):
      result.buildOnSave.workspaceRoot = settings["BuildOnSave"]["workspaceRoot"].getStr().toRunes

    if settings["BuildOnSave"].contains("command"):
      result.buildOnSave.command = settings["BuildOnSave"]["command"].getStr().toRunes

  if settings.contains("Highlight"):
    if settings["Highlight"].contains("reservedWord"):
      let reservedWords = settings["Highlight"]["reservedWord"]
      for i in 0 ..< reservedWords.len:
        let
          word = reservedWords[i].getStr
          reservedWord = ReservedWord(word: word, color: EditorColorPairIndex.reservedWord)
        result.highlight.reservedWords.add(reservedWord)

    if settings["Highlight"].contains("currentLine"):
      result.view.highlightCurrentLine = settings["Highlight"]["currentLine"].getBool()

    if settings["Highlight"].contains("currentWord"):
      result.highlight.currentWord = settings["Highlight"]["currentWord"].getBool()

    if settings["Highlight"].contains("replaceText"):
      result.highlight.replaceText = settings["Highlight"]["replaceText"].getBool()

    if settings["Highlight"].contains("pairOfParen"):
      result.highlight.pairOfParen =  settings["Highlight"]["pairOfParen"].getBool()

    if settings["Highlight"].contains("fullWidthSpace"):
      result.highlight.fullWidthSpace = settings["Highlight"]["fullWidthSpace"].getBool()

    if settings["Highlight"].contains("trailingSpaces"):
      result.highlight.trailingSpaces = settings["Highlight"]["trailingSpaces"].getBool()

  if settings.contains("AutoBackup"):
    if settings["AutoBackup"].contains("enable"):
      result.autoBackup.enable = settings["AutoBackup"]["enable"].getBool()

    if settings["AutoBackup"].contains("idleTime"):
      result.autoBackup.idleTime = settings["AutoBackup"]["idleTime"].getInt()

    if settings["AutoBackup"].contains("interval"):
      result.autoBackup.interval = settings["AutoBackup"]["interval"].getInt()

    if settings["AutoBackup"].contains("backupDir"):
      let dir = settings["AutoBackup"]["backupDir"].getStr()
      result.autoBackup.backupDir = dir.toRunes

    if settings["AutoBackup"].contains("dirToExclude"):
      result.autoBackup.dirToExclude = @[]
      let dirs = settings["AutoBackup"]["dirToExclude"]
      for i in 0 ..< dirs.len:
        result.autoBackup.dirToExclude.add(ru dirs[i].getStr)

  if settings.contains("QuickRun"):
    if settings["QuickRun"].contains("saveBufferWhenQuickRun"):
      let saveBufferWhenQuickRun = settings["QuickRun"]["saveBufferWhenQuickRun"].getBool()
      result.quickRun.saveBufferWhenQuickRun = saveBufferWhenQuickRun

    if settings["QuickRun"].contains("command"):
      result.quickRun.command = settings["QuickRun"]["command"].getStr()

    if settings["QuickRun"].contains("timeout"):
      result.quickRun.timeout = settings["QuickRun"]["timeout"].getInt()

    if settings["QuickRun"].contains("nimAdvancedCommand"):
      result.quickRun.nimAdvancedCommand = settings["QuickRun"]["nimAdvancedCommand"].getStr()

    if settings["QuickRun"].contains("clangOptions"):
      result.quickRun.clangOptions = settings["QuickRun"]["clangOptions"].getStr()

    if settings["QuickRun"].contains("cppOptions"):
      result.quickRun.cppOptions = settings["QuickRun"]["cppOptions"].getStr()

    if settings["QuickRun"].contains("nimOptions"):
      result.quickRun.nimOptions = settings["QuickRun"]["nimOptions"].getStr()

    if settings["QuickRun"].contains("shOptions"):
      result.quickRun.shOptions = settings["QuickRun"]["shOptions"].getStr()

    if settings["QuickRun"].contains("bashOptions"):
      result.quickRun.bashOptions = settings["QuickRun"]["bashOptions"].getStr()

  if settings.contains("Notification"):
    if settings["Notification"].contains("screenNotifications"):
      result.notification.screenNotifications = settings["Notification"]["screenNotifications"].getBool

    if settings["Notification"].contains("logNotifications"):
      result.notification.logNotifications = settings["Notification"]["logNotifications"].getBool

    if settings["Notification"].contains("autoBackupScreenNotify"):
      result.notification.autoBackupScreenNotify = settings["Notification"]["autoBackupScreenNotify"].getBool

    if settings["Notification"].contains("autoBackupLogNotify"):
      result.notification.autoBackupLogNotify = settings["Notification"]["autoBackupLogNotify"].getBool

    if settings["Notification"].contains("autoSaveScreenNotify"):
      result.notification.autoSaveScreenNotify = settings["Notification"]["autoSaveScreenNotify"].getBool

    if settings["Notification"].contains("autoSaveLogNotify"):
      result.notification.autoSaveLogNotify = settings["Notification"]["autoSaveLogNotify"].getBool

    if settings["Notification"].contains("yankScreenNotify"):
      result.notification.yankScreenNotify = settings["Notification"]["yankScreenNotify"].getBool

    if settings["Notification"].contains("yankLogNotify"):
      result.notification.yankLogNotify = settings["Notification"]["yankLogNotify"].getBool

    if settings["Notification"].contains("deleteScreenNotify"):
      result.notification.deleteScreenNotify = settings["Notification"]["deleteScreenNotify"].getBool

    if settings["Notification"].contains("deleteLogNotify"):
      result.notification.deleteLogNotify = settings["Notification"]["deleteLogNotify"].getBool

    if settings["Notification"].contains("saveScreenNotify"):
      result.notification.saveScreenNotify = settings["Notification"]["saveScreenNotify"].getBool

    if settings["Notification"].contains("saveLogNotify"):
      result.notification.saveLogNotify = settings["Notification"]["saveLogNotify"].getBool

    if settings["Notification"].contains("quickRunScreenNotify"):
      result.notification.quickRunScreenNotify = settings["Notification"]["quickRunScreenNotify"].getBool

    if settings["Notification"].contains("quickRunLogNotify"):
      result.notification.quickRunLogNotify = settings["Notification"]["quickRunLogNotify"].getBool

    if settings["Notification"].contains("buildOnSaveScreenNotify"):
      result.notification.buildOnSaveScreenNotify = settings["Notification"]["buildOnSaveScreenNotify"].getBool

    if settings["Notification"].contains("buildOnSaveLogNotify"):
      result.notification.buildOnSaveLogNotify = settings["Notification"]["buildOnSaveLogNotify"].getBool

    if settings["Notification"].contains("filerScreenNotify"):
      result.notification.filerScreenNotify = settings["Notification"]["filerScreenNotify"].getBool

    if settings["Notification"].contains("filerLogNotify"):
      result.notification.filerLogNotify = settings["Notification"]["filerLogNotify"].getBool

    if settings["Notification"].contains("restoreScreenNotify"):
      result.notification.restoreScreenNotify = settings["Notification"]["restoreScreenNotify"].getBool

    if settings["Notification"].contains("restoreLogNotify"):
      result.notification.restoreLogNotify = settings["Notification"]["restoreLogNotify"].getBool

  if settings.contains("Filer"):
    if settings["Filer"].contains("showIcons"):
      result.filer.showIcons = settings["Filer"]["showIcons"].getBool()

  if (const table = "Autocomplete"; settings.contains(table)):
    if (const key = "enable"; settings[table].contains(key)):
      result.autocomplete.enable = settings[table][key].getBool

  if settings.contains("Persist"):
    if settings["Persist"].contains("exCommand"):
      result.persist.exCommand = settings["Persist"]["exCommand"].getBool

    if settings["Persist"].contains("exCommandHistoryLimit"):
      result.persist.exCommandHistoryLimit = settings["Persist"]["exCommandHistoryLimit"].getInt

    if settings["Persist"].contains("search"):
      result.persist.search = settings["Persist"]["search"].getBool

    if settings["Persist"].contains("searchHistoryLimit"):
      result.persist.searchHistoryLimit = settings["Persist"]["searchHistoryLimit"].getInt

    if settings["Persist"].contains("cursorPosition"):
      result.persist.cursorPosition = settings["Persist"]["cursorPosition"].getBool

  if settings.contains("Debug"):
    if settings["Debug"].contains("WindowNode"):
      let windowNodeSettings = settings["Debug"]["WindowNode"]

      if windowNodeSettings.contains("enable"):
        let setting = windowNodeSettings["enable"].getBool
        result.debugMode.windowNode.enable = setting

      if windowNodeSettings.contains("currentWindow"):
        let setting = windowNodeSettings["currentWindow"].getBool
        result.debugMode.windowNode.currentWindow = setting

      if windowNodeSettings.contains("index"):
        let setting = windowNodeSettings["index"].getBool
        result.debugMode.windowNode.index = setting

      if windowNodeSettings.contains("windowIndex"):
        let setting = windowNodeSettings["windowIndex"].getBool
        result.debugMode.windowNode.windowIndex = setting

      if windowNodeSettings.contains("bufferIndex"):
        let setting = windowNodeSettings["bufferIndex"].getBool
        result.debugMode.windowNode.bufferIndex = setting

      if windowNodeSettings.contains("parentIndex"):
        let setting = windowNodeSettings["parentIndex"].getBool
        result.debugMode.windowNode.parentIndex = setting

      if windowNodeSettings.contains("childLen"):
        let setting = windowNodeSettings["childLen"].getBool
        result.debugMode.windowNode.childLen = setting

      if windowNodeSettings.contains("splitType"):
        let setting = windowNodeSettings["splitType"].getBool
        result.debugMode.windowNode.splitType = setting

      if windowNodeSettings.contains("haveCursesWin"):
        let setting = windowNodeSettings["haveCursesWin"].getBool
        result.debugMode.windowNode.haveCursesWin = setting

      if windowNodeSettings.contains("haveCursesWin"):
        let setting = windowNodeSettings["haveCursesWin"].getBool
        result.debugMode.windowNode.haveCursesWin = setting

      if windowNodeSettings.contains("y"):
        let setting = windowNodeSettings["y"].getBool
        result.debugMode.windowNode.y = setting

      if windowNodeSettings.contains("x"):
        let setting = windowNodeSettings["x"].getBool
        result.debugMode.windowNode.x = setting

      if windowNodeSettings.contains("h"):
        let setting = windowNodeSettings["h"].getBool
        result.debugMode.windowNode.h = setting

      if windowNodeSettings.contains("w"):
        let setting = windowNodeSettings["w"].getBool
        result.debugMode.windowNode.w = setting

      if windowNodeSettings.contains("currentLine"):
        let setting = windowNodeSettings["currentLine"].getBool
        result.debugMode.windowNode.currentLine = setting

      if windowNodeSettings.contains("currentColumn"):
        let setting = windowNodeSettings["currentColumn"].getBool
        result.debugMode.windowNode.currentColumn = setting

      if windowNodeSettings.contains("expandedColumn"):
        let setting = windowNodeSettings["expandedColumn"].getBool
        result.debugMode.windowNode.expandedColumn = setting

      if windowNodeSettings.contains("cursor"):
        let setting = windowNodeSettings["cursor"].getBool
        result.debugMode.windowNode.cursor = setting

    if settings["Debug"].contains("EditorView"):
      let editorViewSettings = settings["Debug"]["EditorView"]

      if editorViewSettings.contains("enable"):
        let setting = editorViewSettings["enable"].getBool
        result.debugMode.editorview.enable = setting

      if editorViewSettings.contains("widthOfLineNum"):
        let setting = editorViewSettings["widthOfLineNum"].getBool
        result.debugMode.editorview.widthOfLineNum = setting

      if editorViewSettings.contains("height"):
        let setting = editorViewSettings["height"].getBool
        result.debugMode.editorview.height = setting

      if editorViewSettings.contains("width"):
        let setting = editorViewSettings["width"].getBool
        result.debugMode.editorview.width = setting

      if editorViewSettings.contains("originalLine"):
        let setting = editorViewSettings["originalLine"].getBool
        result.debugMode.editorview.originalLine = setting

      if editorViewSettings.contains("start"):
        let setting = editorViewSettings["start"].getBool
        result.debugMode.editorview.start = setting

      if editorViewSettings.contains("length"):
        let setting = editorViewSettings["length"].getBool
        result.debugMode.editorview.length = setting

    if settings["Debug"].contains("BufferStatus"):
      let bufStatusSettings = settings["Debug"]["BufferStatus"]

      if bufStatusSettings.contains("enable"):
        let setting = bufStatusSettings["enable"].getBool
        result.debugMode.bufStatus.enable = setting

      if bufStatusSettings.contains("bufferIndex"):
        let setting = bufStatusSettings["bufferIndex"].getBool
        result.debugMode.bufStatus.bufferIndex = setting

      if bufStatusSettings.contains("path"):
        let setting = bufStatusSettings["path"].getBool
        result.debugMode.bufStatus.path = setting

      if bufStatusSettings.contains("openDir"):
        let setting = bufStatusSettings["openDir"].getBool
        result.debugMode.bufStatus.openDir = setting

      if bufStatusSettings.contains("currentMode"):
        let setting = bufStatusSettings["currentMode"].getBool
        result.debugMode.bufStatus.currentMode = setting

      if bufStatusSettings.contains("prevMode"):
        let setting = bufStatusSettings["prevMode"].getBool
        result.debugMode.bufStatus.prevMode = setting

      if bufStatusSettings.contains("language"):
        let setting = bufStatusSettings["language"].getBool
        result.debugMode.bufStatus.language = setting

      if bufStatusSettings.contains("encoding"):
        let setting = bufStatusSettings["encoding"].getBool
        result.debugMode.bufStatus.encoding = setting

      if bufStatusSettings.contains("countChange"):
        let setting = bufStatusSettings["countChange"].getBool
        result.debugMode.bufStatus.countChange = setting

      if bufStatusSettings.contains("cmdLoop"):
        let setting = bufStatusSettings["cmdLoop"].getBool
        result.debugMode.bufStatus.cmdLoop = setting

      if bufStatusSettings.contains("lastSaveTime"):
        let setting = bufStatusSettings["lastSaveTime"].getBool
        result.debugMode.bufStatus.lastSaveTime = setting

      if bufStatusSettings.contains("bufferLen"):
        let setting = bufStatusSettings["bufferLen"].getBool
        result.debugMode.bufStatus.bufferLen = setting

  if result.editorColorTheme == ColorTheme.config and
     settings.contains("Theme"):
    if settings["Theme"].contains("baseTheme"):
      let themeString = settings["Theme"]["baseTheme"].getStr()
      if fileExists(themeString):
        let jsonNode =
          try: some(json.parseFile(themeString))
          except CatchableError: none(JsonNode)
        if jsonNode.isSome:
          ColorThemeTable[ColorTheme.config] = makecolorThemeFromVSCodeThemeFile(jsonNode.get)
        else:
          let theme = parseEnum[ColorTheme](themeString)
          ColorThemeTable[ColorTheme.config] = ColorThemeTable[theme]
      else:
        let theme = parseEnum[ColorTheme](themeString)
        ColorThemeTable[ColorTheme.config] = ColorThemeTable[theme]

    proc toRgb(s: string): Rgb =
      let val = settings["Theme"][s].getStr
      case val:
        of "termDefaultFg", "termDefaultBg":
          TerminalDefaultRgb
        else:
          if val.isHexColor:
            val.hexToRgb.get
          else:
            # TODO: Return Result.error
            raise newException(ValueError, fmt"Invalid color value: {s} = {val}")

    result.editorColorTheme = ColorTheme.config

    let configTheme = ColorTheme.config

    if settings["Theme"].contains("foreground"):
      ColorThemeTable[configTheme][EditorColorPairIndex.default].foreground.rgb =
        toRgb("foreground")
      ColorThemeTable[configTheme][EditorColorPairIndex.currentLineBg].foreground.rgb =
        toRgb("foreground")

    if settings["Theme"].contains("background"):
      let bgRgb = toRgb("background")
      ColorThemeTable[configTheme][EditorColorPairIndex.default].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.keyword].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.functionName].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.typeName].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.boolean].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.specialVar].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.builtin].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.stringLit].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.binNumber].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.decNumber].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.floatNumber].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.hexNumber].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.octNumber].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.comment].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.longComment].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.whitespace].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.preprocessor].background.rgb =
        bgRgb
      ColorThemeTable[configTheme][EditorColorPairIndex.pragma].background.rgb =
        bgRgb

    if settings["Theme"].contains("lineNum"):
      ColorThemeTable[configTheme][EditorColorPairIndex.lineNum].foreground.rgb =
        toRgb("lineNum")
    if settings["Theme"].contains("lineNumBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.lineNum].background.rgb =
        toRgb("lineNumBg")

    if settings["Theme"].contains("currentLineNum"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentLineNum].foreground.rgb =
        toRgb("currentLineNum")
    if settings["Theme"].contains("currentLineNumBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentLineNum].background.rgb =
        toRgb("currentLineNumBg")

    if settings["Theme"].contains("statusLineNormalMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineNormalMode].foreground.rgb =
        toRgb("statusLineNormalMode")
    if settings["Theme"].contains("statusLineNormalModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineNormalMode].background.rgb =
        toRgb("statusLineNormalModeBg")

    if settings["Theme"].contains("statusLineModeNormalMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeNormalMode].foreground.rgb =
        toRgb("statusLineModeNormalMode")
    if settings["Theme"].contains("statusLineModeNormalModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeNormalMode].background.rgb =
        toRgb("statusLineModeNormalModeBg")

    if settings["Theme"].contains("statusLineNormalModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineNormalModeInactive].foreground.rgb =
        toRgb("statusLineNormalModeInactive")
    if settings["Theme"].contains("statusLineNormalModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineNormalModeInactive].background.rgb =
        toRgb("statusLineNormalModeInactiveBg")

    if settings["Theme"].contains("statusLineInsertMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineInsertMode].foreground.rgb =
        toRgb("statusLineInsertMode")
    if settings["Theme"].contains("statusLineInsertModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineInsertMode].background.rgb =
        toRgb("statusLineInsertModeBg")

    if settings["Theme"].contains("statusLineModeInsertMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeInsertMode].foreground.rgb =
        toRgb("statusLineModeInsertMode")
    if settings["Theme"].contains("statusLineModeInsertModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeInsertMode].background.rgb =
        toRgb("statusLineModeInsertModeBg")

    if settings["Theme"].contains("statusLineInsertModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineInsertModeInactive].foreground.rgb =
        toRgb("statusLineInsertModeInactive")
    if settings["Theme"].contains("statusLineInsertModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineInsertModeInactive].background.rgb =
        toRgb("statusLineInsertModeInactiveBg")

    if settings["Theme"].contains("statusLineVisualMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineVisualMode].foreground.rgb =
        toRgb("statusLineVisualMode")
    if settings["Theme"].contains("statusLineVisualModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineVisualMode].background.rgb =
        toRgb("statusLineVisualModeBg")

    if settings["Theme"].contains("statusLineModeVisualMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeVisualMode].foreground.rgb =
        toRgb("statusLineModeVisualMode")
    if settings["Theme"].contains("statusLineModeVisualModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeVisualMode].background.rgb =
        toRgb("statusLineModeVisualModeBg")

    if settings["Theme"].contains("statusLineVisualModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineVisualModeInactive].foreground.rgb =
        toRgb("statusLineVisualModeInactive")
    if settings["Theme"].contains("statusLineVisualModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineVisualModeInactive].background.rgb =
        toRgb("statusLineVisualModeInactiveBg")

    if settings["Theme"].contains("statusLineReplaceMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineReplaceMode].foreground.rgb =
        toRgb("statusLineReplaceMode")
    if settings["Theme"].contains("statusLineReplaceModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineReplaceMode].background.rgb =
        toRgb("statusLineReplaceModeBg")

    if settings["Theme"].contains("statusLineModeReplaceMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeReplaceMode].foreground.rgb =
        toRgb("statusLineModeReplaceMode")
    if settings["Theme"].contains("statusLineModeReplaceModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeReplaceMode].background.rgb =
        toRgb("statusLineModeReplaceModeBg")

    if settings["Theme"].contains("statusLineReplaceModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineReplaceModeInactive].foreground.rgb =
        toRgb("statusLineReplaceModeInactive")
    if settings["Theme"].contains("statusLineReplaceModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineReplaceModeInactive].background.rgb =
        toRgb("statusLineReplaceModeInactiveBg")

    if settings["Theme"].contains("statusLineFilerMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineFilerMode].foreground.rgb =
        toRgb("statusLineFilerMode")
    if settings["Theme"].contains("statusLineFilerModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineFilerMode].background.rgb =
        toRgb("statusLineFilerModeBg")

    if settings["Theme"].contains("statusLineModeFilerMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeFilerMode].foreground.rgb =
        toRgb("statusLineModeFilerMode")
    if settings["Theme"].contains("statusLineModeFilerModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeFilerMode].background.rgb =
        toRgb("statusLineModeFilerModeBg")

    if settings["Theme"].contains("statusLineFilerModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineFilerModeInactive].foreground.rgb =
        toRgb("statusLineFilerModeInactive")
    if settings["Theme"].contains("statusLineFilerModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineFilerModeInactive].background.rgb =
        toRgb("statusLineFilerModeInactiveBg")

    if settings["Theme"].contains("statusLineExMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineExMode].foreground.rgb =
        toRgb("statusLineExMode")
    if settings["Theme"].contains("statusLineExModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineExMode].background.rgb =
        toRgb("statusLineExModeBg")

    if settings["Theme"].contains("statusLineModeExMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeExMode].foreground.rgb =
        toRgb("statusLineModeExMode")
    if settings["Theme"].contains("statusLineModeExModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineModeExMode].background.rgb =
        toRgb("statusLineModeExModeBg")

    if settings["Theme"].contains("statusLineExModeInactive"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineExModeInactive].foreground.rgb =
        toRgb("statusLineExModeInactive")
    if settings["Theme"].contains("statusLineExModeInactiveBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineExModeInactive].background.rgb =
        toRgb("statusLineExModeInactiveBg")

    if settings["Theme"].contains("statusLineGitBranch"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineGitBranch].foreground.rgb =
        toRgb("statusLineGitBranch")
    if settings["Theme"].contains("statusLineGitBranchBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.statusLineGitBranch].background.rgb =
        toRgb("statusLineGitBranchBg")

    if settings["Theme"].contains("tab"):
      ColorThemeTable[configTheme][EditorColorPairIndex.tab].foreground.rgb =
        toRgb("tab")
    if settings["Theme"].contains("tabBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.tab].background.rgb =
        toRgb("tabBg")

    if settings["Theme"].contains("currentTab"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentTab].foreground.rgb =
        toRgb("currentTab")
    if settings["Theme"].contains("currentTabBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentTab].background.rgb =
        toRgb("currentTabBg")

    if settings["Theme"].contains("commandLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.commandLine].foreground.rgb =
        toRgb("commandLine")
    if settings["Theme"].contains("commandLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.commandLine].background.rgb =
        toRgb("commandLineBg")

    if settings["Theme"].contains("errorMessage"):
      ColorThemeTable[configTheme][EditorColorPairIndex.errorMessage].foreground.rgb =
        toRgb("errorMessage")
    if settings["Theme"].contains("errorMessageBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.errorMessage].background.rgb =
        toRgb("errorMessageBg")

    if settings["Theme"].contains("searchResult"):
      ColorThemeTable[configTheme][EditorColorPairIndex.searchResult].foreground.rgb =
        toRgb("searchResult")
    if settings["Theme"].contains("searchResultBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.searchResult].background.rgb =
        toRgb("searchResultBg")

    if settings["Theme"].contains("visualMode"):
      ColorThemeTable[configTheme][EditorColorPairIndex.visualMode].foreground.rgb =
        toRgb("visualMode")
    if settings["Theme"].contains("visualModeBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.visualMode].background.rgb =
        toRgb("visualModeBg")

    if settings["Theme"].contains("keyword"):
      ColorThemeTable[configTheme][EditorColorPairIndex.keyword].foreground.rgb =
        toRgb("keyword")

    if settings["Theme"].contains("functionName"):
      ColorThemeTable[configTheme][EditorColorPairIndex.functionName].foreground.rgb =
        toRgb("functionName")
    if settings["Theme"].contains("typeName"):
      ColorThemeTable[configTheme][EditorColorPairIndex.typeName].foreground.rgb =
        toRgb("typeName")
    if settings["Theme"].contains("boolean"):
      ColorThemeTable[configTheme][EditorColorPairIndex.boolean].foreground.rgb =
        toRgb("boolean")

    if settings["Theme"].contains("specialVar"):
      ColorThemeTable[configTheme][EditorColorPairIndex.specialVar].foreground.rgb =
        toRgb("specialVar")

    if settings["Theme"].contains("builtin"):
      ColorThemeTable[configTheme][EditorColorPairIndex.builtin].foreground.rgb =
        toRgb("builtin")

    if settings["Theme"].contains("stringLit"):
      ColorThemeTable[configTheme][EditorColorPairIndex.stringLit].foreground.rgb =
        toRgb("stringLit")

    if settings["Theme"].contains("binNumber"):
      ColorThemeTable[configTheme][EditorColorPairIndex.binNumber].foreground.rgb =
        toRgb("binNumber")

    if settings["Theme"].contains("decNumber"):
      ColorThemeTable[configTheme][EditorColorPairIndex.decNumber].foreground.rgb =
        toRgb("decNumber")

    if settings["Theme"].contains("floatNumber"):
      ColorThemeTable[configTheme][EditorColorPairIndex.floatNumber].foreground.rgb =
        toRgb("floatNumber")

    if settings["Theme"].contains("hexNumber"):
      ColorThemeTable[configTheme][EditorColorPairIndex.hexNumber].foreground.rgb =
        toRgb("hexNumber")

    if settings["Theme"].contains("octNumber"):
      ColorThemeTable[configTheme][EditorColorPairIndex.octNumber].foreground.rgb =
        toRgb("octNumber")

    if settings["Theme"].contains("comment"):
      ColorThemeTable[configTheme][EditorColorPairIndex.comment].foreground.rgb =
        toRgb("comment")

    if settings["Theme"].contains("longComment"):
      ColorThemeTable[configTheme][EditorColorPairIndex.longComment].foreground.rgb =
        toRgb("longComment")

    if settings["Theme"].contains("whitespace"):
      ColorThemeTable[configTheme][EditorColorPairIndex.whitespace].foreground.rgb =
        toRgb("whitespace")

    if settings["Theme"].contains("preprocessor"):
      ColorThemeTable[configTheme][EditorColorPairIndex.preprocessor].foreground.rgb =
        toRgb("preprocessor")

    if settings["Theme"].contains("pragma"):
      ColorThemeTable[configTheme][EditorColorPairIndex.pragma].foreground.rgb =
        toRgb("pragma")

    if settings["Theme"].contains("currentFile"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentFile].foreground.rgb =
        toRgb("currentFile")
    if settings["Theme"].contains("currentFileBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentFile].background.rgb =
        toRgb("currentFileBg")

    if settings["Theme"].contains("file"):
      ColorThemeTable[configTheme][EditorColorPairIndex.file].foreground.rgb =
        toRgb("file")
    if settings["Theme"].contains("fileBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.file].background.rgb =
        toRgb("fileBg")

    if settings["Theme"].contains("dir"):
      ColorThemeTable[configTheme][EditorColorPairIndex.dir].foreground.rgb =
        toRgb("dir")
    if settings["Theme"].contains("dirBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.dir].background.rgb =
        toRgb("dirBg")

    if settings["Theme"].contains("pcLink"):
      ColorThemeTable[configTheme][EditorColorPairIndex.pcLink].foreground.rgb =
        toRgb("pcLink")
    if settings["Theme"].contains("pcLinkBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.pcLink].background.rgb =
        toRgb("pcLinkBg")

    if settings["Theme"].contains("popupWindow"):
      ColorThemeTable[configTheme][EditorColorPairIndex.popupWindow].foreground.rgb =
        toRgb("popupWindow")
    if settings["Theme"].contains("popupWindowBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.popupWindow].background.rgb =
        toRgb("popupWindowBg")

    if settings["Theme"].contains("popupWinCurrentLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.popupWinCurrentLine].foreground.rgb =
        toRgb("popupWinCurrentLine")
    if settings["Theme"].contains("popupWinCurrentLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.popupWinCurrentLine].background.rgb =
        toRgb("popupWinCurrentLineBg")

    if settings["Theme"].contains("replaceText"):
      ColorThemeTable[configTheme][EditorColorPairIndex.replaceText].foreground.rgb =
        toRgb("replaceText")
    if settings["Theme"].contains("replaceTextBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.replaceText].background.rgb =
        toRgb("replaceTextBg")

    if settings["Theme"].contains("parenPair"):
      ColorThemeTable[configTheme][EditorColorPairIndex.parenPair].foreground.rgb =
        toRgb("parenPair")
    if settings["Theme"].contains("parenPairBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.parenPair].background.rgb =
        toRgb("parenPairBg")

    if settings["Theme"].contains("currentWord"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentWord].foreground.rgb =
        toRgb("currentWord")
    if settings["Theme"].contains("currentWordBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentWord].background.rgb =
        toRgb("currentWordBg")

    if settings["Theme"].contains("highlightFullWidthSpace"):
      ColorThemeTable[configTheme][EditorColorPairIndex.highlightFullWidthSpace].foreground.rgb =
        toRgb("highlightFullWidthSpace")
    if settings["Theme"].contains("highlightFullWidthSpaceBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.highlightFullWidthSpace].background.rgb =
        toRgb("highlightFullWidthSpaceBg")

    if settings["Theme"].contains("highlightFullWidthSpaceBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.highlightFullWidthSpace].background.rgb =
        toRgb("highlightFullWidthSpaceBg")

    if settings["Theme"].contains("highlightTrailingSpaces"):
      ColorThemeTable[configTheme][EditorColorPairIndex.highlightTrailingSpaces].foreground.rgb =
        toRgb("highlightTrailingSpaces")

    if settings["Theme"].contains("highlightTrailingSpacesBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.highlightTrailingSpaces].background.rgb =
        toRgb("highlightTrailingSpacesBg")

    if settings["Theme"].contains("reservedWord"):
      ColorThemeTable[configTheme][EditorColorPairIndex.reservedWord].foreground.rgb =
        toRgb("reservedWord")
    if settings["Theme"].contains("reservedWordBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.reservedWord].background.rgb =
        toRgb("reservedWordBg")

    if settings["Theme"].contains("backupManagerCurrentLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.backupManagerCurrentLine].foreground.rgb =
        toRgb("backupManagerCurrentLine")
    if settings["Theme"].contains("backupManagerCurrentLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.backupManagerCurrentLine].background.rgb =
        toRgb("backupManagerCurrentLineBg")

    if settings["Theme"].contains("diffViewerAddedLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.diffViewerAddedLine].foreground.rgb =
        toRgb("diffViewerAddedLine")
    if settings["Theme"].contains("diffViewerAddedLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.diffViewerAddedLine].background.rgb =
        toRgb("diffViewerAddedLineBg")

    if settings["Theme"].contains("diffViewerDeletedLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.diffViewerDeletedLine].foreground.rgb =
        toRgb("diffViewerDeletedLine")
    if settings["Theme"].contains("diffViewerDeletedLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.diffViewerDeletedLine].background.rgb =
        toRgb("diffViewerDeletedLineBg")

    if settings["Theme"].contains("configModeCurrentLine"):
      ColorThemeTable[configTheme][EditorColorPairIndex.configModeCurrentLine].foreground.rgb =
        toRgb("configModeCurrentLine")
    if settings["Theme"].contains("configModeCurrentLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.configModeCurrentLine].background.rgb =
        toRgb("configModeCurrentLineBg")

    if settings["Theme"].contains("currentLineBg"):
      ColorThemeTable[configTheme][EditorColorPairIndex.currentLineBg].background.rgb =
        toRgb("currentLineBg")

  elif result.editorColorTheme == ColorTheme.vscode:
    let vsCodeTheme = loadVSCodeTheme()
    if vsCodeTheme.isOk:
      result.editorColorTheme = vsCodeTheme.get
    else:
      # The default theme is dark
      result.editorColorTheme = ColorTheme.dark

  if settings.contains("Git"):
    if settings["Git"].contains("showChangedLine"):
      result.git.showChangedLine = settings["Git"]["showChangedLine"].getBool

  if settings.contains("SyntaxChecker"):
    if settings["SyntaxChecker"].contains("enable"):
      result.syntaxChecker.enable = settings["SyntaxChecker"]["enable"].getBool

proc validateStandardTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "theme":
        var correctValue = false
        if val.getStr == "vscode":
          correctValue = true
        else:
          for theme in ColorTheme:
            if $theme == val.getStr:
              correctValue = true
        if not correctValue:
          return some(InvalidItem(name: $key, val: $val))
      of "number",
         "currentNumber",
         "cursorLine",
         "statusLine",
         "tabLine",
         "syntax",
         "indentationLines",
         "autoCloseParen",
         "autoIndent",
         "ignorecase",
         "smartcase",
         "disableChangeCursor",
         "autoSave",
         "liveReloadOfConf",
         "incrementalSearch",
         "popupWindowInExmode",
         "autoDeleteParen",
         "systemClipboard",
         "smoothScroll",
         "liveReloadOfFile",
         "sidebar":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "tabStop", "autoSaveInterval", "smoothScrollSpeed":
        if not (val.kind == TomlValueKind.Int and val.getInt > 0):
          return some(InvalidItem(name: $key, val: $val))
      of "defaultCursor",
         "normalModeCursor",
         "insertModeCursor":
        let val = val.getStr
        var correctValue = false
        for cursorType in CursorType:
          if val == $cursorType:
            correctValue = true
            break
        if not correctValue:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateClipboardTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "toolOnLinux":
        if not (
          (val.kind == TomlValueKind.String) and
          (val.getStr == "none" or
           val.getStr == "xclip" or
           val.getStr == "xsel" or
           val.getStr == "wl-clipboard")): return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateTabLineTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "allBuffer":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateBuildOnSaveTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "workspaceRoot",
         "command":
        if not (val.kind == TomlValueKind.String):
          return some(InvalidItem(name: $key, val: $val))
      else:
          return some(InvalidItem(name: $key, val: $val))

proc validateStatusLineTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "multipleStatusLine",
         "merge",
         "mode",
         "filename",
         "chanedMark",
         "line",
         "column",
         "encoding",
         "language",
         "directory",
         "gitbranchName",
         "showGitInactive",
         "showModeInactive":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateWorkSpaceTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "workSpaceLine":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateHighlightTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "reservedWord":
        if val.kind == TomlValueKind.Array:
          for key, val in val.getTable:
            if val.kind != TomlValueKind.String:
              return some(InvalidItem(name: $key, val: $val))
      of "currentLine",
         "fullWidthSpace",
         "trailingSpaces",
         "replaceText",
         "pairOfParen",
         "currentWord":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateAutoBackupTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable", "showMessages":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "idleTime",
         "interval":
        if val.kind != TomlValueKind.Int:
          return some(InvalidItem(name: $key, val: $val))
      of "backupDir":
        if val.kind != TomlValueKind.String:
          return some(InvalidItem(name: $key, val: $val))
      of "dirToExclude":
        if val.kind != TomlValueKind.Array:
          for item in val.getElems:
            if item.kind != TomlValueKind.String:
              return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateQuickRunTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "saveBufferWhenQuickRun":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "command",
         "nimAdvancedCommand",
         "clangOptions",
         "cppOptions",
         "nimOptions",
         "shOptions",
         "bashOptions":
        if val.kind != TomlValueKind.String:
          return some(InvalidItem(name: $key, val: $val))
      of "timeout":
        if val.kind != TomlValueKind.Int:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateNotificationTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "screenNotifications",
         "logNotifications",
         "autoBackupScreenNotify",
         "autoBackupLogNotify",
         "autoSaveScreenNotify",
         "autoSaveLogNotify",
         "yankScreenNotify",
         "yankLogNotify",
         "deleteScreenNotify",
         "deleteLogNotify",
         "saveScreenNotify",
         "saveLogNotify",
         "workspaceScreenNotify",
         "workspaceLogNotify",
         "quickRunScreenNotify",
         "quickRunLogNotify",
         "buildOnSaveScreenNotify",
         "buildOnSaveLogNotify",
         "filerScreenNotify",
         "filerLogNotify",
         "restoreScreenNotify",
         "restoreLogNotify":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateFilerTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "showIcons":
        if val.kind !=  TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateAutocompleteTable(table: TomlValueRef): Option[InvalidItem] =
    for key, val in table.getTable:
      case key:
        of "enable":
          if val.kind != TomlValueKind.Bool:
            return some(InvalidItem(name: $key, val: $val))
        else:
          return some(InvalidItem(name: $key, val: $val))

proc validatePersistTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "exCommand", "search", "cursorPosition":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "exCommandHistoryLimit", "searchHistoryLimit":
        if val.kind != TomlValueKind.Int:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateDebugTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "WorkSpace":
      # Check [Debug.WorkSpace]
        for key,val in table["WorkSpace"].getTable:
          case key:
            of "enable",
                "numOfWorkSpaces",
                "currentWorkSpaceIndex":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      # Check [Debug.WindowNode]
      of "WindowNode":
        for key, val in table["WindowNode"].getTable:
          case key:
            of "enable",
               "currentWindow",
               "index",
               "windowIndex",
               "bufferIndex",
               "parentIndex",
               "childLen",
               "splitType",
               "haveCursesWin",
               "y",
               "x",
               "h",
               "w",
               "currentLine",
               "currentColumn",
               "expandedColumn",
               "cursor":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      # Check [Debug.EditorView]
      of "EditorView":
        for key, val in table["EditorView"].getTable:
          case key:
            of "enable",
               "widthOfLineNum",
               "height",
               "width",
               "originalLine",
               "start",
               "length":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      # Check [Debug.BufferStatus]
      of "BufferStatus":
        for key, val in table["BufferStatus"].getTable:
          case key:
            of "enable",
               "bufferIndex",
               "path",
               "openDir",
               "currentMode",
               "prevMode",
               "language",
               "encoding",
               "countChange",
               "cmdLoop",
               "lastSaveTime",
               "bufferLen":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateThemeTable(table: TomlValueRef): Option[InvalidItem] =
  let editorColors = ColorThemeTable[ColorTheme.config]
  for key, val in table.getTable:
    case key:
      of "baseTheme":
        var correctKey = false
        for theme in ColorTheme:
          if $theme == val.getStr:
            correctKey = true
        if not correctKey: return some(InvalidItem(name: $key, val: $val))
      else:
        var correctKey = false
        for field in EditorColorIndex:
          if (key == "termDefautFg" or  key == "termDefautBg") and
             val.kind == TomlValueKind.String:
               correctKey = true
               break
          elif key == $field and val.kind == TomlValueKind.String:
            correctKey = true
            break
        if not correctKey:
          return some(InvalidItem(name: $key, val: $val))

proc validateGitTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "showChangedLine":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateSyntaxCheckerTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateTomlConfig(toml: TomlValueRef): Option[InvalidItem] =
  for key, val in toml.getTable:
    case key:
      of "Standard":
        let r = validateStandardTable(val)
        if r.isSome: return r
      of "Clipboard":
        let r = validateClipboardTable(val)
        if r.isSome: return r
      of "TabLine":
        let r = validateTabLineTable(val)
        if r.isSome: return r
      of "StatusLine":
        let r = validateStatusLineTable(val)
        if r.isSome: return r
      of "BuildOnSave":
        let r = validateBuildOnSaveTable(val)
        if r.isSome: return r
      of "WorkSpace":
        let r = validateWorkSpaceTable(val)
        if r.isSome: return r
      of "Highlight":
        let r = validateHighlightTable(val)
        if r.isSome: return r
      of "AutoBackup":
        let r = validateAutoBackupTable(val)
        if r.isSome: return r
      of "QuickRun":
        let r = validateQuickRunTable(val)
        if r.isSome: return r
      of "Notification":
        let r = validateNotificationTable(val)
        if r.isSome: return r
      of "Filer":
        let r = validateFilerTable(val)
        if r.isSome: return r
      of "Theme":
        let r = validateThemeTable(val)
        if r.isSome: return r
      of "Autocomplete":
        let r = validateAutocompleteTable(val)
        if r.isSome: return r
      of "Persist":
        let r = validatePersistTable(val)
        if r.isSome: return r
      of "Debug":
        let r = validateDebugTable(val)
        if r.isSome: return r
      of "Git":
        let r = validateGitTable(val)
        if r.isSome: return r
      of "SyntaxChecker":
        let r = validateSyntaxCheckerTable(val)
        if r.isSome: return r
      else:
        return some(InvalidItem(name: $key, val: $val))

proc toValidateErrorMessage(invalidItem: InvalidItem): string =
  # Remove '\n'
  let lines = invalidItem.val.splitLines

  var val = ""
  for i in 0 ..< lines.len:
    val &= lines[i]
    if i < lines.high - 1: val &= " "

  result = fmt"(name: {invalidItem.name}, val: {val})"

proc loadSettingFile*(): EditorSettings =
  let filename = getConfigDir() / "moe" / "moerc.toml"

  if not fileExists(filename):
    return initEditorSettings()

  let
    toml = parsetoml.parseFile(filename)
    invalidItem = toml.validateTomlConfig

  if invalidItem != none(InvalidItem):
    let errorMessage = toValidateErrorMessage(invalidItem.get)
    raise newException(InvalidItemError, $errorMessage)
  else:
    return parseSettingsFile(toml)

## Generate a string of the configuration file of TOML.
proc genTomlConfigStr*(settings: EditorSettings): string =
  proc addLine(buf: var string, str: string) {.inline.} = buf &= "\n" & str

  result = "[Standard]"
  result.addLine fmt "theme = \"{$settings.editorcolorTheme}\""
  result.addLine fmt "number = {$settings.view.lineNumber}"
  result.addLine fmt "currentNumber = {$settings.view.currentLineNumber}"
  result.addLine fmt "statusLine = {$settings.statusLine.enable}"
  result.addLine fmt "tabLine = {$settings.tabLine.enable}"
  result.addLine fmt "syntax = {$settings.syntax}"
  result.addLine fmt "indentationLines = {$settings.view.indentationLines}"
  result.addLine fmt "tabStop = {$settings.tabStop}"
  result.addLine fmt "sidebar = {$settings.view.sidebar}"
  result.addLine fmt "autoCloseParen = {$settings.autoCloseParen}"
  result.addLine fmt "autoIndent = {$settings.autoIndent}"
  result.addLine fmt "ignorecase = {$settings.ignorecase}"
  result.addLine fmt "smartcase = {$settings.smartcase}"
  result.addLine fmt "disableChangeCursor = {$settings.disableChangeCursor}"
  result.addLine fmt "defaultCursor = \"{$settings.defaultCursor}\""
  result.addLine fmt "normalModeCursor = \"{$settings.normalModeCursor}\""
  result.addLine fmt "insertModeCursor = \"{$settings.insertModeCursor}\""
  result.addLine fmt "autoSave = {$settings.autoSave}"
  result.addLine fmt "autoSaveInterval = {$settings.autoSaveInterval}"
  result.addLine fmt "liveReloadOfConf = {$settings.liveReloadOfConf}"
  result.addLine fmt "incrementalSearch = {$settings.incrementalSearch}"
  result.addLine fmt "popupWindowInExmode = {$settings.popupWindowInExmode}"
  result.addLine fmt "autoDeleteParen = {$settings.autoDeleteParen }"
  result.addLine fmt "smoothScroll = {$settings.smoothScroll }"
  result.addLine fmt "smoothScrollSpeed = {$settings.smoothScrollSpeed}"
  result.addLine fmt "liveReloadOfFile = {$settings.liveReloadOfFile}"

  result.addLine ""

  result.addLine fmt "[Clipboard]"
  result.addLine fmt "enable = {$settings.clipboard.enable}"
  result.addLine fmt "toolOnLinux = \"{$settings.clipboard.toolOnLinux}\""

  result.addLine ""

  result.addLine fmt "[BuildOnSave]"
  result.addLine fmt "enable = {$settings.buildOnSave.enable}"
  if settings.buildOnSave.workspaceRoot.len > 0:
    result.addLine fmt "workspaceRoot = {$settings.buildOnSave.workspaceRoot}"
  if settings.buildOnSave.command.len > 0:
    result.addLine fmt "command = {$settings.buildOnSave.command}"

  result.addLine ""

  result.addLine fmt "[TabLine]"
  result.addLine fmt "allBuffer = {$settings.tabLine.allbuffer}"

  result.addLine ""

  result.addLine fmt "[StatusLine]"
  result.addLine fmt "multipleStatusLine = {$settings.statusLine.multipleStatusLine}"
  result.addLine fmt "merge = {$settings.statusLine.merge }"
  result.addLine fmt "mode = {$settings.statusLine.mode }"
  result.addLine fmt "filename = {$settings.statusLine.filename}"
  result.addLine fmt "chanedMark = {$settings.statusLine.chanedMark}"
  result.addLine fmt "line = {$settings.statusLine.line}"
  result.addLine fmt "column = {$settings.statusLine.column}"
  result.addLine fmt "encoding = {$settings.statusLine.characterEncoding}"
  result.addLine fmt "language = {$settings.statusLine.language}"
  result.addLine fmt "directory = {$settings.statusLine.directory}"
  result.addLine fmt "gitbranchName = {$settings.statusLine.gitbranchName}"
  result.addLine fmt "showGitInactive = {$settings.statusLine.showGitInactive}"
  result.addLine fmt "showModeInactive = {$settings.statusLine.showModeInactive}"

  result.addLine ""

  result.addLine fmt "[Highlight]"
  result.addLine fmt "currentLine = {$settings.view.highlightCurrentLine}"
  if settings.highlight.reservedWords.len > 0:
    result.addLine "reservedWord = ["
    for index, reservedWord in settings.highlight.reservedWords:
      if index > 0: result.add ", "
      result.add fmt "\"{reservedWord.word}\""
    result.add "]"
  result.addLine fmt "replaceText = {$settings.highlight.replaceText }"
  result.addLine fmt "pairOfParen = {$settings.highlight.pairOfParen }"
  result.addLine fmt "fullWidthSpace = {$settings.highlight.fullWidthSpace}"
  result.addLine fmt "trailingSpaces = {$settings.highlight.trailingSpaces }"
  result.addLine fmt "currentWord = {$settings.highlight.currentWord}"

  result.addLine ""

  result.addLine fmt "[AutoBackup]"
  result.addLine fmt "enable = {$settings.autoBackup.enable }"
  result.addLine fmt "idleTime = {$settings.autoBackup.idleTime }"
  result.addLine fmt "interval = {$settings.autoBackup.interval }"
  if settings.autoBackup.dirToExclude.len > 0:
    result.addLine "dirToExclude = ["
    for index, dir in settings.autoBackup.dirToExclude:
      if index > 0: result.add ", "
      result.add fmt "\"{$dir}\""
    result.add "]"

  result.addLine ""

  result.addLine fmt "[QuickRun]"
  result.addLine fmt "saveBufferWhenQuickRun = {$settings.quickRun.saveBufferWhenQuickRun}"
  if settings.quickRun.command.len > 0:
    result.addLine fmt "command = {$settings.quickRun.command}"
  result.addLine fmt "timeout = {$settings.quickRun.timeout }"
  if settings.quickRun.nimAdvancedCommand .len > 0:
    result.addLine fmt "nimAdvancedCommand = \"{$settings.quickRun.nimAdvancedCommand}\""
  if settings.quickRun.clangOptions.len > 0:
    result.addLine fmt "clangOptions = \"{$settings.quickRun.clangOptions}\""
  if settings.quickRun.cppOptions.len > 0:
    result.addLine fmt "cppOptions = \"{$settings.quickRun.cppOptions}\""
  if settings.quickRun.nimOptions.len > 0:
    result.addLine fmt "nimOptions = \"{$settings.quickRun.nimOptions}\""
  if settings.quickRun.shOptions.len > 0:
    result.addLine fmt "shOptions = \"{$settings.quickRun.shOptions}\""
  if settings.quickRun.bashOptions.len > 0:
    result.addLine fmt "shOptions = \"{$settings.quickRun.bashOptions}\""

  result.addLine ""

  result.addLine fmt "[Notification]"
  result.addLine fmt "screenNotifications = {$settings.notification.screenNotifications }"
  result.addLine fmt "logNotifications = {$settings.notification.logNotifications }"
  result.addLine fmt "autoBackupScreenNotify = {$settings.notification.autoBackupScreenNotify}"
  result.addLine fmt "autoBackupLogNotify = {$settings.notification.autoBackupLogNotify}"
  result.addLine fmt "autoSaveScreenNotify = {$settings.notification.autoSaveScreenNotify}"
  result.addLine fmt "autoSaveLogNotify = {$settings.notification.autoSaveLogNotify}"
  result.addLine fmt "yankScreenNotify = {$settings.notification.yankScreenNotify}"
  result.addLine fmt "yankLogNotify = {$settings.notification.yankLogNotify}"
  result.addLine fmt "deleteScreenNotify = {$settings.notification.deleteScreenNotify}"
  result.addLine fmt "deleteLogNotify = {$settings.notification.deleteLogNotify}"
  result.addLine fmt "saveScreenNotify = {$settings.notification.saveScreenNotify}"
  result.addLine fmt "saveLogNotify = {$settings.notification.saveLogNotify}"
  result.addLine fmt "quickRunScreenNotify = {$settings.notification.quickRunScreenNotify}"
  result.addLine fmt "quickRunLogNotify  = {$settings.notification.quickRunLogNotify}"
  result.addLine fmt "buildOnSaveScreenNotify = {$settings.notification.buildOnSaveScreenNotify}"
  result.addLine fmt "buildOnSaveLogNotify = {$settings.notification.buildOnSaveLogNotify}"
  result.addLine fmt "filerScreenNotify = {$settings.notification.filerScreenNotify}"
  result.addLine fmt "filerLogNotify = {$settings.notification.filerLogNotify}"
  result.addLine fmt "restoreScreenNotify = {$settings.notification.restoreScreenNotify}"
  result.addLine fmt "restoreLogNotify = {$settings.notification.restoreLogNotify}"

  result.addLine ""

  result.addLine fmt "[Filer]"
  result.addLine fmt "showIcons = {$settings.filer.showIcons}"

  result.addLine ""

  result.addLine fmt "[Autocomplete]"
  result.addLine fmt "enable = {$settings.autocomplete.enable}"

  result.addLine ""

  result.addLine fmt "[Persist]"
  result.addLine fmt "exCommand = {$settings.persist.exCommand}"
  result.addLine fmt "exCommandHistoryLimit = {$settings.persist.exCommandHistoryLimit}"
  result.addLine fmt "search = {$settings.persist.search}"
  result.addLine fmt "searchHistoryLimit = {$settings.persist.searchHistoryLimit}"
  result.addLine fmt "cursorPosition = {$settings.persist.cursorPosition}"

  result.addLine ""

  result.addLine fmt "[Git]"
  result.addLine fmt "showChangedLine = {$settings.git.showChangedLine}"

  result.addLine ""

  result.addLine fmt "[SyntaxChecker]"
  result.addLine fmt "enable = {$settings.syntaxChecker.enable}"

  result.addLine ""

  result.addLine fmt "[Debug.WindowNode]"
  result.addLine fmt "enable = {$settings.debugMode.windowNode.enable}"
  result.addLine fmt "currentWindow = {$settings.debugMode.windowNode.currentWindow}"
  result.addLine fmt "index = {$settings.debugMode.windowNode.index}"
  result.addLine fmt "windowIndex = {$settings.debugMode.windowNode.windowIndex}"
  result.addLine fmt "bufferIndex= {$settings.debugMode.windowNode.bufferIndex}"
  result.addLine fmt "parentIndex= {$settings.debugMode.windowNode.parentIndex}"
  result.addLine fmt "childLen = {$settings.debugMode.windowNode.childLen}"
  result.addLine fmt "splitType = {$settings.debugMode.windowNode.splitType}"
  result.addLine fmt "haveCursesWin= {$settings.debugMode.windowNode.haveCursesWin}"
  result.addLine fmt "y = {$settings.debugMode.windowNode.y}"
  result.addLine fmt "x = {$settings.debugMode.windowNode.x}"
  result.addLine fmt "h = {$settings.debugMode.windowNode.h}"
  result.addLine fmt "w = {$settings.debugMode.windowNode.w}"
  result.addLine fmt "currentLine = {$settings.debugMode.windowNode.currentLine}"
  result.addLine fmt "currentColumn = {$settings.debugMode.windowNode.currentColumn}"
  result.addLine fmt "expandedColumn = {$settings.debugMode.windowNode.expandedColumn}"
  result.addLine fmt "cursor = {$settings.debugMode.windowNode.cursor}"

  result.addLine ""

  result.addLine fmt "[Debug.EditorView]"
  result.addLine fmt "enable = {$settings.debugMode.editorview.enable}"
  result.addLine fmt "widthOfLineNum = {$settings.debugMode.editorview.widthOfLineNum}"
  result.addLine fmt "height = {$settings.debugMode.editorview.height}"
  result.addLine fmt "width = {$settings.debugMode.editorview.width}"
  result.addLine fmt "originalLine = {$settings.debugMode.editorview.originalLine}"
  result.addLine fmt "start = {$settings.debugMode.editorview.start}"
  result.addLine fmt "length = {$settings.debugMode.editorview.length}"

  result.addLine fmt "[Debug.BufferStatus]"
  result.addLine fmt "enable = {$settings.debugMode.bufStatus.enable}"
  result.addLine fmt "bufferIndex = {$settings.debugMode.bufStatus.bufferIndex }"
  result.addLine fmt "path = {$settings.debugMode.bufStatus.path}"
  result.addLine fmt "openDir = {$settings.debugMode.bufStatus.openDir}"
  result.addLine fmt "currentMode = {$settings.debugMode.bufStatus.currentMode}"
  result.addLine fmt "prevMode = {$settings.debugMode.bufStatus.prevMode}"
  result.addLine fmt "language = {$settings.debugMode.bufStatus.language}"
  result.addLine fmt "encoding = {$settings.debugMode.bufStatus.encoding}"
  result.addLine fmt "countChange = {$settings.debugMode.bufStatus.countChange}"
  result.addLine fmt "cmdLoop = {$settings.debugMode.bufStatus.cmdLoop}"
  result.addLine fmt "lastSaveTime = {$settings.debugMode.bufStatus.lastSaveTime}"
  result.addLine fmt "bufferLen = {$settings.debugMode.bufStatus.bufferLen}"

  result.addLine ""

  proc fgColor(t: ColorTheme, index: EditorColorPairIndex): string =
    let hexColor = t.foregroundRgb(index).toHex
    if hexColor.isSome: return hexColor.get
    else: "termDefautFg"

  proc bgColor(t: ColorTheme, index: EditorColorPairIndex): string =
    let hexColor = t.backgroundRgb(index).toHex
    if hexColor.isSome: return hexColor.get
    else: "termDefautBg"

  let theme = settings.editorcolorTheme
  result.addLine fmt "[Theme]"
  result.addLine fmt "baseTheme = \"{$theme}\""
  result.addLine fmt "foreground = \"{theme.fgColor(EditorColorPairIndex.default)}\""
  result.addLine fmt "background = \"{theme.bgColor(EditorColorPairIndex.default)}\""
  result.addLine fmt "lineNum = \"{theme.fgColor(EditorColorPairIndex.lineNum)}\""
  result.addLine fmt "lineNumBg = \"{theme.bgColor(EditorColorPairIndex.lineNum)}\""
  result.addLine fmt "currentLineNum = \"{theme.fgColor(EditorColorPairIndex.currentLineNum)}\""
  result.addLine fmt "currentLineNumBg = \"{theme.bgColor(EditorColorPairIndex.currentLineNum)}\""
  result.addLine fmt "statusLineNormalMode = \"{theme.fgColor(EditorColorPairIndex.statusLineNormalMode)}\""
  result.addLine fmt "statusLineNormalModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineNormalMode)}\""
  result.addLine fmt "statusLineModeNormalMode = \"{theme.fgColor(EditorColorPairIndex.statusLineNormalMode)}\""
  result.addLine fmt "statusLineModeNormalModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineNormalMode)}\""
  result.addLine fmt "statusLineNormalModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineNormalModeInactive)}\""
  result.addLine fmt "statusLineNormalModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineNormalModeInactive)}\""
  result.addLine fmt "statusLineInsertMode = \"{theme.fgColor(EditorColorPairIndex.statusLineInsertMode)}\""
  result.addLine fmt "statusLineInsertModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineInsertMode)}\""
  result.addLine fmt "statusLineModeInsertMode = \"{theme.fgColor(EditorColorPairIndex.statusLineModeInsertMode)}\""
  result.addLine fmt "statusLineModeInsertModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineModeInsertMode)}\""
  result.addLine fmt "statusLineInsertModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineInsertModeInactive)}\""
  result.addLine fmt "statusLineInsertModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineInsertModeInactive)}\""
  result.addLine fmt "statusLineVisualMode = \"{theme.fgColor(EditorColorPairIndex.statusLineVisualMode)}\""
  result.addLine fmt "statusLineVisualModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineVisualMode)}\""
  result.addLine fmt "statusLineModeVisualMode = \"{theme.bgColor(EditorColorPairIndex.statusLineModeVisualMode)}\""
  result.addLine fmt "statusLineModeVisualModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineModeVisualMode)}\""
  result.addLine fmt "statusLineVisualModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineVisualModeInactive)}\""
  result.addLine fmt "statusLineVisualModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineVisualModeInactive)}\""
  result.addLine fmt "statusLineReplaceMode = \"{theme.fgColor(EditorColorPairIndex.statusLineReplaceMode)}\""
  result.addLine fmt "statusLineReplaceModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineReplaceMode)}\""
  result.addLine fmt "statusLineModeReplaceMode = \"{theme.fgColor(EditorColorPairIndex.statusLineModeReplaceMode)}\""
  result.addLine fmt "statusLineModeReplaceModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineModeReplaceMode)}\""
  result.addLine fmt "statusLineReplaceModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineReplaceModeInactive)}\""
  result.addLine fmt "statusLineReplaceModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineReplaceModeInactive)}\""
  result.addLine fmt "statusLineFilerMode = \"{theme.fgColor(EditorColorPairIndex.statusLineFilerMode)}\""
  result.addLine fmt "statusLineFilerModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineFilerMode)}\""
  result.addLine fmt "statusLineModeFilerMode = \"{theme.fgColor(EditorColorPairIndex.statusLineModeFilerMode)}\""
  result.addLine fmt "statusLineModeFilerModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineModeFilerMode)}\""
  result.addLine fmt "statusLineFilerModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineFilerModeInactive)}\""
  result.addLine fmt "statusLineFilerModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineFilerModeInactive)}\""
  result.addLine fmt "statusLineExMode = \"{theme.fgColor(EditorColorPairIndex.statusLineExMode)}\""
  result.addLine fmt "statusLineExModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineExMode)}\""
  result.addLine fmt "statusLineModeExMode = \"{theme.fgColor(EditorColorPairIndex.statusLineModeExMode)}\""
  result.addLine fmt "statusLineModeExModeBg = \"{theme.bgColor(EditorColorPairIndex.statusLineModeExMode)}\""
  result.addLine fmt "statusLineExModeInactive = \"{theme.fgColor(EditorColorPairIndex.statusLineExModeInactive)}\""
  result.addLine fmt "statusLineExModeInactiveBg = \"{theme.bgColor(EditorColorPairIndex.statusLineExModeInactive)}\""
  result.addLine fmt "statusLineGitBranch = \"{theme.fgColor(EditorColorPairIndex.statusLineGitBranch)}\""
  result.addLine fmt "statusLineGitBranchBg = \"{theme.bgColor(EditorColorPairIndex.statusLineGitBranch)}\""
  result.addLine fmt "tab = \"{theme.fgColor(EditorColorPairIndex.tab)}\""
  result.addLine fmt "tabBg = \"{theme.bgColor(EditorColorPairIndex.tab)}\""
  result.addLine fmt "currentTab = \"{theme.fgColor(EditorColorPairIndex.currentTab)}\""
  result.addLine fmt "currentTabBg = \"{theme.bgColor(EditorColorPairIndex.currentTab)}\""
  result.addLine fmt "commandLine = \"{theme.fgColor(EditorColorPairIndex.commandLine)}\""
  result.addLine fmt "commandLineBg = \"{theme.bgColor(EditorColorPairIndex.commandLine)}\""
  result.addLine fmt "errorMessage = \"{theme.fgColor(EditorColorPairIndex.errorMessage)}\""
  result.addLine fmt "errorMessageBg = \"{theme.bgColor(EditorColorPairIndex.errorMessage)}\""
  result.addLine fmt "searchResult = \"{theme.fgColor(EditorColorPairIndex.searchResult)}\""
  result.addLine fmt "searchResultBg = \"{theme.bgColor(EditorColorPairIndex.searchResult)}\""
  result.addLine fmt "visualMode = \"{theme.fgColor(EditorColorPairIndex.visualMode)}\""
  result.addLine fmt "visualModeBg = \"{theme.bgColor(EditorColorPairIndex.visualMode)}\""
  result.addLine fmt "keyword = \"{theme.fgColor(EditorColorPairIndex.keyword)}\""
  result.addLine fmt "functionName = \"{theme.fgColor(EditorColorPairIndex.functionName)}\""
  result.addLine fmt "typeName= \"{theme.fgColor(EditorColorPairIndex.typeName)}\""
  result.addLine fmt "boolean = \"{theme.fgColor(EditorColorPairIndex.boolean)}\""
  result.addLine fmt "stringLit = \"{theme.fgColor(EditorColorPairIndex.stringLit)}\""
  result.addLine fmt "specialVar = \"{theme.fgColor(EditorColorPairIndex.specialVar)}\""
  result.addLine fmt "builtin = \"{theme.fgColor(EditorColorPairIndex.builtin)}\""
  result.addLine fmt "binNumber = \"{theme.fgColor(EditorColorPairIndex.binNumber)}\""
  result.addLine fmt "decNumber = \"{theme.fgColor(EditorColorPairIndex.decNumber)}\""
  result.addLine fmt "floatNumber = \"{theme.fgColor(EditorColorPairIndex.floatNumber)}\""
  result.addLine fmt "hexNumber = \"{theme.fgColor(EditorColorPairIndex.hexNumber)}\""
  result.addLine fmt "octNumber = \"{theme.fgColor(EditorColorPairIndex.octNumber)}\""
  result.addLine fmt "comment = \"{theme.fgColor(EditorColorPairIndex.comment)}\""
  result.addLine fmt "longComment = \"{theme.fgColor(EditorColorPairIndex.longComment)}\""
  result.addLine fmt "whitespace = \"{theme.fgColor(EditorColorPairIndex.whitespace)}\""
  result.addLine fmt "preprocessor = \"{theme.fgColor(EditorColorPairIndex.preprocessor)}\""
  result.addLine fmt "currentFile = \"{theme.fgColor(EditorColorPairIndex.currentFile)}\""
  result.addLine fmt "currentFileBg = \"{theme.fgColor(EditorColorPairIndex.currentFile)}\""
  result.addLine fmt "file = \"{theme.fgColor(EditorColorPairIndex.file)}\""
  result.addLine fmt "fileBg = \"{theme.bgColor(EditorColorPairIndex.file)}\""
  result.addLine fmt "dir = \"{theme.fgColor(EditorColorPairIndex.dir)}\""
  result.addLine fmt "dirBg = \"{theme.bgColor(EditorColorPairIndex.dir)}\""
  result.addLine fmt "pcLink = \"{theme.fgColor(EditorColorPairIndex.pcLink)}\""
  result.addLine fmt "pcLinkBg = \"{theme.bgColor(EditorColorPairIndex.pcLink)}\""
  result.addLine fmt "popupWindow = \"{theme.fgColor(EditorColorPairIndex.popupWindow)}\""
  result.addLine fmt "popupWindowBg = \"{theme.bgColor(EditorColorPairIndex.popupWindow)}\""
  result.addLine fmt "popupWinCurrentLine = \"{theme.fgColor(EditorColorPairIndex.popupWinCurrentLine)}\""
  result.addLine fmt "popupWinCurrentLineBg = \"{theme.bgColor(EditorColorPairIndex.popupWinCurrentLine)}\""
  result.addLine fmt "replaceText = \"{theme.fgColor(EditorColorPairIndex.replaceText)}\""
  result.addLine fmt "replaceTextBg = \"{theme.bgColor(EditorColorPairIndex.replaceText)}\""
  result.addLine fmt "parenPair = \"{theme.fgColor(EditorColorPairIndex.parenPair)}\""
  result.addLine fmt "parenPairBg = \"{theme.bgColor(EditorColorPairIndex.parenPair)}\""
  result.addLine fmt "currentWord = \"{theme.fgColor(EditorColorPairIndex.currentWord)}\""
  result.addLine fmt "currentWordBg = \"{theme.bgColor(EditorColorPairIndex.currentFile)}\""
  result.addLine fmt "highlightFullWidthSpace = \"{theme.fgColor(EditorColorPairIndex.highlightFullWidthSpace)}\""
  result.addLine fmt "highlightFullWidthSpaceBg = \"{theme.bgColor(EditorColorPairIndex.highlightFullWidthSpace)}\""
  result.addLine fmt "highlightTrailingSpaces = \"{theme.fgColor(EditorColorPairIndex.highlightTrailingSpaces)}\""
  result.addLine fmt "highlightTrailingSpacesBg = \"{theme.bgColor(EditorColorPairIndex.highlightTrailingSpaces)}\""
  result.addLine fmt "reservedWord = \"{theme.fgColor(EditorColorPairIndex.reservedWord)}\""
  result.addLine fmt "reservedWordBg = \"{theme.bgColor(EditorColorPairIndex.reservedWord)}\""
  result.addLine fmt "configModeCurrentLine = \"{theme.fgColor(EditorColorPairIndex.configModeCurrentLine)}\""
  result.addLine fmt "configModeCurrentLineBg = \"{theme.bgColor(EditorColorPairIndex.configModeCurrentLine)}\""
  result.addLine fmt "currentLineBg = \"{theme.bgColor(EditorColorPairIndex.currentLineBg)}\""

# Generate a string of the default TOML configuration.
proc genDefaultTomlConfigStr*(): string {.inline.} =
  initEditorSettings().genTomlConfigStr
