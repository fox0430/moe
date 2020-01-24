import parsetoml, os
import editorstatus, ui
from strutils import parseEnum

proc getCursorType(cursorType, mode: string): CursorType =
  case cursorType
  of "block": return CursorType.blockMode
  of "ibeam": return CursorType.ibeamMode
  else:
    case mode
    of "default": return CursorType.blockMode
    of "normal": return CursorType.blockMode
    of "insert": return CursorType.ibeamMode

proc getTheme(theme: string): ColorTheme =
  if theme == "dark": return ColorTheme.dark
  elif theme == "light": return ColorTheme.light
  else: return ColorTheme.vivid

proc parseSettingsFile*(filename: string): EditorSettings =
  result = initEditorSettings()

  var settings: TomlValueRef
  try: settings = parsetoml.parseFile(filename)
  except IOError: return

  if settings.contains("Standard"):
    if settings["Standard"].contains("theme"):
      result.editorColorTheme = getTheme(settings["Standard"]["theme"].getStr())

    if settings["Standard"].contains("number"):
      result.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("currentNumber"):
      result.currentLineNumber = settings["Standard"]["currentNumber"].getbool()

    if settings["Standard"].contains("cursorLine"):
      result.cursorLine = settings["Standard"]["cursorLine"].getbool()

    if settings["Standard"].contains("statusBar"):
      result.statusBar.useBar = settings["Standard"]["statusBar"].getbool()

    if settings["Standard"].contains("tabLine"):
      result.tabLine.useTab= settings["Standard"]["tabLine"].getbool()

    if settings["Standard"].contains("syntax"):
      result.syntax = settings["Standard"]["syntax"].getbool()

    if settings["Standard"].contains("tabStop"):
      result.tabStop = settings["Standard"]["tabStop"].getInt()

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

    if settings["Standard"].contains("systemClipboard"):
      result.systemClipboard = settings["Standard"]["systemClipboard"].getbool()

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
        result.statusBar.language = settings["StatusBar"]["directory"].getbool()

  if settings.contains("Theme"):
    if settings["Theme"].contains("baseTheme"):
      let theme = parseEnum[ColorTheme](settings["Theme"]["baseTheme"].getStr())
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

    if settings["Theme"].contains("statusBarInsertMode"):
      ColorThemeTable[ColorTheme.config].statusBarInsertMode = color("statusBarInsertMode")

    if settings["Theme"].contains("statusBarInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarInsertModeBg = color("statusBarInsertModeBg")

    if settings["Theme"].contains("statusBarModeInsertMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeInsertMode = color("statusBarModeInsertMode")

    if settings["Theme"].contains("statusBarModeInsertModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeInsertModeBg = color("statusBarModeInsertModeBg")

    if settings["Theme"].contains("statusBarVisualMode"):
      ColorThemeTable[ColorTheme.config].statusBarVisualMode = color("statusBarVisualMode")

    if settings["Theme"].contains("statusBarModeVisualMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeVisualMode = color("statusBarModeVisualMode")

    if settings["Theme"].contains("statusBarModeVisualModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeVisualModeBg = color("statusBarModeVisualModeBg")

    if settings["Theme"].contains("statusBarReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceMode = color("statusBarReplaceMode")

    if settings["Theme"].contains("statusBarReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarReplaceModeBg = color("statusBarReplaceModeBg")

    if settings["Theme"].contains("statusBarModeReplaceMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeReplaceMode = color("statusBarModeReplaceMode")

    if settings["Theme"].contains("statusBarModeReplaceModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeReplaceModeBg = color("statusBarModeReplaceModeBg")

    if settings["Theme"].contains("statusBarFilerMode"):
      ColorThemeTable[ColorTheme.config].statusBarFilerMode = color("statusBarFilerMode")

    if settings["Theme"].contains("statusBarFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarFilerModeBg = color("statusBarFilerModeBg")

    if settings["Theme"].contains("statusBarModeFilerMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeFilerMode = color("statusBarModeFilerMode")

    if settings["Theme"].contains("statusBarModeFilerModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeFilerModeBg = color("statusBarModeFilerModeBg")

    if settings["Theme"].contains("statusBarExMode"):
      ColorThemeTable[ColorTheme.config].statusBarExMode = color("statusBarExMode")

    if settings["Theme"].contains("statusBarExModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarExModeBg = color("statusBarExModeBg")

    if settings["Theme"].contains("statusBarModeExMode"):
      ColorThemeTable[ColorTheme.config].statusBarModeExMode = color("statusBarModeExMode")

    if settings["Theme"].contains("statusBarModeExModeBg"):
      ColorThemeTable[ColorTheme.config].statusBarModeExModeBg = color("statusBarModeExModeBg")

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

    if settings["Theme"].contains("popUpWindowBg"):
      ColorThemeTable[ColorTheme.config].popUpWindowBg = color("popUpWindowBg")

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

    result.editorColorTheme = ColorTheme.config

proc loadSettingFile*(settings: var EditorSettings) =
  try: settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")
  except ValueError: return
