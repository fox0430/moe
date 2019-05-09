import parsetoml
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
  try:
    settings = parsetoml.parseFile(filename)
  except IOError:
    return

  if settings.contains("Standard"):
    if settings["Standard"].contains("theme"):
      result.editorColorTheme = getTheme(settings["Standard"]["theme"].getStr())

    if settings["Standard"].contains("number"):
      result.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("currentNumber"):
      result.currentLineNumber = settings["Standard"]["currentNumber"].getbool()

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
      parseEnum[ColorPair](settings["Theme"][str].getStr())

    if settings["Theme"].contains("editor"):
      ColorThemeTable[ColorTheme.config].editor = color("editor")

    if settings["Theme"].contains("lineNum"):
      ColorThemeTable[ColorTheme.config].lineNum = color("lineNum")

    if settings["Theme"].contains("currentLineNum"):
      ColorThemeTable[ColorTheme.config].currentLineNum = color("currentLineNum")

    if settings["Theme"].contains("statusBar"):
      ColorThemeTable[ColorTheme.config].statusBar = color("statusBar")

    if settings["Theme"].contains("statusBarMode"):
      ColorThemeTable[ColorTheme.config].statusBarMode = color("statusBarMode")

    if settings["Theme"].contains("tab"):
      ColorThemeTable[ColorTheme.config].tab = color("tab")

    if settings["Theme"].contains("currentTab"):
      ColorThemeTable[ColorTheme.config].currentTab = color("currentTab")

    if settings["Theme"].contains("commandBar"):
      ColorThemeTable[ColorTheme.config].commandBar = color("commandBar")

    if settings["Theme"].contains("errorMessage"):
      ColorThemeTable[ColorTheme.config].errorMessage = color("errorMessage")

    result.editorColorTheme = ColorTheme.config
    result.editorColor = ColorThemeTable[ColorTheme.config]
