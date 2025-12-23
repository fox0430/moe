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

## Default theme definitions for moe editor
##
## This module provides the default dark theme color scheme.

import color

proc makeColorPair(fg, bg: string): ColorPair =
  ## Helper to create a ColorPair from two hex color strings
  ColorPair(foreground: ThemeColor(rgb: rgb(fg)), background: ThemeColor(rgb: rgb(bg)))

proc makeColorPairDefaultBg(fg: string): ColorPair =
  ## Helper to create a ColorPair with default background (#000000)
  makeColorPair(fg, "#000000")

const DefaultColors*: ThemeColors = [
  # Basic
  EditorColorPairIndex.default: makeColorPair("#f8f5e3", "#000000"),
  EditorColorPairIndex.lineNum: makeColorPair("#8a8a8a", "#000000"),
  EditorColorPairIndex.currentLineNum: makeColorPair("#008080", "#000000"),

  # Status line - Normal mode
  EditorColorPairIndex.statusLineNormalMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineNormalModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineNormalModeInactive: makeColorPair("#09aefa", "#ffffff"),

  # Status line - Insert mode
  EditorColorPairIndex.statusLineInsertMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineInsertModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineInsertModeInactive: makeColorPair("#09aefa", "#ffffff"),

  # Status line - Visual mode
  EditorColorPairIndex.statusLineVisualMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineVisualModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineVisualModeInactive: makeColorPair("#09aefa", "#ffffff"),

  # Status line - Replace mode
  EditorColorPairIndex.statusLineReplaceMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineReplaceModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineReplaceModeInactive:
    makeColorPair("#09aefa", "#ffffff"),

  # Status line - Filer mode
  EditorColorPairIndex.statusLineFilerMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineFilerModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineFilerModeInactive: makeColorPair("#09aefa", "#ffffff"),

  # Status line - Ex mode
  EditorColorPairIndex.statusLineExMode: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineExModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineExModeInactive: makeColorPair("#09aefa", "#ffffff"),

  # Status line - Git info
  EditorColorPairIndex.statusLineGitChangedLines: makeColorPair("#ffffff", "#0040ff"),
  EditorColorPairIndex.statusLineGitBranch: makeColorPair("#ffffff", "#0040ff"),

  # Tab line
  EditorColorPairIndex.tab: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.currentTab: makeColorPair("#ffffff", "#09aefa"),

  # Command line
  EditorColorPairIndex.commandLine: makeColorPair("#ffffff", "#000000"),

  # Messages
  EditorColorPairIndex.errorMessage: makeColorPair("#ff0000", "#000000"),
  EditorColorPairIndex.warnMessage: makeColorPair("#ffff00", "#000000"),

  # Search result
  EditorColorPairIndex.searchResult: makeColorPair("#ffffff", "#ff0000"),

  # Visual mode selection
  EditorColorPairIndex.selectArea: makeColorPair("#ffffff", "#800080"),

  # Syntax highlighting - Core
  EditorColorPairIndex.keyword: makeColorPairDefaultBg("#87d7ff"),
  EditorColorPairIndex.functionName: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.typeName: makeColorPairDefaultBg("#00ffff"),
  EditorColorPairIndex.boolean: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.specialVar: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.builtin: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.charLit: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.stringLit: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.binNumber: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.decNumber: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.floatNumber: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.hexNumber: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.octNumber: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.comment: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.longComment: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.whitespace: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.preprocessor: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.pragma: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.identifier: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.table: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.date: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.operator: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.property: makeColorPairDefaultBg("#00b7ce"),

  # Syntax highlighting - Extended (LSP semantic tokens)
  EditorColorPairIndex.namespace: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.className: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.enumName: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.enumMember: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.interfaceName: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.typeParameter: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.parameter: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.variable: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.lspString: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.event: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.function: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.`method`: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.`macro`: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.regexp: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.decorator: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.angle: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.arithmetic: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.attribute: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.attributeBracket: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.bitwise: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.brace: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.bracket: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.builtinAttribute: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.builtinType: makeColorPairDefaultBg("#00ffff"),
  EditorColorPairIndex.colon: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.comma: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.comparison: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.constParameter: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.derive: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.deriveHelper: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.dot: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.escapeSequence: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.invalidEscapeSequence: makeColorPairDefaultBg("#ff0000"),
  EditorColorPairIndex.formatSpecifier: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.generic: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.label: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.lifetime: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.logical: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.macroBang: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.parenthesis: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.punctuation: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.selfKeyword: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.selfTypeKeyword: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.semicolon: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.typeAlias: makeColorPairDefaultBg("#add8e6"),
  EditorColorPairIndex.toolModule: makeColorPairDefaultBg("#f8f5e3"),
  EditorColorPairIndex.union: makeColorPairDefaultBg("#00b7ce"),
  EditorColorPairIndex.unresolvedReference: makeColorPairDefaultBg("#f8f5e3"),

  # LSP features
  EditorColorPairIndex.inlayHint: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.inlineValue: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.codeLens: makeColorPairDefaultBg("#808080"),

  # Filer mode
  EditorColorPairIndex.currentFile: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.file: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.dir: makeColorPair("#09aefa", "#000000"),
  EditorColorPairIndex.pcLink: makeColorPair("#008080", "#000000"),

  # Popup window
  EditorColorPairIndex.popupWindow: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.popupWinCurrentLine: makeColorPair("#09aefa", "#000000"),

  # Highlighting
  EditorColorPairIndex.replaceText: makeColorPair("#ffffff", "#ff0000"),
  EditorColorPairIndex.parenPair: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.currentWord: makeColorPair("#ffffff", "#808080"),
  EditorColorPairIndex.highlightFullWidthSpace: makeColorPair("#f8f5e3", "#ff0000"),
  EditorColorPairIndex.highlightTrailingSpaces: makeColorPair("#f8f5e3", "#ff0000"),
  EditorColorPairIndex.reservedWord: makeColorPair("#ffffff", "#808080"),

  # Syntax checker
  EditorColorPairIndex.syntaxCheckInfo: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.syntaxCheckHint: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.syntaxCheckWarn: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.syntaxCheckErr: makeColorPair("#ff0000", "#000000"),

  # Git
  EditorColorPairIndex.gitConflict: makeColorPair("#00ff00", "#000000"),

  # Backup manager
  EditorColorPairIndex.backupManagerCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Diff viewer
  EditorColorPairIndex.diffViewerAddedLine: makeColorPair("#008000", "#000000"),
  EditorColorPairIndex.diffViewerDeletedLine: makeColorPair("#ff0000", "#000000"),

  # Configuration mode
  EditorColorPairIndex.configModeCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Current line background
  EditorColorPairIndex.currentLineBg: makeColorPair("#f8f5e3", "#444444"),
  EditorColorPairIndex.foldingLine: makeColorPair("#808080", "#3f3f3f"),

  # Side bar
  EditorColorPairIndex.sidebarGitAddedSign: makeColorPair("#008000", "#000000"),
  EditorColorPairIndex.sidebarGitDeletedSign: makeColorPair("#ff0000", "#000000"),
  EditorColorPairIndex.sidebarGitChangedSign: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckInfoSign: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckHintSign: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckWarnSign: makeColorPair("#ffff00", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckErrSign: makeColorPair("#ff0000", "#000000"),
]

proc initDefaultTheme*() =
  ## Initialize the theme with default colors.
  setThemeColors(DefaultColors)
