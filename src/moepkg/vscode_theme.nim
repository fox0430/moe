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

import std/[os, options, tables, json, strformat]
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

proc isCurrentVsCodeThemePackage(json: JsonNode, themeName: string): bool =
  ## Return true if `json` is the current VSCode theme.

  if json{"contributes", "themes"} != nil:
    let themes = json{"contributes", "themes"}
    if themes != nil and themes.kind == JArray:
      for t in themes:
        if t{"label"} != nil and t{"label"}.getStr == themeName:
          return true

proc parseVsCodeThemeJson(
    packageJson: JsonNode, themeName, extensionDir: string
): Option[JsonNode] =
  let themesJson = packageJson{"contributes", "themes"}
  if themesJson != nil and themesJson.kind == JArray:
    for theme in themesJson:
      if theme{"label"} != nil and theme{"label"}.getStr == themeName:
        let themePath = theme{"path"}

        if themePath != nil and themePath.kind == JString:
          let themeFilePath = parentDir(extensionDir) / themePath.getStr()

          if fileExists(themeFilePath):
            result =
              try:
                some(json.parseFile(themeFilePath))
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

  # Editor foreground
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("editor.foreground"):
    let fg = colorFromNode(jsonNode{"colors", "editor.foreground"})

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
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("editor.background"):
    let bg = colorFromNode(jsonNode{"colors", "editor.background"})

    result[EditorColorPairIndex.default].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.keyword].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.functionName].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.typeName].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.boolean].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.stringLit].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.specialVar].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.binNumber].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.decNumber].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.floatNumber].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.hexNumber].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.octNumber].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.commandLine].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.errorMessage].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.warnMessage].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.currentLineNum].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.file].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.dir].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.pcLink].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.diffViewerAddedLine].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.diffViewerDeletedLine].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.backupManagerCurrentLine].background =
      ThemeColor(rgb: bg)
    result[EditorColorPairIndex.configModeCurrentLine].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.preprocessor].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.pragma].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.comment].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.longComment].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.identifier].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.variable].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.lineNum].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.charLit].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.builtin].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.popupWindow].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.popupWinCurrentLine].background = ThemeColor(rgb: bg)

  # Token colors - keyword
  if tokenNodes.hasKey("keyword"):
    result[EditorColorPairIndex.keyword].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["keyword"]{"foreground"}))

  # Token colors - entity (function, type, etc.)
  if tokenNodes.hasKey("entity"):
    let fg = colorFromNode(tokenNodes["entity"]{"foreground"})
    result[EditorColorPairIndex.functionName].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.typeName].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.boolean].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.builtin].foreground = ThemeColor(rgb: fg)

  # Token colors - entity.name.function
  if tokenNodes.hasKey("entity.name.function"):
    result[EditorColorPairIndex.functionName].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.function"]{"foreground"}))
    result[EditorColorPairIndex.function].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.function"]{"foreground"}))
    result[EditorColorPairIndex.`method`].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.function"]{"foreground"}))

  # Token colors - entity.name.type
  if tokenNodes.hasKey("entity.name.type"):
    result[EditorColorPairIndex.typeName].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.type"]{"foreground"}))
    result[EditorColorPairIndex.className].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.type"]{"foreground"}))
    result[EditorColorPairIndex.interfaceName].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.type"]{"foreground"}))
    result[EditorColorPairIndex.builtinType].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.type"]{"foreground"}))

  # Token colors - string
  if tokenNodes.hasKey("string"):
    let fg = colorFromNode(tokenNodes["string"]{"foreground"})
    result[EditorColorPairIndex.stringLit].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.charLit].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.lspString].foreground = ThemeColor(rgb: fg)

  # Token colors - variable
  if tokenNodes.hasKey("variable"):
    result[EditorColorPairIndex.specialVar].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["variable"]{"foreground"}))
    result[EditorColorPairIndex.variable].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["variable"]{"foreground"}))

  # Token colors - constant
  if tokenNodes.hasKey("constant"):
    let fg = colorFromNode(tokenNodes["constant"]{"foreground"})
    result[EditorColorPairIndex.binNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.decNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.floatNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.hexNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.octNumber].foreground = ThemeColor(rgb: fg)

  # Token colors - constant.numeric
  if tokenNodes.hasKey("constant.numeric"):
    let fg = colorFromNode(tokenNodes["constant.numeric"]{"foreground"})
    result[EditorColorPairIndex.binNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.decNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.floatNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.hexNumber].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.octNumber].foreground = ThemeColor(rgb: fg)

  # Token colors - comment
  if tokenNodes.hasKey("comment"):
    let fg = colorFromNode(tokenNodes["comment"]{"foreground"})
    result[EditorColorPairIndex.comment].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.longComment].foreground = ThemeColor(rgb: fg)

  # Whitespace foreground
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorWhitespace.foreground"):
    result[EditorColorPairIndex.whitespace].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorWhitespace.foreground"}))

  # Line number foreground
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorLineNumber.foreground"):
    result[EditorColorPairIndex.lineNum].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorLineNumber.foreground"}))

  # Active line number foreground
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorLineNumber.activeForeground"):
    result[EditorColorPairIndex.currentLineNum].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editorLineNumber.activeForeground"})
    )

  # Status bar colors
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("statusBar.foreground"):
    let fg = colorFromNode(jsonNode{"colors", "statusBar.foreground"})
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

  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("statusBar.background"):
    let bg = colorFromNode(jsonNode{"colors", "statusBar.background"})
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
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("tab.inactiveForeground"):
    result[EditorColorPairIndex.tab].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "tab.inactiveForeground"}))
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("tab.inactiveBackground"):
    result[EditorColorPairIndex.tab].background =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "tab.inactiveBackground"}))
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("tab.activeForeground"):
    result[EditorColorPairIndex.currentTab].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "tab.activeForeground"}))
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("tab.activeBackground"):
    result[EditorColorPairIndex.currentTab].background =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "tab.activeBackground"}))

  # Selection color
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editor.selectionBackground"):
    result[EditorColorPairIndex.selectArea].background =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editor.selectionBackground"}))

  # Search highlight
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editor.findMatchHighlightBackground"):
    result[EditorColorPairIndex.searchResult].background = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editor.findMatchHighlightBackground"})
    )

  # Current line background
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editor.lineHighlightBackground"):
    result[EditorColorPairIndex.currentLineBg].background = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editor.lineHighlightBackground"})
    )

  # Git diff colors
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("gitDecoration.addedResourceForeground"):
    result[EditorColorPairIndex.diffViewerAddedLine].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "gitDecoration.addedResourceForeground"})
    )
    result[EditorColorPairIndex.sidebarGitAddedSign].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "gitDecoration.addedResourceForeground"})
    )
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("gitDecoration.deletedResourceForeground"):
    result[EditorColorPairIndex.diffViewerDeletedLine].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "gitDecoration.deletedResourceForeground"})
    )
    result[EditorColorPairIndex.sidebarGitDeletedSign].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "gitDecoration.deletedResourceForeground"})
    )
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("gitDecoration.modifiedResourceForeground"):
    result[EditorColorPairIndex.sidebarGitChangedSign].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "gitDecoration.modifiedResourceForeground"})
    )

  # Error/Warning colors
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("editorError.foreground"):
    result[EditorColorPairIndex.errorMessage].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorError.foreground"}))
    result[EditorColorPairIndex.syntaxCheckErr].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorError.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckErrSign].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorError.foreground"}))
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorWarning.foreground"):
    result[EditorColorPairIndex.warnMessage].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorWarning.foreground"}))
    result[EditorColorPairIndex.syntaxCheckWarn].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorWarning.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckWarnSign].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorWarning.foreground"}))
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("editorInfo.foreground"):
    result[EditorColorPairIndex.syntaxCheckInfo].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInfo.foreground"}))
    result[EditorColorPairIndex.syntaxCheckHint].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInfo.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckInfoSign].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInfo.foreground"}))
    result[EditorColorPairIndex.sidebarSyntaxCheckHintSign].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInfo.foreground"}))

  # Operator
  if tokenNodes.hasKey("keyword.operator"):
    result[EditorColorPairIndex.operator].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["keyword.operator"]{"foreground"}))

  # Namespace/module
  if tokenNodes.hasKey("entity.name.namespace"):
    result[EditorColorPairIndex.namespace].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.namespace"]{"foreground"}))

  # Decorator/attribute
  if tokenNodes.hasKey("entity.name.function.decorator"):
    result[EditorColorPairIndex.decorator].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["entity.name.function.decorator"]{"foreground"})
    )
    result[EditorColorPairIndex.attribute].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["entity.name.function.decorator"]{"foreground"})
    )

  # Preprocessor
  if tokenNodes.hasKey("keyword.control.directive"):
    result[EditorColorPairIndex.preprocessor].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["keyword.control.directive"]{"foreground"})
    )
  if tokenNodes.hasKey("meta.preprocessor"):
    result[EditorColorPairIndex.preprocessor].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["meta.preprocessor"]{"foreground"}))

  # Macro
  if tokenNodes.hasKey("entity.name.function.macro"):
    result[EditorColorPairIndex.`macro`].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["entity.name.function.macro"]{"foreground"})
    )

  # Enum
  if tokenNodes.hasKey("entity.name.type.enum"):
    result[EditorColorPairIndex.enumName].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["entity.name.type.enum"]{"foreground"}))
  if tokenNodes.hasKey("variable.other.enummember"):
    result[EditorColorPairIndex.enumMember].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["variable.other.enummember"]{"foreground"})
    )

  # Property
  if tokenNodes.hasKey("variable.other.property"):
    result[EditorColorPairIndex.property].foreground = ThemeColor(
      rgb: colorFromNode(tokenNodes["variable.other.property"]{"foreground"})
    )

  # Parameter
  if tokenNodes.hasKey("variable.parameter"):
    result[EditorColorPairIndex.parameter].foreground =
      ThemeColor(rgb: colorFromNode(tokenNodes["variable.parameter"]{"foreground"}))

  # Inlay hints
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorInlayHint.foreground"):
    result[EditorColorPairIndex.inlayHint].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInlayHint.foreground"}))
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorInlayHint.background"):
    result[EditorColorPairIndex.inlayHint].background =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorInlayHint.background"}))

  # Code lens
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorCodeLens.foreground"):
    result[EditorColorPairIndex.codeLens].foreground =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorCodeLens.foreground"}))

  # Cursor foreground (used for current line num and other highlights)
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains(
    "editorCursor.foreground"
  ):
    let fg = colorFromNode(jsonNode{"colors", "editorCursor.foreground"})
    result[EditorColorPairIndex.currentLineNum].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.backupManagerCurrentLine].foreground =
      ThemeColor(rgb: fg)
    result[EditorColorPairIndex.configModeCurrentLine].foreground = ThemeColor(rgb: fg)

  # Selection background (current word, paren pair, etc.)
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editor.selectionBackground"):
    let bg = colorFromNode(jsonNode{"colors", "editor.selectionBackground"})
    result[EditorColorPairIndex.currentWord].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.parenPair].background = ThemeColor(rgb: bg)
    result[EditorColorPairIndex.currentFile].background = ThemeColor(rgb: bg)

  # Suggest widget (popup window)
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorSuggestWidget.foreground"):
    result[EditorColorPairIndex.popupWindow].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editorSuggestWidget.foreground"})
    )
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorSuggestWidget.background"):
    result[EditorColorPairIndex.popupWindow].background = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editorSuggestWidget.background"})
    )
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorSuggestWidget.highlightForeground"):
    result[EditorColorPairIndex.popupWinCurrentLine].foreground = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editorSuggestWidget.highlightForeground"})
    )
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorSuggestWidget.selectedBackground"):
    result[EditorColorPairIndex.popupWinCurrentLine].background = ThemeColor(
      rgb: colorFromNode(jsonNode{"colors", "editorSuggestWidget.selectedBackground"})
    )

  # Git conflict
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("gitDecoration.conflictingResourceForeground"):
    result[EditorColorPairIndex.gitConflict].foreground = ThemeColor(
      rgb:
        colorFromNode(jsonNode{"colors", "gitDecoration.conflictingResourceForeground"})
    )
    result[EditorColorPairIndex.replaceText].background = ThemeColor(
      rgb:
        colorFromNode(jsonNode{"colors", "gitDecoration.conflictingResourceForeground"})
    )

  # Hyperlink (for filer mode)
  if tokenNodes.hasKey("markup.underline.link"):
    let fg = colorFromNode(tokenNodes["markup.underline.link"]{"foreground"})
    result[EditorColorPairIndex.dir].foreground = ThemeColor(rgb: fg)
    result[EditorColorPairIndex.pcLink].foreground = ThemeColor(rgb: fg)

  # Tab active border (used for highlight spaces)
  if jsonNode{"colors"} != nil and jsonNode["colors"].contains("tab.activeBorder"):
    let color = colorFromNode(jsonNode{"colors", "tab.activeBorder"})
    result[EditorColorPairIndex.highlightFullWidthSpace].background =
      ThemeColor(rgb: color)
    result[EditorColorPairIndex.highlightTrailingSpaces].background =
      ThemeColor(rgb: color)

  # Line number background
  if jsonNode{"colors"} != nil and
      jsonNode["colors"].contains("editorLineNumber.background"):
    result[EditorColorPairIndex.lineNum].background =
      ThemeColor(rgb: colorFromNode(jsonNode{"colors", "editorLineNumber.background"}))

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

  # The current theme name
  if settingsJson{"workbench.colorTheme"} == nil or
      settingsJson{"workbench.colorTheme"}.getStr == "":
    return Result[ThemeColors, string].err(
      "Failed to load VSCode theme: Could not find current theme name in settings"
    )

  let
    currentThemeName = settingsJson{"workbench.colorTheme"}.getStr

    extensionDirs = [
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
