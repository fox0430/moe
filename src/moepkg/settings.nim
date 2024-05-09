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

import std/[os, json, options, strformat, osproc, strutils, sequtils, enumutils,
            tables]
import pkg/[parsetoml, results, regex]
import lsp/[protocol/enums, utils]
import ui, color, unicodeext, highlight, platform, rgb, theme

export TomlError

type
  VsCodeFlavor = enum
    # CodeOss is an Official Arch Linux open-source release.
    # https://archlinux.org/packages/?name=code
    CodeOss
    VSCodium
    VSCode

  ClipboardTool* = enum
    xsel
    xclip
    wlClipboard
    wslDefault # powershell.exe/clip.ext
    macOsDefault # pbcopy/pbpaste

  WindowSplitType* {.pure.} = enum
    vertical
    horizontal

  ColorThemeKind* {.pure.} = enum
    default
    vscode
    config

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
    workspaceRoot*: Runes
    command*: Runes

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
    backupDir*: Runes
    dirToExclude*: seq[Runes]

  FilerSettings* = object
    showIcons*: bool

  StatusLineItem* = enum
    lineNumber
    lineInPercent
    totalLines
    columnNumber
    columnInPercent
    totalColumns
    encoding
    fileType
    fileTypeIcon

  StatusLineSettings* = object
    enable*: bool
    merge*: bool
    mode*: bool
    filename*: bool
    chanedMark*: bool
    directory*: bool
    multipleStatusLine*: bool
    gitChangedLines*: bool
    gitBranchName*: bool
    showGitInactive*: bool
    showModeInactive*: bool
    setupText*: Runes

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

  AutoSaveSettings* = object
    enable*: bool
    interval*: int # minutes

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
    tool*: ClipboardTool

  GitSettings* = object
    showChangedLine*: bool
    updateInterval*: int

  SyntaxCheckerSettings* = object
    enable*: bool

  SmoothScrollSettings* = object
    enable*: bool
    minDelay*: int
    maxDelay*: int

  StartUpFileOpenSettings* = object
    autoSplit*: bool
    splitType*: WindowSplitType

  StartUpSettings* = object
    fileOpen*: StartUpFileOpenSettings

  ThemeSettings* = object
    kind*: ColorThemeKind
    path*: string
    colors*: ThemeColors

  LspLanguageSettings* = object
    extensions*: seq[Runes]
    command*: Runes
    trace*: TraceValue

  LspCompletionSettings* = object
    enable*: bool

  LspDefinitionSettings* = object
    enable*: bool

  LspDiagnosticsSettings* = object
    enable*: bool

  LspHoverSettings* = object
    enable*: bool

  LspInlayHintSettings* = object
    enable*: bool

  LspSemanticTokesnSettings* = object
    enable*: bool

  LspFeatureSettings* = object
    completion*: LspCompletionSettings
    definition*: LspDefinitionSettings
    diagnostics*: LspDiagnosticsSettings
    hover*: LspHoverSettings
    inlayHint*: LspInlayHintSettings
    semanticTokens*: LspSemanticTokesnSettings

  LspSettings* = object
    enable*: bool
    languages*: Table[LanguageId, LspLanguageSettings]
    features*: LspFeatureSettings

  StandardSettings* = object
    syntax*: bool
    disableChangeCursor*: bool
    defaultCursor*: CursorType
    normalModeCursor*: CursorType
    insertModeCursor*: CursorType
    ignorecase*: bool
    smartcase*: bool
    tabStop*: int
    autoCloseParen*: bool
    autoIndent*: bool
    liveReloadOfConf*: bool
    incrementalSearch*: bool
    popupWindowInExmode*: bool
    autoDeleteParen*: bool
    liveReloadOfFile*: bool
    colorMode*: ColorMode

  EditorSettings* = object
    standard*: StandardSettings
    statusLine*: StatusLineSettings
    tabLine*: TabLineSettings
    view*: EditorViewSettings
    smoothScroll*: SmoothScrollSettings
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
    startUp*: StartUpSettings
    autoSave*: AutoSaveSettings
    theme*: ThemeSettings
    lsp*: LspSettings

  InvalidItem = object
    name: string
    val: string

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

proc initAutoSaveSettings(): AutoSaveSettings {.inline.} =
  result.enable = true
  result.interval = 5 # 5 minutes

proc initTabBarSettings*(): TabLineSettings {.inline.} =
  result.enable = true

proc initStatusLineSettings*(): StatusLineSettings =
  result.enable = true
  result.mode = true
  result.filename = true
  result.chanedMark = true
  result.directory = true
  result.multipleStatusLine = true
  result.gitChangedLines = true
  result.gitBranchName = true
  result.setupText =
    ru"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"

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

proc detectClipboardTool(): Option[ClipboardTool] =
  ## Automatically set the clipboard tool for your environment.
  ##
  ## X11: xsel or xclip
  ## Wayland: wl-clipboard
  ## macOS: pbcopy/pbpaste
  ## WSL: clip.exe/powershell.exe

  proc isXsel(): bool {.inline.} = execCmdEx("xsel --version").exitCode == 0

  proc isXclip(): bool =
    if execCmdEx("xclip -version").exitCode == 0:
      let (output, _) = execCmdEx("xclip -version")
      # Check xclip version. Need 0.13 or higher.
      let
        lines = output.splitLines
        versionStr = (strutils.splitWhitespace(lines[0]))[2]
      return parseFloat(versionStr) >= 0.13

  case getGuiEnv():
    of Gui.x11:
      # X11 on UNIX system.
      if isXsel():
        return some(ClipboardTool.xsel)
      elif isXclip():
        return some(ClipboardTool.xclip)
    of Gui.wayland:
      # Wayland on UNIX system.
      return some(ClipboardTool.wlClipboard)
    of Gui.other:
      if getPlatform() == mac:
        # macOS
        return some(macOsDefault)
      elif getPlatform() == wsl:
        return some(wslDefault)
    of Gui.console:
      return none(ClipboardTool)

proc initClipboardSettings(): ClipboardSettings =
  let tool = detectClipboardTool()
  if tool.isSome:
    result.tool = tool.get
    result.enable = true

proc initGitSettings(): GitSettings =
  result.showChangedLine = true
  result.updateInterval = 1000 # Milli seconds

proc initSyntaxCheckerSettings(): SyntaxCheckerSettings =
  result.enable = false

proc initSmoothScrollSettings(): SmoothScrollSettings =
  result.enable = true
  result.minDelay = 5
  result.maxDelay = 20

proc initStartUpFileOpenSettings(): StartUpFileOpenSettings =
  result.autoSplit = true
  result.splitType = WindowSplitType.vertical

proc initStartUpSettings(): StartUpSettings =
  result.fileOpen = initStartUpFileOpenSettings()

proc initThemeSettings(): ThemeSettings =
  result.kind = ColorThemeKind.default
  result.colors = DefaultColors

proc initLspCompletionSettings(): LspCompletionSettings =
  result.enable = true

proc initLspDefinitionSettings(): LspDefinitionSettings =
  result.enable = true

proc initLspDiagnosticsSettings(): LspDiagnosticsSettings =
  result.enable = true

proc initLspHoverSettings(): LspHoverSettings =
  result.enable = true

proc initLspInlayHintSettings(): LspInlayHintSettings =
  result.enable = true

proc initLspSemanticTokesnSettings(): LspSemanticTokesnSettings =
  result.enable = true

proc initLspFeatureSettings(): LspFeatureSettings =
  result.completion = initLspCompletionSettings()
  result.definition = initLspDefinitionSettings()
  result.diagnostics = initLspDiagnosticsSettings()
  result.hover = initLspHoverSettings()
  result.inlayHint = initLspInlayHintSettings()
  result.semanticTokens = initLspSemanticTokesnSettings()

proc initLspSettigns(): LspSettings =
  result.enable = true

  result.features = initLspFeatureSettings()

  result.languages["nim"] = LspLanguageSettings(
    extensions: @[ru"nim"],
    command: ru"nimlangserver",
    trace: TraceValue.verbose)

  result.languages["rust"] = LspLanguageSettings(
    extensions: @[ru"rs"],
    command: ru"rust-analyzer",
    trace: TraceValue.verbose)

proc initStandardSettings(): StandardSettings =
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.ignorecase = true
  result.smartcase = true
  result.defaultCursor = CursorType.terminalDefault
  result.normalModeCursor = CursorType.blinkBlock
  result.insertModeCursor = CursorType.blinkIbeam
  result.incrementalSearch = true
  result.popupWindowInExmode = true
  result.colorMode = checkColorSupportedTerminal()

proc initEditorSettings*(): EditorSettings =
  result.standard = initStandardSettings()
  result.statusLine = initStatusLineSettings()
  result.tabLine = initTabBarSettings()
  result.view = initEditorViewSettings()
  result.smoothScroll = initSmoothScrollSettings()
  result.clipboard = initClipboardSettings()
  result.buildOnSave = BuildOnSaveSettings()
  result.filer = initFilerSettings()
  result.autocomplete = initAutocompleteSettings()
  result.autoSave = initAutoSaveSettings()
  result.autoBackup = initAutoBackupSettings()
  result.quickRun = initQuickRunSettings()
  result.notification = initNotificationSettings()
  result.debugMode = initDebugModeSettings()
  result.highlight = initHighlightSettings()
  result.persist = initPersistSettings()
  result.git = initGitSettings()
  result.syntaxChecker = initSyntaxCheckerSettings()
  result.startUp = initStartUpSettings()
  result.theme = initThemeSettings()
  result.lsp = initLspSettigns()

proc configFilePath*():  string {.inline.} =
  getConfigDir() / "moe" / "moerc.toml"

proc langIdFromLspSettings*(s: LspSettings, ext: Runes): Option[LanguageId] =
  ## Return a languageId if it exists from status.settings.lsp.languages.

  for key, val in s.languages.pairs:
    if val.extensions.contains(ext):
      return some(key)

proc colorFromNode(node: JsonNode): Rgb =
  if node == nil:
    return TerminalDefaultRgb

  var asString = node.getStr
  if asString.len >= 7 and asString[0] == '#':
    # Indexes above 6 are cut.
    return asString[1 .. 6].hexToRgb.get
  else:
    return TerminalDefaultRgb

proc parseWindowSplitType*(s: string): Result[WindowSplitType, string] =
  try:
    return Result[WindowSplitType, string].ok parseEnum[WindowSplitType](s)
  except ValueError:
    return Result[WindowSplitType, string].err "Invalid value"

proc makeColorThemeFromVSCodeThemeFile(jsonNode: JsonNode): ThemeColors =
  # Load the theme file of VSCode and adapt it as the theme of moe.
  # Reproduce the original theme as much as possible.

  # The base theme is the default theme.
  result = DefaultColors

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

    result[EditorColorPairIndex.selectArea].foreground.rgb =
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

    result[EditorColorPairIndex.statusLineNormalModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineNormalModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineInsertModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineVisualMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineVisualModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineVisualModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineReplaceMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineReplaceModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineReplaceModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineFilerMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineFilerModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineFilerModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineExMode].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineExModeLabel].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineExModeInactive].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineGitChangedLines].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

    result[EditorColorPairIndex.statusLineGitBranch].foreground.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.foreground"})

  if jsonNode["colors"].contains("statusBar.background"):
    result[EditorColorPairIndex.statusLineNormalMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineNormalModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineNormalModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineInsertModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineVisualMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineVisualModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineVisualModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineReplaceMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineReplaceModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineReplaceModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineFilerMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineFilerModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineFilerModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineExMode].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineExModeLabel].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineExModeInactive].background.rgb =
      colorFromNode(jsonNode{"colors", "statusBar.background"})

    result[EditorColorPairIndex.statusLineGitChangedLines].background.rgb =
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

    result[EditorColorPairIndex.selectArea].background.rgb =
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
  ## Check settings dirs in the following order.
  ## vscodium -> code-oss -> vscode

  if fileExists(vsCodiumUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCodium)
  elif fileExists(codeOssUserSettingsFilePath()):
    return some(VsCodeFlavor.CodeOss)
  elif fileExists(vsCodeUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCode)

proc isCurrentVsCodeThemePackage(json: JsonNode, themeName: string): bool =
  ## Return true if `json` is the current VSCode theme.

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

proc loadVSCodeTheme*(): Result[ThemeColors, string] =
  ## If no vscode theme can be found, this defaults to the dark theme.
  ## Hopefully other contributors will come and add support for Windows,
  ## and other systems.

  let vsCodeFlavor = detectVsCodeFlavor()
  if vsCodeFlavor.isNone:
    return Result[ThemeColors, string].err "Failed to load VSCode theme: Could not find VSCode"

  let
    # load the VSCode user settings json
    settingsFilePath = vsCodeSettingsFilePath(vsCodeFlavor.get)
    settingsJson =
      try:
        json.parseFile(settingsFilePath)
      except CatchableError as e:
        return Result[ThemeColors, string].err fmt"Failed to load VSCode theme: {e.msg}"

  # The current theme name
  if settingsJson{"workbench.colorTheme"} == nil or
     settingsJson{"workbench.colorTheme"}.getStr == "":
       return Result[ThemeColors, string].err "Failed to load VSCode theme: Failed to get the current theme"

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
            let colors = makecolorThemeFromVSCodeThemeFile(themeJson.get)
            return Result[ThemeColors, string].ok colors

  return Result[ThemeColors, string].err "Failed to load VSCode theme: Could not find files for the current theme"

proc parseStandardTable(s: var EditorSettings, standardConfigs: TomlValueRef) =
  template cursorType(str: string): CursorType =
    parseEnum[CursorType](str)

  if standardConfigs.contains("number"):
    s.view.lineNumber = standardConfigs["number"].getBool

  if standardConfigs.contains("currentNumber"):
    s.view.currentLineNumber = standardConfigs["currentNumber"].getBool

  if standardConfigs.contains("cursorLine"):
    s.view.cursorLine = standardConfigs["cursorLine"].getBool

  if standardConfigs.contains("statusLine"):
    s.statusLine.enable = standardConfigs["statusLine"].getBool

  if standardConfigs.contains("tabLine"):
    s.tabLine.enable = standardConfigs["tabLine"].getBool

  if standardConfigs.contains("syntax"):
    s.standard.syntax = standardConfigs["syntax"].getBool

  if standardConfigs.contains("tabStop"):
    s.standard.tabStop      = standardConfigs["tabStop"].getInt
    s.view.tabStop = standardConfigs["tabStop"].getInt

  if standardConfigs.contains("sidebar"):
    s.view.sidebar = standardConfigs["sidebar"].getBool

  if standardConfigs.contains("autoCloseParen"):
    s.standard.autoCloseParen = standardConfigs["autoCloseParen"].getBool

  if standardConfigs.contains("autoIndent"):
    s.standard.autoIndent = standardConfigs["autoIndent"].getBool

  if standardConfigs.contains("ignorecase"):
    s.standard.ignorecase = standardConfigs["ignorecase"].getBool

  if standardConfigs.contains("smartcase"):
    s.standard.smartcase = standardConfigs["smartcase"].getBool

  if standardConfigs.contains("disableChangeCursor"):
    s.standard.disableChangeCursor = standardConfigs["disableChangeCursor"].getBool

  if standardConfigs.contains("defaultCursor"):
    let str = standardConfigs["defaultCursor"].getStr
    s.standard.defaultCursor = cursorType(str)

  if standardConfigs.contains("normalModeCursor"):
    let str = standardConfigs["normalModeCursor"].getStr
    s.standard.normalModeCursor = cursorType(str)

  if standardConfigs.contains("insertModeCursor"):
    let str = standardConfigs["insertModeCursor"].getStr
    s.standard.insertModeCursor = cursorType(str)

  if standardConfigs.contains("liveReloadOfConf"):
    s.standard.liveReloadOfConf = standardConfigs["liveReloadOfConf"].getBool

  if standardConfigs.contains("incrementalSearch"):
    s.standard.incrementalSearch = standardConfigs["incrementalSearch"].getBool

  if standardConfigs.contains("popupWindowInExmode"):
    s.standard.popupWindowInExmode = standardConfigs["popupWindowInExmode"].getBool

  if standardConfigs.contains("autoDeleteParen"):
    s.standard.autoDeleteParen =  standardConfigs["autoDeleteParen"].getBool

  if standardConfigs.contains("colorMode"):
    s.standard.colorMode = standardConfigs["colorMode"].getStr.parseColorMode.get

  if standardConfigs.contains("liveReloadOfFile"):
    s.standard.liveReloadOfFile = standardConfigs["liveReloadOfFile"].getBool

  if standardConfigs.contains("indentationLines"):
    s.view.indentationLines = standardConfigs["indentationLines"].getBool

proc parseClipboardTable(
  s: var EditorSettings,
  clipboardConfigs: TomlValueRef) =

    if clipboardConfigs.contains("enable"):
      s.clipboard.enable = clipboardConfigs["enable"].getBool

    if clipboardConfigs.contains("tool"):
      let str = clipboardConfigs["tool"].getStr
      case str:
        of "xclip":
          s.clipboard.tool = ClipboardTool.xclip
        of "wl-clipboard":
          s.clipboard.tool = ClipboardTool.wlClipboard
        of "wsl-default":
          s.clipboard.tool = ClipboardTool.wslDefault
        of "macOS-default":
          s.clipboard.tool = ClipboardTool.macOsDefault
        else:
          s.clipboard.tool = ClipboardTool.xsel

proc parseTabLineTable(s: var EditorSettings, tablineConfigs: TomlValueRef) =
  if tablineConfigs.contains("allBuffer"):
    s.tabLine.allBuffer = tablineConfigs["allBuffer"].getBool

proc parseStatusLineTable(
  s: var EditorSettings,
  statusLineConfigs: TomlValueRef) =

    if statusLineConfigs.contains("multipleStatusLine"):
      s.statusLine.multipleStatusLine =
        statusLineConfigs["multipleStatusLine"].getBool

    if statusLineConfigs.contains("merge"):
      s.statusLine.merge = statusLineConfigs["merge"].getBool

    if statusLineConfigs.contains("mode"):
      s.statusLine.mode= statusLineConfigs["mode"].getBool

    if statusLineConfigs.contains("filename"):
      s.statusLine.filename = statusLineConfigs["filename"].getBool

    if statusLineConfigs.contains("chanedMark"):
      s.statusLine.chanedMark = statusLineConfigs["chanedMark"].getBool

    if statusLineConfigs.contains("directory"):
      s.statusLine.directory = statusLineConfigs["directory"].getBool

    if statusLineConfigs.contains("gitChangedLines"):
      s.statusLine.gitChangedLines =
        statusLineConfigs["gitChangedLines"].getBool

    if statusLineConfigs.contains("gitBranchName"):
      s.statusLine.gitBranchName = statusLineConfigs["gitBranchName"].getBool

    if statusLineConfigs.contains("showGitInactive"):
      s.statusLine.showGitInactive =
        statusLineConfigs["showGitInactive"].getBool

    if statusLineConfigs.contains("showModeInactive"):
      s.statusLine.showModeInactive =
        statusLineConfigs["showModeInactive"].getBool

    if statusLineConfigs.contains("setupText"):
      s.statusLine.setupText = statusLineConfigs["setupText"].getStr.toRunes

proc parseBuildOnSaveTable(
  s: var EditorSettings,
  buildOnSaveConfigs: TomlValueRef) =

    if buildOnSaveConfigs.contains("enable"):
      s.buildOnSave.enable = buildOnSaveConfigs["enable"].getBool

    if buildOnSaveConfigs.contains("workspaceRoot"):
      s.buildOnSave.workspaceRoot = buildOnSaveConfigs["workspaceRoot"]
        .getStr
        .toRunes

    if buildOnSaveConfigs.contains("command"):
      s.buildOnSave.command = buildOnSaveConfigs["command"].getStr.toRunes

proc parseHighlightTable(
  s: var EditorSettings,
  highlightConfigs: TomlValueRef) =

    if highlightConfigs.contains("reservedWord"):
      let reservedWords = highlightConfigs["reservedWord"]
      for i in 0 ..< reservedWords.len:
        s.highlight.reservedWords.add(ReservedWord(
          word: reservedWords[i].getStr,
          color: EditorColorPairIndex.reservedWord))

    if highlightConfigs.contains("currentLine"):
      s.view.highlightCurrentLine = highlightConfigs["currentLine"].getBool

    if highlightConfigs.contains("currentWord"):
      s.highlight.currentWord = highlightConfigs["currentWord"].getBool

    if highlightConfigs.contains("replaceText"):
      s.highlight.replaceText = highlightConfigs["replaceText"].getBool

    if highlightConfigs.contains("pairOfParen"):
      s.highlight.pairOfParen =  highlightConfigs["pairOfParen"].getBool

    if highlightConfigs.contains("fullWidthSpace"):
      s.highlight.fullWidthSpace = highlightConfigs["fullWidthSpace"].getBool

    if highlightConfigs.contains("trailingSpaces"):
      s.highlight.trailingSpaces = highlightConfigs["trailingSpaces"].getBool

proc parseAutoBackupTable(
  s: var EditorSettings,
  autoBackupConfigs: TomlValueRef) =

    if autoBackupConfigs.contains("enable"):
      s.autoBackup.enable = autoBackupConfigs["enable"].getBool

    if autoBackupConfigs.contains("idleTime"):
      s.autoBackup.idleTime = autoBackupConfigs["idleTime"].getInt

    if autoBackupConfigs.contains("interval"):
      s.autoBackup.interval = autoBackupConfigs["interval"].getInt

    if autoBackupConfigs.contains("backupDir"):
      s.autoBackup.backupDir = autoBackupConfigs["backupDir"].getStr.toRunes

    if autoBackupConfigs.contains("dirToExclude"):
      s.autoBackup.dirToExclude = @[]
      let dirs = autoBackupConfigs["dirToExclude"]
      for i in 0 ..< dirs.len:
        s.autoBackup.dirToExclude.add dirs[i].getStr.toRunes

proc parseQuickRunTable(s: var EditorSettings, quickRunConfigs: TomlValueRef) =
  if quickRunConfigs.contains("saveBufferWhenQuickRun"):
    s.quickRun.saveBufferWhenQuickRun =
      quickRunConfigs["saveBufferWhenQuickRun"].getBool

  if quickRunConfigs.contains("command"):
    s.quickRun.command = quickRunConfigs["command"].getStr

  if quickRunConfigs.contains("timeout"):
    s.quickRun.timeout = quickRunConfigs["timeout"].getInt

  if quickRunConfigs.contains("nimAdvancedCommand"):
    s.quickRun.nimAdvancedCommand = quickRunConfigs["nimAdvancedCommand"].getStr

  if quickRunConfigs.contains("clangOptions"):
    s.quickRun.clangOptions = quickRunConfigs["clangOptions"].getStr

  if quickRunConfigs.contains("cppOptions"):
    s.quickRun.cppOptions = quickRunConfigs["cppOptions"].getStr

  if quickRunConfigs.contains("nimOptions"):
    s.quickRun.nimOptions = quickRunConfigs["nimOptions"].getStr

  if quickRunConfigs.contains("shOptions"):
    s.quickRun.shOptions = quickRunConfigs["shOptions"].getStr

  if quickRunConfigs.contains("bashOptions"):
    s.quickRun.bashOptions = quickRunConfigs["bashOptions"].getStr

proc parseNotificationTable(
  s: var EditorSettings,
  notificationConfigs: TomlValueRef) =
    if notificationConfigs.contains("screenNotifications"):
      s.notification.screenNotifications =
        notificationConfigs["screenNotifications"].getBool

    if notificationConfigs.contains("logNotifications"):
      s.notification.logNotifications =
        notificationConfigs["logNotifications"].getBool

    if notificationConfigs.contains("autoBackupScreenNotify"):
      s.notification.autoBackupScreenNotify =
        notificationConfigs["autoBackupScreenNotify"].getBool

    if notificationConfigs.contains("autoBackupLogNotify"):
      s.notification.autoBackupLogNotify =
        notificationConfigs["autoBackupLogNotify"].getBool

    if notificationConfigs.contains("autoSaveScreenNotify"):
      s.notification.autoSaveScreenNotify =
        notificationConfigs["autoSaveScreenNotify"].getBool

    if notificationConfigs.contains("autoSaveLogNotify"):
      s.notification.autoSaveLogNotify =
        notificationConfigs["autoSaveLogNotify"].getBool

    if notificationConfigs.contains("yankScreenNotify"):
      s.notification.yankScreenNotify =
        notificationConfigs["yankScreenNotify"].getBool

    if notificationConfigs.contains("yankLogNotify"):
      s.notification.yankLogNotify =
        notificationConfigs["yankLogNotify"].getBool

    if notificationConfigs.contains("deleteScreenNotify"):
      s.notification.deleteScreenNotify =
        notificationConfigs["deleteScreenNotify"].getBool

    if notificationConfigs.contains("deleteLogNotify"):
      s.notification.deleteLogNotify =
        notificationConfigs["deleteLogNotify"].getBool

    if notificationConfigs.contains("saveScreenNotify"):
      s.notification.saveScreenNotify =
        notificationConfigs["saveScreenNotify"].getBool

    if notificationConfigs.contains("saveLogNotify"):
      s.notification.saveLogNotify =
        notificationConfigs["saveLogNotify"].getBool

    if notificationConfigs.contains("quickRunScreenNotify"):
      s.notification.quickRunScreenNotify =
        notificationConfigs["quickRunScreenNotify"].getBool

    if notificationConfigs.contains("quickRunLogNotify"):
      s.notification.quickRunLogNotify =
        notificationConfigs["quickRunLogNotify"].getBool

    if notificationConfigs.contains("buildOnSaveScreenNotify"):
      s.notification.buildOnSaveScreenNotify =
        notificationConfigs["buildOnSaveScreenNotify"].getBool

    if notificationConfigs.contains("buildOnSaveLogNotify"):
      s.notification.buildOnSaveLogNotify =
        notificationConfigs["buildOnSaveLogNotify"].getBool

    if notificationConfigs.contains("filerScreenNotify"):
      s.notification.filerScreenNotify =
        notificationConfigs["filerScreenNotify"].getBool

    if notificationConfigs.contains("filerLogNotify"):
      s.notification.filerLogNotify =
        notificationConfigs["filerLogNotify"].getBool

    if notificationConfigs.contains("restoreScreenNotify"):
      s.notification.restoreScreenNotify =
        notificationConfigs["restoreScreenNotify"].getBool

    if notificationConfigs.contains("restoreLogNotify"):
      s.notification.restoreLogNotify =
        notificationConfigs["restoreLogNotify"].getBool

proc parseFilerTable(s: var EditorSettings, filerConfigs: TomlValueRef) =
  if filerConfigs.contains("showIcons"):
    s.filer.showIcons = filerConfigs["showIcons"].getBool

proc parseAutocompleteTable(
  s: var EditorSettings,
  autocompleteConfigs: TomlValueRef) =

    if autocompleteConfigs.contains("enable"):
      s.autocomplete.enable = autocompleteConfigs["enable"].getBool

proc parseAutoSaveTable(
  s: var EditorSettings,
  autoSaveConfigs: TomlValueRef) =

    if autoSaveConfigs.contains("enable"):
      s.autoSave.enable = autoSaveConfigs["enable"].getBool

    if autoSaveConfigs.contains("interval"):
      s.autoSave.interval = autoSaveConfigs["interval"].getInt

proc parsePersistTable(s: var EditorSettings, persistConfigs: TomlValueRef) =
  if persistConfigs.contains("exCommand"):
    s.persist.exCommand = persistConfigs["exCommand"].getBool

  if persistConfigs.contains("exCommandHistoryLimit"):
    s.persist.exCommandHistoryLimit = persistConfigs["exCommandHistoryLimit"]
      .getInt

  if persistConfigs.contains("search"):
    s.persist.search = persistConfigs["search"].getBool

  if persistConfigs.contains("searchHistoryLimit"):
    s.persist.searchHistoryLimit = persistConfigs["searchHistoryLimit"].getInt

  if persistConfigs.contains("cursorPosition"):
    s.persist.cursorPosition = persistConfigs["cursorPosition"].getBool

proc parseDebugTable(s: var EditorSettings, debugConfigs: TomlValueRef) =
  if debugConfigs.contains("WindowNode"):
    if debugConfigs["WindowNode"].contains("enable"):
      let setting = debugConfigs["WindowNode"]["enable"].getBool
      s.debugMode.windowNode.enable = setting

    if debugConfigs["WindowNode"].contains("currentWindow"):
      let setting = debugConfigs["WindowNode"]["currentWindow"].getBool
      s.debugMode.windowNode.currentWindow = setting

    if debugConfigs["WindowNode"].contains("index"):
      let setting = debugConfigs["WindowNode"]["index"].getBool
      s.debugMode.windowNode.index = setting

    if debugConfigs["WindowNode"].contains("windowIndex"):
      let setting = debugConfigs["WindowNode"]["windowIndex"].getBool
      s.debugMode.windowNode.windowIndex = setting

    if debugConfigs["WindowNode"].contains("bufferIndex"):
      let setting = debugConfigs["WindowNode"]["bufferIndex"].getBool
      s.debugMode.windowNode.bufferIndex = setting

    if debugConfigs["WindowNode"].contains("parentIndex"):
      let setting = debugConfigs["WindowNode"]["parentIndex"].getBool
      s.debugMode.windowNode.parentIndex = setting

    if debugConfigs["WindowNode"].contains("childLen"):
      let setting = debugConfigs["WindowNode"]["childLen"].getBool
      s.debugMode.windowNode.childLen = setting

    if debugConfigs["WindowNode"].contains("splitType"):
      let setting = debugConfigs["WindowNode"]["splitType"].getBool
      s.debugMode.windowNode.splitType = setting

    if debugConfigs["WindowNode"].contains("haveCursesWin"):
      let setting = debugConfigs["WindowNode"]["haveCursesWin"].getBool
      s.debugMode.windowNode.haveCursesWin = setting

    if debugConfigs["WindowNode"].contains("haveCursesWin"):
      let setting = debugConfigs["WindowNode"]["haveCursesWin"].getBool
      s.debugMode.windowNode.haveCursesWin = setting

    if debugConfigs["WindowNode"].contains("y"):
      let setting = debugConfigs["WindowNode"]["y"].getBool
      s.debugMode.windowNode.y = setting

    if debugConfigs["WindowNode"].contains("x"):
      let setting = debugConfigs["WindowNode"]["x"].getBool
      s.debugMode.windowNode.x = setting

    if debugConfigs["WindowNode"].contains("h"):
      let setting = debugConfigs["WindowNode"]["h"].getBool
      s.debugMode.windowNode.h = setting

    if debugConfigs["WindowNode"].contains("w"):
      let setting = debugConfigs["WindowNode"]["w"].getBool
      s.debugMode.windowNode.w = setting

    if debugConfigs["WindowNode"].contains("currentLine"):
      let setting = debugConfigs["WindowNode"]["currentLine"].getBool
      s.debugMode.windowNode.currentLine = setting

    if debugConfigs["WindowNode"].contains("currentColumn"):
      let setting = debugConfigs["WindowNode"]["currentColumn"].getBool
      s.debugMode.windowNode.currentColumn = setting

    if debugConfigs["WindowNode"].contains("expandedColumn"):
      let setting = debugConfigs["WindowNode"]["expandedColumn"].getBool
      s.debugMode.windowNode.expandedColumn = setting

    if debugConfigs["WindowNode"].contains("cursor"):
      let setting = debugConfigs["WindowNode"]["cursor"].getBool
      s.debugMode.windowNode.cursor = setting

  if debugConfigs.contains("EditorView"):
    if debugConfigs["EditorView"].contains("enable"):
      let setting = debugConfigs["EditorView"]["enable"].getBool
      s.debugMode.editorview.enable = setting

    if debugConfigs["EditorView"].contains("widthOfLineNum"):
      let setting = debugConfigs["EditorView"]["widthOfLineNum"].getBool
      s.debugMode.editorview.widthOfLineNum = setting

    if debugConfigs["EditorView"].contains("height"):
      let setting = debugConfigs["EditorView"]["height"].getBool
      s.debugMode.editorview.height = setting

    if debugConfigs["EditorView"].contains("width"):
      let setting = debugConfigs["EditorView"]["width"].getBool
      s.debugMode.editorview.width = setting

    if debugConfigs["EditorView"].contains("originalLine"):
      let setting = debugConfigs["EditorView"]["originalLine"].getBool
      s.debugMode.editorview.originalLine = setting

    if debugConfigs["EditorView"].contains("start"):
      let setting = debugConfigs["EditorView"]["start"].getBool
      s.debugMode.editorview.start = setting

    if debugConfigs["EditorView"].contains("length"):
      let setting = debugConfigs["EditorView"]["length"].getBool
      s.debugMode.editorview.length = setting

  if debugConfigs.contains("BufferStatus"):
    if debugConfigs["BufferStatus"].contains("enable"):
      let setting = debugConfigs["BufferStatus"]["enable"].getBool
      s.debugMode.bufStatus.enable = setting

    if debugConfigs["BufferStatus"].contains("bufferIndex"):
      let setting = debugConfigs["BufferStatus"]["bufferIndex"].getBool
      s.debugMode.bufStatus.bufferIndex = setting

    if debugConfigs["BufferStatus"].contains("path"):
      let setting = debugConfigs["BufferStatus"]["path"].getBool
      s.debugMode.bufStatus.path = setting

    if debugConfigs["BufferStatus"].contains("openDir"):
      let setting = debugConfigs["BufferStatus"]["openDir"].getBool
      s.debugMode.bufStatus.openDir = setting

    if debugConfigs["BufferStatus"].contains("currentMode"):
      let setting = debugConfigs["BufferStatus"]["currentMode"].getBool
      s.debugMode.bufStatus.currentMode = setting

    if debugConfigs["BufferStatus"].contains("prevMode"):
      let setting = debugConfigs["BufferStatus"]["prevMode"].getBool
      s.debugMode.bufStatus.prevMode = setting

    if debugConfigs["BufferStatus"].contains("language"):
      let setting = debugConfigs["BufferStatus"]["language"].getBool
      s.debugMode.bufStatus.language = setting

    if debugConfigs["BufferStatus"].contains("encoding"):
      let setting = debugConfigs["BufferStatus"]["encoding"].getBool
      s.debugMode.bufStatus.encoding = setting

    if debugConfigs["BufferStatus"].contains("countChange"):
      let setting = debugConfigs["BufferStatus"]["countChange"].getBool
      s.debugMode.bufStatus.countChange = setting

    if debugConfigs["BufferStatus"].contains("cmdLoop"):
      let setting = debugConfigs["BufferStatus"]["cmdLoop"].getBool
      s.debugMode.bufStatus.cmdLoop = setting

    if debugConfigs["BufferStatus"].contains("lastSaveTime"):
      let setting = debugConfigs["BufferStatus"]["lastSaveTime"].getBool
      s.debugMode.bufStatus.lastSaveTime = setting

    if debugConfigs["BufferStatus"].contains("bufferLen"):
      let setting = debugConfigs["BufferStatus"]["bufferLen"].getBool
      s.debugMode.bufStatus.bufferLen = setting

proc parseGitTable(s: var EditorSettings, gitConfigs: TomlValueRef) =
  if gitConfigs.contains("showChangedLine"):
    s.git.showChangedLine = gitConfigs["showChangedLine"].getBool

  if gitConfigs.contains("updateInterval"):
    s.git.updateInterval = gitConfigs["updateInterval"].getInt

proc parseSyntaxCheckerTable(
  s: var EditorSettings,
  syntaxCheckConfigs: TomlValueRef) =

    if syntaxCheckConfigs.contains("enable"):
      s.syntaxChecker.enable = syntaxCheckConfigs["enable"].getBool

proc parseSmoothScrollTable(
  s: var EditorSettings,
  smoothScrollConfigs: TomlValueRef) =

    if smoothScrollConfigs.contains("enable"):
      s.smoothScroll.enable = smoothScrollConfigs["enable"].getBool

    if smoothScrollConfigs.contains("minDelay"):
      s.smoothScroll.minDelay = smoothScrollConfigs["minDelay"].getInt

    if smoothScrollConfigs.contains("maxDelay"):
      s.smoothScroll.maxDelay = smoothScrollConfigs["maxDelay"].getInt

proc parseStartUpSettingsTable(
  s: var EditorSettings,
  startUpConfigs: TomlValueRef) =

    if startUpConfigs.contains("FileOpen"):
      if startUpConfigs["FileOpen"].contains("autoSplit"):
        s.startUp.fileOpen.autoSplit =
          startUpConfigs["FileOpen"]["autoSplit"].getBool

      if startUpConfigs["FileOpen"].contains("splitType"):
        s.startUp.fileOpen.splitType = startUpConfigs["FileOpen"]["splitType"]
          .getStr
          .parseWindowSplitType
          .get

proc parseThemeTable(s: var EditorSettings, themeConfigs: TomlValueRef) =
  if themeConfigs.contains("kind"):
    s.theme.kind = parseEnum[ColorThemeKind]themeConfigs["kind"].getStr

  if themeConfigs.contains("path"):
    s.theme.path = themeConfigs["path"].getStr

proc parseLspTable(s: var EditorSettings, lspConfigs: TomlValueRef) =
  for key, val in lspConfigs.getTable:
    case key:
      of "enable":
        s.lsp.enable = lspConfigs["enable"].getBool
      of "Completion":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.completion.enable = val.getBool
            else:
              discard
      of "Definition":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.definition.enable = val.getBool
            else:
              discard
      of "Diagnostics":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.diagnostics.enable = val.getBool
            else:
              discard
      of "Hover":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.hover.enable = val.getBool
            else:
              discard
      of "InlayHint":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.inlayHint.enable = val.getBool
            else:
              discard
      of "SemanticTokens":
        for key, val in val.getTable:
          case key:
            of "enable":
              s.lsp.features.semanticTokens.enable = val.getBool
            else:
              discard
      else:
        let langId = key
        var langSettings = LspLanguageSettings()
        for key, val in val.getTable:
          case key:
            of "extensions":
              for i in 0 ..< val.len:
                langSettings.extensions.add val[i].getStr.toRunes
            of "command":
              langSettings.command = val.getStr.toRunes
            of "trace":
              langSettings.trace = val.getStr.parseTraceValue.get

        s.lsp.languages[langId] = langSettings

proc toThemeColors*(config: TomlValueRef): ThemeColors =
  ## Return ThemeColors based on the TOML theme colors config.

  template toRgb(s: string): Rgb =
    case s:
      of "termDefaultFg", "termDefaultBg":
        TerminalDefaultRgb
      else:
        s.hexToRgb.get

  template configColors: TomlValueRef = config["Colors"]

  # the base color is DefaultColors.
  result = DefaultColors

  for index in EditorColorIndex:
    if configColors.contains($index):
      case index:
        of EditorColorIndex.foreground:
          let rgb = configColors["foreground"].getStr.toRgb
          result[EditorColorPairIndex.default].foreground.rgb = rgb
          result[EditorColorPairIndex.currentLineBg].foreground.rgb = rgb
        of EditorColorIndex.background:
          let rgb = configColors["background"].getStr.toRgb
          result[EditorColorPairIndex.default].background.rgb = rgb
          for i in EditorColorPairIndex.keyword .. EditorColorPairIndex.inlayHint:
            result[i].background.rgb = rgb
        of EditorColorIndex.currentLineBg:
          result[EditorColorPairIndex.currentLineBg].background.rgb =
            configColors[$index].getStr.toRgb
        else:
          if endsWith($index, "Bg"):
            # Set background colors
            let
              # Remove "Bg" and parse enum.
              indexStr = ($index)[0 .. ($index).high - 2]
              pairIndex = parseEnum[EditorColorPairIndex](indexStr)
              rgb = configColors[$index].getStr.toRgb
            result[pairIndex].background.rgb = rgb
          else:
            # Set foreground colors
            let
              pairIndex = parseEnum[EditorColorPairIndex]($index)
              rgb = configColors[$index].getStr.toRgb
            result[pairIndex].foreground.rgb = rgb

proc applyTomlConfigs*(s: var EditorSettings, tomlConfigs: TomlValueRef) =
  if tomlConfigs.contains("Standard"):
    s.parseStandardTable(tomlConfigs["Standard"])

  if tomlConfigs.contains("Clipboard"):
    s.parseClipboardTable(tomlConfigs["Clipboard"])

  if tomlConfigs.contains("TabLine"):
    s.parseTabLineTable(tomlConfigs["TabLine"])

  if tomlConfigs.contains("StatusLine"):
    s.parseStatusLineTable(tomlConfigs["StatusLine"])

  if tomlConfigs.contains("BuildOnSave"):
    s.parseBuildOnSaveTable(tomlConfigs["BuildOnSave"])

  if tomlConfigs.contains("Highlight"):
    s.parseHighlightTable(tomlConfigs["Highlight"])

  if tomlConfigs.contains("AutoBackup"):
    s.parseAutoBackupTable(tomlConfigs["AutoBackup"])

  if tomlConfigs.contains("QuickRun"):
    s.parseQuickRunTable(tomlConfigs["QuickRun"])

  if tomlConfigs.contains("Notification"):
    s.parseNotificationTable(tomlConfigs["Notification"])

  if tomlConfigs.contains("Filer"):
    s.parseFilerTable(tomlConfigs["Filer"])

  if tomlConfigs.contains("Autocomplete"):
    s.parseAutocompleteTable(tomlConfigs["Autocomplete"])

  if tomlConfigs.contains("AutoSave"):
    s.parseAutoSaveTable(tomlConfigs["AutoSave"])

  if tomlConfigs.contains("Persist"):
    s.parsePersistTable(tomlConfigs["Persist"])

  if tomlConfigs.contains("Debug"):
    s.parseDebugTable(tomlConfigs["Debug"])

  if tomlConfigs.contains("Git"):
    s.parseGitTable(tomlConfigs["Git"])

  if tomlConfigs.contains("SyntaxChecker"):
    s.parseSyntaxCheckerTable(tomlConfigs["SyntaxChecker"])

  if tomlConfigs.contains("SmoothScroll"):
    s.parseSmoothScrollTable(tomlConfigs["SmoothScroll"])

  if tomlConfigs.contains("StartUp"):
    s.parseStartUpSettingsTable(tomlConfigs["StartUp"])

  if tomlConfigs.contains("Theme"):
    s.parseThemeTable(tomlConfigs["Theme"])

  if tomlConfigs.contains("Lsp"):
    s.parseLspTable(tomlConfigs["Lsp"])

proc validateStandardTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
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
         "liveReloadOfFile",
         "sidebar":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "tabStop":
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
      of "colorMode":
        if val.getStr.parseColorMode.isErr:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateClipboardTable(table: TomlValueRef): Option[InvalidItem] =
  template isValidTool(s: string): bool =
    s in [ "xclip", "xsel", "wl-clipboard", "wsl-defaut", "macOS-default"]

  for key, val in table.getTable:
    case key:
      of "enable":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "tool":
        if not (val.kind == TomlValueKind.String and val.getStr.isValidTool):
          return some(InvalidItem(name: $key, val: $val))
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

proc validateStatusLineSetupText(text: string): bool =
  ## Check text for StatusLineSettings.setupText.
  ## Text example: "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"

  result = true

  for m in text.findAll(re2"\{(\w+)\}"):
    let word = text[m.group(0)]
    if not StatusLineItem.mapIt($it).contains(word):
      return false

proc validateStatusLineTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "multipleStatusLine",
         "merge",
         "mode",
         "filename",
         "chanedMark",
         "directory",
         "gitChangedLines",
         "gitBranchName",
         "showGitInactive",
         "showModeInactive":
        if not (val.kind == TomlValueKind.Bool):
          return some(InvalidItem(name: $key, val: $val))
      of "setupText":
        if (val.kind != TomlValueKind.String) and
           (not validateStatusLineSetupText(val.getStr)):
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

proc validateAutoSaveTable(table: TomlValueRef): Option[InvalidItem] =
    for key, val in table.getTable:
      case key:
        of "enable":
          if val.kind != TomlValueKind.Bool:
            return some(InvalidItem(name: $key, val: $val))
        of "interval":
          if val.kind != TomlValueKind.Int:
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

proc validateGitTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "showChangedLine":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "updateInterval":
        if val.kind != TomlValueKind.Int:
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

proc validateSmoothScrollTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "minDelay", "maxDelay":
        if val.kind != TomlValueKind.Int:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateStartUpTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "FileOpen":
        # Check [StartUp.FileOpen]
        for key,val in table["FileOpen"].getTable:
          case key:
            of "autoSplit":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            of "splitType":
              if val.kind != TomlValueKind.String or
                 parseWindowSplitType(val.getStr).isErr:
                   return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateThemeTable(table: TomlValueRef): Option[InvalidItem] =
  template isColorThemeKind(s: string): bool = s in ColorThemeKind.mapIt($it)

  for key, val in table.getTable:
    case key:
      of "kind":
        if val.kind != TomlValueKind.String or not isColorThemeKind(val.getStr):
          return some(InvalidItem(name: $key, val: $val))
      of "path":
        if val.kind != TomlValueKind.String:
          return some(InvalidItem(name: $key, val: $val))
      else:
        return some(InvalidItem(name: $key, val: $val))

proc validateLspTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "enable":
        if val.kind != TomlValueKind.Bool:
          return some(InvalidItem(name: $key, val: $val))
      of "Completion":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      of "Definition":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      of "Diagnostics":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      of "Hover":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      of "InlayHint":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      of "SemanticTokens":
        for key, val in val.getTable:
          case key:
            of "enable":
              if val.kind != TomlValueKind.Bool:
                return some(InvalidItem(name: $key, val: $val))
            else:
              return some(InvalidItem(name: $key, val: $val))
      else:
        if val.kind != TomlValueKind.Table:
          return some(InvalidItem(name: $key, val: $val))

        # Languages settings
        for key, val in val.getTable:
          case key:
            of "extensions":
              if val.kind != TomlValueKind.Array:
                return some(InvalidItem(name: $key, val: $val))
            of "command", "trace":
              if val.kind != TomlValueKind.String and
                 val.getStr.parseTraceValue.isErr:
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
      of "Autocomplete":
        let r = validateAutocompleteTable(val)
        if r.isSome: return r
      of "AutoSave":
        let r = validateAutoSaveTable(val)
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
      of "SmoothScroll":
        let r = validateSmoothScrollTable(val)
        if r.isSome: return r
      of "StartUp":
        let r = validateStartUpTable(val)
        if r.isSome: return r
      of "Theme":
        let r = validateThemeTable(val)
        if r.isSome: return r
      of "Lsp":
        let r = validateLspTable(val)
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

proc loadConfigFile*(path: string): Result[TomlValueRef, string] =
  ## Load and validate.

  var toml: TomlValueRef
  try:
    toml = parsetoml.parseFile(path)
  except CatchableError as e:
    return Result[TomlValueRef, string].err e.msg

  let invalidItem = toml.validateTomlConfig
  if invalidItem.isSome:
    return Result[TomlValueRef, string].err toValidateErrorMessage(
      invalidItem.get)

  return Result[TomlValueRef, string].ok toml

proc validateThemeColorsConfig(toml: TomlValueRef): Option[InvalidItem] =
  proc editorColorIndexNames(): seq[string] {.compileTime.} =
    EditorColorIndex.mapIt(it.symbolName)

  template isValidKey(key: string): bool =
    editorColorIndexNames().contains(key)

  template isColorVal(val: string): bool =
    val == "termDefaultFg" or val == "termDefaultBg" or val.isHexColor

  for key, val in toml.getTable:
    if toml.contains("Colors"):
      for key, val in toml["Colors"].getTable:
        if val.kind != TomlValueKind.String or
           not key.isValidKey or
           not val.getStr.isColorVal:
             return some(InvalidItem(name: $key, val: $val))
    else:
      return some(InvalidItem(name: $key, val: ""))

proc loadThemeFile*(path: string): Result[TomlValueRef, string] =
  ## Load and validate.

  let fullPath =  expandTilde(path)

  if not fileExists(fullPath):
    return Result[TomlValueRef, string].err fmt"File not found: {path}"

  var toml: TomlValueRef
  try:
    toml = parsetoml.parseFile(fullPath)
  except CatchableError as e:
    return Result[TomlValueRef, string].err e.msg

  let invalidItem = validateThemeColorsConfig(toml)
  if invalidItem.isSome:
    return Result[TomlValueRef, string].err toValidateErrorMessage(
      invalidItem.get)

  return Result[TomlValueRef, string].ok toml

proc loadConfigs*(s: var EditorSettings): Result[(), string] =
  ## Load config and theme files and init EditorSettings.

  if fileExists(configFilePath()):
    let toml = loadConfigFile(configFilePath())
    if toml.isErr: return Result[(), string].err toml.tryError

    s.applyTomlConfigs(toml.get)

  case s.theme.kind:
    of ColorThemeKind.default:
      s.theme.colors = DefaultColors
    of ColorThemeKind.config:
      let toml = loadThemeFile(s.theme.path)
      if toml.isErr: return Result[(), string].err toml.tryError
      s.theme.colors = toml.get.toThemeColors
    of ColorThemeKind.vscode:
      let colors = loadVSCodeTheme()
      if colors.isErr: return Result[(), string].err colors.error
      s.theme.colors = colors.get

  return Result[(), string].ok ()

proc toConfigStr*(colorMode: ColorMode): string =
  ## Convert ColorMode to string for the config file.

  case colorMode:
    of ColorMode.none: "none"
    of ColorMode.c8: "8"
    of ColorMode.c16: "16"
    of ColorMode.c256: "256"
    of ColorMode.c24bit: "24bit"

proc toConfigStr(tool: ClipboardTool): string =
  case tool:
    of xsel: "xsel"
    of xclip: "xclip"
    of wlClipboard: "wl-clipboard"
    of wslDefault: "wsl-defaut"
    of macOsDefault: "macOS-defaut"

proc genTomlConfigStr*(settings: EditorSettings): string =
  ## Generate a string of the configuration file of TOML.

  proc addLine(buf: var string, str: string) {.inline.} = buf &= "\n" & str

  result = "[Standard]"
  result.addLine fmt "number = {$settings.view.lineNumber}"
  result.addLine fmt "currentNumber = {$settings.view.currentLineNumber}"
  result.addLine fmt "statusLine = {$settings.statusLine.enable}"
  result.addLine fmt "tabLine = {$settings.tabLine.enable}"
  result.addLine fmt "syntax = {$settings.standard.syntax}"
  result.addLine fmt "indentationLines = {$settings.view.indentationLines}"
  result.addLine fmt "tabStop = {$settings.standard.tabStop}"
  result.addLine fmt "sidebar = {$settings.view.sidebar}"
  result.addLine fmt "autoCloseParen = {$settings.standard.autoCloseParen}"
  result.addLine fmt "autoIndent = {$settings.standard.autoIndent}"
  result.addLine fmt "ignorecase = {$settings.standard.ignorecase}"
  result.addLine fmt "smartcase = {$settings.standard.smartcase}"
  result.addLine fmt "disableChangeCursor = {$settings.standard.disableChangeCursor}"
  result.addLine fmt "defaultCursor = \"{$settings.standard.defaultCursor}\""
  result.addLine fmt "normalModeCursor = \"{$settings.standard.normalModeCursor}\""
  result.addLine fmt "insertModeCursor = \"{$settings.standard.insertModeCursor}\""
  result.addLine fmt "liveReloadOfConf = {$settings.standard.liveReloadOfConf}"
  result.addLine fmt "incrementalSearch = {$settings.standard.incrementalSearch}"
  result.addLine fmt "popupWindowInExmode = {$settings.standard.popupWindowInExmode}"
  result.addLine fmt "autoDeleteParen = {$settings.standard.autoDeleteParen }"
  result.addLine fmt "liveReloadOfFile = {$settings.standard.liveReloadOfFile}"
  result.addLine fmt "colorMode = \"{settings.standard.colorMode.toConfigStr}\""

  result.addLine ""

  result.addLine fmt "[Clipboard]"
  result.addLine fmt "enable = {$settings.clipboard.enable}"
  result.addLine fmt "tool = \"{settings.clipboard.tool.toConfigStr}\""

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
  result.addLine fmt "directory = {$settings.statusLine.directory}"
  result.addLine fmt "gitChangedLines = {$settings.statusLine.gitChangedLines}"
  result.addLine fmt "gitBranchName = {$settings.statusLine.gitBranchName}"
  result.addLine fmt "showGitInactive = {$settings.statusLine.showGitInactive}"
  result.addLine fmt "showModeInactive = {$settings.statusLine.showModeInactive}"
  result.addLine fmt "setupText = \"{settings.statusLine.setupText}\""

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

  result.addLine fmt "[AutoSave]"
  result.addLine fmt "enable = {$settings.autoSave.enable}"
  result.addLine fmt "interval = {$settings.autoSave.interval}"

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
  result.addLine fmt "updateInterval = {$settings.git.updateInterval}"

  result.addLine ""

  result.addLine fmt "[SyntaxChecker]"
  result.addLine fmt "enable = {$settings.syntaxChecker.enable}"

  result.addLine ""

  result.addLine fmt "[SmoothScroll]"
  result.addLine fmt "enable = {$settings.smoothScroll.enable}"
  result.addLine fmt "minDelay = {$settings.smoothScroll.minDelay}"
  result.addLine fmt "maxDelay = {$settings.smoothScroll.maxDelay}"

  result.addLine fmt "[StartUp.FileOpen]"
  result.addLine fmt "autoSplit = {$settings.startUp.fileOpen.autoSplit}"
  result.addLine fmt "splitType = \"{$settings.startUp.fileOpen.splitType}\""

  result.addLine fmt "[Lsp]"
  result.addLine fmt "enable = {$settings.lsp.enable}"

  result.addLine fmt "[Lsp.Completion]"
  result.addLine fmt "enable = {$settings.lsp.features.completion.enable}"

  result.addLine fmt "[Lsp.Definition]"
  result.addLine fmt "enable = {$settings.lsp.features.definition.enable}"

  result.addLine fmt "[Lsp.Diagnostics]"
  result.addLine fmt "enable = {$settings.lsp.features.diagnostics.enable}"

  result.addLine fmt "[Lsp.Hover]"
  result.addLine fmt "enable = {$settings.lsp.features.hover.enable}"

  result.addLine fmt "[Lsp.InlayHint]"
  result.addLine fmt "enable = {$settings.lsp.features.inlayHint.enable}"

  result.addLine fmt "[Lsp.SemanticTokens]"
  result.addLine fmt "enable = {$settings.lsp.features.semanticTokens.enable}"

  for key, val in settings.lsp.languages.pairs:
    result.addLine fmt "[Lsp.{key}]"

    # Create array of string.
    var exts = "[]"
    for index, ext in val.extensions:
      exts.insert('"' & $ext & '"', 1)
      if index < val.extensions.high: exts.insert(", ", exts.high - 1)
    result.addLine fmt "extensions = {exts}"

    result.addLine fmt "command = \"{$val.command}\""

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

  result.addLine fmt "[Theme]"
  result.addLine fmt "kind = \"{$settings.theme.kind}\""
  if settings.theme.kind == ColorThemeKind.config:
    result.addLine fmt "path = \"{$settings.theme.path}\""

# Generate a string of the default TOML configuration.
proc genDefaultTomlConfigStr*(): string {.inline.} =
  initEditorSettings().genTomlConfigStr
