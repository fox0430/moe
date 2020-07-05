import parsetoml, os, json, macros
from strutils import parseEnum, endsWith

when (NimMajor, NimMinor, NimPatch) > (1, 3, 0):
  # This addresses a breaking change in https://github.com/nim-lang/Nim/pull/14046.
  from strutils import nimIdentNormalize
  export strutils.nimIdentNormalize

import ui, color, unicodeext, build, highlight

type FilerSettings = object
  showIcons*: bool

type WorkSpaceSettings = object
  useBar*: bool

type StatusBarSettings* = object
  useBar*: bool
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

type TabLineSettings* = object
  useTab*: bool
  allbuffer*: bool

type EditorViewSettings* = object
  lineNumber*: bool
  currentLineNumber*: bool
  cursorLine*: bool
  indentationLines*: bool
  tabStop*: int

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  statusBar*: StatusBarSettings
  tabLine*: TabLineSettings
  view*: EditorViewSettings
  syntax*: bool
  autoCloseParen*: bool
  autoIndent*: bool
  tabStop*: int
  characterEncoding*: CharacterEncoding # TODO: move to EditorStatus ...?
  defaultCursor*: CursorType
  normalModeCursor*: CursorType
  insertModeCursor*: CursorType
  autoSave*: bool
  autoSaveInterval*: int # minutes
  liveReloadOfConf*: bool
  realtimeSearch*: bool
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
  buildOnSaveSettings*: BuildOnSaveSettings
  workSpace*: WorkSpaceSettings
  filerSettings*: FilerSettings
  reservedWords*: seq[ReservedWord]

proc initFilerSettings(): FilerSettings =
  result.showIcons = true

proc initTabBarSettings*(): TabLineSettings =
  result.useTab = true

proc initStatusBarSettings*(): StatusBarSettings =
  result.useBar = true
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

proc initWorkSpaceSettings(): WorkSpaceSettings =
  result.useBar = false

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
  result.editorColorTheme = ColorTheme.vivid
  result.statusBar = initStatusBarSettings()
  result.tabLine = initTabBarSettings()
  result.view = initEditorViewSettings()
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.defaultCursor = CursorType.blinkBlockMode # Terminal default curosr shape
  result.normalModeCursor = CursorType.blinkBlockMode
  result.insertModeCursor = CursorType.blinkIbeamMode
  result.autoSaveInterval = 5
  result.realtimeSearch = true
  result.popUpWindowInExmode = true
  result.replaceTextHighlight = true
  result.highlightPairOfParen = true
  result.autoDeleteParen = true
  result.smoothScroll = true
  result.smoothScrollSpeed = 17
  result.highlightOtherUsesCurrentWord = true
  result.systemClipboard = true
  result.highlightFullWidthSpace = true
  result.highlightTrailingSpaces = true
  result.buildOnSaveSettings = BuildOnSaveSettings()
  result.workSpace= initWorkSpaceSettings()
  result.filerSettings = initFilerSettings()
  result.reservedWords = initReservedWords()

proc getCursorType(cursorType, mode: string): CursorType =
  case cursorType
  of "blinkBlock": return CursorType.blinkBlockMode
  of "noneBlinkBlock": return CursorType.noneBlinkBlockMode
  of "blinkIbeam": return CursorType.blinkIbeamMode
  of "noneBlinkIbeam": return CursorType.noneBlinkIbeamMode
  else:
    case mode
    of "default": return CursorType.blinkBlockMode
    of "normal": return CursorType.blinkBlockMode
    of "insert": return CursorType.blinkIbeamMode

proc getTheme(theme: string): ColorTheme =
  if theme == "dark": return ColorTheme.dark
  elif theme == "light": return ColorTheme.light
  elif theme == "config": return ColorTheme.config
  elif theme == "vscode": return ColorTheme.config
  else: return ColorTheme.vivid

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
      JsonNode.default()

  # This is currently optimized and tested for the Forest Focus theme
  # and even for that theme it only produces a partial and imperfect
  # translation
  expandMacros:
    setEditorColor editorBg:
      background:
        colorFromNode(jsonNode{"colors", "editor.background"})
    setEditorColor defaultChar:
      foreground:
        colorFromNode(jsonNode{"colors", "editor.foreground"})
    setEditorColor gtKeyword:
      foreground:
        colorFromNode(getScope("keyword"){"foreground"})
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

proc parseSettingsFile*(filename: string): EditorSettings =
  result = initEditorSettings()

  var vscodeTheme = false
  var settings: TomlValueRef
  try: settings = parsetoml.parseFile(filename)
  except IOError: return

  if settings.contains("Standard"):
    if settings["Standard"].contains("theme"):
      let themeString = settings["Standard"]["theme"].getStr()
      result.editorColorTheme = getTheme(themeString)
      if themeString == "vscode":
        vscodeTheme = true

    if settings["Standard"].contains("number"):
      result.view.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("currentNumber"):
      result.view.currentLineNumber = settings["Standard"]["currentNumber"].getbool()

    if settings["Standard"].contains("cursorLine"):
      result.view.cursorLine = settings["Standard"]["cursorLine"].getbool()

    if settings["Standard"].contains("statusBar"):
      result.statusBar.useBar = settings["Standard"]["statusBar"].getbool()

    if settings["Standard"].contains("tabLine"):
      result.tabLine.useTab= settings["Standard"]["tabLine"].getbool()

    if settings["Standard"].contains("syntax"):
      result.syntax = settings["Standard"]["syntax"].getbool()

    if settings["Standard"].contains("tabStop"):
      result.tabStop      = settings["Standard"]["tabStop"].getInt()
      result.view.tabStop = settings["Standard"]["tabStop"].getInt()

    if settings["Standard"].contains("autoCloseParen"):
      result.autoCloseParen = settings["Standard"]["autoCloseParen"].getbool()

    if settings["Standard"].contains("autoIndent"):
      result.autoIndent = settings["Standard"]["autoIndent"].getbool()

    if settings["Standard"].contains("defaultCursor"):
      result.defaultCursor = getCursorType(settings["Standard"]["defaultCursor"].getStr(), "default")

    if settings["Standard"].contains("normalModeCursor"):
      result.normalModeCursor = getCursorType(settings["Standard"]["normalModeCursor"].getStr(), "normal")

    if settings["Standard"].contains("insertModeCursor"):
      result.insertModeCursor = getCursorType(settings["Standard"]["insertModeCursor"].getStr(), "insert")

    if settings["Standard"].contains("autoSave"):
      result.autoSave = settings["Standard"]["autoSave"].getbool()

    if settings["Standard"].contains("autoSaveInterval"):
      result.autoSaveInterval = settings["Standard"]["autoSaveInterval"].getInt()

    if settings["Standard"].contains("liveReloadOfConf"):
      result.liveReloadOfConf = settings["Standard"]["liveReloadOfConf"].getbool()

    if settings["Standard"].contains("realtimeSearch"):
      result.realtimeSearch = settings["Standard"]["realtimeSearch"].getbool()

    if settings["Standard"].contains("popUpWindowInExmode "):
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
      result.smoothScrollSpeed =  settings["Standard"]["smoothScrollSpeed"].getint()

    if settings["Standard"].contains("highlightCurrentWord"):
      result.highlightOtherUsesCurrentWord = settings["Standard"]["highlightCurrentWord"].getbool()

    if settings["Standard"].contains("systemClipboard"):
      result.systemClipboard = settings["Standard"]["systemClipboard"].getbool()

    if settings["Standard"].contains("highlightFullWidthSpace"):
      result.highlightFullWidthSpace = settings["Standard"]["highlightFullWidthSpace"].getbool()

    if settings["Standard"].contains("highlightTrailingSpaces"):
      result.highlightTrailingSpaces = settings["Standard"]["highlightTrailingSpaces"].getbool()
    
    if settings["Standard"].contains("indentationLines"):
      result.view.indentationLines= settings["Standard"]["indentationLines"].getbool()

  if settings.contains("TabLine"):
    if settings["TabLine"].contains("allBuffer"):
        result.tabLine.allBuffer= settings["TabLine"]["allBuffer"].getbool()

  if settings.contains("StatusBar"):
    if settings["StatusBar"].contains("mode"):
        result.statusBar.mode= settings["StatusBar"]["mode"].getbool()

    if settings["StatusBar"].contains("filename"):
        result.statusBar.filename = settings["StatusBar"]["chanedMark"].getbool()

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

    if settings["StatusBar"].contains("multipleStatusBar"):
        result.statusBar.multipleStatusBar = settings["StatusBar"]["multipleStatusBar"].getbool()

    if settings["StatusBar"].contains("gitbranchName"):
        result.statusBar.gitbranchName = settings["StatusBar"]["gitbranchName"].getbool()

    if settings["StatusBar"].contains("showGitInactive"):
        result.statusBar.showGitInactive = settings["StatusBar"]["showGitInactive"].getbool()

  if settings.contains("BuildOnSave"):
    if settings["BuildOnSave"].contains("buildOnSave"):
      result.buildOnSaveSettings.buildOnSave = settings["BuildOnSave"]["buildOnSave"].getbool()

    if settings["BuildOnSave"].contains("workspaceRoot"):
      result.buildOnSaveSettings.workspaceRoot = settings["BuildOnSave"]["workspaceRoot"].getStr().toRunes

    if settings["BuildOnSave"].contains("command"):
      result.buildOnSaveSettings.workspaceRoot = settings["BuildOnSave"]["command"].getStr().toRunes

  if settings.contains("WorkSpace"):
    if settings["WorkSpace"].contains("useBar"):
        result.workSpace.useBar = settings["WorkSpace"]["useBar"].getbool()

  if settings["Highlight"].contains("reservedWord"):
    if settings["Highlight"].contains("reservedWord"):
      let reservedWords = settings["Highlight"]["reservedWord"]
      for i in 0 ..< reservedWords.len:
        let
          word = reservedWords[i].getStr
          reservedWord = ReservedWord(word: word, color: EditorColorPair.reservedWord)
        result.reservedWords.add(reservedWord)

  if settings.contains("Filer"):
    if settings["Filer"].contains("showIcons"):
      result.filerSettings.showIcons = settings["Filer"]["showIcons"].getbool()

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

    if settings["Theme"].contains("defaultCharactorColor"):
      ColorThemeTable[ColorTheme.config].defaultChar = color("defaultCharactorColor")

    if settings["Theme"].contains("gtKeywordColor"):
      ColorThemeTable[ColorTheme.config].gtKeyword = color("gtKeywordColor")

    if settings["Theme"].contains("gtStringLitColor"):
      ColorThemeTable[ColorTheme.config].gtStringLit = color("gtStringLitColor")

    if settings["Theme"].contains("gtDecNumberColor"):
      ColorThemeTable[ColorTheme.config].gtDecNumber = color("gtDecNumberColor")

    if settings["Theme"].contains("gtCommentColor"):
      ColorThemeTable[ColorTheme.config].gtComment = color("gtCommentColor")

    if settings["Theme"].contains("gtLongCommentColor"):
      ColorThemeTable[ColorTheme.config].gtLongComment = color("gtLongCommentColor")

    if settings["Theme"].contains("gtWhitespaceColor"):
      ColorThemeTable[ColorTheme.config].gtLongComment = color("gtWhitespaceColor")

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
      ColorThemeTable[ColorTheme.config].workSpaceBar = color("wrokSpaceBar")

    if settings["Theme"].contains("workSpaceBarBg"):
      ColorThemeTable[ColorTheme.config].workSpaceBarBg = color("wrokSpaceBarBg")

    if settings["Theme"].contains("reservedWord"):
      ColorThemeTable[ColorTheme.config].reservedWord = color("reservedWord")

    if settings["Theme"].contains("reservedWordBg"):
      ColorThemeTable[ColorTheme.config].reservedWordBg = color("reservedWordBg")

    result.editorColorTheme = ColorTheme.config
  if vscodeTheme:
    # search for the vscode theme that is set in the current preferences of
    # vscode/vscodium. Vscodium takes precedence, since you can assume that,
    # people that install VScodium prefer it over Vscode for privacy reasons.
    # If no vscode theme can be found, this defaults to the vivid theme.
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
      if not existsFile(vsCodeSettingsFile):
        vsCodeSettingsFile = homeDir & "/.config/Code/User/settings.json"
      if existsFile(vsCodeSettingsFile):
        let vsCodeSettingsJson = json.parseFile(vsCodeSettingsFile)
        vsCodeThemeSetting = vsCodeSettingsJson{"workbench.colorTheme"}.getStr()
        if vsCodeThemeSetting == "":
          break vsCodeThemeLoading

      else:
        break vsCodeThemeLoading
      
      if not existsDir(vsCodeExtensionsDir):
        vsCodeExtensionsDir = homeDir & "/.vscode/extensions/"
        if not existsDir(vsCodeExtensionsDir):
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
        result.editorColorTheme = ColorTheme.config
        ColorThemeTable[ColorTheme.config] =
          makeColorThemeFromVSCodeThemeFile(vsCodeThemeFile)
        vsCodeThemeLoaded = true
    if not vsCodeThemeLoaded:
      result.editorColorTheme = ColorTheme.vivid

proc loadSettingFile*(settings: var EditorSettings) =
  try: settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")
  except ValueError: return
