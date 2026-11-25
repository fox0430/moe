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

import ../[config, config_dir, color, theme as themeMod, vscode_theme]

import ../buffer/atomic_write

when defined(posix):
  from std/posix import geteuid, `==`

import base, save_base

# Top-level TOML section name handled by this module.
const ThemeSectionName* = "Theme"

# Keys of the [Theme] section.
const ThemeConfigKeys* = ["kind", "path"]

# [Theme] section loader (kind/path)

proc isThemePathAllowed*(path: string): bool =
  ## True iff `path` resolves inside a moe config dir. Guards implicit
  ## theme-file creation from crafted moerc paths; reads/overwrites stay
  ## permissive.
  if path.len == 0:
    return false
  let expanded =
    try:
      # `absolutePath` reads the cwd even for an absolute path, and the cwd may
      # have been deleted.
      let tildeExpanded = expandTilde(path)
      normalizedPath(
        if tildeExpanded.isAbsolute:
          tildeExpanded
        else:
          absolutePath(tildeExpanded)
      )
    except CatchableError:
      return false
  for base in moeConfigDirs():
    if expanded == base:
      continue
    # `relativePath` returns the input unchanged across drives/UNC roots,
    # which `isRelativeTo` would misread as contained. Require a genuinely
    # relative result without `..` escapes.
    let rel = relativePath(expanded, base)
    if rel.len > 0 and not rel.isAbsolute and not rel.startsWith "..":
      return true
  false

proc loadThemeConfig*(
    table: TomlTableRef, config: var ThemeConfig, vr: var ValidationResult
) =
  const section = ThemeSectionName
  checkUnknownKeys(table, ThemeConfigKeys, section, vr)
  loadEnum(table, "kind", config.kind, vr, section, parseThemeKind, ValidThemeKinds)
  # Path existence is not validated here even when kind = tkConfig: `initTheme`
  # seeds a missing file with DefaultColors so a fresh environment whose
  # moerc.toml already points at `~/.config/moe/themes/dark.toml` starts
  # cleanly. Bootstrap failures (unwritable path) are still surfaced from
  # `initTheme` under `Theme.path`.
  loadString(table, "path", config.path, vr, section)

# Standalone theme file loader (the [Colors] table)

const FallbackColors = [
  (EditorColorPairIndex.markdownHeading, EditorColorPairIndex.builtin),
  (EditorColorPairIndex.markdownCode, EditorColorPairIndex.specialVar),
  (EditorColorPairIndex.markdownLinkUrl, EditorColorPairIndex.specialVar),
  (EditorColorPairIndex.markdownListMarker, EditorColorPairIndex.operator),
  (EditorColorPairIndex.markdownFrontmatter, EditorColorPairIndex.preprocessor),
  (EditorColorPairIndex.file, EditorColorPairIndex.default),
]

const LegacyColorKeys = {
  # Old theme keys and the entries they set when the theme has no key for those.
  "dir": @[EditorColorPairIndex.filerDirectory],
  "pcLink": @[EditorColorPairIndex.filerSymlink, EditorColorPairIndex.filerSymlinkDir],
}

const StatusLineInactiveFallbacks = block:
  ## The Inactive color of each mode and the active color it falls back to.
  var pairs: seq[tuple[inactive, active: EditorColorPairIndex]]
  for active in EditorColorPairIndex:
    for inactive in EditorColorPairIndex:
      if ($active).startsWith("statusLine") and $inactive == $active & "Inactive":
        pairs.add (inactive, active)
  pairs

const ItalicFallbacks = block:
  ## The entry each entry takes `italic` from when a theme leaves it out.
  var sources: array[EditorColorPairIndex, Option[EditorColorPairIndex]]
  for (specific, generic) in FallbackColors:
    # `file` falls back to `default` for colors, but `default` cannot be italic.
    if specific != EditorColorPairIndex.file:
      sources[specific] = some(generic)
  for (inactive, active) in StatusLineInactiveFallbacks:
    sources[inactive] = some(active)
  sources

const NoItalicEntries = block:
  ## Entries that draw no text of their own, only backgrounds and blank cells,
  ## and ones for frames and guides: slanted box-drawing characters do not join.
  var entries =
    ColorBgOnlyEntries + {
      EditorColorPairIndex.selectArea, EditorColorPairIndex.snippetTabStop,
      EditorColorPairIndex.highlightTrailingSpaces,
      EditorColorPairIndex.highlightFullWidthSpace, EditorColorPairIndex.scrollBarThumb,
      EditorColorPairIndex.scrollBarTrack, EditorColorPairIndex.indentationLine,
      EditorColorPairIndex.popupWindowBorder,
      EditorColorPairIndex.notificationPopupInfoBorder,
      EditorColorPairIndex.notificationPopupWarningBorder,
      EditorColorPairIndex.notificationPopupErrorBorder,
      EditorColorPairIndex.tempMessageBorder, EditorColorPairIndex.whitespace,
    }
  for index in DiffViewerTints:
    entries.incl index
  entries

# Named colors from the optional [Palette] table, in file order.
type ThemePalette* = OrderedTable[string, Rgb]

# One side of one color pair. The top-level foreground/background use
# `EditorColorPairIndex.default`.
type ThemeChannel* = tuple[index: EditorColorPairIndex, isFg: bool]

# A color and the palette name it was written as, if any.
type SharedColor* = object
  color*: ThemeColor
  name*: string

# The `statusLineMode*` keys, which set one side of a color pair for every mode.
# A theme file may set either side of each.
type StatusLineModeChannel* = tuple[kind: StatusLineModeColor, isFg: bool]
type StatusLineModeColors* = OrderedTable[StatusLineModeChannel, SharedColor]

# What the loaded theme file said, so a save can keep its palette and the
# channels it wrote by name or left out without putting that on ThemeColor.
type ThemeSource* = object
  palette*: ThemePalette
  refs*: Table[ThemeChannel, string]
  statusLineModes*: StatusLineModeColors
  omittedFg*, omittedBg*: set[EditorColorPairIndex]
  explicitItalic*: set[EditorColorPairIndex] ## Entries the file sets `italic` of

proc isEmpty*(source: ThemeSource): bool =
  ## True without a palette and references to it.
  source.palette.len == 0 and source.refs.len == 0

proc explicitEntries(source: ThemeSource): set[EditorColorPairIndex] =
  ## Entries the theme file sets at least one channel of.
  {EditorColorPairIndex.low .. EditorColorPairIndex.high} -
    source.omittedFg * source.omittedBg

proc isValidPaletteName(name: string): bool =
  ## Palette names are emitted as bare keys and must not read as color
  ## literals (`abcdef` would be a hex color, `termDefault` a literal).
  if name.len == 0 or name[0] notin {'A' .. 'Z', 'a' .. 'z', '_'}:
    return false
  for c in name:
    if c notin {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-'}:
      return false
  name != "termDefault" and hexToRgb(name).isErr

proc loadThemePalette(toml: TomlValueRef, vr: var ValidationResult): ThemePalette =
  ## Read [Palette] before [Colors], which refers to it. Bad entries are
  ## reported and skipped; a non-table section is reported too.
  result = initOrderedTable[string, Rgb]()
  if not toml.hasKey("Palette"):
    return
  let value = toml["Palette"]
  if value.kind != TomlValueKind.Table:
    vr.addError("Theme.Palette", $value, themePaletteExpected)
    return
  for name, color in value.getTable():
    let path = fullKey("Theme.Palette", name)
    if not isValidPaletteName(name):
      vr.addError(path, name, themePaletteNameExpected)
      continue
    if color.kind != TomlValueKind.String:
      vr.addError(path, $color, themePaletteValueExpected)
      continue
    # Palette values cannot name other palette entries.
    let parsed = parseThemeColor(color.getStr())
    if parsed.isErr:
      vr.addError(path, color.getStr(), themePaletteValueExpected)
      continue
    result[name] = parsed.get

proc resolveThemeColor(s: string, palette: ThemePalette): Result[Rgb, string] =
  ## Palette names win over literals so a name shadows a literal color.
  if s in palette:
    return Result[Rgb, string].ok palette[s]
  parseThemeColor(s)

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

proc legacyColorIndexes(key: string): Option[seq[EditorColorPairIndex]] =
  ## The entries the old theme key `key` stands for; none if it is not one.
  for (legacy, indexes) in LegacyColorKeys:
    if legacy == key:
      return some(indexes)
  none(seq[EditorColorPairIndex])

proc setsColor(colorsTable: TomlTableRef, key: string): bool =
  ## Whether `key` replaces an old key's colors. An entry with neither `fg` nor
  ## `bg`, such as `{ italic = true }`, does not.
  if not colorsTable.hasKey(key):
    return false
  let value = colorsTable[key]
  value.kind != TomlValueKind.Table or value.tableVal.hasKey("fg") or
    value.tableVal.hasKey("bg")

proc toStatusLineModeColor(key: string): Option[StatusLineModeColor] =
  for kind in StatusLineModeColor:
    if $kind == key:
      return some(kind)
  none(StatusLineModeColor)

proc baseThemeColors(default: ColorPair): ThemeColors =
  ## What every entry starts from under the top-level foreground/background.
  ## Entries whose bundled background is #000000 inherit the theme's background
  ## (e.g. "termDefault") instead of keeping the hardcoded color.
  result = DefaultColors
  result[EditorColorPairIndex.default] = default

  let hardcodedDefaultBg = rgb("#000000")
  for index in EditorColorPairIndex:
    if index != EditorColorPairIndex.default and
        result[index].background.rgb == hardcodedDefaultBg:
      result[index].background = default.background

proc applyColorFallback(
    colors: var ThemeColors, omittedFg, omittedBg: set[EditorColorPairIndex]
) =
  ## Entries colored by a more generic one for whichever of fg/bg the theme does
  ## not set, the look of themes written before their keys took effect.
  for (specific, generic) in FallbackColors:
    if specific in omittedFg:
      colors[specific].foreground = colors[generic].foreground
    if specific in omittedBg:
      colors[specific].background = colors[generic].background

proc noteThemeColorEdited*(
    colors: var ThemeColors,
    source: var ThemeSource,
    index: EditorColorPairIndex,
    isFg: bool,
) =
  ## A live color edit makes `index`'s channel explicit from now on, and the
  ## channels the theme still leaves out take their fallbacks again.
  if isFg:
    source.omittedFg.excl index
  else:
    source.omittedBg.excl index
  colors.applyColorFallback(source.omittedFg, source.omittedBg)

proc fallbackItalic(colors: ThemeColors, index: EditorColorPairIndex): bool =
  ## The italic `index` loads with when the theme leaves it out.
  let source = ItalicFallbacks[index]
  source.isSome and colors[source.get].italic

proc applyItalicFallback(
    colors: var ThemeColors, explicitItalic: set[EditorColorPairIndex]
) =
  for index in EditorColorPairIndex:
    if index notin explicitItalic:
      colors[index].italic = colors.fallbackItalic(index)

proc applyStatusLineInactiveFallback(
    colors: var ThemeColors, omittedFg, omittedBg: set[EditorColorPairIndex]
) =
  ## A theme that sets only a mode's active color keeps it in an inactive
  ## window, rather than mixing in the bundled palette.
  ## If that would match the channel the theme does set, the active color's other
  ## channel is used instead, or black or white when that is the terminal's
  ## default, whose color is unknown.
  proc sameColor(a, b: ThemeColor): bool =
    # The terminal's default foreground and background are different colors.
    a.rgb == b.rgb and not a.rgb.isTermDefaultColor

  proc otherChannel(candidate, against: ThemeColor): ThemeColor =
    if not candidate.rgb.isTermDefaultColor:
      candidate
    elif against.rgb.isLightColor:
      ThemeColor(rgb: rgb("#000000"))
    else:
      ThemeColor(rgb: rgb("#ffffff"))

  for (inactive, active) in StatusLineInactiveFallbacks:
    if active in omittedFg * omittedBg:
      continue
    let
      fillFg = inactive in omittedFg
      fillBg = inactive in omittedBg
    if fillFg:
      colors[inactive].foreground = colors[active].foreground
    if fillBg:
      colors[inactive].background = colors[active].background
    if fillFg != fillBg and
        sameColor(colors[inactive].foreground, colors[inactive].background):
      if fillFg:
        colors[inactive].foreground =
          otherChannel(colors[active].background, colors[inactive].background)
      else:
        colors[inactive].background =
          otherChannel(colors[active].foreground, colors[inactive].foreground)

proc applyStatusLineColors(
    colors: var ThemeColors,
    shared: StatusLineModeColors,
    omittedFg, omittedBg: set[EditorColorPairIndex],
) =
  ## Color every mode the theme does not set with the keys shared by all modes,
  ## then fill in the Inactive colors that neither sets.
  var
    unsetFg = omittedFg
    unsetBg = omittedBg
  for channel, value in shared:
    let entries = StatusLineModeEntries[channel.kind]
    for index in entries:
      if channel.isFg and index in omittedFg:
        colors[index].foreground = value.color
      elif not channel.isFg and index in omittedBg:
        colors[index].background = value.color
    if channel.isFg:
      unsetFg = unsetFg - entries
    else:
      unsetBg = unsetBg - entries
  colors.applyStatusLineInactiveFallback(unsetFg, unsetBg)

proc loadThemeWithSource*(
    path: string, vr: var ValidationResult
): Result[(ThemeColors, ThemeSource), string] =
  ## Load theme colors and the palette references they came from.
  ## Returns ThemeColors based on DefaultColors with overrides from the file.
  ## Invalid keys/values inside [Colors] and [Palette] are recorded in `vr`
  ## (and skipped) instead of aborting the load.
  ## File-level errors (file not found, parse failure, missing [Colors]
  ## section) are returned as `Result.err` and are NOT recorded in `vr`.
  ## Callers that want those errors surfaced should record them themselves
  ## (e.g. `initTheme` records them under `Theme.path`).

  type Loaded = Result[(ThemeColors, ThemeSource), string]

  let expandedPath = path.expandTilde
  if not fileExists(expandedPath):
    return Loaded.err("Theme file not found: " & expandedPath)

  var toml: TomlValueRef
  try:
    toml = parseFile(expandedPath)
  except CatchableError as e:
    return Loaded.err("Failed to parse theme file: " & e.msg)

  # Replaced below once the top-level foreground/background are known
  var colors = DefaultColors

  # Check for Colors section
  if not toml.hasKey("Colors"):
    return Loaded.err("Theme file missing [Colors] section")

  if toml["Colors"].kind != TomlValueKind.Table:
    return Loaded.err("Theme file [Colors] section must be a table")

  # The palette has to be known before [Colors] resolves its names.
  var source = ThemeSource(palette: loadThemePalette(toml, vr))

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
      let fgResult = resolveThemeColor(raw, source.palette)
      if fgResult.isOk:
        defaultFg = fgResult.get
        if raw in source.palette:
          source.refs[(EditorColorPairIndex.default, true)] = raw
      else:
        vr.addError(fullKey(section, "foreground"), raw, themeColorExpected)

  if colorsTable.hasKey("background"):
    let v = colorsTable["background"]
    if v.kind != TomlValueKind.String:
      vr.addError(fullKey(section, "background"), $v, themeColorExpected)
    else:
      let raw = v.getStr()
      let bgResult = resolveThemeColor(raw, source.palette)
      if bgResult.isOk:
        defaultBg = bgResult.get
        if raw in source.palette:
          source.refs[(EditorColorPairIndex.default, false)] = raw
      else:
        vr.addError(fullKey(section, "background"), raw, themeColorExpected)

  colors = baseThemeColors(
    ColorPair(
      foreground: ThemeColor(rgb: defaultFg), background: ThemeColor(rgb: defaultBg)
    )
  )

  # Process all color entries. Each entry is an inline table of the form
  # `entry = { fg = "...", bg = "..." }`; both `fg` and `bg` are optional.
  # Omitting `bg` leaves the entry's bg at whatever `DefaultColors` provided:
  # for entries whose bundled default is the hardcoded #000000 (most syntax
  # colors), the upstream sweep above has already replaced that with the
  # user's top-level `background`; for entries with a non-#000000 bundled
  # default (e.g. statusLine*, tab, markdownCodeBlock), that bundled bg is
  # preserved, except as the fallbacks below replace it. An entry may also set
  # bg only (e.g. `currentLine = { bg = ... }`).
  var fgSet, bgSet: set[EditorColorPairIndex]
  for key, value in colorsTable:
    if key == "foreground" or key == "background":
      continue

    let
      sharedOpt = toStatusLineModeColor(key)
      indexOpt = toEditorColorPairIndex(key)
      legacyOpt = legacyColorIndexes(key)
    if sharedOpt.isNone and indexOpt.isNone and legacyOpt.isNone:
      vr.addUnknownKey(fullKey(section, key))
      continue

    if value.kind != TomlValueKind.Table:
      vr.addError(fullKey(section, key), $value, themeInlineTableExpected)
      continue

    let sub = value.getTable()
    if sub.len == 0:
      # `key = {}` is almost always a typo (defaults are already applied
      # before this loop, so an empty table is a no-op). Surface it.
      vr.addError(fullKey(section, key), "{}", themeInlineTableExpected)
      continue

    var indexes: seq[EditorColorPairIndex]
    if indexOpt.isSome:
      indexes.add indexOpt.get
    elif legacyOpt.isSome:
      for index in legacyOpt.get:
        if not colorsTable.setsColor(toTomlColorKey(index)):
          indexes.add index

    for subkey, subval in sub:
      case subkey
      of "fg", "bg":
        let subkeyPath = fullKey(section, key & "." & subkey)
        if subval.kind != TomlValueKind.String:
          vr.addError(subkeyPath, $subval, themeColorExpected)
          continue
        let raw = subval.getStr()
        let parsed = resolveThemeColor(raw, source.palette)
        if parsed.isErr:
          vr.addError(subkeyPath, raw, themeColorExpected)
          continue
        let name = if raw in source.palette: raw else: ""
        if sharedOpt.isSome:
          source.statusLineModes[(sharedOpt.get, subkey == "fg")] =
            SharedColor(color: ThemeColor(rgb: parsed.get), name: name)
          continue
        for index in indexes:
          if name.len > 0:
            source.refs[(index, subkey == "fg")] = name
          if subkey == "fg":
            colors[index].foreground = ThemeColor(rgb: parsed.get)
            fgSet.incl index
          else:
            colors[index].background = ThemeColor(rgb: parsed.get)
            bgSet.incl index
      of "italic":
        let subkeyPath = fullKey(section, key & ".italic")
        if sharedOpt.isSome:
          # Italic is drawn per entry, not for a color shared by every mode.
          vr.addUnknownKey(subkeyPath)
        elif indexOpt.isNone:
          vr.addUnknownKey(subkeyPath)
        else:
          let index = indexOpt.get
          if subval.kind != TomlValueKind.Bool:
            vr.addError(subkeyPath, $subval, themeItalicExpected)
          elif index == EditorColorPairIndex.default:
            vr.addError(subkeyPath, $subval, themeItalicOnDefaultExpected)
          elif index in NoItalicEntries:
            vr.addError(subkeyPath, $subval, themeItalicNoTextExpected)
          else:
            colors[index].italic = subval.getBool()
            source.explicitItalic.incl index
      else:
        vr.addUnknownKey(fullKey(section, key & "." & subkey))

  const allIndexes = {EditorColorPairIndex.low .. EditorColorPairIndex.high}
  source.omittedFg = allIndexes - fgSet - {EditorColorPairIndex.default}
  source.omittedBg = allIndexes - bgSet - {EditorColorPairIndex.default}
  colors.applyStatusLineColors(
    source.statusLineModes, source.omittedFg, source.omittedBg
  )
  colors.applyColorFallback(source.omittedFg, source.omittedBg)
  colors.applyItalicFallback(source.explicitItalic)

  return Loaded.ok((colors, source))

proc loadThemeFromToml*(
    path: string, vr: var ValidationResult
): Result[ThemeColors, string] =
  ## Load only the colors; the palette and its references are dropped.
  let loaded = loadThemeWithSource(path, vr)
  if loaded.isErr:
    return Result[ThemeColors, string].err(loaded.error)
  Result[ThemeColors, string].ok(loaded.get[0])

proc loadThemeFromToml*(path: string): Result[ThemeColors, string] =
  ## Backwards-compatible wrapper that discards validation errors.
  var vr = newValidationResult()
  loadThemeFromToml(path, vr)

proc loadThemeWithSource*(
    config: EditorConfig, vr: var ValidationResult
): Result[(ThemeColors, ThemeSource), string] =
  ## Load theme colors and their palette references based on config settings.
  ## Invalid keys/values from user theme files are recorded in `vr`.
  ## Only `tkConfig` can have a palette; the other kinds return an empty source.

  type Loaded = Result[(ThemeColors, ThemeSource), string]

  let loaded =
    case config.theme.kind
    of tkDefault:
      Loaded.ok((DefaultColors, ThemeSource()))
    of tkConfig:
      loadThemeWithSource(config.theme.path, vr)
    of tkVscode:
      let vscode = loadVSCodeTheme()
      if vscode.isErr:
        Loaded.err(vscode.error)
      else:
        Loaded.ok((vscode.get, ThemeSource()))
  if loaded.isErr:
    return loaded
  var colors = loaded.get[0]
  let explicit =
    if config.theme.kind == tkConfig:
      loaded.get[1].explicitEntries
    else:
      {}
  colors.adaptDiffTintsToBackground(explicit)
  return Loaded.ok((colors, loaded.get[1]))

proc loadTheme*(
    config: EditorConfig, vr: var ValidationResult
): Result[ThemeColors, string] =
  ## Load theme based on config settings, dropping the palette references.
  let loaded = loadThemeWithSource(config, vr)
  if loaded.isErr:
    return Result[ThemeColors, string].err(loaded.error)
  Result[ThemeColors, string].ok(loaded.get[0])

proc loadTheme*(config: EditorConfig): Result[ThemeColors, string] =
  ## Backwards-compatible wrapper that discards validation errors.
  var vr = newValidationResult()
  loadTheme(config, vr)

# Colors `themeColors` held when it was last loaded from or saved to the
# `tkConfig` theme file (after `adaptDiffTintsToBackground`). None when
# `themeColors` did not come from a file, so that a fallback to the defaults is
# never stamped over the user's theme file.
var themeFileColors*: Option[ThemeColors]

proc themeColorsEdited*(): bool =
  ## True when the in-memory colors came from the theme file and differ from
  ## what was last loaded or saved.
  themeFileColors.isSome and themeColors != themeFileColors.get

# What the theme file holds as of the last load or save: the [Palette] table and
# the channels written by name or left out. Empty when the theme did not come from a theme file, so a
# save can never carry over another theme's palette.
var themeSource*: ThemeSource

# The [Theme] setting `themeColors` was last loaded for; none before the first
# `initTheme`. Applying a config rereads the theme only when its setting differs.
var loadedThemeConfig*: Option[ThemeConfig]

proc sharedStatusLineSource*(colors: ThemeColors): ThemeSource

# Forward declaration: `initTheme` bootstraps a missing tkConfig file via
# `saveThemeToToml`, which is defined further down in the Serializers section.
proc saveThemeToToml*(
  colors: ThemeColors, path: string, source = ThemeSource()
): Result[void, string]

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

  loadedThemeConfig = some(config.theme)

  if config.theme.kind == tkConfig and config.theme.path.len > 0:
    let expandedPath = expandTilde(config.theme.path)
    if not fileExists(expandedPath):
      if not isThemePathAllowed(config.theme.path):
        vr.addError("Theme.path", config.theme.path, "theme file inside moe config dir")
        initDefaultTheme()
        themeFileColors = none(ThemeColors)
        themeSource = ThemeSource()
        return
      let saveResult = saveThemeToToml(
        DefaultColors, config.theme.path, sharedStatusLineSource(DefaultColors)
      )
      if saveResult.isErr:
        vr.addLoadFailure("Theme.path", config.theme.path, saveResult.error)
        initDefaultTheme()
        themeFileColors = none(ThemeColors)
        themeSource = ThemeSource()
        return

  let themeResult = loadThemeWithSource(config, vr)
  if themeResult.isOk:
    setThemeColors(themeResult.get[0])
    themeFileColors =
      if config.theme.kind == tkConfig:
        some(themeResult.get[0])
      else:
        none(ThemeColors)
    themeSource = themeResult.get[1]
  else:
    case config.theme.kind
    of tkConfig:
      vr.addLoadFailure("Theme.path", config.theme.path, themeResult.error)
    of tkVscode:
      vr.addLoadFailure("Theme.kind", "vscode", themeResult.error)
    of tkDefault:
      discard
    initDefaultTheme()
    themeFileColors = none(ThemeColors)
    themeSource = ThemeSource()

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

proc reloadedColors(colors: ThemeColors, source: ThemeSource): ThemeColors =
  ## What loading a file that leaves out `source`'s omitted channels would give.
  result = baseThemeColors(colors[EditorColorPairIndex.default])
  for index in EditorColorPairIndex:
    if index notin source.omittedFg:
      result[index].foreground = colors[index].foreground
    if index notin source.omittedBg:
      result[index].background = colors[index].background
  result.applyStatusLineColors(
    source.statusLineModes, source.omittedFg, source.omittedBg
  )
  result.applyColorFallback(source.omittedFg, source.omittedBg)
  result.adaptDiffTintsToBackground(source.explicitEntries)

proc sourceFor*(source: ThemeSource, colors: ThemeColors): ThemeSource =
  ## The part of `source` that still describes `colors`: names whose palette
  ## entry holds the color, and omitted channels that would load back as they are.
  ## Entries whose italic would not load back become explicit.
  result = source
  result.refs.clear()
  for channel, name in source.refs:
    let color =
      if channel.isFg:
        colors[channel.index].foreground
      else:
        colors[channel.index].background
    if name in source.palette and source.palette[name] == color.rgb:
      result.refs[channel] = name

  for index in EditorColorPairIndex:
    if colors[index].italic != colors.fallbackItalic(index):
      result.explicitItalic.incl index

  # Writing one channel can change what another would load as (the color and
  # Inactive fallbacks and the diff tints), so repeat until nothing more is
  # needed.
  while true:
    let reloaded = reloadedColors(colors, result)
    var changedFg, changedBg: set[EditorColorPairIndex]
    for index in EditorColorPairIndex:
      if index in result.omittedFg and
          reloaded[index].foreground != colors[index].foreground:
        changedFg.incl index
      if index in result.omittedBg and
          reloaded[index].background != colors[index].background:
        changedBg.incl index
    if changedFg == {} and changedBg == {}:
      break
    result.omittedFg = result.omittedFg - changedFg
    result.omittedBg = result.omittedBg - changedBg

proc sharedStatusLineSource*(colors: ThemeColors): ThemeSource =
  ## A source that writes what all modes of a status line color have in common
  ## as one key.
  for kind in StatusLineModeColor:
    let entries = StatusLineModeEntries[kind]
    for isFg in [true, false]:
      var values: seq[ThemeColor]
      for index in entries:
        let color =
          if isFg:
            colors[index].foreground
          else:
            colors[index].background
        if color notin values:
          values.add color
      if values.len != 1:
        continue
      result.statusLineModes[(kind, isFg)] = SharedColor(color: values[0])
      if isFg:
        result.omittedFg = result.omittedFg + entries
      else:
        result.omittedBg = result.omittedBg + entries

proc themeChannelToTomlValue(
    color: ThemeColor, channel: ThemeChannel, source: ThemeSource
): string =
  ## The name in `source` for the channel, or else the color itself.
  if channel in source.refs:
    return toTomlString(source.refs[channel])
  themeColorToTomlValue(color)

proc mustWriteInPlace(path: string): bool =
  ## True when renaming a new file over `path` would break a link or take the
  ## file from its owner.
  let target = classifyTarget(path)
  result = target.isSymlink or target.linkCount > 1
  when defined(posix):
    result = result or target.uid != geteuid()

proc writeThemeInPlace(path, content: string): Result[void, string] =
  ## Overwrite `path`, whose content `<path>.bac` holds, and put that content
  ## back when the write fails.
  try:
    writeFile(path, content)
    Result[void, string].ok()
  except CatchableError as e:
    var msg = "Failed to write theme file: " & e.msg
    try:
      copyFile(path & ".bac", path)
    except CatchableError:
      msg.add "; the previous content is in " & path & ".bac"
    Result[void, string].err(msg)

proc saveThemeToToml*(
    colors: ThemeColors, path: string, source = ThemeSource()
): Result[void, string] =
  ## Save theme colors to a TOML file. With a `source`, its [Palette] is
  ## written first (in file order, unused names included), its `statusLineMode*`
  ## keys are written as they were, the channels the
  ## file wrote by name stay names while the palette still holds the color, and
  ## the ones it left out stay out while they would load as the same color.
  let source = source.sourceFor(colors)
  var lines: seq[string] = @[]

  lines.add "# Theme color configuration"
  lines.add "# Color format: \"#RRGGBB\" (hex) or \"termDefault\" (terminal default color)"
  lines.add "# \"termDefault\" can be used for both foreground and background."
  lines.add "# Define named colors under [Palette] and reuse them as fg/bg values."
  lines.add "# Add \"italic = true\" to an entry to draw its text in italics."
  lines.add "# Examples:"
  lines.add "#   foreground = \"termDefault\"  # Use terminal's default foreground color"
  lines.add "#   background = \"termDefault\"  # Use terminal's default background color"
  lines.add ""

  if source.palette.len > 0:
    lines.add "[Palette]"
    for name, color in source.palette:
      lines.add name & " = " & themeColorToTomlValue(ThemeColor(rgb: color))
    lines.add ""

  lines.add "[Colors]"
  lines.add ""

  # Write default foreground/background
  lines.add "foreground = " &
    themeChannelToTomlValue(
      colors[EditorColorPairIndex.default].foreground,
      (index: EditorColorPairIndex.default, isFg: true),
      source,
    )
  lines.add "background = " &
    themeChannelToTomlValue(
      colors[EditorColorPairIndex.default].background,
      (index: EditorColorPairIndex.default, isFg: false),
      source,
    )
  lines.add ""

  # The keys shared by all modes, as far as the theme has them
  for kind in StatusLineModeColor:
    var channels: seq[string]
    for (isFg, side) in [(true, "fg"), (false, "bg")]:
      let channel: StatusLineModeChannel = (kind, isFg)
      if channel in source.statusLineModes:
        let shared = source.statusLineModes[channel]
        let value =
          if shared.name.len > 0:
            toTomlString(shared.name)
          else:
            themeColorToTomlValue(shared.color)
        channels.add side & " = " & value
    if channels.len > 0:
      lines.add $kind & " = { " & channels.join(", ") & " }"
  if source.statusLineModes.len > 0:
    lines.add ""

  # Write all other color pairs as inline tables: `key = { fg = "...", bg = "..." }`.
  # Bg-only entries emit only `bg`.
  for index in EditorColorPairIndex:
    if index == EditorColorPairIndex.default:
      continue

    var channels: seq[string]
    if index notin ColorBgOnlyEntries and index notin source.omittedFg:
      channels.add "fg = " &
        themeChannelToTomlValue(
          colors[index].foreground, (index: index, isFg: true), source
        )
    if index notin source.omittedBg:
      channels.add "bg = " &
        themeChannelToTomlValue(
          colors[index].background, (index: index, isFg: false), source
        )
    if index in source.explicitItalic:
      channels.add "italic = " & $colors[index].italic
    if channels.len > 0:
      lines.add toTomlColorKey(index) & " = { " & channels.join(", ") & " }"

  lines.add ""

  # Ensure directory exists
  let expandedPath = path.expandTilde
  let dir = parentDir(expandedPath)
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return Result[void, string].err("Failed to create directory: " & e.msg)

  let content = lines.join("\n")

  # A dangling symlink: create its target, which `writeAtomic` refuses to do.
  if symlinkExists(expandedPath) and not fileExists(expandedPath):
    try:
      writeFile(expandedPath, content)
      return Result[void, string].ok()
    except CatchableError as e:
      return Result[void, string].err("Failed to write theme file: " & e.msg)

  if fileExists(expandedPath):
    # The rename in `writeAtomic` needs no write access to the file itself, so
    # check that first. Opening for append changes nothing.
    var f: File
    if not open(f, expandedPath, fmAppend):
      return Result[void, string].err(
        "Failed to write theme file: cannot open for writing: " & expandedPath
      )
    close(f)

    # Backup existing file
    try:
      copyFile(expandedPath, expandedPath & ".bac")
    except CatchableError as e:
      return Result[void, string].err("Failed to backup theme file: " & e.msg)

    # The `.bac` file already is the backup of an in-place write; `writeAtomic`
    # would put another at `<path>~`, over whatever is there.
    if mustWriteInPlace(expandedPath):
      return writeThemeInPlace(expandedPath, content)

  # A failed write must not leave a partial theme: a later save skips
  # unchanged colors and would not repair it.
  let written = writeAtomic(expandedPath, content, wpOverwrite)
  if written.isErr:
    return Result[void, string].err("Failed to write theme file: " & written.error)
  Result[void, string].ok()
