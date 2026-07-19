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

## TOML loader/serializer for the [Theme] section, plus the standalone
## per-theme `[Colors]` file (`loadThemeFromToml`/`saveThemeToToml`) and
## the `initTheme` entry point used at editor startup.

import std/[os, options, tables, strutils]

import pkg/[parsetoml, results]

import ../[config, color, theme as themeMod, vscode_theme]

import base, save_base

# Top-level TOML section name handled by this module.
const ThemeSectionName* = "Theme"

# [Theme] section loader (kind/path)

proc loadThemeConfig*(
    table: TomlTableRef, config: var ThemeConfig, vr: var ValidationResult
) =
  const section = "Theme"
  const validKeys = ["kind", "path"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadEnum(table, "kind", config.kind, vr, section, parseThemeKind, ValidThemeKinds)
  # Path existence is not validated here even when kind = tkConfig: `initTheme`
  # seeds a missing file with DefaultColors so a fresh environment whose
  # moerc.toml already points at `~/.config/moe/themes/dark.toml` starts
  # cleanly. Bootstrap failures (unwritable path) are still surfaced from
  # `initTheme` under `Theme.path`.
  loadString(table, "path", config.path, vr, section)

# Standalone theme file loader (the [Colors] table)

proc toEditorColorPairIndex(key: string): Option[EditorColorPairIndex] =
  ## Convert a TOML theme key to its `EditorColorPairIndex` by reverse
  ## lookup against `toTomlColorKey`. Most TOML keys match the enum name
  ## one-to-one; the exceptions (`currentLine`, `currentColumn`,
  ## `configModePopup`, `string`) are defined in `toTomlColorKey` and
  ## inherited here automatically.
  ## Returns none if the key doesn't match any color index. The top-level
  ## `foreground`/`background` overrides are handled by the caller before
  ## reaching this function, so neither maps back to `default` here.
  for index in EditorColorPairIndex:
    if toTomlColorKey(index) == key:
      return some(index)
  return none(EditorColorPairIndex)

proc loadThemeFromToml*(
    path: string, vr: var ValidationResult
): Result[ThemeColors, string] =
  ## Load theme colors from a TOML file.
  ## Returns ThemeColors based on DefaultColors with overrides from the file.
  ## Invalid keys/values inside the [Colors] section are recorded in `vr`
  ## (and skipped) instead of aborting the load.
  ## File-level errors (file not found, parse failure, missing [Colors]
  ## section) are returned as `Result.err` and are NOT recorded in `vr`.
  ## Callers that want those errors surfaced should record them themselves
  ## (e.g. `initTheme` records them under `Theme.path`).

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
  const section = "Theme.Colors"

  # Get default foreground/background for syntax colors
  var defaultFg = colors[EditorColorPairIndex.default].foreground.rgb
  var defaultBg = colors[EditorColorPairIndex.default].background.rgb

  if colorsTable.hasKey("foreground"):
    let v = colorsTable["foreground"]
    if v.kind != TomlValueKind.String:
      vr.addError(fullKey(section, "foreground"), $v, themeColorExpected)
    else:
      let raw = v.getStr()
      let fgResult = parseThemeColor(raw)
      if fgResult.isOk:
        defaultFg = fgResult.get
      else:
        vr.addError(fullKey(section, "foreground"), raw, themeColorExpected)

  if colorsTable.hasKey("background"):
    let v = colorsTable["background"]
    if v.kind != TomlValueKind.String:
      vr.addError(fullKey(section, "background"), $v, themeColorExpected)
    else:
      let raw = v.getStr()
      let bgResult = parseThemeColor(raw)
      if bgResult.isOk:
        defaultBg = bgResult.get
      else:
        vr.addError(fullKey(section, "background"), raw, themeColorExpected)

  # Update default color pair
  colors[EditorColorPairIndex.default] = ColorPair(
    foreground: ThemeColor(rgb: defaultFg), background: ThemeColor(rgb: defaultBg)
  )

  # Apply default background to all entries that still use the old default (#000000).
  # This ensures entries not listed in the theme file inherit the user's chosen
  # background (e.g. "termDefault") instead of keeping hardcoded #000000.
  let hardcodedDefaultBg = rgb("#000000")
  for index in EditorColorPairIndex:
    if index != EditorColorPairIndex.default and
        colors[index].background.rgb == hardcodedDefaultBg:
      colors[index].background = ThemeColor(rgb: defaultBg)

  # Process all color entries. Each entry is an inline table of the form
  # `entry = { fg = "...", bg = "..." }`; both `fg` and `bg` are optional.
  # Omitting `bg` leaves the entry's bg at whatever `DefaultColors` provided:
  # for entries whose bundled default is the hardcoded #000000 (most syntax
  # colors), the upstream sweep above has already replaced that with the
  # user's top-level `background`; for entries with a non-#000000 bundled
  # default (e.g. statusLine*, tab, markdownCodeBlock), that bundled bg is
  # preserved. An entry may also set bg only (e.g. `currentLine = { bg = ... }`).
  for key, value in colorsTable:
    if key == "foreground" or key == "background":
      continue

    let indexOpt = toEditorColorPairIndex(key)
    if indexOpt.isNone:
      vr.addUnknownKey(fullKey(section, key))
      continue
    let index = indexOpt.get

    if value.kind != TomlValueKind.Table:
      vr.addError(fullKey(section, key), $value, themeInlineTableExpected)
      continue

    let sub = value.getTable()
    if sub.len == 0:
      # `key = {}` is almost always a typo (defaults are already applied
      # before this loop, so an empty table is a no-op). Surface it.
      vr.addError(fullKey(section, key), "{}", themeInlineTableExpected)
      continue

    for subkey, subval in sub:
      case subkey
      of "fg", "bg":
        let subkeyPath = fullKey(section, key & "." & subkey)
        if subval.kind != TomlValueKind.String:
          vr.addError(subkeyPath, $subval, themeColorExpected)
          continue
        let raw = subval.getStr()
        let parsed = parseThemeColor(raw)
        if parsed.isErr:
          vr.addError(subkeyPath, raw, themeColorExpected)
          continue
        if subkey == "fg":
          colors[index].foreground = ThemeColor(rgb: parsed.get)
        else:
          colors[index].background = ThemeColor(rgb: parsed.get)
      else:
        vr.addUnknownKey(fullKey(section, key & "." & subkey))

  return Result[ThemeColors, string].ok(colors)

proc loadThemeFromToml*(path: string): Result[ThemeColors, string] =
  ## Backwards-compatible wrapper that discards validation errors.
  var vr = newValidationResult()
  loadThemeFromToml(path, vr)

proc loadTheme*(
    config: EditorConfig, vr: var ValidationResult
): Result[ThemeColors, string] =
  ## Load theme based on config settings.
  ## Invalid keys/values from user theme files are recorded in `vr`.

  case config.theme.kind
  of tkDefault:
    return Result[ThemeColors, string].ok(DefaultColors)
  of tkConfig:
    return loadThemeFromToml(config.theme.path, vr)
  of tkVscode:
    return loadVSCodeTheme()

proc loadTheme*(config: EditorConfig): Result[ThemeColors, string] =
  ## Backwards-compatible wrapper that discards validation errors.
  var vr = newValidationResult()
  loadTheme(config, vr)

# True iff `themeColors` mirrors a successful `tkConfig` load from
# `config.theme.path`. Consulted by `saveConfigToToml` so a fallback-to-defaults
# load doesn't stamp bundled defaults over the user's theme file.
var themeColorsFromFile* = false

# Forward declaration: `initTheme` bootstraps a missing tkConfig file via
# `saveThemeToToml`, which is defined further down in the Serializers section.
proc saveThemeToToml*(colors: ThemeColors, path: string): Result[void, string]

proc initTheme*(config: EditorConfig, vr: var ValidationResult) =
  ## Initialize the theme based on configuration.
  ## Falls back to default theme on error; both file-level errors and any
  ## invalid keys/values within the theme file are recorded in `vr`.
  ## For `tkVscode`, the underlying error message is recorded under
  ## `Theme.kind`. `tkDefault` never fails.
  ##
  ## Bootstrap: when `tkConfig` names a path that does not yet exist, seed
  ## it with `DefaultColors` (creating parent dirs as needed) before loading,
  ## so a fresh environment whose `moerc.toml` already points at
  ## `~/.config/moe/themes/dark.toml` starts up without a "Theme file not
  ## found" error every launch. If seeding fails (unwritable path, etc.),
  ## the write error is recorded under `Theme.path` and the load falls
  ## through to the default theme.

  if config.theme.kind == tkConfig and config.theme.path.len > 0:
    let expandedPath = expandTilde(config.theme.path)
    if not fileExists(expandedPath):
      let saveResult = saveThemeToToml(DefaultColors, config.theme.path)
      if saveResult.isErr:
        vr.addError("Theme.path", config.theme.path, saveResult.error)
        initDefaultTheme()
        themeColorsFromFile = false
        return

  let themeResult = loadTheme(config, vr)
  if themeResult.isOk:
    setThemeColors(themeResult.get)
    themeColorsFromFile = config.theme.kind == tkConfig
  else:
    case config.theme.kind
    of tkConfig:
      vr.addError("Theme.path", config.theme.path, themeResult.error)
    of tkVscode:
      vr.addError("Theme.kind", "vscode", themeResult.error)
    of tkDefault:
      discard
    initDefaultTheme()
    themeColorsFromFile = false

proc initTheme*(config: EditorConfig) =
  ## Backwards-compatible wrapper that discards validation errors.
  var vr = newValidationResult()
  initTheme(config, vr)

# Serializers

proc appendThemeToml*(lines: var seq[string], cfg: ThemeConfig) =
  lines.add "[Theme]"
  lines.add "kind = " & toTomlString($cfg.kind)
  if cfg.path.len > 0:
    lines.add "path = " & toTomlString(cfg.path)
  lines.add ""

proc saveThemeToToml*(colors: ThemeColors, path: string): Result[void, string] =
  ## Save theme colors to a TOML file
  var lines: seq[string] = @[]

  lines.add "# Theme color configuration"
  lines.add "# Color format: \"#RRGGBB\" (hex) or \"termDefault\" (terminal default color)"
  lines.add "# \"termDefault\" can be used for both foreground and background."
  lines.add "# Examples:"
  lines.add "#   foreground = \"termDefault\"  # Use terminal's default foreground color"
  lines.add "#   background = \"termDefault\"  # Use terminal's default background color"
  lines.add ""
  lines.add "[Colors]"
  lines.add ""

  # Write default foreground/background
  lines.add "foreground = " &
    themeColorToTomlValue(colors[EditorColorPairIndex.default].foreground)
  lines.add "background = " &
    themeColorToTomlValue(colors[EditorColorPairIndex.default].background)
  lines.add ""

  # Write all other color pairs as inline tables: `key = { fg = "...", bg = "..." }`.
  # currentLineBg and currentColumnBg are bg-only entities, so emit only `bg`.
  const BgOnlyEntries =
    {EditorColorPairIndex.currentLineBg, EditorColorPairIndex.currentColumnBg}
  for index in EditorColorPairIndex:
    if index == EditorColorPairIndex.default:
      continue

    let key = toTomlColorKey(index)
    let bg = themeColorToTomlValue(colors[index].background)
    if index in BgOnlyEntries:
      lines.add key & " = { bg = " & bg & " }"
    else:
      let fg = themeColorToTomlValue(colors[index].foreground)
      lines.add key & " = { fg = " & fg & ", bg = " & bg & " }"

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
