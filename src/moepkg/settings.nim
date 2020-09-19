import parsetoml, os, json, macros, times, options
from strutils import parseEnum, endsWith, parseInt
export TomlError

when (NimMajor, NimMinor, NimPatch) > (1, 3, 0):
  # This addresses a breaking change in https://github.com/nim-lang/Nim/pull/14046.
  from strutils import nimIdentNormalize
  export strutils.nimIdentNormalize

import ui, color, unicodeext, highlight

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
  workspaceScreenNotify*: bool
  workspaceLogNotify*: bool
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
  idolTime*: int # seconds
  interval*: int # minutes
  backupDir*: seq[Rune]
  dirToExclude*: seq[seq[Rune]]

type FilerSettings = object
  showIcons*: bool

type WorkSpaceSettings = object
  workSpaceLine*: bool

type StatusBarSettings* = object
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
  multipleStatusBar*: bool
  gitbranchName*: bool
  showGitInactive*: bool
  showModeInactive*: bool

type TabLineSettings* = object
  useTab*: bool
  allbuffer*: bool

type EditorViewSettings* = object
  lineNumber*: bool
  currentLineNumber*: bool
  cursorLine*: bool
  indentationLines*: bool
  tabStop*: int

type AutocompleteSettings* = object
  enable*: bool

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  statusBar*: StatusBarSettings
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
  replaceTextHighlight*: bool
  highlightPairOfParen*: bool
  autoDeleteParen*: bool
  smoothScroll*: bool
  smoothScrollSpeed*: int
  highlightOtherUsesCurrentWord*: bool
  systemClipboard*: bool
  highlightFullWidthSpace*: bool
  highlightTrailingSpaces*: bool
  buildOnSave*: BuildOnSaveSettings
  workSpace*: WorkSpaceSettings
  filerSettings*: FilerSettings
  autocompleteSettings*: AutocompleteSettings
  reservedWords*: seq[ReservedWord]
  autoBackupSettings*: AutoBackupSettings
  quickRunSettings*: QuickRunSettings
  notificationSettings*: NotificationSettings

type InvalidItemError* = object of ValueError # Warning: inherit from a more precise exception type like ValueError, IOError or OSError. If these don't suit, inherit from CatchableError or Defect. [InheritFromException]

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
  result.workspaceScreenNotify = true
  result.workspaceLogNotify = true
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
  result.idolTime = 10 # 10 seconds
  result.dirToExclude = @[ru"/etc"]

proc initFilerSettings(): FilerSettings {.inline.} =
  result.showIcons = true

proc initAutocompleteSettings*(): AutocompleteSettings {.inline.} =
  result.enable = true

proc initTabBarSettings*(): TabLineSettings {.inline.} =
  result.useTab = true

proc initStatusBarSettings*(): StatusBarSettings =
  result.enable = true
  result.mode = true
  result.filename = true
  result.chanedMark = true
  result.line = true
  result.column = true
  result.characterEncoding = true
  result.language = true
  result.directory = true
  result.multipleStatusBar = true
  result.gitbranchName = true

proc initWorkSpaceSettings(): WorkSpaceSettings {.inline.} =
  result.workSpaceLine = false

proc initEditorViewSettings*(): EditorViewSettings =
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

proc initEditorSettings*(): EditorSettings =
  result.editorColorTheme = ColorTheme.dark
  result.statusBar = initStatusBarSettings()
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
  result.replaceTextHighlight = true
  result.highlightPairOfParen = true
  result.autoDeleteParen = true
  result.smoothScroll = true
  result.smoothScrollSpeed = 15
  result.highlightOtherUsesCurrentWord = true
  result.systemClipboard = true
  result.highlightFullWidthSpace = true
  result.highlightTrailingSpaces = true
  result.buildOnSave = BuildOnSaveSettings()
  result.workSpace= initWorkSpaceSettings()
  result.filerSettings = initFilerSettings()
  result.autocompleteSettings = initAutocompleteSettings()
  result.reservedWords = initReservedWords()
  result.autoBackupSettings = initAutoBackupSettings()
  result.quickRunSettings = initQuickRunSettings()
  result.notificationSettings = initNotificationSettings()

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
  echo args.treeRepr
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
  when defined isExpandMacros:
    expandMacros:
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

      # status bar
      setEditorColor statusBarNormalMode:
        foreground:
          colorFromNode(jsonNode{"colors", "editor.foreground"})
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeNormalMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarNormalModeInactive:
        foreground:
          colorFromNode(jsonNode{"colors", "statusBar.foreground"})
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "editor.background"})
      setEditorColor statusBarInsertMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeInsertMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          white
      setEditorColor statusBarInsertModeInactive:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarVisualMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeVisualMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          white
      setEditorColor statusBarVisualModeInactive:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarReplaceMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeReplaceMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          white
      setEditorColor statusBarReplaceModeInactive:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarFilerMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeFilerMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          white
      setEditorColor statusBarFilerModeInactive:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarExMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarModeExMode:
        foreground:
          adjust: ReadableVsBackground
        background:
          white
      setEditorColor statusBarExModeInactive:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
      setEditorColor statusBarGitBranch:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "statusBar.background"})
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

      # work space bar
      setEditorColor workSpaceBar:
        foreground:
          colorFromNode(jsonNode{"colors", "activityBar.foreground"})
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "activityBar.background"})
      setEditorColor reservedWord:
        foreground:
          adjust: ReadableVsBackground
        background:
          colorFromNode(jsonNode{"colors", "activityBarBadge.background"})

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
    var vsCodeExtensionsDir = homeDir & "/.vscode-oss/extensions/"
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
      vsCodeExtensionsDir = homeDir & "/.vscode/extensions/"
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

  var vscodeTheme = false

  if settings.contains("Standard"):
    template cursorType(str: string): untyped =
      parseEnum[CursorType](str)

    if settings["Standard"].contains("theme"):
      let themeString = settings["Standard"]["theme"].getStr()
      result.editorColorTheme = getTheme(themeString)
      if result.editorColorTheme == ColorTheme.vscode:
        vscodeTheme = true

    if settings["Standard"].contains("number"):
      result.view.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("currentNumber"):
      result.view.currentLineNumber = settings["Standard"]["currentNumber"].getbool()

    if settings["Standard"].contains("cursorLine"):
      result.view.cursorLine = settings["Standard"]["cursorLine"].getbool()

    if settings["Standard"].contains("statusBar"):
      result.statusBar.enable = settings["Standard"]["statusBar"].getbool()

    if settings["Standard"].contains("tabLine"):
      result.tabLine.useTab = settings["Standard"]["tabLine"].getbool()

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

    if settings["Standard"].contains("replaceTextHighlight"):
      result.replaceTextHighlight = settings["Standard"]["replaceTextHighlight"].getbool()

    if settings["Standard"].contains("highlightPairOfParen"):
      result.highlightPairOfParen =  settings["Standard"]["highlightPairOfParen"].getbool()

    if settings["Standard"].contains("autoDeleteParen"):
      result.autoDeleteParen =  settings["Standard"]["autoDeleteParen"].getbool()

    if settings["Standard"].contains("smoothScroll"):
      result.smoothScroll =  settings["Standard"]["smoothScroll"].getbool()

    if settings["Standard"].contains("smoothScrollSpeed"):
      result.smoothScrollSpeed = settings["Standard"]["smoothScrollSpeed"].getint()

    if settings["Standard"].contains("highlightCurrentWord"):
      result.highlightOtherUsesCurrentWord = settings["Standard"]["highlightCurrentWord"].getbool()

    if settings["Standard"].contains("systemClipboard"):
      result.systemClipboard = settings["Standard"]["systemClipboard"].getbool()

    if settings["Standard"].contains("highlightFullWidthSpace"):
      result.highlightFullWidthSpace = settings["Standard"]["highlightFullWidthSpace"].getbool()

    if settings["Standard"].contains("highlightTrailingSpaces"):
      result.highlightTrailingSpaces = settings["Standard"]["highlightTrailingSpaces"].getbool()

    if settings["Standard"].contains("indentationLines"):
      result.view.indentationLines = settings["Standard"]["indentationLines"].getbool()

  if settings.contains("TabLine"):
    if settings["TabLine"].contains("allBuffer"):
        result.tabLine.allBuffer= settings["TabLine"]["allBuffer"].getbool()

  if settings.contains("StatusBar"):
    if settings["StatusBar"].contains("multipleStatusBar"):
        result.statusBar.multipleStatusBar = settings["StatusBar"]["multipleStatusBar"].getbool()

    if settings["StatusBar"].contains("merge"):
        result.statusBar.merge = settings["StatusBar"]["merge"].getbool()

    if settings["StatusBar"].contains("mode"):
        result.statusBar.mode= settings["StatusBar"]["mode"].getbool()

    if settings["StatusBar"].contains("filename"):
        result.statusBar.filename = settings["StatusBar"]["filename"].getbool()

    if settings["StatusBar"].contains("chanedMark"):
        result.statusBar.chanedMark = settings["StatusBar"]["chanedMark"].getbool()

    if settings["StatusBar"].contains("line"):
        result.statusBar.line = settings["StatusBar"]["line"].getbool()

    if settings["StatusBar"].contains("column"):
        result.statusBar.column = settings["StatusBar"]["column"].getbool()

    if settings["StatusBar"].contains("encoding"):
        result.statusBar.characterEncoding = settings["StatusBar"]["encoding"].getbool()

    if settings["StatusBar"].contains("language"):
        result.statusBar.language = settings["StatusBar"]["language"].getbool()

    if settings["StatusBar"].contains("directory"):
        result.statusBar.directory = settings["StatusBar"]["directory"].getbool()

    if settings["StatusBar"].contains("gitbranchName"):
        result.statusBar.gitbranchName = settings["StatusBar"]["gitbranchName"].getbool()

    if settings["StatusBar"].contains("showGitInactive"):
        result.statusBar.showGitInactive = settings["StatusBar"]["showGitInactive"].getbool()

    if settings["StatusBar"].contains("showModeInactive"):
        result.statusBar.showModeInactive = settings["StatusBar"]["showModeInactive"].getbool()

  if settings.contains("BuildOnSave"):
    if settings["BuildOnSave"].contains("enable"):
      result.buildOnSave.enable = settings["BuildOnSave"]["enable"].getbool()

    if settings["BuildOnSave"].contains("workspaceRoot"):
      result.buildOnSave.workspaceRoot = settings["BuildOnSave"]["workspaceRoot"].getStr().toRunes

    if settings["BuildOnSave"].contains("command"):
      result.buildOnSave.command = settings["BuildOnSave"]["command"].getStr().toRunes

  if settings.contains("WorkSpace"):
    if settings["WorkSpace"].contains("workSpaceLine"):
      result.workSpace.workSpaceLine = settings["WorkSpace"]["workSpaceLine"].getbool()

  if settings.contains("Highlight"):
    if settings["Highlight"].contains("reservedWord"):
      let reservedWords = settings["Highlight"]["reservedWord"]
      for i in 0 ..< reservedWords.len:
        let
          word = reservedWords[i].getStr
          reservedWord = ReservedWord(word: word, color: EditorColorPair.reservedWord)
        result.reservedWords.add(reservedWord)

  if settings.contains("AutoBackup"):
    if settings["AutoBackup"].contains("enable"):
      result.autoBackupSettings.enable = settings["AutoBackup"]["enable"].getbool()

    if settings["AutoBackup"].contains("idolTime"):
      result.autoBackupSettings.idolTime = settings["AutoBackup"]["idolTime"].getInt()

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

    if settings["Notification"].contains("workspaceScreenNotify"):
      result.notificationSettings.workspaceScreenNotify = settings["Notification"]["workspaceScreenNotify"].getBool

    if settings["Notification"].contains("workspaceLogNotify"):
      result.notificationSettings.workspaceLogNotify = settings["Notification"]["workspaceLogNotify"].getBool

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

  if not vscodeTheme and settings.contains("Theme"):
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

    if settings["Theme"].contains("statusBarNormalMode"):
      ColorThemeTable[ColorTheme.config].statusBarNormalMode = color("statusBarNormalMode")

    if settings["Theme"].contains("statusBarNormalModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarNormalModeBg = color("statusBarNormalModeBg")

    if settings["Theme"].contains("statusBarModeNormalMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeNormalMode = color("statusBarModeNormalMode")

    if settings["Theme"].contains("statusBarModeNormalModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeNormalModeBg = color("statusBarModeNormalModeBg")

    if settings["Theme"].contains("statusBarNormalModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarNormalModeInactive = color("statusBarNormalModeInactive")

    if settings["Theme"].contains("statusBarNormalModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarNormalModeInactiveBg = color("statusBarNormalModeInactiveBg")

    if settings["Theme"].contains("statusBarInsertMode"):
      ColorThemeTable[ColorTheme.config].statusBarInsertMode = color("statusBarInsertMode")

    if settings["Theme"].contains("statusBarInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarInsertModeBg = color("statusBarInsertModeBg")

    if settings["Theme"].contains("statusBarModeInsertMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeInsertMode = color("statusBarModeInsertMode")

    if settings["Theme"].contains("statusBarModeInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeInsertModeBg = color("statusBarModeInsertModeBg")

    if settings["Theme"].contains("statusBarInsertModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarInsertModeInactive = color("statusBarInsertModeInactive")

    if settings["Theme"].contains("statusBarInsertModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarInsertModeInactiveBg = color("statusBarInsertModeInactiveBg")

    if settings["Theme"].contains("statusBarVisualMode"):
      ColorThemeTable[ColorTheme.config].statusBarVisualMode = color("statusBarVisualMode")

    if settings["Theme"].contains("statusBarVisualModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarVisualModeBg = color("statusBarVisualModeBg")

    if settings["Theme"].contains("statusBarModeVisualMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeVisualMode = color("statusBarModeVisualMode")

    if settings["Theme"].contains("statusBarModeVisualModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeVisualModeBg = color("statusBarModeVisualModeBg")

    if settings["Theme"].contains("statusBarVisualModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarVisualModeInactive = color("statusBarVisualModeInactive")

    if settings["Theme"].contains("statusBarVisualModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarVisualModeInactiveBg = color("statusBarVisualModeInactiveBg")

    if settings["Theme"].contains("statusBarReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceMode = color("statusBarReplaceMode")

    if settings["Theme"].contains("statusBarReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceModeBg = color("statusBarReplaceModeBg")

    if settings["Theme"].contains("statusBarModeReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeReplaceMode = color("statusBarModeReplaceMode")

    if settings["Theme"].contains("statusBarModeReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeReplaceModeBg = color("statusBarModeReplaceModeBg")

    if settings["Theme"].contains("statusBarReplaceModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceModeInactive = color("statusBarReplaceModeInactive")

    if settings["Theme"].contains("statusBarReplaceModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceModeInactiveBg = color("statusBarReplaceModeInactiveBg")

    if settings["Theme"].contains("statusBarFilerMode"):
      ColorThemeTable[ColorTheme.config].statusBarFilerMode = color("statusBarFilerMode")

    if settings["Theme"].contains("statusBarFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarFilerModeBg = color("statusBarFilerModeBg")

    if settings["Theme"].contains("statusBarModeFilerMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeFilerMode = color("statusBarModeFilerMode")

    if settings["Theme"].contains("statusBarModeFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeFilerModeBg = color("statusBarModeFilerModeBg")

    if settings["Theme"].contains("statusBarFilerModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarFilerModeInactive = color("statusBarFilerModeInactive")

    if settings["Theme"].contains("statusBarFilerModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarFilerModeInactiveBg = color("statusBarFilerModeInactiveBg")

    if settings["Theme"].contains("statusBarExMode"):
      ColorThemeTable[ColorTheme.config].statusBarExMode = color("statusBarExMode")

    if settings["Theme"].contains("statusBarExModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarExModeBg = color("statusBarExModeBg")

    if settings["Theme"].contains("statusBarModeExMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeExMode = color("statusBarModeExMode")

    if settings["Theme"].contains("statusBarModeExModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeExModeBg = color("statusBarModeExModeBg")

    if settings["Theme"].contains("statusBarExModeInactive"):
      ColorThemeTable[ColorTheme.config].statusBarExModeInactive = color("statusBarExModeInactive")

    if settings["Theme"].contains("statusBarExModeInactiveBg"):
      ColorThemeTable[ColorTheme.config].statusBarExModeInactiveBg = color("statusBarExModeInactiveBg")

    if settings["Theme"].contains("statusBarGitBranch"):
      ColorThemeTable[ColorTheme.config].statusBarGitBranch = color("statusBarGitBranch")

    if settings["Theme"].contains("statusBarGitBranchBg"):
      ColorThemeTable[ColorTheme.config].statusBarGitBranchBg = color("statusBarGitBranchBg")

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

    if settings["Theme"].contains("workSpaceBar"):
      ColorThemeTable[ColorTheme.config].workSpaceBar = color("workSpaceBar")

    if settings["Theme"].contains("workSpaceBarBg"):
      ColorThemeTable[ColorTheme.config].workSpaceBarBg = color("workSpaceBarBg")

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

    result.editorColorTheme = ColorTheme.config

  if vscodeTheme:
    result.editorColorTheme = loadVSCodeTheme()

proc validateTomlConfig(toml: TomlValueRef): Option[string] =
  template validateStandardTable() =
    for item in json["Standard"].pairs:
      case item.key:
        of "theme":
          var correctValue = false
          if item.val["value"].getStr == "vscode":
            correctValue = true
          else:
            for theme in ColorTheme:
              if $theme == item.val["value"].getStr:
                correctValue = true
          if not correctValue:
            return some($item)
        of "number",
           "currentNumber",
           "cursorLine",
           "statusBar",
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
           "replaceTextHighlight",
           "highlightPairOfParen",
           "autoDeleteParen",
           "systemClipboard",
           "highlightFullWidthSpace",
           "highlightTrailingSpaces",
           "highlightCurrentWord",
           "smoothScroll":
          if not (item.val["type"].getStr == "bool"):
            return some($item)
        of "tabStop", "autoSaveInterval", "smoothScrollSpeed":
          if not (item.val["type"].getStr == "integer" and
                  parseInt(item.val["value"].getStr) > 0): return some($item)
        of "defaultCursor",
           "normalModeCursor",
           "insertModeCursor":
          let val = item.val["value"].getStr
          var correctValue = false
          for cursorType in CursorType:
            if val == $cursorType:
              correctValue = true
              break

          if not correctValue:
            return some($item)
        else:
          return some($item)

  template validateTabLineTable() =
    for item in json["TabLine"].pairs:
      case item.key:
        of "allBuffer",
           "mode",
           "chanedMark",
           "line",
           "column",
           "encoding",
           "language",
           "directory",
           "gitbranchName",
           "showGitInactive",
           "showModeInactive":
          if not (item.val["type"].getStr == "bool"):
            return some($item)
        else:
          return some($item)

  template validateStatusBarTable() =
    for item in json["StatusBar"].pairs:
      case item.key:
        of "multipleStatusBar",
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
          if not (item.val["type"].getStr == "bool"):
            return some($item)
        else:
          return some($item)

  template validateBuildOnSaveTable() =
    for item in json["BuildOnSave"].pairs:
      case item.key:
        of "enable":
          if not (item.val["type"].getStr == "bool"):
            return some($item)
        of "workspaceRoot",
           "command":
          if not (item.val["type"].getStr == "string"):
            return some($item)
        else:
            return some($item)

  template validateWorkSpaceTable() =
    for item in json["WorkSpace"].pairs:
      case item.key:
        of "workSpaceLine":
          if not (item.val["type"].getStr == "bool"):
            return some($item)
        else:
            return some($item)

  template validateHighlightTable() =
    for item in json["Highlight"].pairs:
      case item.key:
        of "reservedWord":
          if item.val["type"].getStr == "array":
            for word in item.val["value"]:
              if word["type"].getStr != "string":
                return some($item)
        else:
          return some($item)

  template validateAutoBackupTable() =
    for item in json["AutoBackup"].pairs:
      case item.key:
        of "enable", "showMessages":
          if item.val["type"].getStr != "bool":
            return some($item)
        of "idolTime",
           "interval":
          if item.val["type"].getStr != "integer":
            return some($item)
        of "backupDir":
          if item.val["type"].getStr != "string":
            return some($item)
        of "dirToExclude":
          if item.val["type"].getStr == "array":
            for word in item.val["value"]:
              if word["type"].getStr != "string":
                return some($item)
        else:
          return some($item)

  template validateQuickRunTable() =
    for item in json["QuickRun"].pairs:
      case item.key:
        of "saveBufferWhenQuickRun":
          if item.val["type"].getStr != "bool":
            return some($item)
        of "command",
           "nimAdvancedCommand",
           "ClangOptions",
           "CppOptions",
           "NimOptions",
           "shOptions",
           "bashOptions":
          if item.val["type"].getStr != "string":
            return some($item)
        of "timeout":
          if item.val["type"].getStr != "integer":
            return some($item)
        else:
          return some($item)

  template validateNotificationTable() =
    for item in json["Notification"].pairs:
      case item.key:
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
          if item.val["type"].getStr != "bool":
            return some($item)
        else:
          return some($item)

  template validateFilerTable() =
    for item in json["Filer"].pairs:
      case item.key:
        of "showIcons":
          if item.val["type"].getStr != "bool":
            return some($item)
        else:
          return some($item)

  template validateAutocompleteTable() =
    for item in json["Autocomplete"].pairs:
      case item.key:
      of "enable":
        if item.val["type"].getStr != "bool":
          return some($item)
      else:
        return some($item)

  template validateThemeTable() =
    let editorColors = ColorThemeTable[ColorTheme.config].EditorColor
    for item in json["Theme"].pairs:
      case item.key:
        of "baseTheme":
          var correctKey = false
          for theme in ColorTheme:
            if $theme == item.val["value"].getStr:
              correctKey = true
          if not correctKey: return some($item)
        else:
          # Check color names
          var correctKey = false
          for field, val in editorColors.fieldPairs:
            if item.key == field and
               item.val["type"].getStr == "string":
              for color in Color:
                if item.val["value"].getStr == $color:
                  correctKey = true
                  break
              if correctKey: break
          if not correctKey:
            return some($item)

  let json = toml.toJson

  for table in json.keys:
    case table:
      of "Standard":
        validateStandardTable()
      of "TabLine":
        validateTabLineTable()
      of "StatusBar":
        validateStatusBarTable()
      of "BuildOnSave":
        validateBuildOnSaveTable()
      of "WorkSpace":
        validateWorkSpaceTable
      of "Highlight":
        validateHighlightTable()
      of "AutoBackup":
        validateAutoBackupTable()
      of "QuickRun":
        validateQuickRunTable()
      of "Notification":
        validateNotificationTable()
      of "Filer":
        validateFilerTable()
      of "Theme":
        validateThemeTable()
      of "Autocomplete":
        validateAutocompleteTable()
      else: discard

  return none(string)

proc loadSettingFile*(): EditorSettings =
  let filename = getConfigDir() / "moe" / "moerc.toml"

  if not fileExists(filename):
    return initEditorSettings()

  let
    toml = parsetoml.parseFile(filename)
    invalidItem = toml.validateTomlConfig

  if invalidItem != none(string):
    raise newException(InvalidItemError, $invalidItem)
  else:
    return parseSettingsFile(toml)
