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
