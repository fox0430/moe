import parsetoml
import os
import editorstatus

proc parseConfigFile*(settings: var EditorSettings): EditorSettings =

  var config: TomlValueRef
  try:
    config = parsetoml.parseFile(getHomeDir() & ".moerc.toml")
  except IOError:
    return settings

  if config.contains("Standard"):
    if config["Standard"].contains("tabStop"):
      result.tabStop = config["Standard"]["tabStop"].getInt()

    if config["Standard"].contains("autoCloseParen"):
      result.autoCloseParen = config["Standard"]["autoCloseParen"].getbool()

    if config["Standard"].contains("autoIndent"):
      result.autoIndent = config["Standard"]["autoIndent"].getbool()
