#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import std/[os, options, tables, sets, strutils, sequtils]

import pkg/[parsetoml, results]

import config, color, theme, vscode_theme, key_bindings

# Configuration validation types and utilities

type
  InvalidItemKind* = enum
    iikInvalidValue ## Known key with an invalid value
    iikUnknownKey ## Unknown key in a section

  InvalidItem* = object ## Represents a validation error for a configuration item
    kind*: InvalidItemKind # Default = iikInvalidValue
    name*: string # The key name that has an invalid value
    val*: string # The invalid value as a string
    expected*: string # Description of expected value

  ValidationResult* = object ## Result of validating a configuration table
    errors*: seq[InvalidItem]

proc newValidationResult*(): ValidationResult =
  ValidationResult(errors: @[])

proc addError*(vr: var ValidationResult, name, val, expected: string) =
  vr.errors.add(
    InvalidItem(kind: iikInvalidValue, name: name, val: val, expected: expected)
  )

proc hasErrors*(vr: ValidationResult): bool =
  vr.errors.len > 0

proc toErrorMessage*(item: InvalidItem): string =
  ## Convert an InvalidItem to a human-readable error message
  case item.kind
  of iikInvalidValue:
    "Invalid value for '" & item.name & "': got '" & item.val & "', expected " &
      item.expected
  of iikUnknownKey:
    "Unknown key: '" & item.name & "'"

proc toErrorMessages*(vr: ValidationResult): seq[string] =
  ## Convert all validation errors to human-readable messages
  vr.errors.mapIt(it.toErrorMessage)

proc parseColorMode(s: string): ColorMode =
  case s
  of "8": cm8color
  of "16": cm16color
  of "256": cm256color
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
  of "xsel": cbtXsel
  of "xclip": cbtXclip
  of "wl-clipboard": cbtWlClipboard
  of "win32yank": cbtWin32yank
  of "pbcopy": cbtPbcopy
  else: cbtXsel

proc parseSplitType(s: string): SplitType =
  case s
  of "horizontal": stHorizontal
  of "vertical": stVertical
  else: stVertical

proc parseLspTraceLevel(s: string): LspTraceLevel =
  case s
  of "off": ltOff
  of "messages": ltMessages
  of "verbose": ltVerbose
  else: ltOff

# Integrated load+validate helper functions
# These functions validate and load in one step.
# Invalid values are skipped (keeping defaults) and errors are collected.

proc fullKey(section, key: string): string {.inline.} =
  if section.len > 0:
    section & "." & key
  else:
    key

proc checkUnknownKeys(
    table: TomlTableRef,
    validKeys: openArray[string],
    section: string,
    vr: var ValidationResult,
) =
  ## Report unknown keys in a TOML table section.
  for key, _ in table:
    if key notin validKeys:
      vr.errors.add(InvalidItem(kind: iikUnknownKey, name: fullKey(section, key)))

proc loadBool(
    table: TomlTableRef,
    key: string,
    target: var bool,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a boolean value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.Bool:
      target = val.getBool()
    else:
      vr.addError(fullKey(section, key), $val, "boolean (true/false)")

proc loadInt(
    table: TomlTableRef,
    key: string,
    target: var int,
    vr: var ValidationResult,
    section: string = "",
    minVal: int = int.low,
    maxVal: int = int.high,
) =
  ## Load an integer value if valid and within range. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Int:
      vr.addError(fullKey(section, key), $val, "integer")
    else:
      let intVal = val.getInt
      if intVal < minVal or intVal > maxVal:
        let rangeDesc =
          if minVal == int.low:
            "integer <= " & $maxVal
          elif maxVal == int.high:
            "integer >= " & $minVal
          else:
            "integer between " & $minVal & " and " & $maxVal
        vr.addError(fullKey(section, key), $intVal, rangeDesc)
      else:
        target = intVal

proc loadFloat(
    table: TomlTableRef,
    key: string,
    target: var float,
    vr: var ValidationResult,
    section: string = "",
    minVal: float = float.low,
    maxVal: float = float.high,
) =
  ## Load a float value if valid and within range. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Float and val.kind != TomlValueKind.Int:
      vr.addError(fullKey(section, key), $val, "number")
    else:
      let floatVal =
        if val.kind == TomlValueKind.Float:
          val.getFloat
        else:
          float(val.getInt)
      if floatVal < minVal or floatVal > maxVal:
        let rangeDesc =
          if minVal == float.low:
            "number <= " & $maxVal
          elif maxVal == float.high:
            "number >= " & $minVal
          else:
            "number between " & $minVal & " and " & $maxVal
        vr.addError(fullKey(section, key), $floatVal, rangeDesc)
      else:
        target = floatVal

proc loadString(
    table: TomlTableRef,
    key: string,
    target: var string,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a string value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.String:
      target = val.getStr()
    else:
      vr.addError(fullKey(section, key), $val, "string")

proc loadOptionString(
    table: TomlTableRef,
    key: string,
    target: var Option[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load an optional string value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.String:
      target = some(val.getStr())
    else:
      vr.addError(fullKey(section, key), $val, "string")

proc loadStringArray(
    table: TomlTableRef,
    key: string,
    target: var seq[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a string array if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Array:
      vr.addError(fullKey(section, key), $val, "array of strings")
    else:
      var valid = true
      var result: seq[string] = @[]
      for i, item in val.getElems:
        if item.kind != TomlValueKind.String:
          vr.addError(fullKey(section, key) & "[" & $i & "]", $item, "string")
          valid = false
        else:
          result.add(item.getStr())
      if valid:
        target = result

proc loadFilePath(
    table: TomlTableRef,
    key: string,
    target: var string,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a file path if valid and file exists. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "string (file path)")
    else:
      let path = val.getStr().expandTilde
      if not fileExists(path):
        vr.addError(fullKey(section, key), val.getStr(), "existing file path")
      else:
        target = val.getStr()

proc loadOptionDirPath(
    table: TomlTableRef,
    key: string,
    target: var Option[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load an optional directory path if valid and directory exists. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "string (directory path)")
    else:
      let path = val.getStr().expandTilde
      if not dirExists(path):
        vr.addError(fullKey(section, key), val.getStr(), "existing directory path")
      else:
        target = some(val.getStr())

proc loadEnum[T](
    table: TomlTableRef,
    key: string,
    target: var T,
    vr: var ValidationResult,
    section: string = "",
    parseFunc: proc(s: string): T,
    validValues: openArray[string],
) =
  ## Load an enum value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "one of: " & validValues.join(", "))
    else:
      let strVal = val.getStr
      if strVal in validValues:
        target = parseFunc(strVal)
      else:
        vr.addError(fullKey(section, key), strVal, "one of: " & validValues.join(", "))

# Valid enum values for validation
const
  ValidColorModes* = ["8", "16", "256", "24bit", "none"]
  ValidCursorTypes* =
    ["terminalDefault", "blinkBlock", "blinkIbeam", "nonBlinkBlock", "nonBlinkIbeam"]
  ValidThemeKinds* = ["default", "config", "vscode"]
  ValidClipboardTools* = ["xsel", "xclip", "wl-clipboard", "win32yank", "pbcopy"]
  ValidSplitTypes* = ["horizontal", "vertical"]
  ValidLspTraceLevels* = ["off", "messages", "verbose"]

# Integrated load functions (validate + load in one step)

proc loadStandardConfig(
    table: TomlTableRef, config: var StandardConfig, vr: var ValidationResult
) =
  const section = "Standard"
  const validKeys = [
    "number", "statusLine", "syntax", "indentationLines", "tabStop", "expandTab",
    "sidebar", "autoCloseParen", "autoIndent", "ignorecase", "smartcase",
    "disableChangeCursor", "defaultCursor", "normalModeCursor", "insertModeCursor",
    "liveReloadOfConf", "incrementalSearch", "popupWindowInExmode", "autoDeleteParen",
    "liveReloadOfFile", "colorMode", "mouse", "lineWrap", "timeoutlen",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "number", config.number, vr, section)
  loadBool(table, "statusLine", config.statusLine, vr, section)
  loadBool(table, "syntax", config.syntax, vr, section)
  loadBool(table, "indentationLines", config.indentationLines, vr, section)
  loadInt(table, "tabStop", config.tabStop, vr, section, minVal = 1)
  loadBool(table, "expandTab", config.expandTab, vr, section)
  loadBool(table, "sidebar", config.sidebar, vr, section)
  loadBool(table, "autoCloseParen", config.autoCloseParen, vr, section)
  loadBool(table, "autoIndent", config.autoIndent, vr, section)
  loadBool(table, "ignorecase", config.ignorecase, vr, section)
  loadBool(table, "smartcase", config.smartcase, vr, section)
  loadBool(table, "disableChangeCursor", config.disableChangeCursor, vr, section)
  loadEnum(
    table, "defaultCursor", config.defaultCursor, vr, section, parseCursorType,
    ValidCursorTypes,
  )
  loadEnum(
    table, "normalModeCursor", config.normalModeCursor, vr, section, parseCursorType,
    ValidCursorTypes,
  )
  loadEnum(
    table, "insertModeCursor", config.insertModeCursor, vr, section, parseCursorType,
    ValidCursorTypes,
  )
  loadBool(table, "liveReloadOfConf", config.liveReloadOfConf, vr, section)
  loadBool(table, "incrementalSearch", config.incrementalSearch, vr, section)
  loadBool(table, "popupWindowInExmode", config.popupWindowInExmode, vr, section)
  loadBool(table, "autoDeleteParen", config.autoDeleteParen, vr, section)
  loadBool(table, "liveReloadOfFile", config.liveReloadOfFile, vr, section)
  loadEnum(
    table, "colorMode", config.colorMode, vr, section, parseColorMode, ValidColorModes
  )
  loadBool(table, "mouse", config.mouse, vr, section)
  loadBool(table, "lineWrap", config.lineWrap, vr, section)
  loadInt(table, "timeoutlen", config.timeoutlen, vr, section, minVal = 0)

proc loadClipboardConfig(
    table: TomlTableRef, config: var ClipboardConfig, vr: var ValidationResult
) =
  const section = "Clipboard"
  const validKeys = ["enable", "tool"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadEnum(
    table, "tool", config.tool, vr, section, parseClipboardTool, ValidClipboardTools
  )

proc loadBuildOnSaveConfig(
    table: TomlTableRef, config: var BuildOnSaveConfig, vr: var ValidationResult
) =
  const section = "BuildOnSave"
  const validKeys = ["enable", "workspaceRoot", "command"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadOptionDirPath(table, "workspaceRoot", config.workspaceRoot, vr, section)
  loadOptionString(table, "command", config.command, vr, section)

proc loadStatusLineConfig(
    table: TomlTableRef, config: var StatusLineConfig, vr: var ValidationResult
) =
  const section = "StatusLine"
  const validKeys = [
    "multipleStatusLine", "merge", "mode", "filename", "changedMark", "directory",
    "gitChangedLines", "gitBranchName", "showGitInactive", "showModeInactive",
    "setupText",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "multipleStatusLine", config.multipleStatusLine, vr, section)
  loadBool(table, "merge", config.merge, vr, section)
  loadBool(table, "mode", config.mode, vr, section)
  loadBool(table, "filename", config.filename, vr, section)
  loadBool(table, "changedMark", config.changedMark, vr, section)
  loadBool(table, "directory", config.directory, vr, section)
  loadBool(table, "gitChangedLines", config.gitChangedLines, vr, section)
  loadBool(table, "gitBranchName", config.gitBranchName, vr, section)
  loadBool(table, "showGitInactive", config.showGitInactive, vr, section)
  loadBool(table, "showModeInactive", config.showModeInactive, vr, section)
  loadString(table, "setupText", config.setupText, vr, section)

proc loadGitConfig(
    table: TomlTableRef, config: var GitConfig, vr: var ValidationResult
) =
  const section = "Git"
  const validKeys = ["showChangedLine", "updateInterval"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "showChangedLine", config.showChangedLine, vr, section)
  loadInt(table, "updateInterval", config.updateInterval, vr, section, minVal = 1)

proc loadSyntaxCheckerConfig(
    table: TomlTableRef, config: var SyntaxCheckerConfig, vr: var ValidationResult
) =
  const section = "SyntaxChecker"
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadThemeConfig(
    table: TomlTableRef, config: var ThemeConfig, vr: var ValidationResult
) =
  const section = "Theme"
  const validKeys = ["kind", "path"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadEnum(table, "kind", config.kind, vr, section, parseThemeKind, ValidThemeKinds)
  # Only validate path if kind is tkConfig (custom theme file)
  if config.kind == tkConfig:
    loadFilePath(table, "path", config.path, vr, section)
  else:
    loadString(table, "path", config.path, vr, section)

proc loadAutoSaveConfig(
    table: TomlTableRef, config: var AutoSaveConfig, vr: var ValidationResult
) =
  const section = "AutoSave"
  const validKeys = ["enable", "interval"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadInt(table, "interval", config.interval, vr, section, minVal = 1)

proc loadNotificationConfig(
    table: TomlTableRef, config: var NotificationConfig, vr: var ValidationResult
) =
  const section = "Notification"
  const validKeys = [
    "screenNotifications", "logNotifications", "autoBackupScreenNotify",
    "autoBackupLogNotify", "autoSaveScreenNotify", "autoSaveLogNotify",
    "yankScreenNotify", "yankLogNotify", "deleteScreenNotify", "deleteLogNotify",
    "saveScreenNotify", "saveLogNotify", "quickRunScreenNotify", "quickRunLogNotify",
    "buildOnSaveScreenNotify", "buildOnSaveLogNotify", "filerScreenNotify",
    "filerLogNotify", "restoreScreenNotify", "restoreLogNotify", "lspScreenNotify",
    "lspLogNotify",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "screenNotifications", config.screenNotifications, vr, section)
  loadBool(table, "logNotifications", config.logNotifications, vr, section)
  loadBool(table, "autoBackupScreenNotify", config.autoBackupScreenNotify, vr, section)
  loadBool(table, "autoBackupLogNotify", config.autoBackupLogNotify, vr, section)
  loadBool(table, "autoSaveScreenNotify", config.autoSaveScreenNotify, vr, section)
  loadBool(table, "autoSaveLogNotify", config.autoSaveLogNotify, vr, section)
  loadBool(table, "yankScreenNotify", config.yankScreenNotify, vr, section)
  loadBool(table, "yankLogNotify", config.yankLogNotify, vr, section)
  loadBool(table, "deleteScreenNotify", config.deleteScreenNotify, vr, section)
  loadBool(table, "deleteLogNotify", config.deleteLogNotify, vr, section)
  loadBool(table, "saveScreenNotify", config.saveScreenNotify, vr, section)
  loadBool(table, "saveLogNotify", config.saveLogNotify, vr, section)
  loadBool(table, "quickRunScreenNotify", config.quickRunScreenNotify, vr, section)
  loadBool(table, "quickRunLogNotify", config.quickRunLogNotify, vr, section)
  loadBool(
    table, "buildOnSaveScreenNotify", config.buildOnSaveScreenNotify, vr, section
  )
  loadBool(table, "buildOnSaveLogNotify", config.buildOnSaveLogNotify, vr, section)
  loadBool(table, "filerScreenNotify", config.filerScreenNotify, vr, section)
  loadBool(table, "filerLogNotify", config.filerLogNotify, vr, section)
  loadBool(table, "restoreScreenNotify", config.restoreScreenNotify, vr, section)
  loadBool(table, "restoreLogNotify", config.restoreLogNotify, vr, section)
  loadBool(table, "lspScreenNotify", config.lspScreenNotify, vr, section)
  loadBool(table, "lspLogNotify", config.lspLogNotify, vr, section)

proc loadAutoBackupConfig(
    table: TomlTableRef, config: var AutoBackupConfig, vr: var ValidationResult
) =
  const section = "AutoBackup"
  const validKeys = ["enable", "backupDir", "idleTime", "interval", "dirToExclude"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadOptionDirPath(table, "backupDir", config.backupDir, vr, section)
  loadInt(table, "idleTime", config.idleTime, vr, section, minVal = 1)
  loadInt(table, "interval", config.interval, vr, section, minVal = 1)
  loadStringArray(table, "dirToExclude", config.dirToExclude, vr, section)

proc loadSmoothScrollConfig(
    table: TomlTableRef, config: var SmoothScrollConfig, vr: var ValidationResult
) =
  const section = "SmoothScroll"
  const validKeys = ["enable", "friction", "airDrag"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadFloat(table, "friction", config.friction, vr, section, minVal = 0.0)
  loadFloat(table, "airDrag", config.airDrag, vr, section, minVal = 0.0)

proc loadHighlightConfig(
    table: TomlTableRef, config: var HighlightConfig, vr: var ValidationResult
) =
  const section = "Highlight"
  const validKeys = [
    "currentLine", "currentColumn", "reservedWord", "replaceText", "pairOfParen",
    "fullWidthSpace", "trailingSpaces", "currentWord",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "currentLine", config.currentLine, vr, section)
  loadBool(table, "currentColumn", config.currentColumn, vr, section)
  loadStringArray(table, "reservedWord", config.reservedWord, vr, section)
  loadBool(table, "replaceText", config.replaceText, vr, section)
  loadBool(table, "pairOfParen", config.pairOfParen, vr, section)
  loadBool(table, "fullWidthSpace", config.fullWidthSpace, vr, section)
  loadBool(table, "trailingSpaces", config.trailingSpaces, vr, section)
  loadBool(table, "currentWord", config.currentWord, vr, section)

proc loadFilerConfig(
    table: TomlTableRef, config: var FilerConfig, vr: var ValidationResult
) =
  const section = "Filer"
  const validKeys = ["showIcons"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "showIcons", config.showIcons, vr, section)

proc loadAutocompleteConfig(
    table: TomlTableRef, config: var AutocompleteConfig, vr: var ValidationResult
) =
  const section = "Autocomplete"
  const validKeys = ["enable", "windowBorder"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "windowBorder", config.windowBorder, vr, section)

proc loadPersistConfig(
    table: TomlTableRef, config: var PersistConfig, vr: var ValidationResult
) =
  const section = "Persist"
  const validKeys = [
    "exCommand", "exCommandHistoryLimit", "search", "searchHistoryLimit",
    "cursorPosition",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "exCommand", config.exCommand, vr, section)
  loadInt(
    table,
    "exCommandHistoryLimit",
    config.exCommandHistoryLimit,
    vr,
    section,
    minVal = 1,
  )
  loadBool(table, "search", config.search, vr, section)
  loadInt(
    table, "searchHistoryLimit", config.searchHistoryLimit, vr, section, minVal = 1
  )
  loadBool(table, "cursorPosition", config.cursorPosition, vr, section)

proc loadQuickRunConfig(
    table: TomlTableRef, config: var QuickRunConfig, vr: var ValidationResult
) =
  const section = "QuickRun"
  const validKeys = [
    "saveBufferWhenQuickRun", "command", "timeout", "nimAdvancedCommand",
    "ClangOptions", "CppOptions", "NimOptions", "shOptions", "bashOptions",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "saveBufferWhenQuickRun", config.saveBufferWhenQuickRun, vr, section)
  loadOptionString(table, "command", config.command, vr, section)
  loadInt(table, "timeout", config.timeout, vr, section, minVal = 1)
  loadOptionString(table, "nimAdvancedCommand", config.nimAdvancedCommand, vr, section)
  loadOptionString(table, "ClangOptions", config.clangOptions, vr, section)
  loadOptionString(table, "CppOptions", config.cppOptions, vr, section)
  loadOptionString(table, "NimOptions", config.nimOptions, vr, section)
  loadOptionString(table, "shOptions", config.shOptions, vr, section)
  loadOptionString(table, "bashOptions", config.bashOptions, vr, section)

proc loadTabLineConfig(
    table: TomlTableRef, config: var TabLineConfig, vr: var ValidationResult
) =
  const section = "TabLine"
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadStartUpFileOpenConfig(
    table: TomlTableRef, config: var StartUpFileOpenConfig, vr: var ValidationResult
) =
  const section = "StartUp.FileOpen"
  const validKeys = ["autoSplit", "splitType"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "autoSplit", config.autoSplit, vr, section)
  loadEnum(
    table, "splitType", config.splitType, vr, section, parseSplitType, ValidSplitTypes
  )

proc loadDebugWindowNodeConfig(
    table: TomlTableRef,
    config: var DebugWindowNodeConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = [
    "enable", "currentWindow", "index", "windowIndex", "bufferIndex", "parentIndex",
    "childLen", "splitType", "haveCursesWin", "y", "x", "h", "w", "currentLine",
    "currentColumn", "expandedColumn", "cursor",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "currentWindow", config.currentWindow, vr, section)
  loadBool(table, "index", config.index, vr, section)
  loadBool(table, "windowIndex", config.windowIndex, vr, section)
  loadBool(table, "bufferIndex", config.bufferIndex, vr, section)
  loadBool(table, "parentIndex", config.parentIndex, vr, section)
  loadBool(table, "childLen", config.childLen, vr, section)
  loadBool(table, "splitType", config.splitType, vr, section)
  loadBool(table, "haveCursesWin", config.haveCursesWin, vr, section)
  loadBool(table, "y", config.y, vr, section)
  loadBool(table, "x", config.x, vr, section)
  loadBool(table, "h", config.h, vr, section)
  loadBool(table, "w", config.w, vr, section)
  loadBool(table, "currentLine", config.currentLine, vr, section)
  loadBool(table, "currentColumn", config.currentColumn, vr, section)
  loadBool(table, "expandedColumn", config.expandedColumn, vr, section)
  loadBool(table, "cursor", config.cursor, vr, section)

proc loadDebugEditorViewConfig(
    table: TomlTableRef,
    config: var DebugEditorViewConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys =
    ["enable", "widthOfLineNum", "height", "width", "originalLine", "start", "length"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "widthOfLineNum", config.widthOfLineNum, vr, section)
  loadBool(table, "height", config.height, vr, section)
  loadBool(table, "width", config.width, vr, section)
  loadBool(table, "originalLine", config.originalLine, vr, section)
  loadBool(table, "start", config.start, vr, section)
  loadBool(table, "length", config.length, vr, section)

proc loadDebugBufferStatusConfig(
    table: TomlTableRef,
    config: var DebugBufferStatusConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = [
    "enable", "bufferIndex", "path", "openDir", "currentMode", "prevMode", "language",
    "encoding", "countChange", "cmdLoop", "lastSaveTime", "bufferLen",
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "bufferIndex", config.bufferIndex, vr, section)
  loadBool(table, "path", config.path, vr, section)
  loadBool(table, "openDir", config.openDir, vr, section)
  loadBool(table, "currentMode", config.currentMode, vr, section)
  loadBool(table, "prevMode", config.prevMode, vr, section)
  loadBool(table, "language", config.language, vr, section)
  loadBool(table, "encoding", config.encoding, vr, section)
  loadBool(table, "countChange", config.countChange, vr, section)
  loadBool(table, "cmdLoop", config.cmdLoop, vr, section)
  loadBool(table, "lastSaveTime", config.lastSaveTime, vr, section)
  loadBool(table, "bufferLen", config.bufferLen, vr, section)

proc loadDebugSearchConfig(
    table: TomlTableRef,
    config: var DebugSearchConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadDebugMacroConfig(
    table: TomlTableRef,
    config: var DebugMacroConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadDebugVisualConfig(
    table: TomlTableRef,
    config: var DebugVisualConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadDebugJumpListConfig(
    table: TomlTableRef,
    config: var DebugJumpListConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadDebugLspConfig(
    table: TomlTableRef,
    config: var DebugLspConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadDebugConfig(
    table: TomlTableRef, config: var DebugConfig, vr: var ValidationResult
) =
  const validKeys = [
    "WindowNode", "EditorView", "BufferStatus", "Search", "MacroState", "Visual",
    "JumpList", "Lsp",
  ]
  checkUnknownKeys(table, validKeys, "Debug", vr)
  if table.hasKey("WindowNode"):
    loadDebugWindowNodeConfig(
      table["WindowNode"].getTable(), config.windowNode, vr, "Debug.WindowNode"
    )
  if table.hasKey("EditorView"):
    loadDebugEditorViewConfig(
      table["EditorView"].getTable(), config.editorView, vr, "Debug.EditorView"
    )
  if table.hasKey("BufferStatus"):
    loadDebugBufferStatusConfig(
      table["BufferStatus"].getTable(), config.bufferStatus, vr, "Debug.BufferStatus"
    )
  if table.hasKey("Search"):
    loadDebugSearchConfig(table["Search"].getTable(), config.search, vr, "Debug.Search")
  if table.hasKey("MacroState"):
    loadDebugMacroConfig(
      table["MacroState"].getTable(), config.macroState, vr, "Debug.MacroState"
    )
  if table.hasKey("Visual"):
    loadDebugVisualConfig(table["Visual"].getTable(), config.visual, vr, "Debug.Visual")
  if table.hasKey("JumpList"):
    loadDebugJumpListConfig(
      table["JumpList"].getTable(), config.jumpList, vr, "Debug.JumpList"
    )
  if table.hasKey("Lsp"):
    loadDebugLspConfig(table["Lsp"].getTable(), config.lsp, vr, "Debug.Lsp")

proc loadLspFeatureConfig(
    table: TomlTableRef,
    config: var LspFeatureConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadLspOpenWindowConfig(
    table: TomlTableRef,
    config: var LspOpenWindowConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable", "openWindow"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "openWindow", config.openWindow, vr, section)

proc loadLspServerConfig(
    table: TomlTableRef, vr: var ValidationResult, section: string
): LspServerConfig =
  const validKeys = [
    "extensions", "command", "trace", "rustAnalyzerRunSingle", "rustAnalyzerDebugSingle"
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  result = LspServerConfig(
    extensions: @[],
    command: "",
    trace: ltOff,
    rustAnalyzerRunSingle: false,
    rustAnalyzerDebugSingle: false,
  )
  loadStringArray(table, "extensions", result.extensions, vr, section)
  loadString(table, "command", result.command, vr, section)
  loadEnum(
    table, "trace", result.trace, vr, section, parseLspTraceLevel, ValidLspTraceLevels
  )
  loadBool(table, "rustAnalyzerRunSingle", result.rustAnalyzerRunSingle, vr, section)
  loadBool(
    table, "rustAnalyzerDebugSingle", result.rustAnalyzerDebugSingle, vr, section
  )

proc loadLspConfig(
    table: TomlTableRef, config: var LspConfig, vr: var ValidationResult
) =
  const section = "Lsp"
  # Main LSP settings
  loadBool(table, "enable", config.enable, vr, section)
  loadInt(table, "timeout", config.timeout, vr, section, minVal = 1)

  # Feature configs
  if table.hasKey("Completion"):
    loadLspFeatureConfig(
      table["Completion"].getTable(), config.completion, vr, "Lsp.Completion"
    )
  if table.hasKey("Declaration"):
    loadLspOpenWindowConfig(
      table["Declaration"].getTable(), config.declaration, vr, "Lsp.Declaration"
    )
  if table.hasKey("Definition"):
    loadLspOpenWindowConfig(
      table["Definition"].getTable(), config.definition, vr, "Lsp.Definition"
    )
  if table.hasKey("TypeDefinition"):
    loadLspOpenWindowConfig(
      table["TypeDefinition"].getTable(),
      config.typeDefinition,
      vr,
      "Lsp.TypeDefinition",
    )
  if table.hasKey("Implementation"):
    loadLspOpenWindowConfig(
      table["Implementation"].getTable(),
      config.implementation,
      vr,
      "Lsp.Implementation",
    )
  if table.hasKey("Diagnostics"):
    loadLspFeatureConfig(
      table["Diagnostics"].getTable(), config.diagnostics, vr, "Lsp.Diagnostics"
    )
  if table.hasKey("SignatureHelp"):
    loadLspFeatureConfig(
      table["SignatureHelp"].getTable(), config.signatureHelp, vr, "Lsp.SignatureHelp"
    )
  if table.hasKey("DocumentFormatting"):
    loadLspFeatureConfig(
      table["DocumentFormatting"].getTable(),
      config.documentFormatting,
      vr,
      "Lsp.DocumentFormatting",
    )
  if table.hasKey("FoldingRange"):
    loadLspFeatureConfig(
      table["FoldingRange"].getTable(), config.foldingRange, vr, "Lsp.FoldingRange"
    )
  if table.hasKey("SelectionRange"):
    loadLspFeatureConfig(
      table["SelectionRange"].getTable(),
      config.selectionRange,
      vr,
      "Lsp.SelectionRange",
    )
  if table.hasKey("DocumentSymbol"):
    loadLspFeatureConfig(
      table["DocumentSymbol"].getTable(),
      config.documentSymbol,
      vr,
      "Lsp.DocumentSymbol",
    )
  if table.hasKey("Hover"):
    loadLspFeatureConfig(table["Hover"].getTable(), config.hover, vr, "Lsp.Hover")
  if table.hasKey("InlayHint"):
    loadLspFeatureConfig(
      table["InlayHint"].getTable(), config.inlayHint, vr, "Lsp.InlayHint"
    )
  if table.hasKey("InlineValue"):
    loadLspFeatureConfig(
      table["InlineValue"].getTable(), config.inlineValue, vr, "Lsp.InlineValue"
    )
  if table.hasKey("References"):
    loadLspFeatureConfig(
      table["References"].getTable(), config.references, vr, "Lsp.References"
    )
  if table.hasKey("CallHierarchy"):
    loadLspFeatureConfig(
      table["CallHierarchy"].getTable(), config.callHierarchy, vr, "Lsp.CallHierarchy"
    )
  if table.hasKey("DocumentHighlight"):
    loadLspFeatureConfig(
      table["DocumentHighlight"].getTable(),
      config.documentHighlight,
      vr,
      "Lsp.DocumentHighlight",
    )
  if table.hasKey("DocumentLink"):
    loadLspFeatureConfig(
      table["DocumentLink"].getTable(), config.documentLink, vr, "Lsp.DocumentLink"
    )
  if table.hasKey("CodeLens"):
    loadLspFeatureConfig(
      table["CodeLens"].getTable(), config.codeLens, vr, "Lsp.CodeLens"
    )
  if table.hasKey("Rename"):
    loadLspFeatureConfig(table["Rename"].getTable(), config.rename, vr, "Lsp.Rename")
  if table.hasKey("SemanticTokens"):
    loadLspFeatureConfig(
      table["SemanticTokens"].getTable(),
      config.semanticTokens,
      vr,
      "Lsp.SemanticTokens",
    )
  if table.hasKey("ExecuteCommand"):
    loadLspFeatureConfig(
      table["ExecuteCommand"].getTable(),
      config.executeCommand,
      vr,
      "Lsp.ExecuteCommand",
    )

  # Language server configs (any key that's not a known feature is a language server)
  const knownKeys = [
    "enable", "timeout", "Completion", "Declaration", "Definition", "TypeDefinition",
    "Implementation", "Diagnostics", "SignatureHelp", "DocumentFormatting",
    "FoldingRange", "SelectionRange", "DocumentSymbol", "Hover", "InlayHint",
    "InlineValue", "References", "CallHierarchy", "DocumentHighlight", "DocumentLink",
    "CodeLens", "Rename", "SemanticTokens", "ExecuteCommand",
  ]
  for key, value in table:
    if key notin knownKeys:
      if value.kind == TomlValueKind.Table:
        config.servers[key] = loadLspServerConfig(value.getTable(), vr, "Lsp." & key)
      else:
        vr.errors.add(InvalidItem(kind: iikUnknownKey, name: fullKey(section, key)))

proc loadKeyMappingModeConfig(
    table: TomlTableRef,
    target: var OrderedTable[string, string],
    vr: var ValidationResult,
    section: string,
    validCommands: HashSet[string],
) =
  for key, value in table:
    if value.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $value, "string")
      continue

    # LHS (key) validation
    let lhsKeys = parseKeyString(key)
    if lhsKeys.len == 0:
      vr.addError(
        fullKey(section, key), key, "valid key (e.g. \"C-s\", \"jj\", \"g d\")"
      )
      continue

    # RHS (target) validation: command name or key sequence
    let rhs = value.getStr()
    let rhsKeys = parseKeyString(rhs)
    if rhsKeys.len == 0 and rhs notin validCommands:
      vr.addError(fullKey(section, key), rhs, "valid command name or key sequence")
      continue

    target[key] = rhs

proc loadKeyMappingConfig(
    table: TomlTableRef, config: var KeyMappingConfig, vr: var ValidationResult
) =
  const section = "KeyMapping"
  const validKeys = [
    "All", "Normal", "Insert", "Visual", "VisualAll", "VisualLine", "VisualBlock",
    "Replace", "CommandLine", "Filer", "LogViewer", "Help", "BufferManager",
    "BackupManager", "DiffViewer", "Config", "References", "DocumentSymbol",
    "CallHierarchy", "RecentFile", "Debug", "Terminal",
  ]
  checkUnknownKeys(table, validKeys, section, vr)

  let validCommands = getValidMappingCommands()

  if table.hasKey("All"):
    loadKeyMappingModeConfig(
      table["All"].getTable(), config.all, vr, "KeyMapping.All", validCommands
    )
  if table.hasKey("Normal"):
    loadKeyMappingModeConfig(
      table["Normal"].getTable(), config.normal, vr, "KeyMapping.Normal", validCommands
    )
  if table.hasKey("Insert"):
    loadKeyMappingModeConfig(
      table["Insert"].getTable(), config.insert, vr, "KeyMapping.Insert", validCommands
    )
  if table.hasKey("Visual"):
    loadKeyMappingModeConfig(
      table["Visual"].getTable(), config.visual, vr, "KeyMapping.Visual", validCommands
    )
  if table.hasKey("VisualAll"):
    loadKeyMappingModeConfig(
      table["VisualAll"].getTable(),
      config.visualAll,
      vr,
      "KeyMapping.VisualAll",
      validCommands,
    )
  if table.hasKey("VisualLine"):
    loadKeyMappingModeConfig(
      table["VisualLine"].getTable(),
      config.visualLine,
      vr,
      "KeyMapping.VisualLine",
      validCommands,
    )
  if table.hasKey("VisualBlock"):
    loadKeyMappingModeConfig(
      table["VisualBlock"].getTable(),
      config.visualBlock,
      vr,
      "KeyMapping.VisualBlock",
      validCommands,
    )
  if table.hasKey("Replace"):
    loadKeyMappingModeConfig(
      table["Replace"].getTable(),
      config.replace,
      vr,
      "KeyMapping.Replace",
      validCommands,
    )
  if table.hasKey("CommandLine"):
    loadKeyMappingModeConfig(
      table["CommandLine"].getTable(),
      config.commandLine,
      vr,
      "KeyMapping.CommandLine",
      validCommands,
    )
  if table.hasKey("Filer"):
    loadKeyMappingModeConfig(
      table["Filer"].getTable(), config.filer, vr, "KeyMapping.Filer", validCommands
    )
  if table.hasKey("LogViewer"):
    loadKeyMappingModeConfig(
      table["LogViewer"].getTable(),
      config.logViewer,
      vr,
      "KeyMapping.LogViewer",
      validCommands,
    )
  if table.hasKey("Help"):
    loadKeyMappingModeConfig(
      table["Help"].getTable(), config.help, vr, "KeyMapping.Help", validCommands
    )
  if table.hasKey("BufferManager"):
    loadKeyMappingModeConfig(
      table["BufferManager"].getTable(),
      config.bufferManager,
      vr,
      "KeyMapping.BufferManager",
      validCommands,
    )
  if table.hasKey("BackupManager"):
    loadKeyMappingModeConfig(
      table["BackupManager"].getTable(),
      config.backupManager,
      vr,
      "KeyMapping.BackupManager",
      validCommands,
    )
  if table.hasKey("DiffViewer"):
    loadKeyMappingModeConfig(
      table["DiffViewer"].getTable(),
      config.diffViewer,
      vr,
      "KeyMapping.DiffViewer",
      validCommands,
    )
  if table.hasKey("Config"):
    loadKeyMappingModeConfig(
      table["Config"].getTable(), config.config, vr, "KeyMapping.Config", validCommands
    )
  if table.hasKey("References"):
    loadKeyMappingModeConfig(
      table["References"].getTable(),
      config.references,
      vr,
      "KeyMapping.References",
      validCommands,
    )
  if table.hasKey("DocumentSymbol"):
    loadKeyMappingModeConfig(
      table["DocumentSymbol"].getTable(),
      config.documentSymbol,
      vr,
      "KeyMapping.DocumentSymbol",
      validCommands,
    )
  if table.hasKey("CallHierarchy"):
    loadKeyMappingModeConfig(
      table["CallHierarchy"].getTable(),
      config.callHierarchy,
      vr,
      "KeyMapping.CallHierarchy",
      validCommands,
    )
  if table.hasKey("RecentFile"):
    loadKeyMappingModeConfig(
      table["RecentFile"].getTable(),
      config.recentFile,
      vr,
      "KeyMapping.RecentFile",
      validCommands,
    )
  if table.hasKey("Debug"):
    loadKeyMappingModeConfig(
      table["Debug"].getTable(), config.debug, vr, "KeyMapping.Debug", validCommands
    )
  if table.hasKey("Terminal"):
    loadKeyMappingModeConfig(
      table["Terminal"].getTable(),
      config.terminal,
      vr,
      "KeyMapping.Terminal",
      validCommands,
    )

proc loadConfigFromToml*(
    path: string
): Result[(EditorConfig, ValidationResult), string] =
  ## Load configuration from a TOML file with integrated validation
  ## Returns (EditorConfig, ValidationResult) on success
  ## Invalid values are skipped (keeping defaults) and recorded in ValidationResult
  ## Returns error if file cannot be parsed

  if not fileExists(path):
    return Result[(EditorConfig, ValidationResult), string].ok(
      (newEditorConfig(), newValidationResult())
    )

  var toml: TomlValueRef
  try:
    toml = parseFile(path)
  except CatchableError as e:
    return Result[(EditorConfig, ValidationResult), string].err(
      "Failed to parse config file: " & e.msg
    )

  var config = newEditorConfig()
  var vr = newValidationResult()

  # Validate top-level section names
  const knownSections = [
    "Standard", "Clipboard", "BuildOnSave", "TabLine", "StatusLine", "Git",
    "SyntaxChecker", "Theme", "AutoSave", "Notification", "QuickRun", "AutoBackup",
    "SmoothScroll", "Highlight", "Filer", "Autocomplete", "Persist", "StartUp", "Lsp",
    "Debug", "KeyMapping",
  ]
  checkUnknownKeys(toml.getTable(), knownSections, "", vr)

  # Load each section (validation integrated into loading)
  if toml.hasKey("Standard"):
    loadStandardConfig(toml["Standard"].getTable(), config.standard, vr)

  if toml.hasKey("Clipboard"):
    loadClipboardConfig(toml["Clipboard"].getTable(), config.clipboard, vr)

  if toml.hasKey("BuildOnSave"):
    loadBuildOnSaveConfig(toml["BuildOnSave"].getTable(), config.buildOnSave, vr)

  if toml.hasKey("TabLine"):
    loadTabLineConfig(toml["TabLine"].getTable(), config.tabLine, vr)

  if toml.hasKey("StatusLine"):
    loadStatusLineConfig(toml["StatusLine"].getTable(), config.statusLine, vr)

  if toml.hasKey("Git"):
    loadGitConfig(toml["Git"].getTable(), config.git, vr)

  if toml.hasKey("SyntaxChecker"):
    loadSyntaxCheckerConfig(toml["SyntaxChecker"].getTable(), config.syntaxChecker, vr)

  if toml.hasKey("Theme"):
    loadThemeConfig(toml["Theme"].getTable(), config.theme, vr)

  if toml.hasKey("AutoSave"):
    loadAutoSaveConfig(toml["AutoSave"].getTable(), config.autoSave, vr)

  if toml.hasKey("Notification"):
    loadNotificationConfig(toml["Notification"].getTable(), config.notification, vr)

  if toml.hasKey("QuickRun"):
    loadQuickRunConfig(toml["QuickRun"].getTable(), config.quickRun, vr)

  if toml.hasKey("AutoBackup"):
    loadAutoBackupConfig(toml["AutoBackup"].getTable(), config.autoBackup, vr)

  if toml.hasKey("SmoothScroll"):
    loadSmoothScrollConfig(toml["SmoothScroll"].getTable(), config.smoothScroll, vr)

  if toml.hasKey("Highlight"):
    loadHighlightConfig(toml["Highlight"].getTable(), config.highlight, vr)

  if toml.hasKey("Filer"):
    loadFilerConfig(toml["Filer"].getTable(), config.filer, vr)

  if toml.hasKey("Autocomplete"):
    loadAutocompleteConfig(toml["Autocomplete"].getTable(), config.autocomplete, vr)

  if toml.hasKey("Persist"):
    loadPersistConfig(toml["Persist"].getTable(), config.persist, vr)

  if toml.hasKey("StartUp"):
    let startUpTable = toml["StartUp"].getTable()
    const startUpValidKeys = ["FileOpen"]
    checkUnknownKeys(startUpTable, startUpValidKeys, "StartUp", vr)
    if startUpTable.hasKey("FileOpen"):
      loadStartUpFileOpenConfig(
        startUpTable["FileOpen"].getTable(), config.startUpFileOpen, vr
      )

  if toml.hasKey("Lsp"):
    loadLspConfig(toml["Lsp"].getTable(), config.lsp, vr)

  if toml.hasKey("Debug"):
    loadDebugConfig(toml["Debug"].getTable(), config.debug, vr)

  if toml.hasKey("KeyMapping"):
    loadKeyMappingConfig(toml["KeyMapping"].getTable(), config.keyMapping, vr)

  return Result[(EditorConfig, ValidationResult), string].ok((config, vr))

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

proc loadConfig*(): Result[(EditorConfig, ValidationResult), string] =
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
  of "currentColumnBg":
    return some(EditorColorPairIndex.currentColumnBg)
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
  # Viewer common colors
  of "viewerHeader":
    return some(EditorColorPairIndex.viewerHeader)
  of "viewerSelectedLine":
    return some(EditorColorPairIndex.viewerSelectedLine)
  of "viewerEmptyMessage":
    return some(EditorColorPairIndex.viewerEmptyMessage)
  # Filer mode specific
  of "filerDirectory":
    return some(EditorColorPairIndex.filerDirectory)
  of "filerSymlink":
    return some(EditorColorPairIndex.filerSymlink)
  of "filerSymlinkDir":
    return some(EditorColorPairIndex.filerSymlinkDir)
  of "filerHiddenFile":
    return some(EditorColorPairIndex.filerHiddenFile)
  of "filerExecutable":
    return some(EditorColorPairIndex.filerExecutable)
  # Buffer manager specific
  of "bufferManagerActive":
    return some(EditorColorPairIndex.bufferManagerActive)
  of "bufferManagerModified":
    return some(EditorColorPairIndex.bufferManagerModified)
  # Configuration mode specific
  of "configModeSection":
    return some(EditorColorPairIndex.configModeSection)
  of "configModeEditMode":
    return some(EditorColorPairIndex.configModeEditMode)
  of "configModePopupBg":
    return some(EditorColorPairIndex.configModePopupBg)
  of "configModePopupSelected":
    return some(EditorColorPairIndex.configModePopupSelected)
  # Diff viewer specific
  of "diffViewerHeader":
    return some(EditorColorPairIndex.diffViewerHeader)
  of "diffViewerMeta":
    return some(EditorColorPairIndex.diffViewerMeta)
  # Other viewers
  of "recentFileMissing":
    return some(EditorColorPairIndex.recentFileMissing)
  of "debugViewerSectionHeader":
    return some(EditorColorPairIndex.debugViewerSectionHeader)
  of "referencesViewerHeader":
    return some(EditorColorPairIndex.referencesViewerHeader)
  of "documentSymbolViewerHeader":
    return some(EditorColorPairIndex.documentSymbolViewerHeader)
  of "callHierarchyViewerHeader":
    return some(EditorColorPairIndex.callHierarchyViewerHeader)
  of "helpViewerSectionHeader":
    return some(EditorColorPairIndex.helpViewerSectionHeader)
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
    let fgResult = parseThemeColor(colorsTable["foreground"].getStr())
    if fgResult.isOk:
      defaultFg = fgResult.get

  if colorsTable.hasKey("background"):
    let bgResult = parseThemeColor(colorsTable["background"].getStr())
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
    let rgbResult = parseThemeColor(colorStr)
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
    return loadVSCodeTheme()

proc initTheme*(config: EditorConfig) =
  ## Initialize the theme based on configuration
  ## Falls back to default theme on error

  let themeResult = loadTheme(config)
  if themeResult.isOk:
    setThemeColors(themeResult.get)
  else:
    # Log error and use default
    initDefaultTheme()

# Configuration saving

proc toTomlBool(val: bool): string =
  if val: "true" else: "false"

proc toTomlString(val: string): string =
  "\"" & val & "\""

proc toTomlStringArray(val: seq[string]): string =
  result = "["
  for i, s in val:
    if i > 0:
      result.add ", "
    result.add toTomlString(s)
  result.add "]"

proc toTomlColorKey(index: EditorColorPairIndex): string =
  ## Convert EditorColorPairIndex to TOML key name
  case index
  of EditorColorPairIndex.lspString:
    "string"
  else:
    $index

proc themeColorToTomlValue(color: ThemeColor): string =
  ## Convert ThemeColor to TOML value string
  if color.rgb.isTermDefaultColor:
    return "\"termDefault\""
  let hexOpt = color.rgb.toHex()
  if hexOpt.isSome:
    return "\"" & hexOpt.get & "\""
  return "\"termDefault\""

proc saveThemeToToml*(colors: ThemeColors, path: string): Result[void, string] =
  ## Save theme colors to a TOML file
  var lines: seq[string] = @[]

  lines.add "# Theme color configuration"
  lines.add "# Color format: \"#RRGGBB\" (hex) or \"termDefault\" (terminal default color)"
  lines.add ""
  lines.add "[Colors]"
  lines.add ""

  # Write default foreground/background
  lines.add "foreground = " &
    themeColorToTomlValue(colors[EditorColorPairIndex.default].foreground)
  lines.add "background = " &
    themeColorToTomlValue(colors[EditorColorPairIndex.default].background)
  lines.add ""

  # Write all other color pairs
  for index in EditorColorPairIndex:
    if index == EditorColorPairIndex.default:
      continue

    let key = toTomlColorKey(index)
    lines.add key & " = " & themeColorToTomlValue(colors[index].foreground)
    lines.add key & "Bg = " & themeColorToTomlValue(colors[index].background)

  lines.add ""

  # Ensure directory exists
  let expandedPath = path.expandTilde
  let dir = parentDir(expandedPath)
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return Result[void, string].err("Failed to create directory: " & e.msg)

  # Backup existing file
  if fileExists(expandedPath):
    let backupPath = expandedPath & ".bac"
    try:
      copyFile(expandedPath, backupPath)
    except CatchableError as e:
      return Result[void, string].err("Failed to backup theme file: " & e.msg)

  # Write to file
  try:
    writeFile(expandedPath, lines.join("\n"))
    return Result[void, string].ok()
  except CatchableError as e:
    return Result[void, string].err("Failed to write theme file: " & e.msg)

proc saveConfigToToml*(config: EditorConfig, path: string): Result[void, string] =
  ## Save configuration to a TOML file
  var lines: seq[string] = @[]

  # Standard section
  lines.add "[Standard]"
  lines.add "number = " & toTomlBool(config.standard.number)
  lines.add "statusLine = " & toTomlBool(config.standard.statusLine)
  lines.add "syntax = " & toTomlBool(config.standard.syntax)
  lines.add "indentationLines = " & toTomlBool(config.standard.indentationLines)
  lines.add "tabStop = " & $config.standard.tabStop
  lines.add "expandTab = " & toTomlBool(config.standard.expandTab)
  lines.add "sidebar = " & toTomlBool(config.standard.sidebar)
  lines.add "autoCloseParen = " & toTomlBool(config.standard.autoCloseParen)
  lines.add "autoIndent = " & toTomlBool(config.standard.autoIndent)
  lines.add "ignorecase = " & toTomlBool(config.standard.ignorecase)
  lines.add "smartcase = " & toTomlBool(config.standard.smartcase)
  lines.add "disableChangeCursor = " & toTomlBool(config.standard.disableChangeCursor)
  lines.add "defaultCursor = " & toTomlString($config.standard.defaultCursor)
  lines.add "normalModeCursor = " & toTomlString($config.standard.normalModeCursor)
  lines.add "insertModeCursor = " & toTomlString($config.standard.insertModeCursor)
  lines.add "liveReloadOfConf = " & toTomlBool(config.standard.liveReloadOfConf)
  lines.add "incrementalSearch = " & toTomlBool(config.standard.incrementalSearch)
  lines.add "popupWindowInExmode = " & toTomlBool(config.standard.popupWindowInExmode)
  lines.add "autoDeleteParen = " & toTomlBool(config.standard.autoDeleteParen)
  lines.add "liveReloadOfFile = " & toTomlBool(config.standard.liveReloadOfFile)
  lines.add "colorMode = " & toTomlString($config.standard.colorMode)
  lines.add "mouse = " & toTomlBool(config.standard.mouse)
  lines.add "lineWrap = " & toTomlBool(config.standard.lineWrap)
  lines.add "timeoutlen = " & $config.standard.timeoutlen
  lines.add ""

  # Clipboard section
  lines.add "[Clipboard]"
  lines.add "enable = " & toTomlBool(config.clipboard.enable)
  lines.add "tool = " & toTomlString($config.clipboard.tool)
  lines.add ""

  # BuildOnSave section
  lines.add "[BuildOnSave]"
  lines.add "enable = " & toTomlBool(config.buildOnSave.enable)
  if config.buildOnSave.workspaceRoot.isSome:
    lines.add "workspaceRoot = " & toTomlString(config.buildOnSave.workspaceRoot.get)
  if config.buildOnSave.command.isSome:
    lines.add "command = " & toTomlString(config.buildOnSave.command.get)
  lines.add ""

  # TabLine section
  lines.add "[TabLine]"
  lines.add "enable = " & toTomlBool(config.tabLine.enable)
  lines.add ""

  # StatusLine section
  lines.add "[StatusLine]"
  lines.add "multipleStatusLine = " & toTomlBool(config.statusLine.multipleStatusLine)
  lines.add "merge = " & toTomlBool(config.statusLine.merge)
  lines.add "mode = " & toTomlBool(config.statusLine.mode)
  lines.add "filename = " & toTomlBool(config.statusLine.filename)
  lines.add "changedMark = " & toTomlBool(config.statusLine.changedMark)
  lines.add "directory = " & toTomlBool(config.statusLine.directory)
  lines.add "gitChangedLines = " & toTomlBool(config.statusLine.gitChangedLines)
  lines.add "gitBranchName = " & toTomlBool(config.statusLine.gitBranchName)
  lines.add "showGitInactive = " & toTomlBool(config.statusLine.showGitInactive)
  lines.add "showModeInactive = " & toTomlBool(config.statusLine.showModeInactive)
  lines.add "setupText = " & toTomlString(config.statusLine.setupText)
  lines.add ""

  # Theme section
  lines.add "[Theme]"
  lines.add "kind = " & toTomlString($config.theme.kind)
  if config.theme.path.len > 0:
    lines.add "path = " & toTomlString(config.theme.path)
  lines.add ""

  # Highlight section
  lines.add "[Highlight]"
  lines.add "currentLine = " & toTomlBool(config.highlight.currentLine)
  lines.add "currentColumn = " & toTomlBool(config.highlight.currentColumn)
  lines.add "reservedWord = " & toTomlStringArray(config.highlight.reservedWord)
  lines.add "replaceText = " & toTomlBool(config.highlight.replaceText)
  lines.add "pairOfParen = " & toTomlBool(config.highlight.pairOfParen)
  lines.add "fullWidthSpace = " & toTomlBool(config.highlight.fullWidthSpace)
  lines.add "trailingSpaces = " & toTomlBool(config.highlight.trailingSpaces)
  lines.add "currentWord = " & toTomlBool(config.highlight.currentWord)
  lines.add ""

  # AutoBackup section
  lines.add "[AutoBackup]"
  lines.add "enable = " & toTomlBool(config.autoBackup.enable)
  if config.autoBackup.backupDir.isSome:
    lines.add "backupDir = " & toTomlString(config.autoBackup.backupDir.get)
  lines.add "idleTime = " & $config.autoBackup.idleTime
  lines.add "interval = " & $config.autoBackup.interval
  if config.autoBackup.dirToExclude.len > 0:
    lines.add "dirToExclude = " & toTomlStringArray(config.autoBackup.dirToExclude)
  lines.add ""

  # Notification section
  lines.add "[Notification]"
  lines.add "screenNotifications = " &
    toTomlBool(config.notification.screenNotifications)
  lines.add "logNotifications = " & toTomlBool(config.notification.logNotifications)
  lines.add "autoBackupScreenNotify = " &
    toTomlBool(config.notification.autoBackupScreenNotify)
  lines.add "autoBackupLogNotify = " &
    toTomlBool(config.notification.autoBackupLogNotify)
  lines.add "autoSaveScreenNotify = " &
    toTomlBool(config.notification.autoSaveScreenNotify)
  lines.add "autoSaveLogNotify = " & toTomlBool(config.notification.autoSaveLogNotify)
  lines.add "yankScreenNotify = " & toTomlBool(config.notification.yankScreenNotify)
  lines.add "yankLogNotify = " & toTomlBool(config.notification.yankLogNotify)
  lines.add "deleteScreenNotify = " & toTomlBool(config.notification.deleteScreenNotify)
  lines.add "deleteLogNotify = " & toTomlBool(config.notification.deleteLogNotify)
  lines.add "saveScreenNotify = " & toTomlBool(config.notification.saveScreenNotify)
  lines.add "saveLogNotify = " & toTomlBool(config.notification.saveLogNotify)
  lines.add "quickRunScreenNotify = " &
    toTomlBool(config.notification.quickRunScreenNotify)
  lines.add "quickRunLogNotify = " & toTomlBool(config.notification.quickRunLogNotify)
  lines.add "buildOnSaveScreenNotify = " &
    toTomlBool(config.notification.buildOnSaveScreenNotify)
  lines.add "buildOnSaveLogNotify = " &
    toTomlBool(config.notification.buildOnSaveLogNotify)
  lines.add "filerScreenNotify = " & toTomlBool(config.notification.filerScreenNotify)
  lines.add "filerLogNotify = " & toTomlBool(config.notification.filerLogNotify)
  lines.add "restoreScreenNotify = " &
    toTomlBool(config.notification.restoreScreenNotify)
  lines.add "restoreLogNotify = " & toTomlBool(config.notification.restoreLogNotify)
  lines.add "lspScreenNotify = " & toTomlBool(config.notification.lspScreenNotify)
  lines.add "lspLogNotify = " & toTomlBool(config.notification.lspLogNotify)
  lines.add ""

  # Filer section
  lines.add "[Filer]"
  lines.add "showIcons = " & toTomlBool(config.filer.showIcons)
  lines.add ""

  # Autocomplete section
  lines.add "[Autocomplete]"
  lines.add "enable = " & toTomlBool(config.autocomplete.enable)
  lines.add "windowBorder = " & toTomlBool(config.autocomplete.windowBorder)
  lines.add ""

  # AutoSave section
  lines.add "[AutoSave]"
  lines.add "enable = " & toTomlBool(config.autoSave.enable)
  lines.add "interval = " & $config.autoSave.interval
  lines.add ""

  # Persist section
  lines.add "[Persist]"
  lines.add "exCommand = " & toTomlBool(config.persist.exCommand)
  lines.add "exCommandHistoryLimit = " & $config.persist.exCommandHistoryLimit
  lines.add "search = " & toTomlBool(config.persist.search)
  lines.add "searchHistoryLimit = " & $config.persist.searchHistoryLimit
  lines.add "cursorPosition = " & toTomlBool(config.persist.cursorPosition)
  lines.add ""

  # Git section
  lines.add "[Git]"
  lines.add "showChangedLine = " & toTomlBool(config.git.showChangedLine)
  lines.add "updateInterval = " & $config.git.updateInterval
  lines.add ""

  # SyntaxChecker section
  lines.add "[SyntaxChecker]"
  lines.add "enable = " & toTomlBool(config.syntaxChecker.enable)
  lines.add ""

  # SmoothScroll section
  lines.add "[SmoothScroll]"
  lines.add "enable = " & toTomlBool(config.smoothScroll.enable)
  lines.add "friction = " & $config.smoothScroll.friction
  lines.add "airDrag = " & $config.smoothScroll.airDrag
  lines.add ""

  # StartUp.FileOpen section
  lines.add "[StartUp.FileOpen]"
  lines.add "autoSplit = " & toTomlBool(config.startUpFileOpen.autoSplit)
  lines.add "splitType = " & toTomlString($config.startUpFileOpen.splitType)
  lines.add ""

  # QuickRun section
  lines.add "[QuickRun]"
  lines.add "saveBufferWhenQuickRun = " &
    toTomlBool(config.quickRun.saveBufferWhenQuickRun)
  if config.quickRun.command.isSome:
    lines.add "command = " & toTomlString(config.quickRun.command.get)
  lines.add "timeout = " & $config.quickRun.timeout
  if config.quickRun.nimAdvancedCommand.isSome:
    lines.add "nimAdvancedCommand = " &
      toTomlString(config.quickRun.nimAdvancedCommand.get)
  if config.quickRun.clangOptions.isSome:
    lines.add "ClangOptions = " & toTomlString(config.quickRun.clangOptions.get)
  if config.quickRun.cppOptions.isSome:
    lines.add "CppOptions = " & toTomlString(config.quickRun.cppOptions.get)
  if config.quickRun.nimOptions.isSome:
    lines.add "NimOptions = " & toTomlString(config.quickRun.nimOptions.get)
  if config.quickRun.shOptions.isSome:
    lines.add "shOptions = " & toTomlString(config.quickRun.shOptions.get)
  if config.quickRun.bashOptions.isSome:
    lines.add "bashOptions = " & toTomlString(config.quickRun.bashOptions.get)
  lines.add ""

  # Lsp section
  lines.add "[Lsp]"
  lines.add "enable = " & toTomlBool(config.lsp.enable)
  lines.add "timeout = " & $config.lsp.timeout
  lines.add ""

  # Lsp feature configs
  lines.add "[Lsp.Completion]"
  lines.add "enable = " & toTomlBool(config.lsp.completion.enable)
  lines.add ""

  lines.add "[Lsp.Declaration]"
  lines.add "enable = " & toTomlBool(config.lsp.declaration.enable)
  lines.add "openWindow = " & toTomlBool(config.lsp.declaration.openWindow)
  lines.add ""

  lines.add "[Lsp.Definition]"
  lines.add "enable = " & toTomlBool(config.lsp.definition.enable)
  lines.add "openWindow = " & toTomlBool(config.lsp.definition.openWindow)
  lines.add ""

  lines.add "[Lsp.TypeDefinition]"
  lines.add "enable = " & toTomlBool(config.lsp.typeDefinition.enable)
  lines.add "openWindow = " & toTomlBool(config.lsp.typeDefinition.openWindow)
  lines.add ""

  lines.add "[Lsp.Implementation]"
  lines.add "enable = " & toTomlBool(config.lsp.implementation.enable)
  lines.add "openWindow = " & toTomlBool(config.lsp.implementation.openWindow)
  lines.add ""

  lines.add "[Lsp.Diagnostics]"
  lines.add "enable = " & toTomlBool(config.lsp.diagnostics.enable)
  lines.add ""

  lines.add "[Lsp.SignatureHelp]"
  lines.add "enable = " & toTomlBool(config.lsp.signatureHelp.enable)
  lines.add ""

  lines.add "[Lsp.DocumentFormatting]"
  lines.add "enable = " & toTomlBool(config.lsp.documentFormatting.enable)
  lines.add ""

  lines.add "[Lsp.FoldingRange]"
  lines.add "enable = " & toTomlBool(config.lsp.foldingRange.enable)
  lines.add ""

  lines.add "[Lsp.SelectionRange]"
  lines.add "enable = " & toTomlBool(config.lsp.selectionRange.enable)
  lines.add ""

  lines.add "[Lsp.DocumentSymbol]"
  lines.add "enable = " & toTomlBool(config.lsp.documentSymbol.enable)
  lines.add ""

  lines.add "[Lsp.Hover]"
  lines.add "enable = " & toTomlBool(config.lsp.hover.enable)
  lines.add ""

  lines.add "[Lsp.InlayHint]"
  lines.add "enable = " & toTomlBool(config.lsp.inlayHint.enable)
  lines.add ""

  lines.add "[Lsp.InlineValue]"
  lines.add "enable = " & toTomlBool(config.lsp.inlineValue.enable)
  lines.add ""

  lines.add "[Lsp.References]"
  lines.add "enable = " & toTomlBool(config.lsp.references.enable)
  lines.add ""

  lines.add "[Lsp.CallHierarchy]"
  lines.add "enable = " & toTomlBool(config.lsp.callHierarchy.enable)
  lines.add ""

  lines.add "[Lsp.DocumentHighlight]"
  lines.add "enable = " & toTomlBool(config.lsp.documentHighlight.enable)
  lines.add ""

  lines.add "[Lsp.DocumentLink]"
  lines.add "enable = " & toTomlBool(config.lsp.documentLink.enable)
  lines.add ""

  lines.add "[Lsp.CodeLens]"
  lines.add "enable = " & toTomlBool(config.lsp.codeLens.enable)
  lines.add ""

  lines.add "[Lsp.Rename]"
  lines.add "enable = " & toTomlBool(config.lsp.rename.enable)
  lines.add ""

  lines.add "[Lsp.SemanticTokens]"
  lines.add "enable = " & toTomlBool(config.lsp.semanticTokens.enable)
  lines.add ""

  lines.add "[Lsp.ExecuteCommand]"
  lines.add "enable = " & toTomlBool(config.lsp.executeCommand.enable)
  lines.add ""

  # Lsp language server configs
  for name, server in config.lsp.servers:
    lines.add "[Lsp." & name & "]"
    lines.add "extensions = " & toTomlStringArray(server.extensions)
    lines.add "command = " & toTomlString(server.command)
    lines.add "trace = " & toTomlString($server.trace)
    lines.add "rustAnalyzerRunSingle = " & toTomlBool(server.rustAnalyzerRunSingle)
    lines.add "rustAnalyzerDebugSingle = " & toTomlBool(server.rustAnalyzerDebugSingle)
    lines.add ""

  # KeyMapping section (only output modes that have mappings)
  if config.keyMapping.all.len > 0:
    lines.add "[KeyMapping.All]"
    for lhs, rhs in config.keyMapping.all:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.normal.len > 0:
    lines.add "[KeyMapping.Normal]"
    for lhs, rhs in config.keyMapping.normal:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.insert.len > 0:
    lines.add "[KeyMapping.Insert]"
    for lhs, rhs in config.keyMapping.insert:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.visual.len > 0:
    lines.add "[KeyMapping.Visual]"
    for lhs, rhs in config.keyMapping.visual:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.visualAll.len > 0:
    lines.add "[KeyMapping.VisualAll]"
    for lhs, rhs in config.keyMapping.visualAll:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.visualLine.len > 0:
    lines.add "[KeyMapping.VisualLine]"
    for lhs, rhs in config.keyMapping.visualLine:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.visualBlock.len > 0:
    lines.add "[KeyMapping.VisualBlock]"
    for lhs, rhs in config.keyMapping.visualBlock:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.replace.len > 0:
    lines.add "[KeyMapping.Replace]"
    for lhs, rhs in config.keyMapping.replace:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.commandLine.len > 0:
    lines.add "[KeyMapping.CommandLine]"
    for lhs, rhs in config.keyMapping.commandLine:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.filer.len > 0:
    lines.add "[KeyMapping.Filer]"
    for lhs, rhs in config.keyMapping.filer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.logViewer.len > 0:
    lines.add "[KeyMapping.LogViewer]"
    for lhs, rhs in config.keyMapping.logViewer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.help.len > 0:
    lines.add "[KeyMapping.Help]"
    for lhs, rhs in config.keyMapping.help:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.bufferManager.len > 0:
    lines.add "[KeyMapping.BufferManager]"
    for lhs, rhs in config.keyMapping.bufferManager:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.backupManager.len > 0:
    lines.add "[KeyMapping.BackupManager]"
    for lhs, rhs in config.keyMapping.backupManager:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.diffViewer.len > 0:
    lines.add "[KeyMapping.DiffViewer]"
    for lhs, rhs in config.keyMapping.diffViewer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.config.len > 0:
    lines.add "[KeyMapping.Config]"
    for lhs, rhs in config.keyMapping.config:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.references.len > 0:
    lines.add "[KeyMapping.References]"
    for lhs, rhs in config.keyMapping.references:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.documentSymbol.len > 0:
    lines.add "[KeyMapping.DocumentSymbol]"
    for lhs, rhs in config.keyMapping.documentSymbol:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.callHierarchy.len > 0:
    lines.add "[KeyMapping.CallHierarchy]"
    for lhs, rhs in config.keyMapping.callHierarchy:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.recentFile.len > 0:
    lines.add "[KeyMapping.RecentFile]"
    for lhs, rhs in config.keyMapping.recentFile:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.debug.len > 0:
    lines.add "[KeyMapping.Debug]"
    for lhs, rhs in config.keyMapping.debug:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if config.keyMapping.terminal.len > 0:
    lines.add "[KeyMapping.Terminal]"
    for lhs, rhs in config.keyMapping.terminal:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  # Debug section
  lines.add "[Debug.WindowNode]"
  lines.add "enable = " & toTomlBool(config.debug.windowNode.enable)
  lines.add "currentWindow = " & toTomlBool(config.debug.windowNode.currentWindow)
  lines.add "index = " & toTomlBool(config.debug.windowNode.index)
  lines.add "windowIndex = " & toTomlBool(config.debug.windowNode.windowIndex)
  lines.add "bufferIndex = " & toTomlBool(config.debug.windowNode.bufferIndex)
  lines.add "parentIndex = " & toTomlBool(config.debug.windowNode.parentIndex)
  lines.add "childLen = " & toTomlBool(config.debug.windowNode.childLen)
  lines.add "splitType = " & toTomlBool(config.debug.windowNode.splitType)
  lines.add "haveCursesWin = " & toTomlBool(config.debug.windowNode.haveCursesWin)
  lines.add "y = " & toTomlBool(config.debug.windowNode.y)
  lines.add "x = " & toTomlBool(config.debug.windowNode.x)
  lines.add "h = " & toTomlBool(config.debug.windowNode.h)
  lines.add "w = " & toTomlBool(config.debug.windowNode.w)
  lines.add "currentLine = " & toTomlBool(config.debug.windowNode.currentLine)
  lines.add "currentColumn = " & toTomlBool(config.debug.windowNode.currentColumn)
  lines.add "expandedColumn = " & toTomlBool(config.debug.windowNode.expandedColumn)
  lines.add "cursor = " & toTomlBool(config.debug.windowNode.cursor)
  lines.add ""

  lines.add "[Debug.EditorView]"
  lines.add "enable = " & toTomlBool(config.debug.editorView.enable)
  lines.add "widthOfLineNum = " & toTomlBool(config.debug.editorView.widthOfLineNum)
  lines.add "height = " & toTomlBool(config.debug.editorView.height)
  lines.add "width = " & toTomlBool(config.debug.editorView.width)
  lines.add "originalLine = " & toTomlBool(config.debug.editorView.originalLine)
  lines.add "start = " & toTomlBool(config.debug.editorView.start)
  lines.add "length = " & toTomlBool(config.debug.editorView.length)
  lines.add ""

  lines.add "[Debug.BufferStatus]"
  lines.add "enable = " & toTomlBool(config.debug.bufferStatus.enable)
  lines.add "bufferIndex = " & toTomlBool(config.debug.bufferStatus.bufferIndex)
  lines.add "path = " & toTomlBool(config.debug.bufferStatus.path)
  lines.add "openDir = " & toTomlBool(config.debug.bufferStatus.openDir)
  lines.add "currentMode = " & toTomlBool(config.debug.bufferStatus.currentMode)
  lines.add "prevMode = " & toTomlBool(config.debug.bufferStatus.prevMode)
  lines.add "language = " & toTomlBool(config.debug.bufferStatus.language)
  lines.add "encoding = " & toTomlBool(config.debug.bufferStatus.encoding)
  lines.add "countChange = " & toTomlBool(config.debug.bufferStatus.countChange)
  lines.add "cmdLoop = " & toTomlBool(config.debug.bufferStatus.cmdLoop)
  lines.add "lastSaveTime = " & toTomlBool(config.debug.bufferStatus.lastSaveTime)
  lines.add "bufferLen = " & toTomlBool(config.debug.bufferStatus.bufferLen)
  lines.add ""

  lines.add "[Debug.Search]"
  lines.add "enable = " & toTomlBool(config.debug.search.enable)
  lines.add ""

  lines.add "[Debug.MacroState]"
  lines.add "enable = " & toTomlBool(config.debug.macroState.enable)
  lines.add ""

  lines.add "[Debug.Visual]"
  lines.add "enable = " & toTomlBool(config.debug.visual.enable)
  lines.add ""

  lines.add "[Debug.JumpList]"
  lines.add "enable = " & toTomlBool(config.debug.jumpList.enable)
  lines.add ""

  lines.add "[Debug.Lsp]"
  lines.add "enable = " & toTomlBool(config.debug.lsp.enable)
  lines.add ""

  # Ensure directory exists
  let dir = parentDir(path)
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return Result[void, string].err("Failed to create directory: " & e.msg)

  # Write to file
  try:
    writeFile(path, lines.join("\n"))
  except CatchableError as e:
    return Result[void, string].err("Failed to write config file: " & e.msg)

  # Save theme colors to the theme file if using config theme with a path
  if config.theme.kind == tkConfig and config.theme.path.len > 0:
    let themeResult = saveThemeToToml(themeColors, config.theme.path)
    if themeResult.isErr:
      return Result[void, string].err(themeResult.error)

  return Result[void, string].ok()

proc saveConfig*(config: EditorConfig): Result[void, string] =
  ## Save configuration to the default location
  let configPath = getConfigPath()
  return saveConfigToToml(config, configPath)
