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

## VSCode theme loader for moe editor
##
## This module handles loading color themes from VSCode, VSCodium, and Code-OSS
## installations and converting them to moe's ThemeColors format.

import
  std/[
    os, options, tables, json, strformat, strutils, math, xmlparser, xmltree, times,
    sequtils,
  ]
import pkg/results

import color, theme

# All `statusLine*` entries (per-mode triplets plus the git info pair) form a
# contiguous block in `EditorColorPairIndex`; the statusBar.* mapping below
# relies on that layout.
const StatusLineColorIndexes =
  EditorColorPairIndex.statusLineNormalMode .. EditorColorPairIndex.statusLineGitBranch

static:
  for i in EditorColorPairIndex:
    doAssert ($i).startsWith("statusLine") == (i in StatusLineColorIndexes),
      "statusLine* entries must form a contiguous block in EditorColorPairIndex"

# Text colored by tokenColors rules. With no rule VS Code draws such text in
# the editor foreground. Relies on the enum's syntax blocks.
const TokenColorIndexes =
  {
    EditorColorPairIndex.keyword .. EditorColorPairIndex.property,
    EditorColorPairIndex.namespace .. EditorColorPairIndex.unresolvedReference,
  } - {
    EditorColorPairIndex.whitespace, EditorColorPairIndex.logError,
    EditorColorPairIndex.logWarning, EditorColorPairIndex.logInfo,
    EditorColorPairIndex.logUuid,
  }

static:
  # Between the two blocks is only markdownCodeBlock, a block background.
  doAssert succ(EditorColorPairIndex.property) == EditorColorPairIndex.markdownCodeBlock
  doAssert succ(EditorColorPairIndex.markdownCodeBlock) == EditorColorPairIndex.namespace

type I = EditorColorPairIndex

const TokenScopes = [
  # Each entry's TextMate scopes, as grammars give such text; the first one
  # the theme colors, itself or through a parent, is used. A lookup falls back
  # to parent scopes, as in TextMate, never to children: a child rule colors
  # only text with that scope. So a later scope counts only when no earlier
  # one, nor any of its parents, is colored. rust-analyzer's types use its VS Code extension's scopes or the
  # Rust grammar's.
  # Most keywords are keyword.control, which themes may color alone.
  (I.keyword, @["keyword", "keyword.control"]),
  (I.functionName, @["entity.name.function"]),
  (I.typeName, @["entity.name.type"]),
  (I.boolean, @["constant.language.boolean"]),
  # Language-defined: Nim's result, Lua's self.
  (I.specialVar, @["variable.language"]),
  (I.builtin, @["support.function"]),
  # Strings and comments take their common form's scope, which themes may
  # color without coloring the parent.
  (I.charLit, @["string.quoted.single", "constant.character"]),
  (I.stringLit, @["string.quoted.double"]),
  (I.binNumber, @["constant.numeric"]),
  (I.decNumber, @["constant.numeric"]),
  (I.floatNumber, @["constant.numeric"]),
  (I.hexNumber, @["constant.numeric"]),
  (I.octNumber, @["constant.numeric"]),
  (I.comment, @["comment.line"]),
  (I.longComment, @["comment.block"]),
  (I.docComment, @["comment.line.documentation"]),
  (I.docLongComment, @["comment.block.documentation"]),
  (I.preprocessor, @["meta.preprocessor", "keyword.control.directive"]),
  (I.pragma, @["meta.preprocessor", "keyword.control.directive"]),
  (I.identifier, @[]),
  (I.table, @["entity.name.section", "support.type.property-name"]),
  (I.date, @["constant.other.time", "constant.numeric"]),
  (I.operator, @["keyword.operator"]),
  (I.property, @["variable.other.property"]),
  (I.namespace, @["entity.name.namespace"]),
  (I.className, @["entity.name.type.class", "support.class"]),
  (I.enumName, @["entity.name.type.enum"]),
  (I.enumMember, @["variable.other.enummember"]),
  (I.interfaceName, @["entity.name.type.interface"]),
  (I.typeParameter, @["entity.name.type.parameter"]),
  (I.parameter, @["variable.parameter"]),
  # What grammars scope a plain variable reference as.
  (I.variable, @["variable.other.readwrite"]),
  (I.lspString, @["string.quoted.double"]),
  (I.event, @["variable.other.event"]),
  (I.function, @["entity.name.function", "support.function"]),
  (I.`method`, @["entity.name.function.member", "support.function"]),
  (I.`macro`, @["entity.name.function.macro"]),
  (I.regexp, @["string.regexp"]),
  (I.decorator, @["entity.name.function.decorator"]),
  (I.angle, @["punctuation.brackets.angle"]),
  (I.arithmetic, @["keyword.operator.arithmetic"]),
  (I.attribute, @["meta.attribute", "entity.name.function.decorator"]),
  (I.attributeBracket, @["punctuation.brackets.attribute"]),
  (I.bitwise, @["keyword.operator.bitwise"]),
  (I.brace, @["punctuation.brackets.curly"]),
  (I.bracket, @["punctuation.brackets.square"]),
  (I.builtinAttribute, @["meta.attribute", "entity.name.function.decorator"]),
  (I.builtinType, @["support.type.primitive", "entity.name.type"]),
  (I.colon, @["keyword.operator.key-value"]),
  (I.comma, @["punctuation.comma"]),
  (I.comparison, @["keyword.operator.comparison"]),
  (I.constParameter, @["constant.other.caps"]),
  (I.derive, @["meta.attribute", "entity.name.function.decorator"]),
  (I.deriveHelper, @["meta.attribute", "entity.name.function.decorator"]),
  (I.dot, @["keyword.operator.access.dot"]),
  # Inside a string, so they take its color where the theme has none for them.
  (I.escapeSequence, @["constant.character.escape", "string.quoted.double"]),
  (
    I.invalidEscapeSequence,
    @["invalid.illegal", "constant.character.escape", "string.quoted.double"],
  ),
  (I.formatSpecifier, @["constant.other.placeholder", "string.quoted.double"]),
  (I.generic, @[]),
  (I.label, @["entity.name.label"]),
  (I.lifetime, @["storage.modifier.lifetime"]),
  (I.logical, @["keyword.operator.logical"]),
  (I.macroBang, @["entity.name.function.macro"]),
  (I.parenthesis, @["punctuation.brackets.round"]),
  (I.punctuation, @["punctuation"]),
  (I.selfKeyword, @["variable.language.self", "keyword"]),
  (I.selfTypeKeyword, @["variable.language.self", "keyword"]),
  (I.semicolon, @["punctuation.semi"]),
  (I.typeAlias, @["entity.name.type.declaration"]),
  (I.toolModule, @[]),
  (I.union, @["entity.name.type.union"]),
  (I.unresolvedReference, @[]),
]

static:
  var covered: set[EditorColorPairIndex]
  for (index, _) in TokenScopes:
    doAssert index notin covered, $index & " is in TokenScopes twice"
    covered.incl index
  doAssert covered == TokenColorIndexes,
    "TokenScopes must cover TokenColorIndexes: " &
      $((covered - TokenColorIndexes) + (TokenColorIndexes - covered))

type VsCodeFlavor* = enum
  VSCodium
  CodeOss
  VSCode

proc vsCodeUserDataDir(flavor: VsCodeFlavor): string =
  ## Where the flavor keeps its `User` dir (settings and global state).
  let name =
    case flavor
    of VsCodeFlavor.VSCodium: "VSCodium"
    of VsCodeFlavor.CodeOss: "Code - OSS"
    of VsCodeFlavor.VSCode: "Code"
  when defined(macosx):
    getHomeDir() / "Library" / "Application Support" / name
  else:
    # Electron honors XDG_CONFIG_HOME, as getConfigDir does.
    getConfigDir() / name

proc vsCodeSettingsFilePath(flavor: VsCodeFlavor): string =
  vsCodeUserDataDir(flavor) / "User" / "settings.json"

proc vsCodeStateDbPath(flavor: VsCodeFlavor): string =
  vsCodeUserDataDir(flavor) / "User" / "globalStorage" / "state.vscdb"

proc vsCodeUserExtensionsDir(flavor: VsCodeFlavor): string =
  case flavor
  of VsCodeFlavor.VSCodium, VsCodeFlavor.CodeOss:
    getHomeDir() / ".vscode-oss" / "extensions"
  of VsCodeFlavor.VSCode:
    getHomeDir() / ".vscode" / "extensions"

proc vsCodeBuiltinExtensionsDirs(flavor: VsCodeFlavor): seq[string] =
  ## Built-in extension dirs of the common installs. Only the ones that
  ## exist are searched.
  when defined(macosx):
    let app =
      case flavor
      of VsCodeFlavor.VSCodium: "VSCodium.app"
      of VsCodeFlavor.CodeOss: "Code - OSS.app"
      of VsCodeFlavor.VSCode: "Visual Studio Code.app"
    for root in ["/Applications", getHomeDir() / "Applications"]:
      result.add root / app / "Contents" / "Resources" / "app" / "extensions"
  else:
    case flavor
    of VsCodeFlavor.VSCodium:
      result = @[
        "/usr/share/codium/resources/app/extensions", # deb, rpm
        "/opt/vscodium-bin/resources/app/extensions", # AUR vscodium-bin
        "/usr/share/vscodium/resources/app/extensions", # AUR vscodium
        "/snap/codium/current/usr/share/codium/resources/app/extensions",
      ]
    of VsCodeFlavor.CodeOss:
      result = @["/usr/lib/code/extensions"] # Arch code
    of VsCodeFlavor.VSCode:
      result = @[
        "/usr/share/code/resources/app/extensions", # deb, rpm
        "/opt/visual-studio-code/resources/app/extensions", # AUR visual-studio-code-bin
        "/snap/code/current/usr/share/code/resources/app/extensions",
      ]

proc readThemeNameFromStateDb(path: string): Option[string] =
  ## Read the active color theme name from VSCode's state.vscdb.
  ## The DB stores a JSON value for key "colorThemeData" containing "settingsId".
  ## We search for the pattern in the raw file bytes to avoid a SQLite dependency.

  try:
    let data = readFile(path)
    # Find the JSON blob: "colorThemeData{" marks the start of the actual data.
    const keyWithJson = "colorThemeData{"
    let keyPos = data.find(keyWithJson)
    if keyPos >= 0:
      const marker = "\"settingsId\":\""
      let pos = data.find(marker, keyPos)
      if pos >= 0:
        let start = pos + marker.len
        let endPos = data.find('"', start)
        if endPos > start:
          let name = data[start ..< endPos]
          if name.len > 0:
            return some(name)
  except CatchableError:
    discard

proc lastUsed(flavor: VsCodeFlavor): Option[Time] =
  ## When the flavor last wrote its settings or state, which it does as it runs.
  ## None if it has neither. One whose settings were never changed has state
  ## only.
  for path in [vsCodeSettingsFilePath(flavor), vsCodeStateDbPath(flavor)]:
    try:
      let time = getLastModificationTime(path)
      if result.isNone or time > result.get:
        result = some(time)
    except CatchableError:
      discard

proc vsCodeFlavorInUse(): Option[VsCodeFlavor] =
  ## The most recently used flavor. A tie keeps enum order (VSCodium,
  ## Code - OSS, VS Code).
  var latest: Time
  for flavor in VsCodeFlavor:
    let used = flavor.lastUsed
    if used.isSome and (result.isNone or used.get > latest):
      result = some(flavor)
      latest = used.get

proc matchesThemeName(theme: JsonNode, themeName: string): bool =
  ## Check if a theme entry matches the given name by label or id.
  if theme{"label"} != nil and theme{"label"}.getStr == themeName:
    return true
  if theme{"id"} != nil and theme{"id"}.getStr == themeName:
    return true

type
  VsThemeKind* = enum
    ## VS Code's theme types, as `uiTheme` in package.json names them.
    vtkDark = "vs-dark"
    vtkLight = "vs"
    vtkHcDark = "hc-black"
    vtkHcLight = "hc-light"

  Rgba = object
    rgb*: Rgb
    alpha*: float

  VsColors = object
    ## A theme's `colors`, falling back to VS Code's defaults for its kind.
    colors: JsonNode
    kind: VsThemeKind
    surface: Rgb ## The opaque editor background translucent colors sit on

proc byKind(dark, light, hcDark, hcLight: string): array[VsThemeKind, string] =
  [vtkDark: dark, vtkLight: light, vtkHcDark: hcDark, vtkHcLight: hcLight]

proc allKinds(value: string): array[VsThemeKind, string] =
  byKind(value, value, value, value)

const VsColorDefaults = [
  # VS Code's own defaults (its color registry as of 1.138, and the git
  # extension) for the colors read here and those they refer to. "@key" is
  # another color, "@key*a" that color with its alpha scaled by a, "" none.
  ("foreground", byKind("#CCCCCC", "#616161", "#FFFFFF", "#292929")),
  ("contrastBorder", byKind("", "", "#6FC3DF", "#0F4A85")),
  ("contrastActiveBorder", byKind("", "", "@focusBorder", "@focusBorder")),
  ("focusBorder", byKind("#007FD4", "#0090F1", "#F38518", "#006BBD")),
  ("badge.background", byKind("#4D4D4D", "#C4C4C4", "#000000", "#0F4A85")),
  ("editor.background", byKind("#1E1E1E", "#FFFFFF", "#000000", "#FFFFFF")),
  ("editor.foreground", byKind("#BBBBBB", "#333333", "#FFFFFF", "@foreground")),
  ("editor.selectionBackground", byKind("#264F78", "#ADD6FF", "#F3F518", "#0F4A85")),
  ("editor.selectionForeground", byKind("", "", "#000000", "#FFFFFF")),
  ("editor.findMatchHighlightBackground", byKind("#EA5C0055", "#EA5C0055", "", "")),
  # Unset, VS Code draws the border instead; a terminal can only fill the line.
  (
    "editor.lineHighlightBackground",
    byKind("@editor.lineHighlightBorder", "@editor.lineHighlightBorder", "", ""),
  ),
  (
    "editor.lineHighlightBorder",
    byKind("#282828", "#EEEEEE", "#F38518", "@contrastBorder"),
  ),
  (
    "editorWhitespace.foreground",
    byKind("#E3E4E229", "#33333333", "#E3E4E229", "#CCCCCC"),
  ),
  ("editorGutter.background", allKinds("@editor.background")),
  # Not a VS Code color, read for themes written with it.
  ("editorLineNumber.background", allKinds("@editorGutter.background")),
  ("editorLineNumber.foreground", byKind("#858585", "#237893", "#FFFFFF", "#292929")),
  ("editorLineNumber.activeForeground", allKinds("@editorActiveLineNumber.foreground")),
  (
    "editorActiveLineNumber.foreground",
    byKind("#C6C6C6", "#0B216F", "@contrastActiveBorder", "@contrastActiveBorder"),
  ),
  ("editorError.foreground", byKind("#F14C4C", "#E51400", "#F48771", "#B5200D")),
  ("editorWarning.foreground", byKind("#CCA700", "#BF8803", "#FFD370", "#895503")),
  ("editorInfo.foreground", byKind("#59A4F9", "#0063D3", "#59A4F9", "#0063D3")),
  ("editorInlayHint.foreground", byKind("#969696", "#969696", "#FFFFFF", "#000000")),
  (
    "editorInlayHint.background",
    byKind(
      "@badge.background*0.1", "@badge.background*0.1", "#FFFFFF1A",
      "@badge.background*0.1",
    ),
  ),
  ("editorCodeLens.foreground", byKind("#999999", "#919191", "#999999", "#292929")),
  ("editorWidget.background", byKind("#252526", "#F3F3F3", "#0C141F", "#FFFFFF")),
  ("editorSuggestWidget.background", allKinds("@editorWidget.background")),
  ("editorSuggestWidget.foreground", allKinds("@editor.foreground")),
  # High contrast inverts the selected item.
  (
    "editorSuggestWidget.selectedBackground",
    byKind(
      "@list.activeSelectionBackground", "@list.activeSelectionBackground",
      "@editorSuggestWidget.foreground", "@editorSuggestWidget.foreground",
    ),
  ),
  (
    "editorSuggestWidget.selectedForeground",
    byKind(
      "@list.activeSelectionForeground", "@list.activeSelectionForeground",
      "@editorSuggestWidget.background", "@editorSuggestWidget.background",
    ),
  ),
  ("list.activeSelectionBackground", byKind("#04395E", "#0060C0", "", "#0F4A851A")),
  ("list.activeSelectionForeground", byKind("#FFFFFF", "#FFFFFF", "", "")),
  ("statusBar.background", byKind("#007ACC", "#007ACC", "", "")),
  (
    "statusBar.foreground",
    byKind("#FFFFFF", "#FFFFFF", "#FFFFFF", "@editor.foreground"),
  ),
  ("tab.activeBackground", allKinds("@editor.background")),
  ("tab.activeForeground", byKind("#FFFFFF", "#333333", "#FFFFFF", "#292929")),
  ("tab.inactiveBackground", byKind("#2D2D2D", "#ECECEC", "", "")),
  (
    "tab.inactiveForeground",
    byKind(
      "@tab.activeForeground*0.5", "@tab.activeForeground*0.7", "#FFFFFF", "#292929"
    ),
  ),
  (
    "gitDecoration.addedResourceForeground",
    byKind("#81B88B", "#587C0C", "#A1E3AD", "#374E06"),
  ),
  (
    "gitDecoration.modifiedResourceForeground",
    byKind("#E2C08D", "#895503", "#E2C08D", "#895503"),
  ),
  (
    "gitDecoration.deletedResourceForeground",
    byKind("#C74E39", "#AD0707", "#C74E39", "#AD0707"),
  ),
  (
    "gitDecoration.conflictingResourceForeground",
    byKind("#E4676B", "#AD0707", "#C74E39", "#AD0707"),
  ),
  ("diffEditor.insertedTextBackground", byKind("#9CCC2C33", "#9CCC2C40", "", "")),
  ("merge.currentHeaderBackground", byKind("#40C8AE80", "#40C8AE80", "", "")),
  ("merge.currentContentBackground", allKinds("@merge.currentHeaderBackground*0.4")),
  ("merge.incomingHeaderBackground", byKind("#40A6FF80", "#40A6FF80", "", "")),
  ("merge.incomingContentBackground", allKinds("@merge.incomingHeaderBackground*0.4")),
  ("merge.commonHeaderBackground", byKind("#60606066", "#60606066", "", "")),
  ("merge.commonContentBackground", allKinds("@merge.commonHeaderBackground*0.4")),
]

proc parseVsColor(s: string): Option[Rgba] =
  ## "#RGB", "#RGBA", "#RRGGBB" or "#RRGGBBAA", as VS Code takes them.
  if s.len notin [4, 5, 7, 9] or s[0] != '#' or not s[1 .. ^1].allCharsInSet(HexDigits):
    return none(Rgba)
  var hex = s[1 .. ^1]
  if hex.len <= 4:
    var long = ""
    for c in hex:
      long.add c
      long.add c
    hex = long
  let alpha =
    if hex.len == 8:
      parseHexInt(hex[6 .. 7]) / 255
    else:
      1.0
  some(
    Rgba(
      rgb: Rgb(
        red: parseHexInt(hex[0 .. 1]).int16,
        green: parseHexInt(hex[2 .. 3]).int16,
        blue: parseHexInt(hex[4 .. 5]).int16,
      ),
      alpha: alpha,
    )
  )

proc blend(c: Rgba, under: Rgb): Rgb =
  ## `c` painted over `under`. A terminal cell has no alpha.
  if c.alpha >= 1.0:
    return c.rgb
  proc mix(top, bottom: int16): int16 =
    int16(round(top.float * c.alpha + bottom.float * (1.0 - c.alpha)))

  Rgb(
    red: mix(c.rgb.red, under.red),
    green: mix(c.rgb.green, under.green),
    blue: mix(c.rgb.blue, under.blue),
  )

proc vsDefault(key: string, kind: VsThemeKind): string =
  for (k, values) in VsColorDefaults:
    if k == key:
      return values[kind]

proc themeRgba(colors: JsonNode, key: string): Option[Rgba] =
  if colors != nil and colors.kind == JObject and colors.hasKey(key) and
      colors[key].kind == JString:
    return parseVsColor(colors[key].getStr)

proc defaultRgba(vs: VsColors, key: string, depth = 0): Option[Rgba]

proc rgba(vs: VsColors, key: string, depth = 0): Option[Rgba] =
  ## The theme's color for `key`, else VS Code's default for the theme kind.
  result = themeRgba(vs.colors, key)
  if result.isNone:
    result = vs.defaultRgba(key, depth)

proc defaultRgba(vs: VsColors, key: string, depth = 0): Option[Rgba] =
  ## VS Code's default for `key` in the theme kind, whatever the theme sets.
  if depth > 8:
    return
  let default = vsDefault(key, vs.kind)
  if not default.startsWith('@'):
    return parseVsColor(default)
  let star = default.find('*')
  if star < 0:
    return vs.rgba(default[1 .. ^1], depth + 1)
  result = vs.rgba(default[1 ..< star], depth + 1)
  if result.isSome:
    result.get.alpha *= parseFloat(default[star + 1 .. ^1])

proc over(c: Option[Rgba], under: Rgb): Option[Rgb] =
  ## `c` as moe draws it on `under`.
  if c.isSome:
    return some(c.get.blend(under))

proc color(vs: VsColors, key: string): Option[Rgb] =
  ## `key` as moe draws it on the editor background, with VS Code's default
  ## when the theme omits it.
  vs.rgba(key).over(vs.surface)

proc blended(vs: VsColors, node: JsonNode, key: string): Option[Rgb] =
  ## `key` of `node` (nil allowed) as moe draws it, when set.
  themeRgba(node, key).over(vs.surface)

proc orElse[T](c, fallback: Option[T]): Option[T] =
  if c.isSome: c else: fallback

proc lineHighlight(vs: VsColors): Option[Rgb] =
  ## The cursor line's fill. A theme that clears the background leaves the
  ## border to mark the line, so it falls back as if the background were unset.
  const key = "editor.lineHighlightBackground"
  let set = themeRgba(vs.colors, key)
  let c =
    if set.isSome and set.get.alpha == 0:
      vs.defaultRgba(key)
    else:
      vs.rgba(key)
  c.over(vs.surface)

proc background(vs: VsColors, key: string): Option[Rgb] =
  ## `key` as a background. VS Code draws none where it has no color, so the
  ## editor background shows through.
  some(vs.color(key).get(vs.surface))

proc setFg(
    colors: var ThemeColors, c: Option[Rgb], targets: openArray[EditorColorPairIndex]
) =
  if c.isSome:
    for t in targets:
      colors[t].foreground = ThemeColor(rgb: c.get)

proc setBg(
    colors: var ThemeColors, c: Option[Rgb], targets: openArray[EditorColorPairIndex]
) =
  if c.isSome:
    for t in targets:
      colors[t].background = ThemeColor(rgb: c.get)

proc setPair(
    colors: var ThemeColors,
    fg: Option[Rgba],
    bg: Option[Rgb],
    targets: openArray[EditorColorPairIndex],
) =
  ## Text in `fg` on `bg`, both from VS Code or neither: moe's own pair stays
  ## whole rather than mixing with a color VS Code never draws it with. A
  ## translucent `fg` is blended onto `bg`, the surface it is drawn on.
  if fg.isSome and bg.isSome:
    colors.setFg(fg.over(bg.get), targets)
    colors.setBg(bg, targets)

proc themeEntry(packageJson: JsonNode, themeName: string): JsonNode =
  ## The package's `contributes.themes` entry for the theme, nil if it has
  ## none. Its file and its kind both come from this one entry.
  let themes = packageJson{"contributes", "themes"}
  if themes != nil and themes.kind == JArray:
    for t in themes:
      if t.matchesThemeName(themeName):
        return t

proc themeKind(entry: JsonNode): VsThemeKind =
  ## The kind a `contributes.themes` entry declares. VS Code assumes dark.
  parseEnum[VsThemeKind](entry{"uiTheme"}.getStr, vtkDark)

const TmThemeGlobalColors = [
  # A TextMate theme's global settings VS Code takes as these colors.
  ("background", "editor.background"),
  ("foreground", "editor.foreground"),
  ("selection", "editor.selectionBackground"),
  ("findMatchHighlight", "editor.findMatchHighlightBackground"),
  ("lineHighlight", "editor.lineHighlightBackground"),
  ("invisibles", "editorWhitespace.foreground"),
]

proc isUnscoped(scope: JsonNode): bool =
  ## Whether a rule's `scope` is absent, null or empty: the rule applies to
  ## all text.
  scope == nil or scope.kind == JNull or (scope.kind == JString and scope.getStr == "")

proc fromTextMateRules(rules: JsonNode): JsonNode =
  ## A theme of TextMate rules, as VS Code converts them: an unscoped rule's
  ## settings also give editor colors.
  var colors = newJObject()
  for rule in rules:
    let settings = rule{"settings"}
    if rule{"scope"}.isUnscoped and settings != nil and settings.kind == JObject:
      for (setting, key) in TmThemeGlobalColors:
        if settings{setting} != nil and settings{setting}.kind == JString:
          colors[key] = settings[setting]
  %*{"colors": colors, "tokenColors": rules}

proc plistToJson(node: XmlNode): JsonNode =
  ## A property list value as JSON. Values a theme does not use are null.
  case node.tag
  of "dict":
    result = newJObject()
    var key = ""
    for child in node:
      if child.kind != xnElement:
        continue
      if child.tag == "key":
        key = child.innerText
      else:
        result[key] = plistToJson(child)
  of "array":
    result = newJArray()
    for child in node:
      if child.kind == xnElement:
        result.add plistToJson(child)
  of "string":
    result = %node.innerText
  else:
    result = newJNull()

proc readTmTheme(path: string): Result[JsonNode, string] =
  ## A TextMate theme file (a property list) as a theme.
  if not fileExists(path):
    return err(path & " does not exist")
  let root =
    try:
      parseXml(readFile(path))
    except CatchableError as e:
      return err("cannot read " & path & ": " & e.msg)
  var plist = newJNull()
  if root.tag == "plist":
    for child in root:
      if child.kind == xnElement:
        plist = plistToJson(child)
        break
  let settings = plist{"settings"}
  if settings == nil or settings.kind != JArray:
    return err(path & " has no settings array")
  ok(fromTextMateRules(settings))

proc readThemeFile(path: string): Result[JsonNode, string] =
  ## The theme file at `path` as VS Code reads it: JSON if named so, else a
  ## TextMate theme. Its `include` is left to the caller. The error says why
  ## it cannot be read.
  if path.splitFile.ext != ".json":
    return readTmTheme(path)
  if not fileExists(path):
    return err(path & " does not exist")
  let theme =
    try:
      json.parseFile(path)
    except JsonParsingError as e:
      # The message starts with the file name and position.
      return err(e.msg)
    except CatchableError as e:
      return err("cannot read " & path & ": " & e.msg)
  if theme.kind != JObject:
    return err(path & " is not a JSON object")

  let settings = theme{"settings"}
  if settings != nil and settings.kind == JArray:
    # The old format, TextMate rules in JSON: VS Code reads nothing else.
    let converted = fromTextMateRules(settings)
    if theme.hasKey("include"):
      converted["include"] = theme["include"]
    return ok(converted)

  let tokenColors = theme{"tokenColors"}
  if tokenColors != nil and tokenColors.kind == JString and tokenColors.getStr != "":
    # A TextMate theme to take the rules from. Its global settings override
    # this file's colors, as in VS Code, which ignores an empty one.
    let tm = ?readTmTheme(parentDir(path) / tokenColors.getStr)
    var colors = newJObject()
    if theme{"colors"} != nil and theme{"colors"}.kind == JObject:
      colors = theme["colors"]
    for key, value in tm["colors"]:
      colors[key] = value
    theme["colors"] = colors
    theme["tokenColors"] = tm["tokenColors"]
  ok(theme)

proc realThemePath(path: string): Result[string, string] =
  ## `path` with symlinks resolved, so a cycle through one is caught too.
  try:
    ok(expandFilename(path))
  except CatchableError as e:
    err("cannot read " & path & ": " & e.msg)

proc resolveThemeIncludes(
    themeJson: JsonNode, themeDir: string, visited: seq[string] = @[]
): Result[JsonNode, string] =
  ## Resolve the `include` chain in a VSCode theme file.
  ## Merges colors and tokenColors from included (base) themes,
  ## with the current file's values taking priority. `visited` holds the real
  ## paths of the files already in the chain. A base that cannot be read fails
  ## the theme, as in VS Code, and so does a cycle. The error says why.

  let includeNode = themeJson{"include"}
  # An empty one is no include, as in VS Code.
  if includeNode == nil or includeNode.kind != JString or includeNode.getStr == "":
    return ok(themeJson)

  let
    includePath = themeDir / includeNode.getStr
    base = ?readThemeFile(includePath)
    realPath = ?realThemePath(includePath)
  if realPath in visited:
    return err("include cycle at " & includePath)
  let baseJson = ?resolveThemeIncludes(base, parentDir(includePath), visited & realPath)

  # Merge colors: base first, current overrides
  var mergedColors = newJObject()
  if baseJson{"colors"} != nil and baseJson{"colors"}.kind == JObject:
    for key, val in baseJson["colors"]:
      mergedColors[key] = val
  if themeJson{"colors"} != nil and themeJson{"colors"}.kind == JObject:
    for key, val in themeJson["colors"]:
      mergedColors[key] = val

  # Merge tokenColors: base first, then current (later entries override in table)
  var mergedTokenColors = newJArray()
  if baseJson{"tokenColors"} != nil and baseJson{"tokenColors"}.kind == JArray:
    for item in baseJson["tokenColors"]:
      mergedTokenColors.add(item)
  if themeJson{"tokenColors"} != nil and themeJson{"tokenColors"}.kind == JArray:
    for item in themeJson["tokenColors"]:
      mergedTokenColors.add(item)

  ok(%*{"colors": mergedColors, "tokenColors": mergedTokenColors})

proc findTokenSettings(
    tokenNodes: Table[string, JsonNode], scope: string, key = "foreground"
): JsonNode =
  ## The rule `scope` takes its `key` color from: the scope's own rule or its
  ## nearest parent's that sets it, as TextMate inherits. Nil if none does.
  var s = scope
  while true:
    if s in tokenNodes and themeRgba(tokenNodes[s], key).isSome:
      return tokenNodes[s]
    let dot = s.rfind('.')
    if dot < 0:
      return nil
    s = s[0 ..< dot]

proc addTokenRule(
    tokenNodes: var Table[string, JsonNode], selector: string, settings: JsonNode
) =
  ## A later rule for the same selector overrides only what it sets, as in
  ## VS Code.
  if selector in tokenNodes:
    let merged = tokenNodes[selector].copy
    for k, v in settings:
      merged[k] = v
    tokenNodes[selector] = merged
  else:
    tokenNodes[selector] = settings

proc parseVsCodeThemeJson(
    entry: JsonNode, packageJsonPath: string
): Result[JsonNode, string] =
  ## The theme file a `contributes.themes` entry of the package at
  ## `packageJsonPath` names, its includes resolved. The error says why it
  ## cannot be read.
  let themePath = entry{"path"}
  if themePath == nil or themePath.kind != JString:
    return err(packageJsonPath & " gives the theme no path")

  let
    themeFilePath = parentDir(packageJsonPath) / themePath.getStr()
    loaded = ?readThemeFile(themeFilePath)
    realPath = ?realThemePath(themeFilePath)
  resolveThemeIncludes(loaded, parentDir(themeFilePath), @[realPath])

proc scopeSelectors(scope: JsonNode): seq[string] =
  ## A rule's `scope`: an array of selectors or a comma-separated string.
  ## Selectors with a context ("source.js keyword", "a - b") are dropped:
  ## moe has no scope stack to match them against.
  let items =
    if scope.kind == JArray:
      scope.getElems
    else:
      @[scope]
  for item in items:
    for s in item.getStr.split(','):
      let selector = s.strip
      if selector.len > 0 and not selector.contains(Whitespace):
        result.add selector

proc makeColorThemeFromVSCodeThemeFile(
    jsonNode: JsonNode, kind = vtkDark
): ThemeColors =
  ## moe's colors for a VS Code theme of `kind`. A color the theme leaves out
  ## takes VS Code's default for that kind, and what VS Code has no color for
  ## comes from moe's bundled theme as bright as the editor background.

  var vs = VsColors(colors: jsonNode{"colors"}, kind: kind)
  # The background, not the kind: a theme may declare none, and dark is assumed.
  let editorBg = vs.rgba("editor.background")
  result =
    if editorBg.isSome and editorBg.get.rgb.isLightColor: LightColors else: DefaultColors
  let baseBg = result[I.default].background.rgb
  vs.surface = editorBg.over(baseBg).get(baseBg)

  var tokenNodes = initTable[string, JsonNode]()
  let tokenColors = jsonNode{"tokenColors"}
  if tokenColors != nil and tokenColors.kind == JArray:
    for node in tokenColors:
      let settings = node{"settings"}
      if settings == nil or settings.kind != JObject:
        continue
      let scope = node{"scope"}
      if scope.isUnscoped:
        tokenNodes.addTokenRule("unnamedScope", settings)
      else:
        for selector in scope.scopeSelectors:
          tokenNodes.addTokenRule(selector, settings)

  proc token(scope: string): Option[Rgb] =
    vs.blended(tokenNodes.findTokenSettings(scope), "foreground")

  let
    # Unblended: pairs blend text onto their own background.
    editorText = vs.rgba("editor.foreground")
    editorFg = editorText.over(vs.surface)
    # High contrast themes give selected text its own color.
    selectionFg = vs.rgba("editor.selectionForeground").orElse(editorText)
    selectionBg = vs.color("editor.selectionBackground")
  result.setFg(editorFg, [I.default, I.commandLine, I.file])

  # The editor background replaces the base's, keeping entries that differ
  # from it on purpose (status line, selection, search result...).
  for idx in EditorColorPairIndex:
    if result[idx].background.rgb == baseBg:
      result[idx].background = ThemeColor(rgb: vs.surface)

  # Text no rule colors is the editor's, as in VS Code.
  for (index, scopes) in TokenScopes:
    var c = editorFg
    for scope in scopes:
      let fg = token(scope)
      if fg.isSome:
        c = fg
        break
    result.setFg(c, [index])

  result.setFg(vs.color("editorWhitespace.foreground"), [I.whitespace])
  let lineNumBg = vs.background("editorLineNumber.background")
  result.setPair(vs.rgba("editorLineNumber.foreground"), lineNumBg, [I.lineNum])
  result.setPair(
    vs.rgba("editorLineNumber.activeForeground"), lineNumBg, [I.currentLineNum]
  )

  let
    statusFg = vs.rgba("statusBar.foreground")
    statusBg = vs.background("statusBar.background")
  for index in StatusLineColorIndexes:
    result.setPair(statusFg, statusBg, [index])

  result.setPair(
    vs.rgba("tab.inactiveForeground"), vs.background("tab.inactiveBackground"), [I.tab]
  )
  result.setPair(
    vs.rgba("tab.activeForeground"),
    vs.background("tab.activeBackground"),
    [I.currentTab],
  )

  result.setPair(selectionFg, selectionBg, [I.selectArea, I.currentWord, I.currentFile])
  let bracketFg =
    themeRgba(tokenNodes.getOrDefault("unnamedScope"), "bracketsForeground")
  result.setPair(bracketFg.orElse(selectionFg), selectionBg, [I.parenPair])

  # Where high contrast themes have no background for these, VS Code draws a
  # border, which a terminal cannot; moe's own highlight stays.
  result.setPair(
    editorText,
    vs.color("editor.findMatchHighlightBackground"),
    [I.searchResult, I.findCharMatch],
  )
  # VS Code has no column highlight; use the line's. Only the background shows.
  result.setBg(vs.lineHighlight, [I.currentLineBg, I.currentColumnBg])
  result.setPair(
    editorText, vs.color("merge.currentContentBackground"), [I.gitConflictOurs]
  )
  result.setPair(
    editorText, vs.color("merge.currentHeaderBackground"), [I.gitConflictMarker]
  )
  result.setPair(
    editorText, vs.color("merge.incomingContentBackground"), [I.gitConflictTheirs]
  )
  result.setPair(
    editorText, vs.color("merge.commonContentBackground"), [I.gitConflictBase]
  )
  # The :s preview shows replacements as VS Code's search view does.
  result.setPair(
    editorText, vs.color("diffEditor.insertedTextBackground"), [I.replaceText]
  )

  result.setFg(
    vs.color("gitDecoration.addedResourceForeground"),
    [I.diffViewerAddedLine, I.sidebarGitAddedSign],
  )
  result.setFg(
    vs.color("gitDecoration.deletedResourceForeground"),
    [I.diffViewerDeletedLine, I.sidebarGitDeletedSign],
  )
  result.setFg(
    vs.color("gitDecoration.modifiedResourceForeground"), [I.sidebarGitChangedSign]
  )
  result.setFg(
    vs.color("gitDecoration.conflictingResourceForeground"),
    [I.sidebarGitConflictSign, I.gitConflict],
  )

  result.setFg(
    vs.color("editorError.foreground"),
    [I.errorMessage, I.syntaxCheckErr, I.sidebarSyntaxCheckErrSign],
  )
  result.setFg(
    vs.color("editorWarning.foreground"),
    [I.warnMessage, I.syntaxCheckWarn, I.sidebarSyntaxCheckWarnSign],
  )
  result.setFg(
    vs.color("editorInfo.foreground"),
    [
      I.syntaxCheckInfo, I.syntaxCheckHint, I.sidebarSyntaxCheckInfoSign,
      I.sidebarSyntaxCheckHintSign,
    ],
  )

  result.setPair(
    vs.rgba("editorInlayHint.foreground"),
    vs.color("editorInlayHint.background"),
    [I.inlayHint],
  )
  result.setFg(vs.color("editorCodeLens.foreground"), [I.codeLens])

  let popupBg = vs.color("editorSuggestWidget.background")
  result.setPair(vs.rgba("editorSuggestWidget.foreground"), popupBg, [I.popupWindow])
  # The selected item sits on the widget, not on the editor.
  result.setPair(
    vs.rgba("editorSuggestWidget.selectedForeground"),
    vs.rgba("editorSuggestWidget.selectedBackground").over(popupBg.get(vs.surface)),
    [I.popupWinCurrentLine],
  )
  # A manager's current line is VS Code's selected list item.
  result.setPair(
    vs.rgba("list.activeSelectionForeground"),
    vs.color("list.activeSelectionBackground"),
    [I.backupManagerCurrentLine, I.recoveryManagerCurrentLine, I.configModeCurrentLine],
  )

  # A link as the Markdown grammar scopes it, which themes color.
  result.setFg(token("markup.underline.link.markdown"), [I.dir, I.pcLink])

  # VS Code has no color for marking blanks, so moe's own highlight stays.
  # Border colors such as tab.activeBorder often match the editor background.

proc userPackageFiles(dir: string): seq[string] =
  ## The package.json of each extension installed in the user dir `dir`.
  ## VS Code loads the ones its extensions.json lists: a folder it leaves out
  ## is an old version not yet deleted. Without the list every folder counts.
  try:
    let list = json.parseFile(dir / "extensions.json")
    if list.kind == JArray:
      for e in list:
        let relative = e{"relativeLocation"}
        let absolute = e{"location", "path"}
        if relative != nil and relative.kind == JString and relative.getStr.len > 0:
          result.add dir / relative.getStr / "package.json"
        elif absolute != nil and absolute.kind == JString:
          result.add absolute.getStr / "package.json"
      return
  except CatchableError:
    discard
  toSeq(walkPattern(dir / "*/package.json"))

proc isNewerVersion(a, b: string): bool =
  ## Whether version `a` is newer than `b`, number by number. Pre-release tags
  ## are not compared.
  proc numbers(v: string): seq[int] =
    for part in v.split({'-', '+'})[0].split('.'):
      result.add(
        try:
          parseInt(part)
        except ValueError:
          0
      )

  var (x, y) = (numbers(a), numbers(b))
  # A missing number is 0: 1.2 is 1.2.0.
  let width = max(x.len, y.len)
  x.setLen(width)
  y.setLen(width)
  for i in 0 ..< width:
    if x[i] != y[i]:
      return x[i] > y[i]

type ThemePackage = object
  path: string ## package.json
  theme: JsonNode ## Its `contributes.themes` entry for the theme
  id: string ## The extension, as VS Code tells extensions apart
  version: string

proc themePackage(path: string, json, theme: JsonNode): ThemePackage =
  let publisher = json{"publisher"}.getStr
  let name = json{"name"}.getStr
  let id =
    if publisher.len > 0 and name.len > 0:
      toLowerAscii(publisher & "." & name)
    else:
      path
  ThemePackage(path: path, theme: theme, id: id, version: json{"version"}.getStr)

proc loadFlavorTheme(flavor: VsCodeFlavor): Result[ThemeColors, string] =
  ## The theme `flavor` has active. The error says what was looked for and
  ## where.

  let
    settingsFilePath = vsCodeSettingsFilePath(flavor)
    settingsJson =
      try:
        let text =
          if fileExists(settingsFilePath):
            readFile(settingsFilePath)
          else:
            ""
        # VS Code takes a missing or blank file as no settings.
        if text.isEmptyOrWhitespace:
          newJObject()
        else:
          parseJson(text)
      except CatchableError as e:
        return Result[ThemeColors, string].err(
          "cannot read " & settingsFilePath & ": " & e.msg
        )

  # The current theme name.
  # 1. Check settings.json (explicit user setting)
  # 2. Check state.vscdb (VSCode stores the active theme here)
  # 3. Fall back to "Default Dark Modern"
  let currentThemeName =
    if settingsJson{"workbench.colorTheme"} != nil and
        settingsJson{"workbench.colorTheme"}.getStr != "":
      settingsJson{"workbench.colorTheme"}.getStr
    else:
      let stateDbPath = vsCodeStateDbPath(flavor)
      let fromState = readThemeNameFromStateDb(stateDbPath)
      if fromState.isSome: fromState.get else: "Default Dark Modern"

  let
    userDir = vsCodeUserExtensionsDir(flavor)
    extensionDirs = vsCodeBuiltinExtensionsDirs(flavor) & userDir

  var
    searched: seq[string] = @[]
    # One version of each extension: the newest, a built-in one at a tie, as
    # VS Code picks. Built-in dirs come first.
    packages: seq[ThemePackage] = @[]
  for dir in extensionDirs:
    if not dirExists(dir):
      continue
    searched.add dir
    let files =
      if dir == userDir:
        userPackageFiles(dir)
      else:
        toSeq(walkPattern(dir / "*/package.json"))
    for file in files:
      let packageJson =
        try:
          json.parseFile(file)
        except CatchableError:
          continue
      let theme = packageJson.themeEntry(currentThemeName)
      if theme == nil:
        continue
      let package = themePackage(file, packageJson, theme)
      var known = false
      for p in packages.mitems:
        if p.id == package.id:
          known = true
          if package.version.isNewerVersion(p.version):
            p = package
          break
      if not known:
        packages.add package

  var unreadable: seq[string] = @[] ## Why the packages declaring the theme failed
  for package in packages:
    let themeJson = parseVsCodeThemeJson(package.theme, package.path)
    if themeJson.isOk:
      let colors =
        makeColorThemeFromVSCodeThemeFile(themeJson.get, package.theme.themeKind)
      return Result[ThemeColors, string].ok(colors)
    unreadable.add themeJson.error

  if unreadable.len > 0:
    return Result[ThemeColors, string].err(
      fmt"cannot read theme '{currentThemeName}': " & unreadable.join("; ")
    )

  let where =
    if searched.len > 0:
      "searched " & searched.join(", ")
    else:
      "none of " & extensionDirs.join(", ") & " exists"
  return
    Result[ThemeColors, string].err(fmt"theme '{currentThemeName}' not found ({where})")

proc loadVSCodeTheme*(): Result[ThemeColors, string] =
  ## Load the active theme of the most recently used of VSCodium, Code - OSS
  ## and VS Code. Its failure is reported, not another one's theme loaded:
  ## that would be another editor's colors with nothing to say why. The error
  ## says what was looked for and where.

  let flavor = vsCodeFlavorInUse()
  if flavor.isNone:
    var dirs: seq[string] = @[]
    for f in VsCodeFlavor:
      dirs.add vsCodeUserDataDir(f) / "User"
    return Result[ThemeColors, string].err(
      "no VS Code settings.json or globalStorage/state.vscdb (looked in " &
        dirs.join(", ") & ")"
    )

  loadFlavorTheme(flavor.get)
