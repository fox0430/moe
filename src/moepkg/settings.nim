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

import std/[os, json, macros, times, options, strformat, osproc,
            strutils]
import pkg/parsetoml
import ui, color, unicodeext, highlight, platform, independentutils

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

  EditorSettings* = object
    editorColorTheme*: colorTheme
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

proc initReservedWords*(): seq[ReservedWord] =
  result = @[
    ReservedWord(word: "TODO", color: EditorColorPair.reservedWord),
    ReservedWord(word: "WIP", color: EditorColorPair.reservedWord),
    ReservedWord(word: "NOTE", color: EditorColorPair.reservedWord),
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

proc initEditorSettings*(): EditorSettings =
  result.editorColorTheme = colorTheme.dark
  result.statusLine = initStatusLineSettings()
  result.tabLine = initTabBarSettings()
  result.view = initEditorViewSettings()
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.ignorecase = true
  result.smartcase = true
  # defaultCursor is terminal default curosr shape
  result.defaultCursor = CursorType.blinkBlock
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

proc getTheme(theme: string): colorTheme =
  if theme == "vivid": return colorTheme.vivid
  elif theme == "light": return colorTheme.light
  elif theme == "config": return colorTheme.config
  elif theme == "vscode": return colorTheme.vscode
  else: return colorTheme.dark

# This macro takes statement lists for the foreground and
# background colors of a foreground/background color setting.
# these statements are supposed to set the color, and
# the first statement that doesn't result in Color.default
# will be used. Color.default will only be used when there's
# no success at all.
# Finally adjusts can be used to generate a suitable color.
# adjusts:
#   InverseBackground    - inversing the background color
#   InverseForeground    - inversing the foreground color
#   ReadableVsBackground - adjusts foreground to be readable
macro setEditorColor(args: varargs[untyped]): untyped =
  let colorNameIdent           = args[0]
  let colorNameBackgroundIdent = ident(colorNameIdent.strVal & "Bg")
  let resultIdent              = ident"result"
  let fgColorIdent             = genSym(nskVar, "fgColor")
  let bgColorIdent             = genSym(nskVar, "bgColor")
  let stmtList                 = args[^1]
  let fgStmtList               = stmtList[0][^1]
  let bgStmtList               = stmtList[^1][^1]
  var setFgColor               : NimNode = quote do: discard
  var setBgColor               : NimNode = quote do: discard
  var fgDynamicAdjust          : NimNode = quote do: discard
  var bgDynamicAdjust          : NimNode = quote do: discard
  var assignColors             : NimNode = quote do: discard
  var fallbackInverseBg        : NimNode = quote do:
    if (`fgColorIdent` == Color.default and
        `bgColorIdent` != Color.default):
      `fgColorIdent` = inverseColor(`bgColorIdent`)
  var fallbackInverseFg        : NimNode = quote do:
    if (`fgColorIdent` != Color.default and
        `bgColorIdent` == Color.default):
      `bgColorIdent` = inverseColor(`fgColorIdent`)
  var readableVsBackground     : NimNode = quote do:
    `fgColorIdent` = readableOnBackground(`fgColorIdent`, `bgColorIdent`)
  for statement in fgStmtList:
    if (statement.kind == nnkCall and statement[0].kind == nnkIdent and
        statement[0].strVal() == "adjust"):
        let adjust = statement[^1][0].strVal()
        case adjust
        of "InverseBackground":
          fgDynamicAdjust = quote do:
            `fgDynamicAdjust`
            `fallbackInverseBg`
        of "ReadableVsBackground":
          fgDynamicAdjust = quote do:
            `fgDynamicAdjust`
            `readableVsBackground`
        else: discard
    else:
      setFgColor = quote do:
        `setFgColor`
        if `fgColorIdent` == Color.default:
          `fgColorIdent` = `statement`
  for statement in bgStmtList:
    setBgColor = quote do:
      `setBgColor`
      if `bgColorIdent` == Color.default:
        `bgColorIdent` = `statement`
  if stmtList[0][0].strVal() == stmtList[^1][0].strVal():
    # they are the same => there's only one
    setBgColor = quote do: discard
    #fgDynamicAdjust = quote do: discard
    #bgDynamicAdjust = quote do: discard
    assignColors    = quote do:
      `resultIdent`.`colorNameIdent`           = `fgColorIdent`
  else:
    assignColors    = quote do:
      `resultIdent`.`colorNameIdent`           = `fgColorIdent`
      `resultIdent`.`colorNameBackgroundIdent` = `bgColorIdent`

  return quote do:
    var `fgColorIdent` = Color.default
    var `bgColorIdent` = Color.default
    `setFgColor`
    `setBgColor`
    `fgDynamicAdjust`
    `bgDynamicAdjust`
    `assignColors`

proc makecolorThemeFromVSCodeThemeFile(jsonNode: JsonNode): EditorColor =
  # This converts a JsonNode JString to a 256-Color-Terminal-Color
  proc colorFromNode(node: JsonNode): Color =
    if node == nil:
      return Color.default
    var asString = node.getStr()
    if (asString.len() >= 7   and
        asString[0]    == '#'):
        return hexToColor(asString[1..asString.len()-1])
    return Color.default

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

  # Convenience
  proc getScope(key: string): JsonNode =
    if tokenNodes.hasKey(key):
      return tokenNodes[key]
    else:
      return JsonNode.default()

  # This is currently optimized and tested for the Forest Focus theme
  # and even for that theme it only produces a partial and imperfect
  # translation
  setEditorColor editorBg:
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})

  # Color scheme
  setEditorColor defaultChar:
    foreground:
      colorFromNode(jsonNode{"colors", "editor.foreground"})
  setEditorColor gtKeyword:
    foreground:
      colorFromNode(getScope("keyword"){"foreground"})
  setEditorColor gtFunctionName:
    foreground:
      colorFromNode(getScope("entity"){"foreground"})
  setEditorColor gtTypeName:
    foreground:
      colorFromNode(getScope("entity"){"foreground"})
  setEditorColor gtBoolean:
    foreground:
      colorFromNode(getScope("entity"){"foreground"})
  setEditorColor gtSpecialVar:
    foreground:
      colorFromNode(getScope("variable"){"foreground"})
  setEditorColor gtBuiltin:
    foreground:
      colorFromNode(getScope("entity"){"foreground"})
  setEditorColor gtStringLit:
    foreground:
      colorFromNode(getScope("string"){"foreground"})
  setEditorColor gtBinNumber:
    foreground:
      colorFromNode(getScope("constant"){"foreground"})
  setEditorColor gtDecNumber:
    foreground:
      colorFromNode(getScope("constant"){"foreground"})
  setEditorColor gtFloatNumber:
    foreground:
      colorFromNode(getScope("constant"){"foreground"})
  setEditorColor gtHexNumber:
    foreground:
      colorFromNode(getScope("constant"){"foreground"})
  setEditorColor gtOctNumber:
    foreground:
      colorFromNode(getScope("constant"){"foreground"})
  setEditorColor gtComment:
    foreground:
      colorFromNode(getScope("comment"){"foreground"})
  setEditorColor gtLongComment:
    foreground:
      colorFromNode(getScope("comment"){"foreground"})
  setEditorColor gtWhitespace:
    foreground:
      colorFromNode(jsonNode{"colors", "editorWhitespace.foreground"})

  # status line
  setEditorColor statusLineNormalMode:
    foreground:
      colorFromNode(jsonNode{"colors", "editor.foreground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeNormalMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineNormalModeInactive:
    foreground:
      colorFromNode(jsonNode{"colors", "statusLine.foreground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})
  setEditorColor statusLineInsertMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeInsertMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      white
  setEditorColor statusLineInsertModeInactive:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineVisualMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeVisualMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      white
  setEditorColor statusLineVisualModeInactive:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineReplaceMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeReplaceMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      white
  setEditorColor statusLineReplaceModeInactive:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineFilerMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeFilerMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      white
  setEditorColor statusLineFilerModeInactive:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineExMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineModeExMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      white
  setEditorColor statusLineExModeInactive:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  setEditorColor statusLineGitBranch:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "statusLine.background"})
  # command  bar
  setEditorColor commandBar:
    foreground:
      adjust: ReadableVsBackground
    background:
      Color.default
  # error message
  setEditorColor errorMessage:
    foreground:
      colorFromNode(getScope("console.error"){"foreground"})
    background:
      Color.default
  setEditorColor currentTab:
    foreground:
      colorFromNode(jsonNode{"colors", "tab.foreground"})
    background:
      colorFromNode(jsonNode{"colors", "tab.activeBackground"})

  setEditorColor tab:
    foreground:
      colorFromNode(jsonNode{"colors", "tab.foreground"})
    background:
      colorFromNode(jsonNode{"colors", "tab.inactiveBackground"})

  setEditorColor lineNum:
    foreground:
      colorFromNode(jsonNode{"colors", "editorLineNumber.foreground"})
      adjust: InverseBackground
    background:
      colorFromNode(jsonNode{"colors", "editorLineNumber.background"})

  setEditorColor currentLineNum:
    foreground:
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})

  setEditorColor pcLink:
    foreground:
      colorFromNode(getScope("hyperlink"){"foreground"})
      adjust: ReadableVsBackground
    background:
      Color.default

  # highlight other uses current word
  setEditorColor currentWord:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})

  setEditorColor popupWinCurrentLine:
    foreground:
      colorFromNode(jsonNode{"colors", "sideBarTitle.forground"})
    background:
      colorFromNode(jsonNode{"colors", "sideBarSectionHeader.background"})

  # pop up window
  setEditorColor popupWindow:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "sideBar.background"})
  setEditorColor popupWinCurrentLine:
    foreground:
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "sideBar.background"})

  # pair of paren highlighting
  setEditorColor parenText:
    foreground:
      colorFromNode(getScope("unnamedScope"){"bracketsForeground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})

  # replace text highlighting
  setEditorColor replaceText:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors",
        "gitDecoration.conflictingResourceForeground"})

  # filer mode
  setEditorColor currentFile:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.selectionBackground"})
  setEditorColor file:
    foreground:
      adjust: ReadableVsBackground
    background:
      Color.default
  setEditorColor dir:
    foreground:
      colorFromNode(getScope("hyperlink"){"foreground"})
      adjust: ReadableVsBackground
    background:
      Color.default

  # highlight full width space
  setEditorColor highlightFullWidthSpace:
    foreground:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})
    background:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

  # highlight trailing spaces
  setEditorColor highlightTrailingSpaces:
    foreground:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})
    background:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

  # highlight diff
  setEditorColor addedLine:
    foreground:
      colorFromNode(jsonNode{"colors", "diff.inserted"})
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})
  setEditorColor deletedLine:
    foreground:
      colorFromNode(jsonNode{"colors", "diff.deleted"})
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})

  # search result highlighting
  setEditorColor searchResult:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

  # selected area in visual mode
  setEditorColor visualMode:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "tab.activeBorder"})

  # Backup manager
  setEditorColor currentBackup:
    foreground:
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})

  # Configuration mode
  setEditorColor currentSetting:
    foreground:
      colorFromNode(jsonNode{"colors", "editorCursor.foreground"})
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "editor.background"})

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

proc parseVsCodeThemeJson(
  packageJson: JsonNode,
  themeName, extensionDir: string): Option[JsonNode] =

    let themesJson = packageJson{"contributes", "themes"}
    if themesJson != nil and themesJson.kind == JArray:
      for theme in themesJson:
        if theme{"id"} != nil and theme{"id"}.getStr == themeName:
          let themePath = theme{"path"}

          if themePath != nil and themePath.kind == JString:
            let themeFilePath = parentDir(extensionDir) / themePath.getStr()

            if fileExists(themeFilePath):
              result =
                try: some(json.parseFile(themeFilePath))
                except CatchableError: none(JsonNode)

proc isCurrentVsCodeThemePackage(json: JsonNode, themeName: string): bool =
  # Return true if `json` is the current VSCode theme.

  if json{"displayName"} != nil:
    if json{"displayName"}.getStr == "%displayName%":
      let themes = json{"contributes", "themes"}
      if themes != nil and themes.kind == JArray:
        for t in themes:
          if t{"id"} != nil and t{"id"}.getStr == themeName:
            return true
    else:
      if json{"displayName"}.getStr == themeName: return true

proc loadVSCodeTheme*(): colorTheme =
  # If no vscode theme can be found, this defaults to the dark theme.
  # Hopefully other contributors will come and add support for Windows,
  # and other systems.

  result = colorTheme.dark

  let vsCodeFlavor = detectVsCodeFlavor()
  if vsCodeFlavor.isNone: return colorTheme.dark

  let
    # load the VSCode user settings json
    settingsFilePath = vsCodeSettingsFilePath(vsCodeFlavor.get)
    settingsJson =
      try: json.parseFile(settingsFilePath)
      except CatchableError: return colorTheme.dark

  # The current theme name
  if settingsJson{"workbench.colorTheme"} == nil or
     settingsJson{"workbench.colorTheme"}.getStr == "": return colorTheme.dark

  let themeSetting = settingsJson{"workbench.colorTheme"}.getStr

  # First, Check build in themes.
  let defaultExtesionsDir = vsCodeDefaultExtensionsDir(vsCodeFlavor.get)
  if dirExists(defaultExtesionsDir):
    for file in walkPattern(defaultExtesionsDir / "*/package.json" ):
      let packageJson =
        try: json.parseFile(file)
        except CatchableError: continue

      if isCurrentVsCodeThemePackage(packageJson, themeSetting):
        let themeJson = parseVsCodeThemeJson(
          packageJson,
          themeSetting,
          file)
        if themeJson.isSome:
          colorThemeTable[colorTheme.vscode] =
            makecolorThemeFromVSCodeThemeFile(themeJson.get)
          return colorTheme.vscode

  # Check user themes.
  let userExtensionsDir = vsCodeUserExtensionsDir(vsCodeFlavor.get)
  if dirExists(userExtensionsDir):
    for file in walkPattern(userExtensionsDir / "*/package.json" ):
      let packageJson =
        try: json.parseFile(file)
        except CatchableError: continue

      if isCurrentVsCodeThemePackage(packageJson, themeSetting):
        let themeJson = parseVsCodeThemeJson(
          packageJson,
          themeSetting,
          file)
        if themeJson.isSome:
          colorThemeTable[colorTheme.vscode] =
            makecolorThemeFromVSCodeThemeFile(themeJson.get)
          return colorTheme.vscode

proc parseSettingsFile*(settings: TomlValueRef): EditorSettings =
  result = initEditorSettings()

  if settings.contains("Standard"):
    template cursorType(str: string): untyped =
      parseEnum[CursorType](str)

    if settings["Standard"].contains("theme"):
      let themeString = settings["Standard"]["theme"].getStr()
      result.editorColorTheme = getTheme(themeString)

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
          reservedWord = ReservedWord(word: word, color: EditorColorPair.reservedWord)
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

  if result.editorColorTheme == colorTheme.config and
     settings.contains("Theme"):
    if settings["Theme"].contains("baseTheme"):
      let themeString = settings["Theme"]["baseTheme"].getStr()
      if fileExists(themeString):
        # TODO: Test this
        let jsonNode =
          try: some(json.parseFile(themeString))
          except CatchableError: none(JsonNode)
        if jsonNode.isSome:
          colorThemeTable[colorTheme.config] = makecolorThemeFromVSCodeThemeFile(jsonNode.get)
        else:
          let theme = parseEnum[colorTheme](themeString)
          colorThemeTable[colorTheme.config] = colorThemeTable[theme]
      else:
        let theme = parseEnum[colorTheme](themeString)
        colorThemeTable[colorTheme.config] = colorThemeTable[theme]

    template color(str: string): untyped =
      parseEnum[Color](settings["Theme"][str].getStr())

    if settings["Theme"].contains("editorBg"):
      colorThemeTable[colorTheme.config].editorBg = color("editorBg")

    if settings["Theme"].contains("lineNum"):
      colorThemeTable[colorTheme.config].lineNum = color("lineNum")

    if settings["Theme"].contains("lineNumBg"):
      colorThemeTable[colorTheme.config].lineNumBg = color("lineNumBg")

    if settings["Theme"].contains("currentLineNum"):
      colorThemeTable[colorTheme.config].currentLineNum = color("currentLineNum")

    if settings["Theme"].contains("currentLineNumBg"):
      colorThemeTable[colorTheme.config].currentLineNumBg = color("currentLineNumBg")

    if settings["Theme"].contains("statusLineNormalMode"):
      colorThemeTable[colorTheme.config].statusLineNormalMode = color("statusLineNormalMode")

    if settings["Theme"].contains("statusLineNormalModeBg"):
      colorThemeTable[colorTheme.config].statusLineNormalModeBg = color("statusLineNormalModeBg")

    if settings["Theme"].contains("statusLineModeNormalMode"):
      colorThemeTable[colorTheme.config].statusLineModeNormalMode = color("statusLineModeNormalMode")

    if settings["Theme"].contains("statusLineModeNormalModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeNormalModeBg = color("statusLineModeNormalModeBg")

    if settings["Theme"].contains("statusLineNormalModeInactive"):
      colorThemeTable[colorTheme.config].statusLineNormalModeInactive = color("statusLineNormalModeInactive")

    if settings["Theme"].contains("statusLineNormalModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineNormalModeInactiveBg = color("statusLineNormalModeInactiveBg")

    if settings["Theme"].contains("statusLineInsertMode"):
      colorThemeTable[colorTheme.config].statusLineInsertMode = color("statusLineInsertMode")

    if settings["Theme"].contains("statusLineInsertModeBg"):
      colorThemeTable[colorTheme.config].statusLineInsertModeBg = color("statusLineInsertModeBg")

    if settings["Theme"].contains("statusLineModeInsertMode"):
      colorThemeTable[colorTheme.config].statusLineModeInsertMode = color("statusLineModeInsertMode")

    if settings["Theme"].contains("statusLineModeInsertModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeInsertModeBg = color("statusLineModeInsertModeBg")

    if settings["Theme"].contains("statusLineInsertModeInactive"):
      colorThemeTable[colorTheme.config].statusLineInsertModeInactive = color("statusLineInsertModeInactive")

    if settings["Theme"].contains("statusLineInsertModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineInsertModeInactiveBg = color("statusLineInsertModeInactiveBg")

    if settings["Theme"].contains("statusLineVisualMode"):
      colorThemeTable[colorTheme.config].statusLineVisualMode = color("statusLineVisualMode")

    if settings["Theme"].contains("statusLineVisualModeBg"):
      colorThemeTable[colorTheme.config].statusLineVisualModeBg = color("statusLineVisualModeBg")

    if settings["Theme"].contains("statusLineModeVisualMode"):
      colorThemeTable[colorTheme.config].statusLineModeVisualMode = color("statusLineModeVisualMode")

    if settings["Theme"].contains("statusLineModeVisualModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeVisualModeBg = color("statusLineModeVisualModeBg")

    if settings["Theme"].contains("statusLineVisualModeInactive"):
      colorThemeTable[colorTheme.config].statusLineVisualModeInactive = color("statusLineVisualModeInactive")

    if settings["Theme"].contains("statusLineVisualModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineVisualModeInactiveBg = color("statusLineVisualModeInactiveBg")

    if settings["Theme"].contains("statusLineReplaceMode"):
      colorThemeTable[colorTheme.config].statusLineReplaceMode = color("statusLineReplaceMode")

    if settings["Theme"].contains("statusLineReplaceModeBg"):
      colorThemeTable[colorTheme.config].statusLineReplaceModeBg = color("statusLineReplaceModeBg")

    if settings["Theme"].contains("statusLineModeReplaceMode"):
      colorThemeTable[colorTheme.config].statusLineModeReplaceMode = color("statusLineModeReplaceMode")

    if settings["Theme"].contains("statusLineModeReplaceModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeReplaceModeBg = color("statusLineModeReplaceModeBg")

    if settings["Theme"].contains("statusLineReplaceModeInactive"):
      colorThemeTable[colorTheme.config].statusLineReplaceModeInactive = color("statusLineReplaceModeInactive")

    if settings["Theme"].contains("statusLineReplaceModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineReplaceModeInactiveBg = color("statusLineReplaceModeInactiveBg")

    if settings["Theme"].contains("statusLineFilerMode"):
      colorThemeTable[colorTheme.config].statusLineFilerMode = color("statusLineFilerMode")

    if settings["Theme"].contains("statusLineFilerModeBg"):
      colorThemeTable[colorTheme.config].statusLineFilerModeBg = color("statusLineFilerModeBg")

    if settings["Theme"].contains("statusLineModeFilerMode"):
      colorThemeTable[colorTheme.config].statusLineModeFilerMode = color("statusLineModeFilerMode")

    if settings["Theme"].contains("statusLineModeFilerModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeFilerModeBg = color("statusLineModeFilerModeBg")

    if settings["Theme"].contains("statusLineFilerModeInactive"):
      colorThemeTable[colorTheme.config].statusLineFilerModeInactive = color("statusLineFilerModeInactive")

    if settings["Theme"].contains("statusLineFilerModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineFilerModeInactiveBg = color("statusLineFilerModeInactiveBg")

    if settings["Theme"].contains("statusLineExMode"):
      colorThemeTable[colorTheme.config].statusLineExMode = color("statusLineExMode")

    if settings["Theme"].contains("statusLineExModeBg"):
      colorThemeTable[colorTheme.config].statusLineExModeBg = color("statusLineExModeBg")

    if settings["Theme"].contains("statusLineModeExMode"):
      colorThemeTable[colorTheme.config].statusLineModeExMode = color("statusLineModeExMode")

    if settings["Theme"].contains("statusLineModeExModeBg"):
      colorThemeTable[colorTheme.config].statusLineModeExModeBg = color("statusLineModeExModeBg")

    if settings["Theme"].contains("statusLineExModeInactive"):
      colorThemeTable[colorTheme.config].statusLineExModeInactive = color("statusLineExModeInactive")

    if settings["Theme"].contains("statusLineExModeInactiveBg"):
      colorThemeTable[colorTheme.config].statusLineExModeInactiveBg = color("statusLineExModeInactiveBg")

    if settings["Theme"].contains("statusLineGitBranch"):
      colorThemeTable[colorTheme.config].statusLineGitBranch = color("statusLineGitBranch")

    if settings["Theme"].contains("statusLineGitBranchBg"):
      colorThemeTable[colorTheme.config].statusLineGitBranchBg = color("statusLineGitBranchBg")

    if settings["Theme"].contains("tab"):
      colorThemeTable[colorTheme.config].tab = color("tab")

    if settings["Theme"].contains("tabBg"):
      colorThemeTable[colorTheme.config].tabBg = color("tabBg")

    if settings["Theme"].contains("currentTab"):
      colorThemeTable[colorTheme.config].currentTab = color("currentTab")

    if settings["Theme"].contains("currentTabBg"):
      colorThemeTable[colorTheme.config].currentTabBg = color("currentTabBg")

    if settings["Theme"].contains("commandBar"):
      colorThemeTable[colorTheme.config].commandBar = color("commandBar")

    if settings["Theme"].contains("commandBarBg"):
      colorThemeTable[colorTheme.config].commandBarBg = color("commandBarBg")

    if settings["Theme"].contains("errorMessage"):
      colorThemeTable[colorTheme.config].errorMessage = color("errorMessage")

    if settings["Theme"].contains("errorMessageBg"):
      colorThemeTable[colorTheme.config].errorMessageBg = color("errorMessageBg")

    if settings["Theme"].contains("searchResult"):
      colorThemeTable[colorTheme.config].searchResult = color("searchResult")

    if settings["Theme"].contains("searchResultBg"):
      colorThemeTable[colorTheme.config].searchResultBg = color("searchResultBg")

    if settings["Theme"].contains("visualMode"):
      colorThemeTable[colorTheme.config].visualMode = color("visualMode")

    if settings["Theme"].contains("visualModeBg"):
      colorThemeTable[colorTheme.config].visualModeBg = color("visualModeBg")

    if settings["Theme"].contains("defaultChar"):
      colorThemeTable[colorTheme.config].defaultChar = color("defaultChar")

    if settings["Theme"].contains("gtKeyword"):
      colorThemeTable[colorTheme.config].gtKeyword = color("gtKeyword")

    if settings["Theme"].contains("gtFunctionName"):
      colorThemeTable[colorTheme.config].gtFunctionName = color("gtFunctionName")

    if settings["Theme"].contains("gtTypeName"):
      colorThemeTable[colorTheme.config].gtTypeName = color("gtTypeName")

    if settings["Theme"].contains("gtBoolean"):
      colorThemeTable[colorTheme.config].gtBoolean = color("gtBoolean")

    if settings["Theme"].contains("gtSpecialVar"):
      colorThemeTable[colorTheme.config].gtSpecialVar = color("gtSpecialVar")

    if settings["Theme"].contains("gtBuiltin"):
      colorThemeTable[colorTheme.config].gtBuiltin = color("gtBuiltin")

    if settings["Theme"].contains("gtStringLit"):
      colorThemeTable[colorTheme.config].gtStringLit = color("gtStringLit")

    if settings["Theme"].contains("gtBinNumber"):
      colorThemeTable[colorTheme.config].gtBinNumber = color("gtBinNumber")

    if settings["Theme"].contains("gtDecNumber"):
      colorThemeTable[colorTheme.config].gtDecNumber = color("gtDecNumber")

    if settings["Theme"].contains("gtFloatNumber"):
      colorThemeTable[colorTheme.config].gtFloatNumber = color("gtFloatNumber")

    if settings["Theme"].contains("gtHexNumber"):
      colorThemeTable[colorTheme.config].gtHexNumber = color("gtHexNumber")

    if settings["Theme"].contains("gtOctNumber"):
      colorThemeTable[colorTheme.config].gtOctNumber = color("gtOctNumber")

    if settings["Theme"].contains("gtComment"):
      colorThemeTable[colorTheme.config].gtComment = color("gtComment")

    if settings["Theme"].contains("gtLongComment"):
      colorThemeTable[colorTheme.config].gtLongComment = color("gtLongComment")

    if settings["Theme"].contains("gtWhitespace"):
      colorThemeTable[colorTheme.config].gtWhitespace = color("gtWhitespace")

    if settings["Theme"].contains("gtPreprocessor"):
      colorThemeTable[colorTheme.config].gtPreprocessor = color("gtPreprocessor")

    if settings["Theme"].contains("currentFile"):
      colorThemeTable[colorTheme.config].currentFile = color("currentFile")

    if settings["Theme"].contains("currentFileBg"):
      colorThemeTable[colorTheme.config].currentFileBg = color("currentFileBg")

    if settings["Theme"].contains("file"):
      colorThemeTable[colorTheme.config].file = color("file")

    if settings["Theme"].contains("fileBg"):
      colorThemeTable[colorTheme.config].fileBg = color("fileBg")

    if settings["Theme"].contains("dir"):
      colorThemeTable[colorTheme.config].dir = color("dir")

    if settings["Theme"].contains("dirBg"):
      colorThemeTable[colorTheme.config].dirBg = color("dirBg")

    if settings["Theme"].contains("pcLink"):
      colorThemeTable[colorTheme.config].pcLink = color("pcLink")

    if settings["Theme"].contains("pcLinkBg"):
      colorThemeTable[colorTheme.config].pcLinkBg = color("pcLinkBg")

    if settings["Theme"].contains("popupWindow"):
      colorThemeTable[colorTheme.config].popupWindow = color("popupWindow")

    if settings["Theme"].contains("popupWindowBg"):
      colorThemeTable[colorTheme.config].popupWindowBg = color("popupWindowBg")

    if settings["Theme"].contains("popupWinCurrentLine"):
      colorThemeTable[colorTheme.config].popupWinCurrentLine = color("popupWinCurrentLine")

    if settings["Theme"].contains("popupWinCurrentLineBg"):
      colorThemeTable[colorTheme.config].popupWinCurrentLineBg = color("popupWinCurrentLineBg")

    if settings["Theme"].contains("replaceText"):
      colorThemeTable[colorTheme.config].replaceText = color("replaceText")

    if settings["Theme"].contains("replaceTextBg"):
      colorThemeTable[colorTheme.config].replaceTextBg = color("replaceTextBg")

    if settings["Theme"].contains("parenText"):
      colorThemeTable[colorTheme.config].parenText = color("parenText")

    if settings["Theme"].contains("parenTextBg"):
      colorThemeTable[colorTheme.config].parenTextBg = color("parenTextBg")

    if settings["Theme"].contains("currentWordBg"):
      colorThemeTable[colorTheme.config].currentWordBg = color("currentWordBg")

    if settings["Theme"].contains("highlightFullWidthSpace"):
      colorThemeTable[colorTheme.config].highlightFullWidthSpace = color("highlightFullWidthSpace")

    if settings["Theme"].contains("highlightFullWidthSpaceBg"):
      colorThemeTable[colorTheme.config].highlightFullWidthSpaceBg = color("highlightFullWidthSpaceBg")

    if settings["Theme"].contains("highlightTrailingSpaces"):
      colorThemeTable[colorTheme.config].highlightTrailingSpaces = color("highlightTrailingSpaces")

    if settings["Theme"].contains("highlightTrailingSpacesBg"):
      colorThemeTable[colorTheme.config].highlightTrailingSpacesBg = color("highlightTrailingSpacesBg")

    if settings["Theme"].contains("reservedWord"):
      colorThemeTable[colorTheme.config].reservedWord = color("reservedWord")

    if settings["Theme"].contains("reservedWordBg"):
      colorThemeTable[colorTheme.config].reservedWordBg = color("reservedWordBg")

    if settings["Theme"].contains("currentBackup"):
      colorThemeTable[colorTheme.config].currentBackup = color("currentBackup")

    if settings["Theme"].contains("currentBackupBg"):
      colorThemeTable[colorTheme.config].currentBackupBg = color("currentBackupBg")

    if settings["Theme"].contains("addedLine"):
      colorThemeTable[colorTheme.config].addedLine = color("addedLine")

    if settings["Theme"].contains("addedLineBg"):
      colorThemeTable[colorTheme.config].addedLineBg = color("addedLineBg")

    if settings["Theme"].contains("deletedLine"):
      colorThemeTable[colorTheme.config].deletedLine = color("deletedLine")

    if settings["Theme"].contains("deletedLineBg"):
      colorThemeTable[colorTheme.config].deletedLineBg = color("deletedLineBg")

    if settings["Theme"].contains("currentSetting"):
      colorThemeTable[colorTheme.config].currentSetting = color("currentSetting")

    if settings["Theme"].contains("currentSettingBg"):
      colorThemeTable[colorTheme.config].currentSettingBg = color("currentSettingBg")

    if settings["Theme"].contains("currentLineBg"):
      colorThemeTable[colorTheme.config].currentLineBg = color("currentLineBg")

    result.editorColorTheme = colorTheme.config

  if result.editorColorTheme == colorTheme.vscode:
    result.editorColorTheme = loadVSCodeTheme()

proc validateStandardTable(table: TomlValueRef): Option[InvalidItem] =
  for key, val in table.getTable:
    case key:
      of "theme":
        var correctValue = false
        if val.getStr == "vscode":
          correctValue = true
        else:
          for theme in colorTheme:
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
         "liveReloadOfFile":
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
  let editorColors = colorThemeTable[colorTheme.config]
  for key, val in table.getTable:
    case key:
      of "baseTheme":
        var correctKey = false
        for theme in colorTheme:
          if $theme == val.getStr:
            correctKey = true
        if not correctKey: return some(InvalidItem(name: $key, val: $val))
      else:
        # Check color names
        var correctKey = false
        for field, fieldVal in editorColors.fieldPairs:
          if key == field and
             val.kind == TomlValueKind.String:
            for color in Color:
              if val.getStr == $color:
                correctKey = true
                break
            if correctKey: break
        if not correctKey:
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

# Generate a string of the configuration file of  TOML.
proc generateTomlConfigStr*(settings: EditorSettings): string =
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

  let theme = colorThemeTable[colorTheme.config]
  result.addLine fmt "[Theme]"
  result.addLine fmt "baseTheme = \"{$settings.editorcolorTheme}\""
  result.addLine fmt "editorBg = \"{$theme.editorBg}\""
  result.addLine fmt "lineNum = \"{$theme.lineNum}\""
  result.addLine fmt "lineNumBg = \"{$theme.lineNumBg}\""
  result.addLine fmt "currentLineNum = \"{$theme.currentLineNum}\""
  result.addLine fmt "currentLineNumBg = \"{$theme.currentLineNumBg}\""
  result.addLine fmt "statusLineNormalMode = \"{$theme.statusLineNormalMode}\""
  result.addLine fmt "statusLineNormalModeBg = \"{$theme.statusLineNormalModeBg}\""
  result.addLine fmt "statusLineModeNormalMode = \"{$theme.statusLineNormalMode}\""
  result.addLine fmt "statusLineModeNormalModeBg = \"{$theme.statusLineNormalModeBg}\""
  result.addLine fmt "statusLineNormalModeInactive = \"{$theme.statusLineNormalModeInactive}\""
  result.addLine fmt "statusLineNormalModeInactiveBg = \"{$theme.statusLineNormalModeInactiveBg}\""
  result.addLine fmt "statusLineInsertMode = \"{$theme.statusLineInsertMode}\""
  result.addLine fmt "statusLineInsertModeBg = \"{$theme.statusLineInsertModeBg}\""
  result.addLine fmt "statusLineModeInsertMode = \"{$theme.statusLineModeInsertMode}\""
  result.addLine fmt "statusLineModeInsertModeBg = \"{$theme.statusLineModeInsertModeBg}\""
  result.addLine fmt "statusLineInsertModeInactive = \"{$theme.statusLineInsertModeInactive}\""
  result.addLine fmt "statusLineInsertModeInactiveBg = \"{$theme.statusLineInsertModeInactiveBg}\""
  result.addLine fmt "statusLineVisualMode = \"{$theme.statusLineVisualMode}\""
  result.addLine fmt "statusLineVisualModeBg = \"{$theme.statusLineVisualModeBg}\""
  result.addLine fmt "statusLineModeVisualMode = \"{$theme.statusLineModeVisualMode}\""
  result.addLine fmt "statusLineModeVisualModeBg = \"{$theme.statusLineModeVisualModeBg}\""
  result.addLine fmt "statusLineVisualModeInactive = \"{$theme.statusLineVisualModeInactive}\""
  result.addLine fmt "statusLineVisualModeInactiveBg = \"{$theme.statusLineVisualModeInactiveBg}\""
  result.addLine fmt "statusLineReplaceMode = \"{$theme.statusLineReplaceMode}\""
  result.addLine fmt "statusLineReplaceModeBg = \"{$theme.statusLineReplaceModeBg}\""
  result.addLine fmt "statusLineModeReplaceMode = \"{$theme.statusLineModeReplaceMode}\""
  result.addLine fmt "statusLineModeReplaceModeBg = \"{$theme.statusLineModeReplaceModeBg}\""
  result.addLine fmt "statusLineReplaceModeInactive = \"{$theme.statusLineReplaceModeInactive}\""
  result.addLine fmt "statusLineReplaceModeInactiveBg = \"{$theme.statusLineReplaceModeInactiveBg}\""
  result.addLine fmt "statusLineFilerMode = \"{$theme.statusLineFilerMode}\""
  result.addLine fmt "statusLineFilerModeBg = \"{$theme.statusLineFilerModeBg}\""
  result.addLine fmt "statusLineModeFilerMode = \"{$theme.statusLineModeFilerMode}\""
  result.addLine fmt "statusLineModeFilerModeBg = \"{$theme.statusLineModeFilerModeBg}\""
  result.addLine fmt "statusLineFilerModeInactive = \"{$theme.statusLineFilerModeInactive}\""
  result.addLine fmt "statusLineFilerModeInactiveBg = \"{$theme.statusLineFilerModeInactiveBg}\""
  result.addLine fmt "statusLineExMode = \"{$theme.statusLineExMode}\""
  result.addLine fmt "statusLineExModeBg = \"{$theme.statusLineExModeBg}\""
  result.addLine fmt "statusLineModeExMode = \"{$theme.statusLineModeExMode}\""
  result.addLine fmt "statusLineModeExModeBg = \"{$theme.statusLineModeExModeBg}\""
  result.addLine fmt "statusLineExModeInactive = \"{$theme.statusLineExModeInactive}\""
  result.addLine fmt "statusLineExModeInactiveBg = \"{$theme.statusLineExModeInactiveBg}\""
  result.addLine fmt "statusLineGitBranch = \"{$theme.statusLineGitBranch}\""
  result.addLine fmt "statusLineGitBranchBg = \"{$theme.statusLineGitBranchBg}\""
  result.addLine fmt "tab = \"{$theme.tab}\""
  result.addLine fmt "tabBg = \"{$theme.tabBg}\""
  result.addLine fmt "currentTab = \"{$theme.currentTab}\""
  result.addLine fmt "currentTabBg = \"{$theme.currentTabBg}\""
  result.addLine fmt "commandBar = \"{$theme.commandBar}\""
  result.addLine fmt "commandBarBg = \"{$theme.currentTabBg}\""
  result.addLine fmt "errorMessage = \"{$theme.errorMessage}\""
  result.addLine fmt "errorMessageBg = \"{$theme.errorMessageBg}\""
  result.addLine fmt "searchResult = \"{$theme.searchResult}\""
  result.addLine fmt "searchResultBg = \"{$theme.searchResultBg}\""
  result.addLine fmt "visualMode = \"{$theme.visualMode}\""
  result.addLine fmt "visualModeBg = \"{$theme.visualModeBg}\""
  result.addLine fmt "defaultChar = \"{$theme.defaultChar}\""
  result.addLine fmt "gtKeyword = \"{$theme.gtKeyword}\""
  result.addLine fmt "gtFunctionName = \"{$theme.gtFunctionName}\""
  result.addLine fmt "gtTypeName= \"{$theme.gtTypeName}\""
  result.addLine fmt "gtBoolean = \"{$theme.gtBoolean}\""
  result.addLine fmt "gtStringLit = \"{$theme.gtStringLit}\""
  result.addLine fmt "gtSpecialVar = \"{$theme.gtSpecialVar}\""
  result.addLine fmt "gtBuiltin = \"{$theme.gtBuiltin}\""
  result.addLine fmt "gtBinNumber = \"{$theme.gtBinNumber}\""
  result.addLine fmt "gtDecNumber = \"{$theme.gtDecNumber}\""
  result.addLine fmt "gtFloatNumber = \"{$theme.gtFloatNumber}\""
  result.addLine fmt "gtHexNumber = \"{$theme.gtHexNumber}\""
  result.addLine fmt "gtOctNumber = \"{$theme.gtOctNumber}\""
  result.addLine fmt "gtComment = \"{$theme.gtComment}\""
  result.addLine fmt "gtLongComment = \"{$theme.gtLongComment}\""
  result.addLine fmt "gtWhitespace = \"{$theme.gtWhitespace}\""
  result.addLine fmt "gtPreprocessor = \"{$theme.gtPreprocessor}\""
  result.addLine fmt "currentFile = \"{$theme.currentFile}\""
  result.addLine fmt "currentFileBg = \"{$theme.currentFileBg}\""
  result.addLine fmt "file = \"{$theme.file}\""
  result.addLine fmt "fileBg = \"{$theme.fileBg}\""
  result.addLine fmt "dir = \"{$theme.dir}\""
  result.addLine fmt "dirBg = \"{$theme.dirBg}\""
  result.addLine fmt "pcLink = \"{$theme.pcLink}\""
  result.addLine fmt "pcLinkBg = \"{$theme.pcLinkBg}\""
  result.addLine fmt "popupWindow = \"{$theme.popupWindow}\""
  result.addLine fmt "popupWindowBg = \"{$theme.popupWindowBg}\""
  result.addLine fmt "popupWinCurrentLine = \"{$theme.popupWinCurrentLine}\""
  result.addLine fmt "popupWinCurrentLineBg = \"{$theme.popupWinCurrentLineBg}\""
  result.addLine fmt "replaceText = \"{$theme.replaceText}\""
  result.addLine fmt "replaceTextBg = \"{$theme.replaceTextBg}\""
  result.addLine fmt "parenText = \"{$theme.parenText}\""
  result.addLine fmt "parenTextBg = \"{$theme.parenTextBg}\""
  result.addLine fmt "currentWord = \"{$theme.currentWord}\""
  result.addLine fmt "currentWordBg = \"{$theme.currentFileBg}\""
  result.addLine fmt "highlightFullWidthSpace = \"{$theme.highlightFullWidthSpace}\""
  result.addLine fmt "highlightFullWidthSpaceBg = \"{$theme.highlightFullWidthSpaceBg}\""
  result.addLine fmt "highlightTrailingSpaces = \"{$theme.highlightTrailingSpaces}\""
  result.addLine fmt "highlightTrailingSpacesBg = \"{$theme.highlightTrailingSpacesBg}\""
  result.addLine fmt "reservedWord = \"{$theme.reservedWord}\""
  result.addLine fmt "reservedWordBg = \"{$theme.reservedWordBg}\""
  result.addLine fmt "currentSetting = \"{$theme.currentSetting}\""
  result.addLine fmt "currentSettingBg = \"{$theme.currentSettingBg}\""
  result.addLine fmt "currentLineBg = \"{$theme.currentLineBg}\""
