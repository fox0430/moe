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

## TOML configuration loader entry point.
##
## This module is the orchestrator: per-section loaders/serializers live in
## `config_loader/<section>.nim` and are re-exported here so external callers
## (`editor.nim`, `command_handlers/*`, etc.) can keep `import config_loader`
## unchanged. The actual TOML <-> `EditorConfig` work happens via the
## `loadXxxConfig` / `appendXxxToml` helpers exposed from the sub-modules.

import std/[os, strutils, tables]

import pkg/[parsetoml, results]

import config, color

import
  config_loader/[
    base, save_base, simple, debug, lsp, theme as themeLoader, keymapping, user_commands
  ]
export base, save_base, simple, debug, lsp, themeLoader, keymapping, user_commands

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

  # Validate top-level section names. Each sub-module owns the section names
  # it handles; "StartUp" is a parent table for `[StartUp.FileOpen]` and
  # `[StartUp.FileTree]` so it lives here at the orchestrator level.
  const knownSections =
    @SimpleSectionNames &
    @[
      DebugSectionName, LspSectionName, ThemeSectionName, KeyMappingSectionName,
      "StartUp",
    ] & @UserCommandsSectionNames
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

  if toml.hasKey("FileTree"):
    loadFileTreeConfig(toml["FileTree"].getTable(), config.fileTree, vr)

  if toml.hasKey("Autocomplete"):
    loadAutocompleteConfig(toml["Autocomplete"].getTable(), config.autocomplete, vr)

  if toml.hasKey("Persist"):
    loadPersistConfig(toml["Persist"].getTable(), config.persist, vr)

  if toml.hasKey("StartUp"):
    let startUpTable = toml["StartUp"].getTable()
    const startUpValidKeys = ["FileOpen", "FileTree"]
    checkUnknownKeys(startUpTable, startUpValidKeys, "StartUp", vr)
    if startUpTable.hasKey("FileOpen"):
      loadStartUpFileOpenConfig(
        startUpTable["FileOpen"].getTable(), config.startUpFileOpen, vr
      )
    if startUpTable.hasKey("FileTree"):
      loadStartUpFileTreeConfig(
        startUpTable["FileTree"].getTable(), config.startUpFileTree, vr
      )

  if toml.hasKey("EditorConfig"):
    loadEditorConfigSettings(toml["EditorConfig"].getTable(), config.editorConfig, vr)

  if toml.hasKey("Lsp"):
    loadLspConfig(toml["Lsp"].getTable(), config.lsp, vr)

  if toml.hasKey("Log"):
    loadLogConfig(toml["Log"].getTable(), config.log, vr)

  if toml.hasKey("Debug"):
    loadDebugConfig(toml["Debug"].getTable(), config.debug, vr)

  if toml.hasKey("KeyMapping"):
    loadKeyMappingConfig(toml["KeyMapping"].getTable(), config.keyMapping, vr)

  if toml.hasKey("CommandAliases"):
    loadCommandAliasesConfig(
      toml["CommandAliases"].getTable(), config.commandAliases, vr
    )

  if toml.hasKey("ShellCommands"):
    loadShellCommandsConfig(toml["ShellCommands"].getTable(), config.shellCommands, vr)

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

proc saveConfigToToml*(config: EditorConfig, path: string): Result[void, string] =
  ## Save configuration to a TOML file
  var lines: seq[string] = @[]

  appendStandardToml(lines, config.standard)
  appendClipboardToml(lines, config.clipboard)
  appendBuildOnSaveToml(lines, config.buildOnSave)
  appendTabLineToml(lines, config.tabLine)
  appendStatusLineToml(lines, config.statusLine)
  appendThemeToml(lines, config.theme)
  appendHighlightToml(lines, config.highlight)
  appendAutoBackupToml(lines, config.autoBackup)
  appendNotificationToml(lines, config.notification)
  appendFilerToml(lines, config.filer)
  appendFileTreeToml(lines, config.fileTree)
  appendAutocompleteToml(lines, config.autocomplete)
  appendAutoSaveToml(lines, config.autoSave)
  appendPersistToml(lines, config.persist)
  appendGitToml(lines, config.git)
  appendSyntaxCheckerToml(lines, config.syntaxChecker)
  appendSmoothScrollToml(lines, config.smoothScroll)
  appendStartUpFileOpenToml(lines, config.startUpFileOpen)
  appendStartUpFileTreeToml(lines, config.startUpFileTree)
  appendEditorConfigToml(lines, config.editorConfig)
  appendQuickRunToml(lines, config.quickRun)

  appendLspToml(lines, config.lsp)

  appendKeyMappingToml(lines, config.keyMapping)

  appendLogToml(lines, config.log)
  appendDebugToml(lines, config.debug)
  appendCommandAliasesToml(lines, config.commandAliases)
  appendShellCommandsToml(lines, config.shellCommands)

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
