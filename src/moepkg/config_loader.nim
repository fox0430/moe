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
## This module is the orchestrator. Most sections are loaded and serialized by
## the whole-config dispatch macros (`generateSectionLoaders` /
## `generateSectionSerializers` from `config_macros`), which derive the section
## set from `EditorConfig`'s `{.cfgSection.}` fields so it cannot drift from the
## type. Sections without a `{.cfgSection.}` (Theme, Lsp, Debug, KeyMapping,
## CommandAliases, ShellCommands, DisabledCommandAliases) and the nested
## `[StartUp.*]` tables are dispatched by hand here, using the helpers from
## `config_loader/<section>.nim`. `[Lsp]` is dispatched by hand because its
## parent table also holds the dynamic `[Lsp.<languageId>]` keyspace, but its
## body is derived from `LspConfig` all the same (see `config_loader/lsp`).
## Those sub-modules are re-exported so external callers (`editor.nim`,
## `command_handlers/*`, etc.) can keep `import config_loader` unchanged.

import std/[options, os, strutils, tables]

import pkg/[parsetoml, results]

import config, color, config_macros

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

  # Load each top-level {.cfgSection.} section (validation integrated into
  # loading). This single macro call expands to the per-section
  # `if toml.hasKey(...)` dispatch derived from EditorConfig's fields, so it
  # stays in sync with the type automatically. Sections with no {.cfgSection.}
  # (Theme, Lsp, Debug, KeyMapping, CommandAliases, ShellCommands,
  # DisabledCommandAliases) and the nested [StartUp.*] sections are handled by
  # hand below.
  generateSectionLoaders(toml, config, vr, EditorConfig)

  if toml.hasKey("Theme"):
    loadThemeConfig(toml["Theme"].getTable(), config.theme, vr)

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

  if toml.hasKey("Lsp"):
    loadLspConfig(toml["Lsp"].getTable(), config.lsp, vr)

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

  if toml.hasKey("DisabledCommandAliases"):
    loadDisabledCommandAliasesConfig(
      toml["DisabledCommandAliases"].getTable(), config.disabledCommandAliases, vr
    )

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
  ## Load configuration from the default location, then merge the optional
  ## dedicated keymap file (keybindings.toml) on top of moerc.toml [KeyMapping].
  let configPath = getConfigPath()
  result = loadConfigFromToml(configPath)
  if result.isOk:
    var (config, vr) = result.get
    loadKeyMappingFile(config.keyMapping, vr)
    result = Result[(EditorConfig, ValidationResult), string].ok((config, vr))

proc saveConfigToToml*(config: EditorConfig, path: string): Result[void, string] =
  ## Save configuration to a TOML file
  var lines: seq[string] = @[]

  # Serialize every {.cfgSection.} section of EditorConfig (in field-declaration
  # order). This single macro call expands to one `appendXxxToml`-equivalent per
  # section, derived from the type, so it cannot drift from the loader dispatch
  # above. Sections without {.cfgSection.} are appended by hand afterwards.
  generateSectionSerializers(lines, config, EditorConfig)

  appendThemeToml(lines, config.theme)
  appendLspToml(lines, config.lsp)
  appendKeyMappingToml(lines, config.keyMapping)
  appendDebugToml(lines, config.debug)
  appendCommandAliasesToml(lines, config.commandAliases)
  appendShellCommandsToml(lines, config.shellCommands)
  appendDisabledCommandAliasesToml(lines, config.disabledCommandAliases)

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

  # Skip the theme write when the user's file is on disk but `themeColors`
  # doesn't mirror it (initTheme fell back to defaults); the `not fileExists`
  # branch keeps the bootstrap case working.
  if config.theme.kind == tkConfig and config.theme.path.len > 0:
    let expandedThemePath = expandTilde(config.theme.path)
    if themeColorsFromFile or not fileExists(expandedThemePath):
      let themeResult = saveThemeToToml(themeColors, config.theme.path)
      if themeResult.isErr:
        return Result[void, string].err(themeResult.error)

  return Result[void, string].ok()

proc saveConfig*(config: EditorConfig): Result[void, string] =
  ## Save configuration to the default location
  let configPath = getConfigPath()
  return saveConfigToToml(config, configPath)
