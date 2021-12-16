import std/[os, json, macros, times, options, strformat, osproc,
            strutils]
import ui, color, unicodeext, highlight, platform, independentutils
import parsetoml

export TomlError

type DebugWindowNodeSettings* = object
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

type DebugBufferStatusSettings* = object
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

type DebugEditorViewSettings* = object
  enable*: bool
  widthOfLineNum*: bool
  height*: bool
  width*: bool
  originalLine*: bool
  start*: bool
  length*: bool

type DebugModeSettings* = object
  windowNode*: DebugWindowNodeSettings
  editorview*: DebugEditorViewSettings
  bufStatus*: DebugBufferStatusSettings

type NotificationSettings* = object
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

type BuildOnSaveSettings* = object
  enable*: bool
  workspaceRoot*: seq[Rune]
  command*: seq[Rune]

type QuickRunSettings* = object
  saveBufferWhenQuickRun*: bool
  command*: string
  timeout*: int # seconds
  nimAdvancedCommand*: string
  ClangOptions*: string
  CppOptions*: string
  NimOptions*: string
  shOptions*: string
  bashOptions*: string

type AutoBackupSettings* = object
  enable*: bool
  idleTime*: int # seconds
  interval*: int # minutes
  backupDir*: seq[Rune]
  dirToExclude*: seq[seq[Rune]]

type FilerSettings* = object
  showIcons*: bool

type StatusLineSettings* = object
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

type TabLineSettings* = object
  enable*: bool
  allbuffer*: bool

type EditorViewSettings* = object
  highlightCurrentLine*: bool
  lineNumber*: bool
  currentLineNumber*: bool
  cursorLine*: bool
  indentationLines*: bool
  tabStop*: int

type AutocompleteSettings* = object
  enable*: bool

type HighlightSettings* = object
  replaceText*: bool
  pairOfParen*: bool
  currentWord*: bool
  fullWidthSpace*: bool
  trailingSpaces*: bool
  reservedWords*: seq[ReservedWord]

type PersistSettings* = object
  exCommand*: bool
  search*: bool
  cursorPosition*: bool

type ClipboardToolOnLinux* = enum
  none
  xsel
  xclip
  wlClipboard

type ClipboardSettings* = object
  enable*: bool
  toolOnLinux*: ClipboardToolOnLinux

type EditorSettings* = object
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
  popUpWindowInExmode*: bool
  autoDeleteParen*: bool
  smoothScroll*: bool
  smoothScrollSpeed*: int
  clipboard*: ClipboardSettings
  buildOnSave*: BuildOnSaveSettings
  filerSettings*: FilerSettings
  autocompleteSettings*: AutocompleteSettings
  autoBackupSettings*: AutoBackupSettings
  quickRunSettings*: QuickRunSettings
  notificationSettings*: NotificationSettings
  debugModeSettings*: DebugModeSettings
  highlightSettings*: HighlightSettings
  persist*: PersistSettings

type InvalidItem = object
  name: string
  val: string

# Warning: inherit from a more precise exception type like ValueError, IOError or OSError.
# If these don't suit, inherit from CatchableError or Defect. [InheritFromException]
type InvalidItemError* = object of ValueError

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
  result.enable = true
  result.interval = 5 # 5 minutes
  result.idleTime = 10 # 10 seconds
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
  result.search = true
  result.cursorPosition = true

# Automatically set the clipboard tool on GNU/Linux
proc autoSetClipboardTool(): ClipboardToolOnLinux =
  result = ClipboardToolOnLinux.none

  case CURRENT_PLATFORM:
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
  result.enable = true
  result.toolOnLinux = autoSetClipboardTool()

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
  # defaultCursor is terminal default curosr shape
  result.defaultCursor = CursorType.blinkBlock
  result.normalModeCursor = CursorType.blinkBlock
  result.insertModeCursor = CursorType.blinkIbeam
  result.autoSaveInterval = 5
  result.incrementalSearch = true
  result.popUpWindowInExmode = true
  result.smoothScroll = true
  result.smoothScrollSpeed = 15
  result.clipboard = initClipboardSettings()
  result.buildOnSave = BuildOnSaveSettings()
  result.filerSettings = initFilerSettings()
  result.autocompleteSettings = initAutocompleteSettings()
  result.autoBackupSettings = initAutoBackupSettings()
  result.quickRunSettings = initQuickRunSettings()
  result.notificationSettings = initNotificationSettings()
  result.debugModeSettings = initDebugModeSettings()
  result.highlightSettings = initHighlightSettings()
  result.persist = initPersistSettings()

proc getTheme(theme: string): ColorTheme =
  if theme == "vivid": return ColorTheme.vivid
  elif theme == "light": return ColorTheme.light
  elif theme == "config": return ColorTheme.config
  elif theme == "vscode": return ColorTheme.vscode
  else: return ColorTheme.dark

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

proc makeColorThemeFromVSCodeThemeFile(fileName: string): EditorColor =
  let jsonNode = json.parseFile(fileName)

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
  setEditorColor gtDecNumber:
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

  setEditorColor popUpWinCurrentLine:
    foreground:
      colorFromNode(jsonNode{"colors", "sideBarTitle.forground"})
    background:
      colorFromNode(jsonNode{"colors", "sideBarSectionHeader.background"})

  # pop up window
  setEditorColor popUpWindow:
    foreground:
      adjust: ReadableVsBackground
    background:
      colorFromNode(jsonNode{"colors", "sideBar.background"})
  setEditorColor popUpWinCurrentLine:
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

  # History manager
  setEditorColor currentHistory:
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

proc loadVSCodeTheme*(): ColorTheme =
  # search for the vscode theme that is set in the current preferences of
  # vscode/vscodium. Vscodium takes precedence, since you can assume that,
  # people that install VScodium prefer it over Vscode for privacy reasons.
  # If no vscode theme can be found, this defaults to the dark theme.
  # The first implementation is for finding the VsCode/VsCodium config and
  # extension folders on Linux. Hopefully other contributors will come and
  # add support for Windows, and other systems.
  var vsCodeThemeLoaded = false
  block vsCodeThemeLoading:
    let homeDir = getHomeDir()
    var vsCodeSettingsFile = homeDir & "/.config/VSCodium/User/settings.json"
    var vsCodeThemeFile = ""
    var vsCodeExtensionsDir = homeDir & "/.vscode/extensions/"
    var vsCodeThemeSetting = ""
    if not fileExists(vsCodeSettingsFile):
      vsCodeSettingsFile = homeDir & "/.config/Code/User/settings.json"
    if fileExists(vsCodeSettingsFile):
      let vsCodeSettingsJson = json.parseFile(vsCodeSettingsFile)
      vsCodeThemeSetting = vsCodeSettingsJson{"workbench.colorTheme"}.getStr()
      if vsCodeThemeSetting == "":
        break vsCodeThemeLoading

    else:
      break vsCodeThemeLoading

    if not dirExists(vsCodeExtensionsDir):
      vsCodeExtensionsDir = homeDir & "/.vscode-oss/extensions/"
      if not dirExists(vsCodeExtensionsDir):
        break vsCodeThemeLoading

    # Note: walkDirRec was first used to solve this, however
    #       the performance at runtime was much worse
    for file in walkPattern(vsCodeExtensionsDir & "/*/package.json"):
      if file.endsWith("/package.json"):
        var vsCodePackageJson: JsonNode
        try:
          vsCodePackageJson = json.parseFile(file)
        except:
          break vsCodeThemeLoading
        let displayName = vsCodePackageJson{"displayName"}
        if displayName == nil: continue

        if displayName.getStr() == vsCodeThemeSetting:
          let themesJson = vsCodePackageJson{"contributes", "themes"}
          if themesJson != nil and themesJson.len() > 0:
            let theTheme = themesJson[0]
            let theThemePath = theTheme{"path"}
            if theThemePath != nil and theThemePath.kind == JString:
              vsCodeThemeFile = parentDir(file) / theThemePath.getStr()
          else:
            break vsCodeThemeLoading
          break

    if fileExists(vsCodeThemeFile):
      result = ColorTheme.vscode
      ColorThemeTable[ColorTheme.vscode] =
        makeColorThemeFromVSCodeThemeFile(vsCodeThemeFile)
      vsCodeThemeLoaded = true
  if not vsCodeThemeLoaded:
    result = ColorTheme.dark

proc parseSettingsFile*(settings: TomlValueRef): EditorSettings =
  result = initEditorSettings()

  if settings.contains("Standard"):
    template cursorType(str: string): untyped =
      parseEnum[CursorType](str)

    if settings["Standard"].contains("theme"):
      let themeString = settings["Standard"]["theme"].getStr()
      result.editorColorTheme = getTheme(themeString)

    if settings["Standard"].contains("number"):
      result.view.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("currentNumber"):
      result.view.currentLineNumber = settings["Standard"]["currentNumber"].getbool()

    if settings["Standard"].contains("cursorLine"):
      result.view.cursorLine = settings["Standard"]["cursorLine"].getbool()

    if settings["Standard"].contains("statusLine"):
      result.statusLine.enable = settings["Standard"]["statusLine"].getbool()

    if settings["Standard"].contains("tabLine"):
      result.tabLine.enable = settings["Standard"]["tabLine"].getbool()

    if settings["Standard"].contains("syntax"):
      result.syntax = settings["Standard"]["syntax"].getbool()

    if settings["Standard"].contains("tabStop"):
      result.tabStop      = settings["Standard"]["tabStop"].getInt()
      result.view.tabStop = settings["Standard"]["tabStop"].getInt()

    if settings["Standard"].contains("autoCloseParen"):
      result.autoCloseParen = settings["Standard"]["autoCloseParen"].getbool()

    if settings["Standard"].contains("autoIndent"):
      result.autoIndent = settings["Standard"]["autoIndent"].getbool()

    if settings["Standard"].contains("ignorecase"):
      result.ignorecase = settings["Standard"]["ignorecase"].getbool()

    if settings["Standard"].contains("smartcase"):
      result.smartcase = settings["Standard"]["smartcase"].getbool()

    if settings["Standard"].contains("disableChangeCursor"):
      result.disableChangeCursor = settings["Standard"]["disableChangeCursor"].getbool()

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
      result.autoSave = settings["Standard"]["autoSave"].getbool()

    if settings["Standard"].contains("autoSaveInterval"):
      result.autoSaveInterval = settings["Standard"]["autoSaveInterval"].getInt()

    if settings["Standard"].contains("liveReloadOfConf"):
      result.liveReloadOfConf = settings["Standard"]["liveReloadOfConf"].getbool()

    if settings["Standard"].contains("incrementalSearch"):
      result.incrementalSearch = settings["Standard"]["incrementalSearch"].getbool()

    if settings["Standard"].contains("popUpWindowInExmode"):
      result.popUpWindowInExmode = settings["Standard"]["popUpWindowInExmode"].getbool()

    if settings["Standard"].contains("autoDeleteParen"):
      result.autoDeleteParen =  settings["Standard"]["autoDeleteParen"].getbool()

    if settings["Standard"].contains("smoothScroll"):
      result.smoothScroll =  settings["Standard"]["smoothScroll"].getbool()

    if settings["Standard"].contains("smoothScrollSpeed"):
      result.smoothScrollSpeed = settings["Standard"]["smoothScrollSpeed"].getint()

    if settings["Standard"].contains("indentationLines"):
      result.view.indentationLines = settings["Standard"]["indentationLines"].getbool()

  if settings.contains("Clipboard"):
    if settings["Clipboard"].contains("enable"):
      result.clipboard.enable = settings["Clipboard"]["enable"].getbool()

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
        result.tabLine.allBuffer= settings["TabLine"]["allBuffer"].getbool()

  if settings.contains("StatusLine"):
    if settings["StatusLine"].contains("multipleStatusLine"):
        result.statusLine.multipleStatusLine = settings["StatusLine"]["multipleStatusLine"].getbool()

    if settings["StatusLine"].contains("merge"):
        result.statusLine.merge = settings["StatusLine"]["merge"].getbool()

    if settings["StatusLine"].contains("mode"):
        result.statusLine.mode= settings["StatusLine"]["mode"].getbool()

    if settings["StatusLine"].contains("filename"):
        result.statusLine.filename = settings["StatusLine"]["filename"].getbool()

    if settings["StatusLine"].contains("chanedMark"):
        result.statusLine.chanedMark = settings["StatusLine"]["chanedMark"].getbool()

    if settings["StatusLine"].contains("line"):
        result.statusLine.line = settings["StatusLine"]["line"].getbool()

    if settings["StatusLine"].contains("column"):
        result.statusLine.column = settings["StatusLine"]["column"].getbool()

    if settings["StatusLine"].contains("encoding"):
        result.statusLine.characterEncoding = settings["StatusLine"]["encoding"].getbool()

    if settings["StatusLine"].contains("language"):
        result.statusLine.language = settings["StatusLine"]["language"].getbool()

    if settings["StatusLine"].contains("directory"):
        result.statusLine.directory = settings["StatusLine"]["directory"].getbool()

    if settings["StatusLine"].contains("gitbranchName"):
        result.statusLine.gitbranchName = settings["StatusLine"]["gitbranchName"].getbool()

    if settings["StatusLine"].contains("showGitInactive"):
        result.statusLine.showGitInactive = settings["StatusLine"]["showGitInactive"].getbool()

    if settings["StatusLine"].contains("showModeInactive"):
        result.statusLine.showModeInactive = settings["StatusLine"]["showModeInactive"].getbool()

  if settings.contains("BuildOnSave"):
    if settings["BuildOnSave"].contains("enable"):
      result.buildOnSave.enable = settings["BuildOnSave"]["enable"].getbool()

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
        result.highlightSettings.reservedWords.add(reservedWord)

    if settings["Highlight"].contains("currentLine"):
      result.view.highlightCurrentLine = settings["Highlight"]["currentLine"].getbool()

    if settings["Highlight"].contains("currentWord"):
      result.highlightSettings.currentWord = settings["Highlight"]["currentWord"].getbool()

    if settings["Highlight"].contains("replaceText"):
      result.highlightSettings.replaceText = settings["Highlight"]["replaceText"].getbool()

    if settings["Highlight"].contains("pairOfParen"):
      result.highlightSettings.pairOfParen =  settings["Highlight"]["pairOfParen"].getbool()

    if settings["Highlight"].contains("fullWidthSpace"):
      result.highlightSettings.fullWidthSpace = settings["Highlight"]["fullWidthSpace"].getbool()

    if settings["Highlight"].contains("trailingSpaces"):
      result.highlightSettings.trailingSpaces = settings["Highlight"]["trailingSpaces"].getbool()

  if settings.contains("AutoBackup"):
    if settings["AutoBackup"].contains("enable"):
      result.autoBackupSettings.enable = settings["AutoBackup"]["enable"].getbool()

    if settings["AutoBackup"].contains("idleTime"):
      result.autoBackupSettings.idleTime = settings["AutoBackup"]["idleTime"].getInt()

    if settings["AutoBackup"].contains("interval"):
      result.autoBackupSettings.interval = settings["AutoBackup"]["interval"].getInt()

    if settings["AutoBackup"].contains("backupDir"):
      let dir = settings["AutoBackup"]["backupDir"].getStr()
      result.autoBackupSettings.backupDir = dir.toRunes

    if settings["AutoBackup"].contains("dirToExclude"):
      result.autoBackupSettings.dirToExclude = @[]
      let dirs = settings["AutoBackup"]["dirToExclude"]
      for i in 0 ..< dirs.len:
        result.autoBackupSettings.dirToExclude.add(ru dirs[i].getStr)

  if settings.contains("QuickRun"):
    if settings["QuickRun"].contains("saveBufferWhenQuickRun"):
      let saveBufferWhenQuickRun = settings["QuickRun"]["saveBufferWhenQuickRun"].getBool()
      result.quickRunSettings.saveBufferWhenQuickRun = saveBufferWhenQuickRun

    if settings["QuickRun"].contains("command"):
      result.quickRunSettings.command = settings["QuickRun"]["command"].getStr()

    if settings["QuickRun"].contains("timeout"):
      result.quickRunSettings.timeout = settings["QuickRun"]["timeout"].getInt()

    if settings["QuickRun"].contains("nimAdvancedCommand"):
      result.quickRunSettings.nimAdvancedCommand = settings["QuickRun"]["nimAdvancedCommand"].getStr()

    if settings["QuickRun"].contains("ClangOptions"):
      result.quickRunSettings.ClangOptions = settings["QuickRun"]["ClangOptions"].getStr()

    if settings["QuickRun"].contains("CppOptions"):
      result.quickRunSettings.CppOptions = settings["QuickRun"]["CppOptions"].getStr()

    if settings["QuickRun"].contains("NimOptions"):
      result.quickRunSettings.NimOptions = settings["QuickRun"]["NimOptions"].getStr()

    if settings["QuickRun"].contains("shOptions"):
      result.quickRunSettings.shOptions = settings["QuickRun"]["shOptions"].getStr()

    if settings["QuickRun"].contains("bashOptions"):
      result.quickRunSettings.bashOptions = settings["QuickRun"]["bashOptions"].getStr()

  if settings.contains("Notification"):
    if settings["Notification"].contains("screenNotifications"):
      result.notificationSettings.screenNotifications = settings["Notification"]["screenNotifications"].getBool

    if settings["Notification"].contains("logNotifications"):
      result.notificationSettings.logNotifications = settings["Notification"]["logNotifications"].getBool

    if settings["Notification"].contains("autoBackupScreenNotify"):
      result.notificationSettings.autoBackupScreenNotify = settings["Notification"]["autoBackupScreenNotify"].getBool

    if settings["Notification"].contains("autoBackupLogNotify"):
      result.notificationSettings.autoBackupLogNotify = settings["Notification"]["autoBackupLogNotify"].getBool

    if settings["Notification"].contains("autoSaveScreenNotify"):
      result.notificationSettings.autoSaveScreenNotify = settings["Notification"]["autoSaveScreenNotify"].getBool

    if settings["Notification"].contains("autoSaveLogNotify"):
      result.notificationSettings.autoSaveLogNotify = settings["Notification"]["autoSaveLogNotify"].getBool

    if settings["Notification"].contains("yankScreenNotify"):
      result.notificationSettings.yankScreenNotify = settings["Notification"]["yankScreenNotify"].getBool

    if settings["Notification"].contains("yankLogNotify"):
      result.notificationSettings.yankLogNotify = settings["Notification"]["yankLogNotify"].getBool

    if settings["Notification"].contains("deleteScreenNotify"):
      result.notificationSettings.deleteScreenNotify = settings["Notification"]["deleteScreenNotify"].getBool

    if settings["Notification"].contains("deleteLogNotify"):
      result.notificationSettings.deleteLogNotify = settings["Notification"]["deleteLogNotify"].getBool

    if settings["Notification"].contains("saveScreenNotify"):
      result.notificationSettings.saveScreenNotify = settings["Notification"]["saveScreenNotify"].getBool

    if settings["Notification"].contains("saveLogNotify"):
      result.notificationSettings.saveLogNotify = settings["Notification"]["saveLogNotify"].getBool

    if settings["Notification"].contains("quickRunScreenNotify"):
      result.notificationSettings.quickRunScreenNotify = settings["Notification"]["quickRunScreenNotify"].getBool

    if settings["Notification"].contains("quickRunLogNotify"):
      result.notificationSettings.quickRunLogNotify = settings["Notification"]["quickRunLogNotify"].getBool

    if settings["Notification"].contains("buildOnSaveScreenNotify"):
      result.notificationSettings.buildOnSaveScreenNotify = settings["Notification"]["buildOnSaveScreenNotify"].getBool

    if settings["Notification"].contains("buildOnSaveLogNotify"):
      result.notificationSettings.buildOnSaveLogNotify = settings["Notification"]["buildOnSaveLogNotify"].getBool

    if settings["Notification"].contains("filerScreenNotify"):
      result.notificationSettings.filerScreenNotify = settings["Notification"]["filerScreenNotify"].getBool

    if settings["Notification"].contains("filerLogNotify"):
      result.notificationSettings.filerLogNotify = settings["Notification"]["filerLogNotify"].getBool

    if settings["Notification"].contains("restoreScreenNotify"):
      result.notificationSettings.restoreScreenNotify = settings["Notification"]["restoreScreenNotify"].getBool

    if settings["Notification"].contains("restoreLogNotify"):
      result.notificationSettings.restoreLogNotify = settings["Notification"]["restoreLogNotify"].getBool

  if settings.contains("Filer"):
    if settings["Filer"].contains("showIcons"):
      result.filerSettings.showIcons = settings["Filer"]["showIcons"].getbool()

  if (const table = "Autocomplete"; settings.contains(table)):
    if (const key = "enable"; settings[table].contains(key)):
      result.autocompleteSettings.enable = settings[table][key].getbool

  if settings.contains("Persist"):
    if settings["Persist"].contains("exCommand"):
      result.persist.exCommand = settings["Persist"]["exCommand"].getBool

    if settings["Persist"].contains("search"):
      result.persist.search = settings["Persist"]["search"].getBool

    if settings["Persist"].contains("cursorPosition"):
      result.persist.cursorPosition = settings["Persist"]["cursorPosition"].getBool

  if settings.contains("Debug"):
    if settings["Debug"].contains("WindowNode"):
      let windowNodeSettings = settings["Debug"]["WindowNode"]

      if windowNodeSettings.contains("enable"):
        let setting = windowNodeSettings["enable"].getbool
        result.debugModeSettings.windowNode.enable = setting

      if windowNodeSettings.contains("currentWindow"):
        let setting = windowNodeSettings["currentWindow"].getbool
        result.debugModeSettings.windowNode.currentWindow = setting

      if windowNodeSettings.contains("index"):
        let setting = windowNodeSettings["index"].getbool
        result.debugModeSettings.windowNode.index = setting

      if windowNodeSettings.contains("windowIndex"):
        let setting = windowNodeSettings["windowIndex"].getbool
        result.debugModeSettings.windowNode.windowIndex = setting

      if windowNodeSettings.contains("bufferIndex"):
        let setting = windowNodeSettings["bufferIndex"].getbool
        result.debugModeSettings.windowNode.bufferIndex = setting

      if windowNodeSettings.contains("parentIndex"):
        let setting = windowNodeSettings["parentIndex"].getbool
        result.debugModeSettings.windowNode.parentIndex = setting

      if windowNodeSettings.contains("childLen"):
        let setting = windowNodeSettings["childLen"].getbool
        result.debugModeSettings.windowNode.childLen = setting

      if windowNodeSettings.contains("splitType"):
        let setting = windowNodeSettings["splitType"].getbool
        result.debugModeSettings.windowNode.splitType = setting

      if windowNodeSettings.contains("haveCursesWin"):
        let setting = windowNodeSettings["haveCursesWin"].getbool
        result.debugModeSettings.windowNode.haveCursesWin = setting

      if windowNodeSettings.contains("haveCursesWin"):
        let setting = windowNodeSettings["haveCursesWin"].getbool
        result.debugModeSettings.windowNode.haveCursesWin = setting

      if windowNodeSettings.contains("y"):
        let setting = windowNodeSettings["y"].getbool
        result.debugModeSettings.windowNode.y = setting

      if windowNodeSettings.contains("x"):
        let setting = windowNodeSettings["x"].getbool
        result.debugModeSettings.windowNode.x = setting

      if windowNodeSettings.contains("h"):
        let setting = windowNodeSettings["h"].getbool
        result.debugModeSettings.windowNode.h = setting

      if windowNodeSettings.contains("w"):
        let setting = windowNodeSettings["w"].getbool
        result.debugModeSettings.windowNode.w = setting

      if windowNodeSettings.contains("currentLine"):
        let setting = windowNodeSettings["currentLine"].getbool
        result.debugModeSettings.windowNode.currentLine = setting

      if windowNodeSettings.contains("currentColumn"):
        let setting = windowNodeSettings["currentColumn"].getbool
        result.debugModeSettings.windowNode.currentColumn = setting

      if windowNodeSettings.contains("expandedColumn"):
        let setting = windowNodeSettings["expandedColumn"].getbool
        result.debugModeSettings.windowNode.expandedColumn = setting

      if windowNodeSettings.contains("cursor"):
        let setting = windowNodeSettings["cursor"].getbool
        result.debugModeSettings.windowNode.cursor = setting

    if settings["Debug"].contains("EditorView"):
      let editorViewSettings = settings["Debug"]["EditorView"]

      if editorViewSettings.contains("enable"):
        let setting = editorViewSettings["enable"].getbool
        result.debugModeSettings.editorview.enable = setting

      if editorViewSettings.contains("widthOfLineNum"):
        let setting = editorViewSettings["widthOfLineNum"].getbool
        result.debugModeSettings.editorview.widthOfLineNum = setting

      if editorViewSettings.contains("height"):
        let setting = editorViewSettings["height"].getbool
        result.debugModeSettings.editorview.height = setting

      if editorViewSettings.contains("width"):
        let setting = editorViewSettings["width"].getbool
        result.debugModeSettings.editorview.width = setting

      if editorViewSettings.contains("originalLine"):
        let setting = editorViewSettings["originalLine"].getbool
        result.debugModeSettings.editorview.originalLine = setting

      if editorViewSettings.contains("start"):
        let setting = editorViewSettings["start"].getbool
        result.debugModeSettings.editorview.start = setting

      if editorViewSettings.contains("length"):
        let setting = editorViewSettings["length"].getbool
        result.debugModeSettings.editorview.length = setting

    if settings["Debug"].contains("BufferStatus"):
      let bufStatusSettings = settings["Debug"]["BufferStatus"]

      if bufStatusSettings.contains("enable"):
        let setting = bufStatusSettings["enable"].getbool
        result.debugModeSettings.bufStatus.enable = setting

      if bufStatusSettings.contains("bufferIndex"):
        let setting = bufStatusSettings["bufferIndex"].getbool
        result.debugModeSettings.bufStatus.bufferIndex = setting

      if bufStatusSettings.contains("path"):
        let setting = bufStatusSettings["path"].getbool
        result.debugModeSettings.bufStatus.path = setting

      if bufStatusSettings.contains("openDir"):
        let setting = bufStatusSettings["openDir"].getbool
        result.debugModeSettings.bufStatus.openDir = setting

      if bufStatusSettings.contains("currentMode"):
        let setting = bufStatusSettings["currentMode"].getbool
        result.debugModeSettings.bufStatus.currentMode = setting

      if bufStatusSettings.contains("prevMode"):
        let setting = bufStatusSettings["prevMode"].getbool
        result.debugModeSettings.bufStatus.prevMode = setting

      if bufStatusSettings.contains("language"):
        let setting = bufStatusSettings["language"].getbool
        result.debugModeSettings.bufStatus.language = setting

      if bufStatusSettings.contains("encoding"):
        let setting = bufStatusSettings["encoding"].getbool
        result.debugModeSettings.bufStatus.encoding = setting

      if bufStatusSettings.contains("countChange"):
        let setting = bufStatusSettings["countChange"].getbool
        result.debugModeSettings.bufStatus.countChange = setting

      if bufStatusSettings.contains("cmdLoop"):
        let setting = bufStatusSettings["cmdLoop"].getbool
        result.debugModeSettings.bufStatus.cmdLoop = setting

      if bufStatusSettings.contains("lastSaveTime"):
        let setting = bufStatusSettings["lastSaveTime"].getbool
        result.debugModeSettings.bufStatus.lastSaveTime = setting

      if bufStatusSettings.contains("bufferLen"):
        let setting = bufStatusSettings["bufferLen"].getbool
        result.debugModeSettings.bufStatus.bufferLen = setting

  if result.editorColorTheme == ColorTheme.config and
     settings.contains("Theme"):
    if settings["Theme"].contains("baseTheme"):
      let themeString = settings["Theme"]["baseTheme"].getStr()
      if fileExists(themeString):
        ColorThemeTable[ColorTheme.config] = makeColorThemeFromVSCodeThemeFile(themeString)
      else:
        let theme = parseEnum[ColorTheme](themeString)
        ColorThemeTable[ColorTheme.config] = ColorThemeTable[theme]

    template color(str: string): untyped =
      parseEnum[Color](settings["Theme"][str].getStr())

    if settings["Theme"].contains("editorBg"):
      ColorThemeTable[ColorTheme.config].editorBg = color("editorBg")

    if settings["Theme"].contains("lineNum"):
      ColorThemeTable[ColorTheme.config].lineNum = color("lineNum")

    if settings["Theme"].contains("lineNumBg"):
      ColorThemeTable[ColorTheme.config].lineNumBg = color("lineNumBg")

    if settings["Theme"].contains("currentLineNum"):
      ColorThemeTable[ColorTheme.config].currentLineNum = color("currentLineNum")

    if settings["Theme"].contains("currentLineNumBg"):
      ColorThemeTable[ColorTheme.config].currentLineNumBg = color("currentLineNumBg")

    if settings["Theme"].contains("statusLineNormalMode"):
      ColorThemeTable[ColorTheme.config].statusLineNormalMode = color("statusLineNormalMode")

    if settings["Theme"].contains("statusLineNormalModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineNormalModeBg = color("statusLineNormalModeBg")

    if settings["Theme"].contains("statusLineModeNormalMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeNormalMode = color("statusLineModeNormalMode")

    if settings["Theme"].contains("statusLineModeNormalModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeNormalModeBg = color("statusLineModeNormalModeBg")

    if settings["Theme"].contains("statusLineNormalModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineNormalModeInactive = color("statusLineNormalModeInactive")

    if settings["Theme"].contains("statusLineNormalModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineNormalModeInactiveBg = color("statusLineNormalModeInactiveBg")

    if settings["Theme"].contains("statusLineInsertMode"):
      ColorThemeTable[ColorTheme.config].statusLineInsertMode = color("statusLineInsertMode")

    if settings["Theme"].contains("statusLineInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineInsertModeBg = color("statusLineInsertModeBg")

    if settings["Theme"].contains("statusLineModeInsertMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeInsertMode = color("statusLineModeInsertMode")

    if settings["Theme"].contains("statusLineModeInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeInsertModeBg = color("statusLineModeInsertModeBg")

    if settings["Theme"].contains("statusLineInsertModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineInsertModeInactive = color("statusLineInsertModeInactive")

    if settings["Theme"].contains("statusLineInsertModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineInsertModeInactiveBg = color("statusLineInsertModeInactiveBg")

    if settings["Theme"].contains("statusLineVisualMode"):
      ColorThemeTable[ColorTheme.config].statusLineVisualMode = color("statusLineVisualMode")

    if settings["Theme"].contains("statusLineVisualModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineVisualModeBg = color("statusLineVisualModeBg")

    if settings["Theme"].contains("statusLineModeVisualMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeVisualMode = color("statusLineModeVisualMode")

    if settings["Theme"].contains("statusLineModeVisualModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeVisualModeBg = color("statusLineModeVisualModeBg")

    if settings["Theme"].contains("statusLineVisualModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineVisualModeInactive = color("statusLineVisualModeInactive")

    if settings["Theme"].contains("statusLineVisualModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineVisualModeInactiveBg = color("statusLineVisualModeInactiveBg")

    if settings["Theme"].contains("statusLineReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusLineReplaceMode = color("statusLineReplaceMode")

    if settings["Theme"].contains("statusLineReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineReplaceModeBg = color("statusLineReplaceModeBg")

    if settings["Theme"].contains("statusLineModeReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeReplaceMode = color("statusLineModeReplaceMode")

    if settings["Theme"].contains("statusLineModeReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeReplaceModeBg = color("statusLineModeReplaceModeBg")

    if settings["Theme"].contains("statusLineReplaceModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineReplaceModeInactive = color("statusLineReplaceModeInactive")

    if settings["Theme"].contains("statusLineReplaceModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineReplaceModeInactiveBg = color("statusLineReplaceModeInactiveBg")

    if settings["Theme"].contains("statusLineFilerMode"):
      ColorThemeTable[ColorTheme.config].statusLineFilerMode = color("statusLineFilerMode")

    if settings["Theme"].contains("statusLineFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineFilerModeBg = color("statusLineFilerModeBg")

    if settings["Theme"].contains("statusLineModeFilerMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeFilerMode = color("statusLineModeFilerMode")

    if settings["Theme"].contains("statusLineModeFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeFilerModeBg = color("statusLineModeFilerModeBg")

    if settings["Theme"].contains("statusLineFilerModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineFilerModeInactive = color("statusLineFilerModeInactive")

    if settings["Theme"].contains("statusLineFilerModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineFilerModeInactiveBg = color("statusLineFilerModeInactiveBg")

    if settings["Theme"].contains("statusLineExMode"):
      ColorThemeTable[ColorTheme.config].statusLineExMode = color("statusLineExMode")

    if settings["Theme"].contains("statusLineExModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineExModeBg = color("statusLineExModeBg")

    if settings["Theme"].contains("statusLineModeExMode"):
      ColorThemeTable[ColorTheme.config].statusLineModeExMode = color("statusLineModeExMode")

    if settings["Theme"].contains("statusLineModeExModeBg"):
      ColorThemeTable[ColorTheme.config].statusLineModeExModeBg = color("statusLineModeExModeBg")

    if settings["Theme"].contains("statusLineExModeInactive"):
      ColorThemeTable[ColorTheme.config].statusLineExModeInactive = color("statusLineExModeInactive")

    if settings["Theme"].contains("statusLineExModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusLineExModeInactiveBg = color("statusLineExModeInactiveBg")

    if settings["Theme"].contains("statusLineGitBranch"):
      ColorThemeTable[ColorTheme.config].statusLineGitBranch = color("statusLineGitBranch")

    if settings["Theme"].contains("statusLineGitBranchBg"):
      ColorThemeTable[ColorTheme.config].statusLineGitBranchBg = color("statusLineGitBranchBg")

    if settings["Theme"].contains("tab"):
      ColorThemeTable[ColorTheme.config].tab = color("tab")

    if settings["Theme"].contains("tabBg"):
      ColorThemeTable[ColorTheme.config].tabBg = color("tabBg")

    if settings["Theme"].contains("currentTab"):
      ColorThemeTable[ColorTheme.config].currentTab = color("currentTab")

    if settings["Theme"].contains("currentTabBg"):
      ColorThemeTable[ColorTheme.config].currentTabBg = color("currentTabBg")

    if settings["Theme"].contains("commandBar"):
      ColorThemeTable[ColorTheme.config].commandBar = color("commandBar")

    if settings["Theme"].contains("commandBarBg"):
      ColorThemeTable[ColorTheme.config].commandBarBg = color("commandBarBg")

    if settings["Theme"].contains("errorMessage"):
      ColorThemeTable[ColorTheme.config].errorMessage = color("errorMessage")

    if settings["Theme"].contains("errorMessageBg"):
      ColorThemeTable[ColorTheme.config].errorMessageBg = color("errorMessageBg")

    if settings["Theme"].contains("searchResult"):
      ColorThemeTable[ColorTheme.config].searchResult = color("searchResult")

    if settings["Theme"].contains("searchResultBg"):
      ColorThemeTable[ColorTheme.config].searchResultBg = color("searchResultBg")

    if settings["Theme"].contains("visualMode"):
      ColorThemeTable[ColorTheme.config].visualMode = color("visualMode")

    if settings["Theme"].contains("visualModeBg"):
      ColorThemeTable[ColorTheme.config].visualModeBg = color("visualModeBg")

    if settings["Theme"].contains("defaultChar"):
      ColorThemeTable[ColorTheme.config].defaultChar = color("defaultChar")

    if settings["Theme"].contains("gtKeyword"):
      ColorThemeTable[ColorTheme.config].gtKeyword = color("gtKeyword")

    if settings["Theme"].contains("gtFunctionName"):
      ColorThemeTable[ColorTheme.config].gtFunctionName = color("gtFunctionName")

    if settings["Theme"].contains("gtTypeName"):
      ColorThemeTable[ColorTheme.config].gtTypeName = color("gtTypeName")

    if settings["Theme"].contains("gtBoolean"):
      ColorThemeTable[ColorTheme.config].gtBoolean = color("gtBoolean")

    if settings["Theme"].contains("gtSpecialVar"):
      ColorThemeTable[ColorTheme.config].gtSpecialVar = color("gtSpecialVar")

    if settings["Theme"].contains("gtBuiltin"):
      ColorThemeTable[ColorTheme.config].gtBuiltin = color("gtBuiltin")

    if settings["Theme"].contains("gtStringLit"):
      ColorThemeTable[ColorTheme.config].gtStringLit = color("gtStringLit")

    if settings["Theme"].contains("gtDecNumber"):
      ColorThemeTable[ColorTheme.config].gtDecNumber = color("gtDecNumber")

    if settings["Theme"].contains("gtComment"):
      ColorThemeTable[ColorTheme.config].gtComment = color("gtComment")

    if settings["Theme"].contains("gtLongComment"):
      ColorThemeTable[ColorTheme.config].gtLongComment = color("gtLongComment")

    if settings["Theme"].contains("gtWhitespace"):
      ColorThemeTable[ColorTheme.config].gtWhitespace = color("gtWhitespace")

    if settings["Theme"].contains("gtPreprocessor"):
      ColorThemeTable[ColorTheme.config].gtPreprocessor = color("gtPreprocessor")

    if settings["Theme"].contains("currentFile"):
      ColorThemeTable[ColorTheme.config].currentFile = color("currentFile")

    if settings["Theme"].contains("currentFileBg"):
      ColorThemeTable[ColorTheme.config].currentFileBg = color("currentFileBg")

    if settings["Theme"].contains("file"):
      ColorThemeTable[ColorTheme.config].file = color("file")

    if settings["Theme"].contains("fileBg"):
      ColorThemeTable[ColorTheme.config].fileBg = color("fileBg")

    if settings["Theme"].contains("dir"):
      ColorThemeTable[ColorTheme.config].dir = color("dir")

    if settings["Theme"].contains("dirBg"):
      ColorThemeTable[ColorTheme.config].dirBg = color("dirBg")

    if settings["Theme"].contains("pcLink"):
      ColorThemeTable[ColorTheme.config].pcLink = color("pcLink")

    if settings["Theme"].contains("pcLinkBg"):
      ColorThemeTable[ColorTheme.config].pcLinkBg = color("pcLinkBg")

    if settings["Theme"].contains("popUpWindow"):
      ColorThemeTable[ColorTheme.config].popUpWindow = color("popUpWindow")

    if settings["Theme"].contains("popUpWindowBg"):
      ColorThemeTable[ColorTheme.config].popUpWindowBg = color("popUpWindowBg")

    if settings["Theme"].contains("popUpWinCurrentLine"):
      ColorThemeTable[ColorTheme.config].popUpWinCurrentLine = color("popUpWinCurrentLine")

    if settings["Theme"].contains("popUpWinCurrentLineBg"):
      ColorThemeTable[ColorTheme.config].popUpWinCurrentLineBg = color("popUpWinCurrentLineBg")

    if settings["Theme"].contains("replaceText"):
      ColorThemeTable[ColorTheme.config].replaceText = color("replaceText")

    if settings["Theme"].contains("replaceTextBg"):
      ColorThemeTable[ColorTheme.config].replaceTextBg = color("replaceTextBg")

    if settings["Theme"].contains("parenText"):
      ColorThemeTable[ColorTheme.config].parenText = color("parenText")

    if settings["Theme"].contains("parenTextBg"):
      ColorThemeTable[ColorTheme.config].parenTextBg = color("parenTextBg")

    if settings["Theme"].contains("currentWordBg"):
      ColorThemeTable[ColorTheme.config].currentWordBg = color("currentWordBg")

    if settings["Theme"].contains("highlightFullWidthSpace"):
      ColorThemeTable[ColorTheme.config].highlightFullWidthSpace = color("highlightFullWidthSpace")

    if settings["Theme"].contains("highlightFullWidthSpaceBg"):
      ColorThemeTable[ColorTheme.config].highlightFullWidthSpaceBg = color("highlightFullWidthSpaceBg")

    if settings["Theme"].contains("highlightTrailingSpaces"):
      ColorThemeTable[ColorTheme.config].highlightTrailingSpaces = color("highlightTrailingSpaces")

    if settings["Theme"].contains("highlightTrailingSpacesBg"):
      ColorThemeTable[ColorTheme.config].highlightTrailingSpacesBg = color("highlightTrailingSpacesBg")

    if settings["Theme"].contains("reservedWord"):
      ColorThemeTable[ColorTheme.config].reservedWord = color("reservedWord")

    if settings["Theme"].contains("reservedWordBg"):
      ColorThemeTable[ColorTheme.config].reservedWordBg = color("reservedWordBg")

    if settings["Theme"].contains("currentHistory"):
      ColorThemeTable[ColorTheme.config].currentHistory = color("currentHistory")

    if settings["Theme"].contains("currentHistoryBg"):
      ColorThemeTable[ColorTheme.config].currentHistoryBg = color("currentHistoryBg")

    if settings["Theme"].contains("addedLine"):
      ColorThemeTable[ColorTheme.config].addedLine = color("addedLine")

    if settings["Theme"].contains("addedLineBg"):
      ColorThemeTable[ColorTheme.config].addedLineBg = color("addedLineBg")

    if settings["Theme"].contains("deletedLine"):
      ColorThemeTable[ColorTheme.config].deletedLine = color("deletedLine")

    if settings["Theme"].contains("deletedLineBg"):
      ColorThemeTable[ColorTheme.config].deletedLineBg = color("deletedLineBg")

    if settings["Theme"].contains("currentSetting"):
      ColorThemeTable[ColorTheme.config].currentSetting = color("currentSetting")

    if settings["Theme"].contains("currentSettingBg"):
      ColorThemeTable[ColorTheme.config].currentSettingBg = color("currentSettingBg")

    if settings["Theme"].contains("currentLineBg"):
      ColorThemeTable[ColorTheme.config].currentLineBg = color("currentLineBg")

    result.editorColorTheme = ColorTheme.config

  if result.editorColorTheme == ColorTheme.vscode:
    result.editorColorTheme = loadVSCodeTheme()

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
         "popUpWindowInExmode",
         "autoDeleteParen",
         "systemClipboard",
         "smoothScroll":
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
         "ClangOptions",
         "CppOptions",
         "NimOptions",
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
  let editorColors = ColorThemeTable[ColorTheme.config].EditorColor
  for key, val in table.getTable:
    case key:
      of "baseTheme":
        var correctKey = false
        for theme in ColorTheme:
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
  result.addLine fmt "theme = \"{$settings.editorColorTheme}\""
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
  result.addLine fmt "popUpWindowInExmode = {$settings.popUpWindowInExmode}"
  result.addLine fmt "autoDeleteParen = {$settings.autoDeleteParen }"
  result.addLine fmt "smoothScroll = {$settings.smoothScroll }"
  result.addLine fmt "smoothScrollSpeed = {$settings.smoothScrollSpeed}"

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
  if settings.highlightSettings.reservedWords.len > 0:
    result.addLine "reservedWord = ["
    for index, reservedWord in settings.highlightSettings.reservedWords:
      if index > 0: result.add ", "
      result.add fmt "\"{reservedWord.word}\""
    result.add "]"
  result.addLine fmt "replaceText = {$settings.highlightSettings.replaceText }"
  result.addLine fmt "pairOfParen = {$settings.highlightSettings.pairOfParen }"
  result.addLine fmt "fullWidthSpace = {$settings.highlightSettings.fullWidthSpace}"
  result.addLine fmt "trailingSpaces = {$settings.highlightSettings.trailingSpaces }"
  result.addLine fmt "currentWord = {$settings.highlightSettings.currentWord}"

  result.addLine ""

  result.addLine fmt "[AutoBackup]"
  result.addLine fmt "enable = {$settings.autoBackupSettings.enable }"
  result.addLine fmt "idleTime = {$settings.autoBackupSettings.idleTime }"
  result.addLine fmt "interval = {$settings.autoBackupSettings.interval }"
  if settings.autoBackupSettings.dirToExclude.len > 0:
    result.addLine "dirToExclude = ["
    for index, dir in settings.autoBackupSettings.dirToExclude:
      if index > 0: result.add ", "
      result.add fmt "\"{$dir}\""
    result.add "]"

  result.addLine ""

  result.addLine fmt "[QuickRun]"
  result.addLine fmt "saveBufferWhenQuickRun = {$settings.quickRunSettings.saveBufferWhenQuickRun}"
  if settings.quickRunSettings.command.len > 0:
    result.addLine fmt "command = {$settings.quickRunSettings.command}"
  result.addLine fmt "timeout = {$settings.quickRunSettings.timeout }"
  if settings.quickRunSettings.nimAdvancedCommand .len > 0:
    result.addLine fmt "nimAdvancedCommand = \"{$settings.quickRunSettings.nimAdvancedCommand}\""
  if settings.quickRunSettings.ClangOptions.len > 0:
    result.addLine fmt "ClangOptions = \"{$settings.quickRunSettings.ClangOptions}\""
  if settings.quickRunSettings.CppOptions.len > 0:
    result.addLine fmt "CppOptions = \"{$settings.quickRunSettings.CppOptions}\""
  if settings.quickRunSettings.NimOptions.len > 0:
    result.addLine fmt "NimOptions = \"{$settings.quickRunSettings.NimOptions}\""
  if settings.quickRunSettings.shOptions.len > 0:
    result.addLine fmt "shOptions = \"{$settings.quickRunSettings.shOptions}\""
  if settings.quickRunSettings.bashOptions.len > 0:
    result.addLine fmt "shOptions = \"{$settings.quickRunSettings.bashOptions}\""

  result.addLine ""

  result.addLine fmt "[Notification]"
  result.addLine fmt "screenNotifications = {$settings.notificationSettings.screenNotifications }"
  result.addLine fmt "logNotifications = {$settings.notificationSettings.logNotifications }"
  result.addLine fmt "autoBackupScreenNotify = {$settings.notificationSettings.autoBackupScreenNotify}"
  result.addLine fmt "autoBackupLogNotify = {$settings.notificationSettings.autoBackupLogNotify}"
  result.addLine fmt "autoSaveScreenNotify = {$settings.notificationSettings.autoSaveScreenNotify}"
  result.addLine fmt "autoSaveLogNotify = {$settings.notificationSettings.autoSaveLogNotify}"
  result.addLine fmt "yankScreenNotify = {$settings.notificationSettings.yankScreenNotify}"
  result.addLine fmt "yankLogNotify = {$settings.notificationSettings.yankLogNotify}"
  result.addLine fmt "deleteScreenNotify = {$settings.notificationSettings.deleteScreenNotify}"
  result.addLine fmt "deleteLogNotify = {$settings.notificationSettings.deleteLogNotify}"
  result.addLine fmt "saveScreenNotify = {$settings.notificationSettings.saveScreenNotify}"
  result.addLine fmt "saveLogNotify = {$settings.notificationSettings.saveLogNotify}"
  result.addLine fmt "quickRunScreenNotify = {$settings.notificationSettings.quickRunScreenNotify}"
  result.addLine fmt "quickRunLogNotify  = {$settings.notificationSettings.quickRunLogNotify}"
  result.addLine fmt "buildOnSaveScreenNotify = {$settings.notificationSettings.buildOnSaveScreenNotify}"
  result.addLine fmt "buildOnSaveLogNotify = {$settings.notificationSettings.buildOnSaveLogNotify}"
  result.addLine fmt "filerScreenNotify = {$settings.notificationSettings.filerScreenNotify}"
  result.addLine fmt "filerLogNotify = {$settings.notificationSettings.filerLogNotify}"
  result.addLine fmt "restoreScreenNotify = {$settings.notificationSettings.restoreScreenNotify}"
  result.addLine fmt "restoreLogNotify = {$settings.notificationSettings.restoreLogNotify}"

  result.addLine ""

  result.addLine fmt "[Filer]"
  result.addLine fmt "showIcons = {$settings.filerSettings.showIcons}"

  result.addLine ""

  result.addLine fmt "[Autocomplete]"
  result.addLine fmt "enable = {$settings.autocompleteSettings.enable}"

  result.addLine ""

  result.addLine fmt "[Persist]"
  result.addLine fmt "exCommand = {$settings.persist.exCommand}"
  result.addLine fmt "search = {$settings.persist.search}"
  result.addLine fmt "cursorPosition = {$settings.persist.cursorPosition}"

  result.addLine ""

  result.addLine fmt "[Debug.WindowNode]"
  result.addLine fmt "enable = {$settings.debugModeSettings.windowNode.enable}"
  result.addLine fmt "currentWindow = {$settings.debugModeSettings.windowNode.currentWindow}"
  result.addLine fmt "index = {$settings.debugModeSettings.windowNode.index}"
  result.addLine fmt "windowIndex = {$settings.debugModeSettings.windowNode.windowIndex}"
  result.addLine fmt "bufferIndex= {$settings.debugModeSettings.windowNode.bufferIndex}"
  result.addLine fmt "parentIndex= {$settings.debugModeSettings.windowNode.parentIndex}"
  result.addLine fmt "childLen = {$settings.debugModeSettings.windowNode.childLen}"
  result.addLine fmt "splitType = {$settings.debugModeSettings.windowNode.splitType}"
  result.addLine fmt "haveCursesWin= {$settings.debugModeSettings.windowNode.haveCursesWin}"
  result.addLine fmt "y = {$settings.debugModeSettings.windowNode.y}"
  result.addLine fmt "x = {$settings.debugModeSettings.windowNode.x}"
  result.addLine fmt "h = {$settings.debugModeSettings.windowNode.h}"
  result.addLine fmt "w = {$settings.debugModeSettings.windowNode.w}"
  result.addLine fmt "currentLine = {$settings.debugModeSettings.windowNode.currentLine}"
  result.addLine fmt "currentColumn = {$settings.debugModeSettings.windowNode.currentColumn}"
  result.addLine fmt "expandedColumn = {$settings.debugModeSettings.windowNode.expandedColumn}"
  result.addLine fmt "cursor = {$settings.debugModeSettings.windowNode.cursor}"

  result.addLine ""

  result.addLine fmt "[Debug.EditorView]"
  result.addLine fmt "enable = {$settings.debugModeSettings.editorview.enable}"
  result.addLine fmt "widthOfLineNum = {$settings.debugModeSettings.editorview.widthOfLineNum}"
  result.addLine fmt "height = {$settings.debugModeSettings.editorview.height}"
  result.addLine fmt "width = {$settings.debugModeSettings.editorview.width}"
  result.addLine fmt "originalLine = {$settings.debugModeSettings.editorview.originalLine}"
  result.addLine fmt "start = {$settings.debugModeSettings.editorview.start}"
  result.addLine fmt "length = {$settings.debugModeSettings.editorview.length}"

  result.addLine fmt "[Debug.BufferStatus]"
  result.addLine fmt "enable = {$settings.debugModeSettings.bufStatus.enable}"
  result.addLine fmt "bufferIndex = {$settings.debugModeSettings.bufStatus.bufferIndex }"
  result.addLine fmt "path = {$settings.debugModeSettings.bufStatus.path}"
  result.addLine fmt "openDir = {$settings.debugModeSettings.bufStatus.openDir}"
  result.addLine fmt "currentMode = {$settings.debugModeSettings.bufStatus.currentMode}"
  result.addLine fmt "prevMode = {$settings.debugModeSettings.bufStatus.prevMode}"
  result.addLine fmt "language = {$settings.debugModeSettings.bufStatus.language}"
  result.addLine fmt "encoding = {$settings.debugModeSettings.bufStatus.encoding}"
  result.addLine fmt "countChange = {$settings.debugModeSettings.bufStatus.countChange}"
  result.addLine fmt "cmdLoop = {$settings.debugModeSettings.bufStatus.cmdLoop}"
  result.addLine fmt "lastSaveTime = {$settings.debugModeSettings.bufStatus.lastSaveTime}"
  result.addLine fmt "bufferLen = {$settings.debugModeSettings.bufStatus.bufferLen}"

  result.addLine ""

  let theme = ColorThemeTable[ColorTheme.config]
  result.addLine fmt "[Theme]"
  result.addLine fmt "baseTheme = \"{$settings.editorColorTheme}\""
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
  result.addLine fmt "gtDecNumber = \"{$theme.gtDecNumber}\""
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
  result.addLine fmt "popUpWindow = \"{$theme.popUpWindow}\""
  result.addLine fmt "popUpWindowBg = \"{$theme.popUpWindowBg}\""
  result.addLine fmt "popUpWinCurrentLine = \"{$theme.popUpWinCurrentLine}\""
  result.addLine fmt "popUpWinCurrentLineBg = \"{$theme.popUpWinCurrentLineBg}\""
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
