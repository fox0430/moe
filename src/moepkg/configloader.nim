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

import std/[os, options, tables]

import pkg/parsetoml

import config

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
