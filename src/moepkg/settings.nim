import parsetoml
import editorstatus

proc parseSettingsFile*(filename: string): EditorSettings =
  result = initEditorSettings()
  
  var settings: TomlValueRef
  try:
    settings = parsetoml.parseFile(filename)
  except IOError:
    return

  if settings.contains("Standard"):
    if settings["Standard"].contains("number"):
      result.lineNumber = settings["Standard"]["number"].getbool()

    if settings["Standard"].contains("statusBar"):
      result.statusBar.useBar = settings["Standard"]["statusBar"].getbool()

    if settings["Standard"].contains("syntax"):
      result.syntax = settings["Standard"]["syntax"].getbool()

    if settings["Standard"].contains("tabStop"):
      result.tabStop = settings["Standard"]["tabStop"].getInt()

    if settings["Standard"].contains("autoCloseParen"):
      result.autoCloseParen = settings["Standard"]["autoCloseParen"].getbool()

    if settings["Standard"].contains("autoIndent"):
      result.autoIndent = settings["Standard"]["autoIndent"].getbool()

  if settings.contains("StatusBar"):
    if settings["StatusBar"].contains("mode"):
        result.statusBar.mode= settings["useStatusBar"]["mode"].getbool()

    if settings["StatusBar"].contains("filename"):
        result.statusBar.filename = settings["useStatusBar"]["chanedMark"].getbool()

    if settings["StatusBar"].contains("line"):
        result.statusBar.line = settings["useStatusBar"]["line"].getbool()

    if settings["StatusBar"].contains("column"):
        result.statusBar.column = settings["useStatusBar"]["column"].getbool()

    if settings["StatusBar"].contains("encoding"):
        result.statusBar.characterEncoding = settings["useStatusBar"]["encoding"].getbool()

    if settings["StatusBar"].contains("language"):
        result.statusBar.language = settings["useStatusBar"]["language"].getbool()

    if settings["StatusBar"].contains("directory"):
        result.statusBar.language = settings["useStatusBar"]["directory"].getbool()
