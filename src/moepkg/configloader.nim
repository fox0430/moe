#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Configuration loader for TOML files
##
## This module handles loading configuration from TOML files and converting
## them into EditorConfig structures.

import std/[os, options, tables, strutils]

import pkg/[parsetoml, results]

import config, color, theme

proc parseColorMode(s: string): ColorMode =
  case s
  of "8bit": cm8bit
  of "24bit": cm24bit
  of "none": cmNone
  else: cm24bit

proc parseCursorType(s: string): CursorType =
  case s
  of "terminalDefault": ctTerminalDefault
  of "blinkBlock": ctBlinkBlock
  of "blinkIbeam": ctBlinkIbeam
  of "nonBlinkBlock": ctNonBlinkBlock
  of "nonBlinkIbeam": ctNonBlinkIbeam
  else: ctTerminalDefault

proc parseThemeKind(s: string): ThemeKind =
  case s
  of "default": tkDefault
  of "config": tkConfig
  of "vscode": tkVscode
  else: tkConfig

proc parseClipboardTool(s: string): ClipboardTool =
  case s
  of "xsel": ctXsel
  of "xclip": ctXclip
  of "wl-clipboard": ctWlClipboard
  of "win32yank": ctWin32yank
  of "pbcopy": ctPbcopy
  else: ctXsel

proc parseSplitType(s: string): SplitType =
  case s
  of "horizontal": stHorizontal
  of "vertical": stVertical
  else: stVertical

proc loadStandardConfig(table: TomlTableRef, config: var StandardConfig) =
  if table.hasKey("number"):
    config.number = table["number"].getBool()
  if table.hasKey("currentNumber"):
    config.currentNumber = table["currentNumber"].getBool()
  if table.hasKey("cursorLine"):
    config.cursorLine = table["cursorLine"].getBool()
  if table.hasKey("statusLine"):
    config.statusLine = table["statusLine"].getBool()
  if table.hasKey("tabLine"):
    config.tabLine = table["tabLine"].getBool()
  if table.hasKey("syntax"):
    config.syntax = table["syntax"].getBool()
  if table.hasKey("indentationLines"):
    config.indentationLines = table["indentationLines"].getBool()
  if table.hasKey("tabStop"):
    config.tabStop = table["tabStop"].getInt()
  if table.hasKey("expandTab"):
    config.expandTab = table["expandTab"].getBool()
  if table.hasKey("sidebar"):
    config.sidebar = table["sidebar"].getBool()
  if table.hasKey("autoCloseParen"):
    config.autoCloseParen = table["autoCloseParen"].getBool()
  if table.hasKey("autoIndent"):
    config.autoIndent = table["autoIndent"].getBool()
  if table.hasKey("ignorecase"):
    config.ignorecase = table["ignorecase"].getBool()
  if table.hasKey("smartcase"):
    config.smartcase = table["smartcase"].getBool()
  if table.hasKey("disableChangeCursor"):
    config.disableChangeCursor = table["disableChangeCursor"].getBool()
  if table.hasKey("defaultCursor"):
    config.defaultCursor = parseCursorType(table["defaultCursor"].getStr())
  if table.hasKey("normalModeCursor"):
    config.normalModeCursor = parseCursorType(table["normalModeCursor"].getStr())
  if table.hasKey("insertModeCursor"):
    config.insertModeCursor = parseCursorType(table["insertModeCursor"].getStr())
  if table.hasKey("liveReloadOfConf"):
    config.liveReloadOfConf = table["liveReloadOfConf"].getBool()
  if table.hasKey("incrementalSearch"):
    config.incrementalSearch = table["incrementalSearch"].getBool()
  if table.hasKey("popupWindowInExmode"):
    config.popupWindowInExmode = table["popupWindowInExmode"].getBool()
  if table.hasKey("autoDeleteParen"):
    config.autoDeleteParen = table["autoDeleteParen"].getBool()
  if table.hasKey("liveReloadOfFile"):
    config.liveReloadOfFile = table["liveReloadOfFile"].getBool()
  if table.hasKey("colorMode"):
    config.colorMode = parseColorMode(table["colorMode"].getStr())

proc loadClipboardConfig(table: TomlTableRef, config: var ClipboardConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("tool"):
    config.tool = parseClipboardTool(table["tool"].getStr())

proc loadBuildOnSaveConfig(table: TomlTableRef, config: var BuildOnSaveConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("workspaceRoot"):
    config.workspaceRoot = some(table["workspaceRoot"].getStr())
  if table.hasKey("command"):
    config.command = some(table["command"].getStr())

proc loadTabLineConfig(table: TomlTableRef, config: var TabLineConfig) =
  if table.hasKey("allBuffer"):
    config.allBuffer = table["allBuffer"].getBool()

proc loadStatusLineConfig(table: TomlTableRef, config: var StatusLineConfig) =
  if table.hasKey("multipleStatusLine"):
    config.multipleStatusLine = table["multipleStatusLine"].getBool()
  if table.hasKey("merge"):
    config.merge = table["merge"].getBool()
  if table.hasKey("mode"):
    config.mode = table["mode"].getBool()
  if table.hasKey("filename"):
    config.filename = table["filename"].getBool()
  if table.hasKey("chanedMark"):
    config.chanedMark = table["chanedMark"].getBool()
  if table.hasKey("directory"):
    config.directory = table["directory"].getBool()
  if table.hasKey("gitChangedLines"):
    config.gitChangedLines = table["gitChangedLines"].getBool()
  if table.hasKey("gitBranchName"):
    config.gitBranchName = table["gitBranchName"].getBool()
  if table.hasKey("showGitInactive"):
    config.showGitInactive = table["showGitInactive"].getBool()
  if table.hasKey("showModeInactive"):
    config.showModeInactive = table["showModeInactive"].getBool()
  if table.hasKey("setupText"):
    config.setupText = table["setupText"].getStr()

proc loadGitConfig(table: TomlTableRef, config: var GitConfig) =
  if table.hasKey("showChangedLine"):
    config.showChangedLine = table["showChangedLine"].getBool()
  if table.hasKey("updateInterval"):
    config.updateInterval = table["updateInterval"].getInt()

proc loadSyntaxCheckerConfig(table: TomlTableRef, config: var SyntaxCheckerConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadThemeConfig(table: TomlTableRef, config: var ThemeConfig) =
  if table.hasKey("kind"):
    config.kind = parseThemeKind(table["kind"].getStr())
  if table.hasKey("path"):
    config.path = table["path"].getStr()

proc loadAutoSaveConfig(table: TomlTableRef, config: var AutoSaveConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("interval"):
    config.interval = table["interval"].getInt()

proc loadNotificationConfig(table: TomlTableRef, config: var NotificationConfig) =
  if table.hasKey("screenNotifications"):
    config.screenNotifications = table["screenNotifications"].getBool()
  if table.hasKey("logNotifications"):
    config.logNotifications = table["logNotifications"].getBool()
  if table.hasKey("autoBackupScreenNotify"):
    config.autoBackupScreenNotify = table["autoBackupScreenNotify"].getBool()
  if table.hasKey("autoBackupLogNotify"):
    config.autoBackupLogNotify = table["autoBackupLogNotify"].getBool()
  if table.hasKey("autoSaveScreenNotify"):
    config.autoSaveScreenNotify = table["autoSaveScreenNotify"].getBool()
  if table.hasKey("autoSaveLogNotify"):
    config.autoSaveLogNotify = table["autoSaveLogNotify"].getBool()
  if table.hasKey("yankScreenNotify"):
    config.yankScreenNotify = table["yankScreenNotify"].getBool()
  if table.hasKey("yankLogNotify"):
    config.yankLogNotify = table["yankLogNotify"].getBool()
  if table.hasKey("deleteScreenNotify"):
    config.deleteScreenNotify = table["deleteScreenNotify"].getBool()
  if table.hasKey("deleteLogNotify"):
    config.deleteLogNotify = table["deleteLogNotify"].getBool()
  if table.hasKey("saveScreenNotify"):
    config.saveScreenNotify = table["saveScreenNotify"].getBool()
  if table.hasKey("saveLogNotify"):
    config.saveLogNotify = table["saveLogNotify"].getBool()
  if table.hasKey("quickRunScreenNotify"):
    config.quickRunScreenNotify = table["quickRunScreenNotify"].getBool()
  if table.hasKey("quickRunLogNotify"):
    config.quickRunLogNotify = table["quickRunLogNotify"].getBool()
  if table.hasKey("buildOnSaveScreenNotify"):
    config.buildOnSaveScreenNotify = table["buildOnSaveScreenNotify"].getBool()
  if table.hasKey("buildOnSaveLogNotify"):
    config.buildOnSaveLogNotify = table["buildOnSaveLogNotify"].getBool()
  if table.hasKey("filerScreenNotify"):
    config.filerScreenNotify = table["filerScreenNotify"].getBool()
  if table.hasKey("filerLogNotify"):
    config.filerLogNotify = table["filerLogNotify"].getBool()
  if table.hasKey("restoreScreenNotify"):
    config.restoreScreenNotify = table["restoreScreenNotify"].getBool()
  if table.hasKey("restoreLogNotify"):
    config.restoreLogNotify = table["restoreLogNotify"].getBool()
  if table.hasKey("lspScreenNotify"):
    config.lspScreenNotify = table["lspScreenNotify"].getBool()
  if table.hasKey("lspLogNotify"):
    config.lspLogNotify = table["lspLogNotify"].getBool()

proc loadAutoBackupConfig(table: TomlTableRef, config: var AutoBackupConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("backupDir"):
    config.backupDir = some(table["backupDir"].getStr())
  if table.hasKey("idleTime"):
    config.idleTime = table["idleTime"].getInt()
  if table.hasKey("interval"):
    config.interval = table["interval"].getInt()
  if table.hasKey("dirToExclude"):
    config.dirToExclude = @[]
    for item in table["dirToExclude"].getElems():
      config.dirToExclude.add(item.getStr())

proc loadConfigFromToml*(path: string): EditorConfig =
  ## Load configuration from a TOML file
  ## Returns a new EditorConfig with values loaded from the file
  ## Falls back to defaults for any missing values

  if not fileExists(path):
    return newEditorConfig()

  let toml = parseFile(path)
  result = newEditorConfig()

  # Load each section
  if toml.hasKey("Standard"):
    loadStandardConfig(toml["Standard"].getTable(), result.standard)

  if toml.hasKey("Clipboard"):
    loadClipboardConfig(toml["Clipboard"].getTable(), result.clipboard)

  if toml.hasKey("BuildOnSave"):
    loadBuildOnSaveConfig(toml["BuildOnSave"].getTable(), result.buildOnSave)

  if toml.hasKey("TabLine"):
    loadTabLineConfig(toml["TabLine"].getTable(), result.tabLine)

  if toml.hasKey("StatusLine"):
    loadStatusLineConfig(toml["StatusLine"].getTable(), result.statusLine)

  if toml.hasKey("Git"):
    loadGitConfig(toml["Git"].getTable(), result.git)

  if toml.hasKey("SyntaxChecker"):
    loadSyntaxCheckerConfig(toml["SyntaxChecker"].getTable(), result.syntaxChecker)

  if toml.hasKey("Theme"):
    loadThemeConfig(toml["Theme"].getTable(), result.theme)

  if toml.hasKey("AutoSave"):
    loadAutoSaveConfig(toml["AutoSave"].getTable(), result.autoSave)

  if toml.hasKey("Notification"):
    loadNotificationConfig(toml["Notification"].getTable(), result.notification)

  if toml.hasKey("AutoBackup"):
    loadAutoBackupConfig(toml["AutoBackup"].getTable(), result.autoBackup)

proc getConfigPath*(): string =
  ## Get the path to the configuration file
  ## Searches in standard locations:
  ## 1. $XDG_CONFIG_HOME/moe/moerc.toml
  ## 2. ~/.config/moe/moerc.toml

  let configPaths = [
    getConfigDir() / "moe" / "moerc.toml",
    getHomeDir() / ".config" / "moe" / "moerc.toml",
  ]

  for path in configPaths:
    if fileExists(path):
      return path

  # Return the default location even if it doesn't exist
  return getConfigDir() / "moe" / "moerc.toml"

proc loadConfig*(): EditorConfig =
  ## Load configuration from the default location
  let configPath = getConfigPath()
  return loadConfigFromToml(configPath)

# Theme loading functions

proc toEditorColorPairIndex(key: string): Option[EditorColorPairIndex] =
  ## Convert a TOML key to EditorColorPairIndex
  ## Keys ending with "Bg" are treated as background colors
  ## Returns none if the key doesn't match any color index

  # Remove "Bg" suffix if present for lookup
  let lookupKey =
    if key.endsWith("Bg"):
      key[0 ..< key.len - 2]
    else:
      key

  case lookupKey
  of "foreground", "default":
    return some(EditorColorPairIndex.default)
  of "lineNum":
    return some(EditorColorPairIndex.lineNum)
  of "currentLineNum":
    return some(EditorColorPairIndex.currentLineNum)
  of "statusLineNormalMode":
    return some(EditorColorPairIndex.statusLineNormalMode)
  of "statusLineNormalModeLabel":
    return some(EditorColorPairIndex.statusLineNormalModeLabel)
  of "statusLineNormalModeInactive":
    return some(EditorColorPairIndex.statusLineNormalModeInactive)
  of "statusLineInsertMode":
    return some(EditorColorPairIndex.statusLineInsertMode)
  of "statusLineInsertModeLabel":
    return some(EditorColorPairIndex.statusLineInsertModeLabel)
  of "statusLineInsertModeInactive":
    return some(EditorColorPairIndex.statusLineInsertModeInactive)
  of "statusLineVisualMode":
    return some(EditorColorPairIndex.statusLineVisualMode)
  of "statusLineVisualModeLabel":
    return some(EditorColorPairIndex.statusLineVisualModeLabel)
  of "statusLineVisualModeInactive":
    return some(EditorColorPairIndex.statusLineVisualModeInactive)
  of "statusLineReplaceMode":
    return some(EditorColorPairIndex.statusLineReplaceMode)
  of "statusLineReplaceModeLabel":
    return some(EditorColorPairIndex.statusLineReplaceModeLabel)
  of "statusLineReplaceModeInactive":
    return some(EditorColorPairIndex.statusLineReplaceModeInactive)
  of "statusLineFilerMode":
    return some(EditorColorPairIndex.statusLineFilerMode)
  of "statusLineFilerModeLabel":
    return some(EditorColorPairIndex.statusLineFilerModeLabel)
  of "statusLineFilerModeInactive":
    return some(EditorColorPairIndex.statusLineFilerModeInactive)
  of "statusLineExMode":
    return some(EditorColorPairIndex.statusLineExMode)
  of "statusLineExModeLabel":
    return some(EditorColorPairIndex.statusLineExModeLabel)
  of "statusLineExModeInactive":
    return some(EditorColorPairIndex.statusLineExModeInactive)
  of "statusLineGitChangedLines":
    return some(EditorColorPairIndex.statusLineGitChangedLines)
  of "statusLineGitBranch":
    return some(EditorColorPairIndex.statusLineGitBranch)
  of "tab":
    return some(EditorColorPairIndex.tab)
  of "currentTab":
    return some(EditorColorPairIndex.currentTab)
  of "commandLine":
    return some(EditorColorPairIndex.commandLine)
  of "errorMessage":
    return some(EditorColorPairIndex.errorMessage)
  of "warnMessage":
    return some(EditorColorPairIndex.warnMessage)
  of "searchResult":
    return some(EditorColorPairIndex.searchResult)
  of "selectArea":
    return some(EditorColorPairIndex.selectArea)
  of "keyword":
    return some(EditorColorPairIndex.keyword)
  of "functionName":
    return some(EditorColorPairIndex.functionName)
  of "typeName":
    return some(EditorColorPairIndex.typeName)
  of "boolean":
    return some(EditorColorPairIndex.boolean)
  of "specialVar":
    return some(EditorColorPairIndex.specialVar)
  of "builtin":
    return some(EditorColorPairIndex.builtin)
  of "charLit":
    return some(EditorColorPairIndex.charLit)
  of "stringLit":
    return some(EditorColorPairIndex.stringLit)
  of "binNumber":
    return some(EditorColorPairIndex.binNumber)
  of "decNumber":
    return some(EditorColorPairIndex.decNumber)
  of "floatNumber":
    return some(EditorColorPairIndex.floatNumber)
  of "hexNumber":
    return some(EditorColorPairIndex.hexNumber)
  of "octNumber":
    return some(EditorColorPairIndex.octNumber)
  of "comment":
    return some(EditorColorPairIndex.comment)
  of "longComment":
    return some(EditorColorPairIndex.longComment)
  of "whitespace":
    return some(EditorColorPairIndex.whitespace)
  of "preprocessor":
    return some(EditorColorPairIndex.preprocessor)
  of "pragma":
    return some(EditorColorPairIndex.pragma)
  of "identifier":
    return some(EditorColorPairIndex.identifier)
  of "table":
    return some(EditorColorPairIndex.table)
  of "date":
    return some(EditorColorPairIndex.date)
  of "operator":
    return some(EditorColorPairIndex.operator)
  of "property":
    return some(EditorColorPairIndex.property)
  of "namespace":
    return some(EditorColorPairIndex.namespace)
  of "className":
    return some(EditorColorPairIndex.className)
  of "enumName":
    return some(EditorColorPairIndex.enumName)
  of "enumMember":
    return some(EditorColorPairIndex.enumMember)
  of "interfaceName":
    return some(EditorColorPairIndex.interfaceName)
  of "typeParameter":
    return some(EditorColorPairIndex.typeParameter)
  of "parameter":
    return some(EditorColorPairIndex.parameter)
  of "variable":
    return some(EditorColorPairIndex.variable)
  of "string":
    return some(EditorColorPairIndex.lspString)
  of "event":
    return some(EditorColorPairIndex.event)
  of "function":
    return some(EditorColorPairIndex.function)
  of "method":
    return some(EditorColorPairIndex.`method`)
  of "macro":
    return some(EditorColorPairIndex.`macro`)
  of "regexp":
    return some(EditorColorPairIndex.regexp)
  of "decorator":
    return some(EditorColorPairIndex.decorator)
  of "angle":
    return some(EditorColorPairIndex.angle)
  of "arithmetic":
    return some(EditorColorPairIndex.arithmetic)
  of "attribute":
    return some(EditorColorPairIndex.attribute)
  of "attributeBracket":
    return some(EditorColorPairIndex.attributeBracket)
  of "bitwise":
    return some(EditorColorPairIndex.bitwise)
  of "brace":
    return some(EditorColorPairIndex.brace)
  of "bracket":
    return some(EditorColorPairIndex.bracket)
  of "builtinAttribute":
    return some(EditorColorPairIndex.builtinAttribute)
  of "builtinType":
    return some(EditorColorPairIndex.builtinType)
  of "colon":
    return some(EditorColorPairIndex.colon)
  of "comma":
    return some(EditorColorPairIndex.comma)
  of "comparison":
    return some(EditorColorPairIndex.comparison)
  of "constParameter":
    return some(EditorColorPairIndex.constParameter)
  of "derive":
    return some(EditorColorPairIndex.derive)
  of "deriveHelper":
    return some(EditorColorPairIndex.deriveHelper)
  of "dot":
    return some(EditorColorPairIndex.dot)
  of "escapeSequence":
    return some(EditorColorPairIndex.escapeSequence)
  of "invalidEscapeSequence":
    return some(EditorColorPairIndex.invalidEscapeSequence)
  of "formatSpecifier":
    return some(EditorColorPairIndex.formatSpecifier)
  of "generic":
    return some(EditorColorPairIndex.generic)
  of "label":
    return some(EditorColorPairIndex.label)
  of "lifetime":
    return some(EditorColorPairIndex.lifetime)
  of "logical":
    return some(EditorColorPairIndex.logical)
  of "macroBang":
    return some(EditorColorPairIndex.macroBang)
  of "parenthesis":
    return some(EditorColorPairIndex.parenthesis)
  of "punctuation":
    return some(EditorColorPairIndex.punctuation)
  of "selfKeyword":
    return some(EditorColorPairIndex.selfKeyword)
  of "selfTypeKeyword":
    return some(EditorColorPairIndex.selfTypeKeyword)
  of "semicolon":
    return some(EditorColorPairIndex.semicolon)
  of "typeAlias":
    return some(EditorColorPairIndex.typeAlias)
  of "toolModule":
    return some(EditorColorPairIndex.toolModule)
  of "union":
    return some(EditorColorPairIndex.union)
  of "unresolvedReference":
    return some(EditorColorPairIndex.unresolvedReference)
  of "inlayHint":
    return some(EditorColorPairIndex.inlayHint)
  of "inlineValue":
    return some(EditorColorPairIndex.inlineValue)
  of "codeLens":
    return some(EditorColorPairIndex.codeLens)
  of "currentFile":
    return some(EditorColorPairIndex.currentFile)
  of "file":
    return some(EditorColorPairIndex.file)
  of "dir":
    return some(EditorColorPairIndex.dir)
  of "pcLink":
    return some(EditorColorPairIndex.pcLink)
  of "popupWindow":
    return some(EditorColorPairIndex.popupWindow)
  of "popupWinCurrentLine":
    return some(EditorColorPairIndex.popupWinCurrentLine)
  of "replaceText":
    return some(EditorColorPairIndex.replaceText)
  of "parenPair":
    return some(EditorColorPairIndex.parenPair)
  of "currentWord":
    return some(EditorColorPairIndex.currentWord)
  of "highlightFullWidthSpace":
    return some(EditorColorPairIndex.highlightFullWidthSpace)
  of "highlightTrailingSpaces":
    return some(EditorColorPairIndex.highlightTrailingSpaces)
  of "reservedWord":
    return some(EditorColorPairIndex.reservedWord)
  of "syntaxCheckInfo":
    return some(EditorColorPairIndex.syntaxCheckInfo)
  of "syntaxCheckHint":
    return some(EditorColorPairIndex.syntaxCheckHint)
  of "syntaxCheckWarn":
    return some(EditorColorPairIndex.syntaxCheckWarn)
  of "syntaxCheckErr":
    return some(EditorColorPairIndex.syntaxCheckErr)
  of "gitConflict":
    return some(EditorColorPairIndex.gitConflict)
  of "backupManagerCurrentLine":
    return some(EditorColorPairIndex.backupManagerCurrentLine)
  of "diffViewerAddedLine":
    return some(EditorColorPairIndex.diffViewerAddedLine)
  of "diffViewerDeletedLine":
    return some(EditorColorPairIndex.diffViewerDeletedLine)
  of "configModeCurrentLine":
    return some(EditorColorPairIndex.configModeCurrentLine)
  of "currentLineBg":
    return some(EditorColorPairIndex.currentLineBg)
  of "foldingLine":
    return some(EditorColorPairIndex.foldingLine)
  of "sidebarGitAddedSign":
    return some(EditorColorPairIndex.sidebarGitAddedSign)
  of "sidebarGitDeletedSign":
    return some(EditorColorPairIndex.sidebarGitDeletedSign)
  of "sidebarGitChangedSign":
    return some(EditorColorPairIndex.sidebarGitChangedSign)
  of "sidebarSyntaxCheckInfoSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckInfoSign)
  of "sidebarSyntaxCheckHintSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckHintSign)
  of "sidebarSyntaxCheckWarnSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckWarnSign)
  of "sidebarSyntaxCheckErrSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckErrSign)
  else:
    return none(EditorColorPairIndex)

proc loadThemeFromToml*(path: string): Result[ThemeColors, string] =
  ## Load theme colors from a TOML file
  ## Returns ThemeColors based on DefaultColors with overrides from the file

  let expandedPath = path.expandTilde
  if not fileExists(expandedPath):
    return Result[ThemeColors, string].err("Theme file not found: " & expandedPath)

  var toml: TomlValueRef
  try:
    toml = parseFile(expandedPath)
  except CatchableError as e:
    return Result[ThemeColors, string].err("Failed to parse theme file: " & e.msg)

  # Start with default colors
  var colors = DefaultColors

  # Check for Colors section
  if not toml.hasKey("Colors"):
    return Result[ThemeColors, string].err("Theme file missing [Colors] section")

  let colorsTable = toml["Colors"].getTable()

  # Get default foreground/background for syntax colors
  var defaultFg = colors[EditorColorPairIndex.default].foreground.rgb
  var defaultBg = colors[EditorColorPairIndex.default].background.rgb

  if colorsTable.hasKey("foreground"):
    let fgResult = hexToRgb(colorsTable["foreground"].getStr())
    if fgResult.isOk:
      defaultFg = fgResult.get

  if colorsTable.hasKey("background"):
    let bgResult = hexToRgb(colorsTable["background"].getStr())
    if bgResult.isOk:
      defaultBg = bgResult.get

  # Update default color pair
  colors[EditorColorPairIndex.default] = ColorPair(
    foreground: ThemeColor(rgb: defaultFg), background: ThemeColor(rgb: defaultBg)
  )

  # Process all color entries
  for key, value in colorsTable:
    if key == "foreground" or key == "background":
      continue

    let colorStr = value.getStr()
    let rgbResult = hexToRgb(colorStr)
    if rgbResult.isErr:
      continue

    let rgb = rgbResult.get
    let isBackground = key.endsWith("Bg")
    let indexOpt = toEditorColorPairIndex(key)

    if indexOpt.isNone:
      continue

    let index = indexOpt.get

    if isBackground:
      colors[index].background = ThemeColor(rgb: rgb)
    else:
      colors[index].foreground = ThemeColor(rgb: rgb)
      # For syntax colors without explicit background, use default background
      if not colorsTable.hasKey(key & "Bg"):
        colors[index].background = ThemeColor(rgb: defaultBg)

  return Result[ThemeColors, string].ok(colors)

proc loadTheme*(config: EditorConfig): Result[ThemeColors, string] =
  ## Load theme based on config settings

  case config.theme.kind
  of tkDefault:
    return Result[ThemeColors, string].ok(DefaultColors)
  of tkConfig:
    return loadThemeFromToml(config.theme.path)
  of tkVscode:
    # VSCode theme loading not yet implemented
    return Result[ThemeColors, string].err("VSCode themes not yet supported")

proc initTheme*(config: EditorConfig) =
  ## Initialize the theme based on configuration
  ## Falls back to default theme on error

  let themeResult = loadTheme(config)
  if themeResult.isOk:
    setThemeColors(themeResult.get)
  else:
    # Log error and use default
    initDefaultTheme()
