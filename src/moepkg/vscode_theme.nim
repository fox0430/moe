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

import std/[os, options, tables, json, strformat, strutils]
import pkg/results

import color, theme

type VsCodeFlavor* = enum
  VSCodium
  CodeOss
  VSCode

# VSCodium paths
proc vsCodiumUserSettingsFilePath(): string {.inline.} =
  getHomeDir() / ".config/VSCodium/User/settings.json"

proc vsCodiumDefaultExtensionsDir(): string {.inline.} =
  "/opt/vscodium-bin/resources/app/extensions"

proc vsCodiumUserExtensionsDir(): string {.inline.} =
  getHomeDir() / ".vscode-oss/extensions"

# Code-OSS paths
proc codeOssUserSettingsFilePath(): string {.inline.} =
  getHomeDir() / ".config/Code - OSS/User/settings.json"

proc codeOssDefaultExtensionsDir(): string {.inline.} =
  "/usr/lib/code/extensions"

proc codeOssUserExtensionsDir(): string {.inline.} =
  getHomeDir() / ".vscode-oss/extensions"

# VSCode paths
proc vsCodeUserSettingsFilePath(): string {.inline.} =
  getHomeDir() / ".config/Code/User/settings.json"

proc vsCodeDefaultExtensionsDir(): string {.inline.} =
  "/opt/visual-studio-code/resources/app/extensions"

proc vsCodeUserExtensionsDir(): string {.inline.} =
  getHomeDir() / ".vscode/extensions"

proc vsCodeStateDbPath(flavor: VsCodeFlavor): string =
  case flavor
  of VsCodeFlavor.VSCodium:
    return getHomeDir() / ".config/VSCodium/User/globalStorage/state.vscdb"
  of VsCodeFlavor.CodeOss:
    return getHomeDir() / ".config/Code - OSS/User/globalStorage/state.vscdb"
  of VsCodeFlavor.VSCode:
    return getHomeDir() / ".config/Code/User/globalStorage/state.vscdb"

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

proc vsCodeSettingsFilePath(flavor: VsCodeFlavor): string =
  case flavor
  of VsCodeFlavor.VSCodium:
    return vsCodiumUserSettingsFilePath()
  of VsCodeFlavor.CodeOss:
    return codeOssUserSettingsFilePath()
  of VsCodeFlavor.VSCode:
    return vsCodeUserSettingsFilePath()

proc vsCodeUserExtensionsDir(flavor: VsCodeFlavor): string =
  case flavor
  of VsCodeFlavor.VSCodium:
    return vsCodiumUserExtensionsDir()
  of VsCodeFlavor.CodeOss:
    return codeOssUserExtensionsDir()
  of VsCodeFlavor.VSCode:
    return vsCodeUserExtensionsDir()

proc vsCodeDefaultExtensionsDir(flavor: VsCodeFlavor): string =
  case flavor
  of VsCodeFlavor.VSCodium:
    return vsCodiumDefaultExtensionsDir()
  of VsCodeFlavor.CodeOss:
    return codeOssDefaultExtensionsDir()
  of VsCodeFlavor.VSCode:
    return vsCodeDefaultExtensionsDir()

proc detectVsCodeFlavor(): Option[VsCodeFlavor] =
  ## Check settings dirs in the following order.
  ## vscodium -> code-oss -> vscode

  if fileExists(vsCodiumUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCodium)
  elif fileExists(codeOssUserSettingsFilePath()):
    return some(VsCodeFlavor.CodeOss)
  elif fileExists(vsCodeUserSettingsFilePath()):
    return some(VsCodeFlavor.VSCode)

proc colorFromNode(node: JsonNode): Rgb =
  ## Parse a color from a JSON node.
  ## Returns TerminalDefaultRgb if node is nil or invalid.

  if node == nil:
    return TerminalDefaultRgb

  var asString = node.getStr
  if asString.len >= 7 and asString[0] == '#':
    # Indexes above 6 are cut (handles #RRGGBBAA format).
    let r = hexToRgb(asString[0 .. 6])
    if r.isOk:
      return r.get
    else:
      return TerminalDefaultRgb
  else:
    return TerminalDefaultRgb

proc matchesThemeName(theme: JsonNode, themeName: string): bool =
  ## Check if a theme entry matches the given name by label or id.
  if theme{"label"} != nil and theme{"label"}.getStr == themeName:
    return true
  if theme{"id"} != nil and theme{"id"}.getStr == themeName:
    return true

proc isCurrentVsCodeThemePackage(json: JsonNode, themeName: string): bool =
  ## Return true if `json` is the current VSCode theme.

  let themes = json{"contributes", "themes"}
  if themes != nil and themes.kind == JArray:
    for t in themes:
      if t.matchesThemeName(themeName):
        return true

proc resolveThemeIncludes(themeJson: JsonNode, themeDir: string): JsonNode =
  ## Resolve the `include` chain in a VSCode theme file.
  ## Merges colors and tokenColors from included (base) themes,
  ## with the current file's values taking priority.

  let includeNode = themeJson{"include"}
  if includeNode == nil or includeNode.kind != JString:
    return themeJson

  let includePath = themeDir / includeNode.getStr
  if not fileExists(includePath):
    return themeJson

  let baseJson =
    try:
      resolveThemeIncludes(json.parseFile(includePath), parentDir(includePath))
    except CatchableError:
      return themeJson

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

  result = newJObject()
  result["colors"] = mergedColors
  result["tokenColors"] = mergedTokenColors

proc findTokenSettings(tokenNodes: Table[string, JsonNode], scope: string): JsonNode =
  ## Find the best matching token settings for a scope using TextMate-style
  ## hierarchical matching.
  ##
  ## Priority: exact match > longest parent scope > shortest child scope.
  ## Returns nil if no match found.

  # 1. Exact match
  if scope in tokenNodes:
    return tokenNodes[scope]

  # 2. Longest parent scope (theme scope is a prefix of target)
  # e.g., scope="entity.name.function", theme has "entity" -> match
  var bestParentLen = 0
  var bestParent: JsonNode
  for key, val in tokenNodes:
    if scope.startsWith(key & ".") and key.len > bestParentLen:
      bestParentLen = key.len
      bestParent = val
  if bestParentLen > 0:
    return bestParent

  # 3. Shortest child scope (target is a prefix of theme scope)
  # e.g., scope="keyword", theme has "keyword.control" -> match
  var bestChildLen = int.high
  var bestChild: JsonNode
  for key, val in tokenNodes:
    if key.startsWith(scope & ".") and key.len < bestChildLen:
      bestChildLen = key.len
      bestChild = val
  if bestChildLen < int.high:
    return bestChild

proc parseVsCodeThemeJson(
    packageJson: JsonNode, themeName, extensionDir: string
): Option[JsonNode] =
  let themesJson = packageJson{"contributes", "themes"}
  if themesJson != nil and themesJson.kind == JArray:
    for theme in themesJson:
      if theme.matchesThemeName(themeName):
        let themePath = theme{"path"}

        if themePath != nil and themePath.kind == JString:
          let themeFilePath = parentDir(extensionDir) / themePath.getStr()

          if fileExists(themeFilePath):
            result =
              try:
                let raw = json.parseFile(themeFilePath)
                some(resolveThemeIncludes(raw, parentDir(themeFilePath)))
              except CatchableError:
                none(JsonNode)

proc makeColorThemeFromVSCodeThemeFile(jsonNode: JsonNode): ThemeColors =
  ## Load the theme file of VSCode and adapt it as the theme of moe.
  ## Reproduce the original theme as much as possible.

  # The base theme is the default theme.
  result = DefaultColors

  var tokenNodes = initTable[string, JsonNode]()
  if jsonNode{"tokenColors"} != nil:
    for node in jsonNode{"tokenColors"}:
      var scope = node{"scope"}
      let settings = node{"settings"}
      if scope == nil:
        scope = parseJson("\"unnamedScope\"")
      if settings == nil:
        continue
      if scope.len() > 0:
        for item in scope:
          tokenNodes[item.getStr()] = settings
      else:
        tokenNodes[scope.getStr()] = settings

  let colors = jsonNode{"colors"}

  # Editor foreground
  if colors != nil and colors.contains("editor.foreground"):
    let fg = colorFromNode(colors{"editor.foreground"})

    result[EditorColorPairIndex.default].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.commandLine].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.currentWord].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.replaceText].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.currentFile].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.searchResult].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.selectArea].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.file].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.identifier].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.variable].foreground = ThemeColor(rgb: fg)

  # Editor background
  # Apply to all elements that still have the default editor background,
  # preserving elements with intentionally different backgrounds
  # (e.g., statusLine, selectArea, searchResult).
  if colors != nil and colors.contains("editor.background"):
    let bg = colorFromNode(colors{"editor.background"})
    let defaultBg = DefaultColors[EditorColorPairIndex.default].background.rgb
    for idx in EditorColorPairIndex:
      if result[idx].background.rgb == defaultBg:
        result[idx].background = ThemeColor(rgb: bg)

  # Token colors - keyword
  block:
    let s = tokenNodes.findTokenSettings("keyword")
    if s != nil:
      result[EditorColorPairIndex.keyword].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Token colors - entity (function, type, etc.)
  block:
    let s = tokenNodes.findTokenSettings("entity")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.functionName].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.typeName].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.boolean].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.builtin].foreground = ThemeColor(rgb: fg)

  # Token colors - entity.name.function
  block:
    let s = tokenNodes.findTokenSettings("entity.name.function")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.functionName].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.function].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.`method`].foreground = ThemeColor(rgb: fg)

  # Token colors - entity.name.type
  block:
    let s = tokenNodes.findTokenSettings("entity.name.type")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.typeName].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.className].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.interfaceName].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.builtinType].foreground = ThemeColor(rgb: fg)

  # Token colors - string
  block:
    let s = tokenNodes.findTokenSettings("string")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.stringLit].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.charLit].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.lspString].foreground = ThemeColor(rgb: fg)

  # Token colors - variable
  block:
    let s = tokenNodes.findTokenSettings("variable")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.specialVar].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.variable].foreground = ThemeColor(rgb: fg)

  # Token colors - constant
  block:
    let s = tokenNodes.findTokenSettings("constant")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.binNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.decNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.floatNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.hexNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.octNumber].foreground = ThemeColor(rgb: fg)

  # Token colors - constant.numeric
  block:
    let s = tokenNodes.findTokenSettings("constant.numeric")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.binNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.decNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.floatNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.hexNumber].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.octNumber].foreground = ThemeColor(rgb: fg)

  # Token colors - comment
  block:
    let s = tokenNodes.findTokenSettings("comment")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.comment].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.longComment].foreground = ThemeColor(rgb: fg)

  # Whitespace foreground
  if colors != nil and colors.contains("editorWhitespace.foreground"):
    result[EditorColorPairIndex.whitespace].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorWhitespace.foreground"}))

  # Line number foreground
  if colors != nil and colors.contains("editorLineNumber.foreground"):
    result[EditorColorPairIndex.lineNum].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorLineNumber.foreground"}))

  # Active line number foreground
  if colors != nil and colors.contains("editorLineNumber.activeForeground"):
    result[EditorColorPairIndex.currentLineNum].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorLineNumber.activeForeground"}))

  # Status bar colors
  if colors != nil and colors.contains("statusBar.foreground"):
    let fg = colorFromNode(colors{"statusBar.foreground"})
    result[EditorColorPairIndex.statusLineNormalMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineNormalModeLabel].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineNormalModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineInsertMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineInsertModeLabel].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineInsertModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineVisualMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineVisualModeLabel].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineVisualModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineReplaceMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineReplaceModeLabel].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineReplaceModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineFilerMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineFilerModeLabel].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineFilerModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineExMode].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineExModeLabel].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineExModeInactive].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineGitChangedLines].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.statusLineGitBranch].foreground = ThemeColor(rgb: fg)

  if colors != nil and colors.contains("statusBar.background"):
    let bg = colorFromNode(colors{"statusBar.background"})
    result[EditorColorPairIndex.statusLineNormalMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineNormalModeLabel].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineNormalModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineInsertMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineInsertModeLabel].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineInsertModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineVisualMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineVisualModeLabel].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineVisualModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineReplaceMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineReplaceModeLabel].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineReplaceModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineFilerMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineFilerModeLabel].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineFilerModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineExMode].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineExModeLabel].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineExModeInactive].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineGitChangedLines].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.statusLineGitBranch].background = ThemeColor(rgb: bg)

  # Tab bar colors
  if colors != nil and colors.contains("tab.inactiveForeground"):
    result[EditorColorPairIndex.tab].foreground =
      ThemeColor(rgb: colorFromNode(colors{"tab.inactiveForeground"}))
  if colors != nil and colors.contains("tab.inactiveBackground"):
    result[EditorColorPairIndex.tab].background =
      ThemeColor(rgb: colorFromNode(colors{"tab.inactiveBackground"}))
  if colors != nil and colors.contains("tab.activeForeground"):
    result[EditorColorPairIndex.currentTab].foreground =
      ThemeColor(rgb: colorFromNode(colors{"tab.activeForeground"}))
  if colors != nil and colors.contains("tab.activeBackground"):
    result[EditorColorPairIndex.currentTab].background =
      ThemeColor(rgb: colorFromNode(colors{"tab.activeBackground"}))

  # Selection color
  if colors != nil and colors.contains("editor.selectionBackground"):
    let selBg = colorFromNode(colors{"editor.selectionBackground"})
    result[EditorColorPairIndex.selectArea].background = ThemeColor(rgb: selBg)
    result[EditorColorPairIndex.currentWord].background = ThemeColor(rgb: selBg)
    result[EditorColorPairIndex.parenPair].background = ThemeColor(rgb: selBg)
    result[EditorColorPairIndex.currentFile].background = ThemeColor(rgb: selBg)

  # Search highlight
  if colors != nil and colors.contains("editor.findMatchHighlightBackground"):
    result[EditorColorPairIndex.searchResult].background =
      ThemeColor(rgb: colorFromNode(colors{"editor.findMatchHighlightBackground"}))

  # Current line background
  if colors != nil and colors.contains("editor.lineHighlightBackground"):
    result[EditorColorPairIndex.currentLineBg].background =
      ThemeColor(rgb: colorFromNode(colors{"editor.lineHighlightBackground"}))
    # Use same color for column highlight (VSCode has no separate setting)
    result[EditorColorPairIndex.currentColumnBg].background =
      ThemeColor(rgb: colorFromNode(colors{"editor.lineHighlightBackground"}))

  # Git diff colors
  if colors != nil and colors.contains("gitDecoration.addedResourceForeground"):
    result[EditorColorPairIndex.diffViewerAddedLine].foreground =
      ThemeColor(rgb: colorFromNode(colors{"gitDecoration.addedResourceForeground"}))
    result[EditorColorPairIndex.sidebarGitAddedSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"gitDecoration.addedResourceForeground"}))
  if colors != nil and colors.contains("gitDecoration.deletedResourceForeground"):
    result[EditorColorPairIndex.diffViewerDeletedLine].foreground =
      ThemeColor(rgb: colorFromNode(colors{"gitDecoration.deletedResourceForeground"}))
    result[EditorColorPairIndex.sidebarGitDeletedSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"gitDecoration.deletedResourceForeground"}))
  if colors != nil and colors.contains("gitDecoration.modifiedResourceForeground"):
    result[EditorColorPairIndex.sidebarGitChangedSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"gitDecoration.modifiedResourceForeground"}))

  # Error/Warning colors
  if colors != nil and colors.contains("editorError.foreground"):
    result[EditorColorPairIndex.errorMessage].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorError.foreground"}))
    result[EditorColorPairIndex.syntaxCheckErr].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorError.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckErrSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorError.foreground"}))
  if colors != nil and colors.contains("editorWarning.foreground"):
    result[EditorColorPairIndex.warnMessage].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorWarning.foreground"}))
    result[EditorColorPairIndex.syntaxCheckWarn].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorWarning.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckWarnSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorWarning.foreground"}))
  if colors != nil and colors.contains("editorInfo.foreground"):
    result[EditorColorPairIndex.syntaxCheckInfo].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorInfo.foreground"}))
    result[EditorColorPairIndex.syntaxCheckHint].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorInfo.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckInfoSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorInfo.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckHintSign].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorInfo.foreground"}))

  # Operator
  block:
    let s = tokenNodes.findTokenSettings("keyword.operator")
    if s != nil:
      result[EditorColorPairIndex.operator].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Namespace/module
  block:
    let s = tokenNodes.findTokenSettings("entity.name.namespace")
    if s != nil:
      result[EditorColorPairIndex.namespace].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Decorator/attribute
  block:
    let s = tokenNodes.findTokenSettings("entity.name.function.decorator")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.decorator].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.attribute].foreground = ThemeColor(rgb: fg)

  # Preprocessor
  block:
    let s = tokenNodes.findTokenSettings("keyword.control.directive")
    if s != nil:
      result[EditorColorPairIndex.preprocessor].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))
  block:
    let s = tokenNodes.findTokenSettings("meta.preprocessor")
    if s != nil:
      result[EditorColorPairIndex.preprocessor].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Macro
  block:
    let s = tokenNodes.findTokenSettings("entity.name.function.macro")
    if s != nil:
      result[EditorColorPairIndex.`macro`].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Enum
  block:
    let s = tokenNodes.findTokenSettings("entity.name.type.enum")
    if s != nil:
      result[EditorColorPairIndex.enumName].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))
  block:
    let s = tokenNodes.findTokenSettings("variable.other.enummember")
    if s != nil:
      result[EditorColorPairIndex.enumMember].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Property
  block:
    let s = tokenNodes.findTokenSettings("variable.other.property")
    if s != nil:
      result[EditorColorPairIndex.property].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Parameter
  block:
    let s = tokenNodes.findTokenSettings("variable.parameter")
    if s != nil:
      result[EditorColorPairIndex.parameter].foreground =
        ThemeColor(rgb: colorFromNode(s{"foreground"}))

  # Inlay hints
  if colors != nil and colors.contains("editorInlayHint.foreground"):
    result[EditorColorPairIndex.inlayHint].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorInlayHint.foreground"}))
  if colors != nil and colors.contains("editorInlayHint.background"):
    result[EditorColorPairIndex.inlayHint].background =
      ThemeColor(rgb: colorFromNode(colors{"editorInlayHint.background"}))

  # Code lens
  if colors != nil and colors.contains("editorCodeLens.foreground"):
    result[EditorColorPairIndex.codeLens].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorCodeLens.foreground"}))

  # Cursor foreground (used for current line num and other highlights)
  if colors != nil and colors.contains("editorCursor.foreground"):
    let fg = colorFromNode(colors{"editorCursor.foreground"})
    result[EditorColorPairIndex.currentLineNum].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.backupManagerCurrentLine].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.configModeCurrentLine].foreground = ThemeColor(rgb: fg)

  # Suggest widget (popup window)
  if colors != nil and colors.contains("editorSuggestWidget.foreground"):
    result[EditorColorPairIndex.popupWindow].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorSuggestWidget.foreground"}))
  if colors != nil and colors.contains("editorSuggestWidget.background"):
    result[EditorColorPairIndex.popupWindow].background =
      ThemeColor(rgb: colorFromNode(colors{"editorSuggestWidget.background"}))
  if colors != nil and colors.contains("editorSuggestWidget.highlightForeground"):
    result[EditorColorPairIndex.popupWinCurrentLine].foreground =
      ThemeColor(rgb: colorFromNode(colors{"editorSuggestWidget.highlightForeground"}))
  if colors != nil and colors.contains("editorSuggestWidget.selectedBackground"):
    result[EditorColorPairIndex.popupWinCurrentLine].background =
      ThemeColor(rgb: colorFromNode(colors{"editorSuggestWidget.selectedBackground"}))

  # Git conflict
  if colors != nil and colors.contains("gitDecoration.conflictingResourceForeground"):
    result[EditorColorPairIndex.gitConflict].foreground = ThemeColor(
      rgb: colorFromNode(colors{"gitDecoration.conflictingResourceForeground"})
    )
    result[EditorColorPairIndex.replaceText].background = ThemeColor(
      rgb: colorFromNode(colors{"gitDecoration.conflictingResourceForeground"})
    )

  # Hyperlink (for filer mode)
  block:
    let s = tokenNodes.findTokenSettings("markup.underline.link")
    if s != nil:
      let fg = colorFromNode(s{"foreground"})
      result[EditorColorPairIndex.dir].foreground = ThemeColor(rgb: fg)
      result[EditorColorPairIndex.pcLink].foreground = ThemeColor(rgb: fg)

  # Tab active border (used for highlight spaces)
  if colors != nil and colors.contains("tab.activeBorder"):
    let color = colorFromNode(colors{"tab.activeBorder"})
    result[EditorColorPairIndex.highlightFullWidthSpace].background =
      ThemeColor(rgb: color)
    result[EditorColorPairIndex.highlightTrailingSpaces].background =
      ThemeColor(rgb: color)

  # Line number background
  if colors != nil and colors.contains("editorLineNumber.background"):
    result[EditorColorPairIndex.lineNum].background =
      ThemeColor(rgb: colorFromNode(colors{"editorLineNumber.background"}))

  # Paren pair foreground from bracket colors
  if tokenNodes.hasKey("unnamedScope"):
    let bracketFg = tokenNodes["unnamedScope"]{"bracketsForeground"}
    if bracketFg != nil:
      result[EditorColorPairIndex.parenPair].foreground =
        ThemeColor(rgb: colorFromNode(bracketFg))

proc loadVSCodeTheme*(): Result[ThemeColors, string] =
  ## Load the current VSCode theme.
  ## Detects VSCodium, Code-OSS, or VSCode and loads the active theme.
  ## Returns an error if no VSCode installation is found or theme can't be loaded.

  let vsCodeFlavor = detectVsCodeFlavor()
  if vsCodeFlavor.isNone:
    return Result[ThemeColors, string].err(
      "Failed to load VSCode theme: Could not find VSCode/VSCodium/Code-OSS installation"
    )

  let
    # load the VSCode user settings json
    settingsFilePath = vsCodeSettingsFilePath(vsCodeFlavor.get)
    settingsJson =
      try:
        json.parseFile(settingsFilePath)
      except CatchableError as e:
        return
          Result[ThemeColors, string].err(fmt"Failed to load VSCode theme: {e.msg}")

  # The current theme name.
  # 1. Check settings.json (explicit user setting)
  # 2. Check state.vscdb (VSCode stores the active theme here)
  # 3. Fall back to "Default Dark Modern"
  let currentThemeName =
    if settingsJson{"workbench.colorTheme"} != nil and
        settingsJson{"workbench.colorTheme"}.getStr != "":
      settingsJson{"workbench.colorTheme"}.getStr
    else:
      let stateDbPath = vsCodeStateDbPath(vsCodeFlavor.get)
      let fromState = readThemeNameFromStateDb(stateDbPath)
      if fromState.isSome: fromState.get else: "Default Dark Modern"

  let extensionDirs = [
    # Built in themes.
    vsCodeDefaultExtensionsDir(vsCodeFlavor.get),
    # User themes.
    vsCodeUserExtensionsDir(vsCodeFlavor.get),
  ]

  for dir in extensionDirs:
    if dirExists(dir):
      for file in walkPattern(dir / "*/package.json"):
        let packageJson =
          try:
            json.parseFile(file)
          except CatchableError:
            continue

        if isCurrentVsCodeThemePackage(packageJson, currentThemeName):
          let themeJson = parseVsCodeThemeJson(packageJson, currentThemeName, file)
          if themeJson.isSome:
            let colors = makeColorThemeFromVSCodeThemeFile(themeJson.get)
            return Result[ThemeColors, string].ok(colors)

  return Result[ThemeColors, string].err(
    fmt"Failed to load VSCode theme: Could not find theme '{currentThemeName}'"
  )
