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
  EditorColorPairIndex.default: makeColorPair("#dde1e8", "#000000"),
  EditorColorPairIndex.lineNum: makeColorPair("#636d83", "#000000"),
  EditorColorPairIndex.currentLineNum: makeColorPair("#56b6c2", "#000000"),

  # Status line - Normal mode
  EditorColorPairIndex.statusLineNormalMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineNormalModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineNormalModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Insert mode
  EditorColorPairIndex.statusLineInsertMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineInsertModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineInsertModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Visual mode
  EditorColorPairIndex.statusLineVisualMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineVisualModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineVisualModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Replace mode
  EditorColorPairIndex.statusLineReplaceMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineReplaceModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineReplaceModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Filer mode
  EditorColorPairIndex.statusLineFilerMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineFilerModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineFilerModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Command mode
  EditorColorPairIndex.statusLineExMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineExModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineExModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Git info
  EditorColorPairIndex.statusLineGitChangedLines: makeColorPair("#ffffff", "#3d59a1"),
  EditorColorPairIndex.statusLineGitBranch: makeColorPair("#ffffff", "#3d59a1"),

  # Tab line
  EditorColorPairIndex.tab: makeColorPair("#888888", "#252526"),
  EditorColorPairIndex.currentTab: makeColorPair("#ffffff", "#1e1e1e"),

  # Command line
  EditorColorPairIndex.commandLine: makeColorPair("#ffffff", "#000000"),

  # Messages
  EditorColorPairIndex.errorMessage: makeColorPair("#e06c75", "#000000"),
  EditorColorPairIndex.warnMessage: makeColorPair("#e5c07b", "#000000"),

  # Search result
  EditorColorPairIndex.searchResult: makeColorPair("#ffffff", "#be5046"),
  EditorColorPairIndex.findCharMatch: makeColorPair("#ffffff", "#be5046"),

  # Visual mode selection
  EditorColorPairIndex.selectArea: makeColorPair("#ffffff", "#5c3d6e"),

  # Syntax highlighting - Core
  EditorColorPairIndex.keyword: makeColorPairDefaultBg("#87d7ff"),
  EditorColorPairIndex.functionName: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.typeName: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.boolean: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.specialVar: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.builtin: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.charLit: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.stringLit: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.binNumber: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.decNumber: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.floatNumber: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.hexNumber: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.octNumber: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.comment: makeColorPairDefaultBg("#5c6773"),
  EditorColorPairIndex.longComment: makeColorPairDefaultBg("#5c6773"),
  EditorColorPairIndex.whitespace: makeColorPairDefaultBg("#4b5263"),
  EditorColorPairIndex.preprocessor: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.pragma: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.identifier: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.table: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.date: makeColorPairDefaultBg("#0090a8"),
  EditorColorPairIndex.operator: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.property: makeColorPairDefaultBg("#61afef"),

  # Syntax highlighting - Extended (LSP semantic tokens)
  EditorColorPairIndex.namespace: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.className: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.enumName: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.enumMember: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.interfaceName: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.typeParameter: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.parameter: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.variable: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.lspString: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.event: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.function: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.`method`: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.`macro`: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.regexp: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.decorator: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.angle: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.arithmetic: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.attribute: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.attributeBracket: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.bitwise: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.brace: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.bracket: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.builtinAttribute: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.builtinType: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.colon: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.comma: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.comparison: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.constParameter: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.derive: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.deriveHelper: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.dot: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.escapeSequence: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.invalidEscapeSequence: makeColorPairDefaultBg("#e06c75"),
  EditorColorPairIndex.formatSpecifier: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.generic: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.label: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.lifetime: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.logical: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.macroBang: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.parenthesis: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.punctuation: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.selfKeyword: makeColorPairDefaultBg("#e06c75"),
  EditorColorPairIndex.selfTypeKeyword: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.semicolon: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.typeAlias: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.toolModule: makeColorPairDefaultBg("#dde1e8"),
  EditorColorPairIndex.union: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.unresolvedReference: makeColorPairDefaultBg("#dde1e8"),

  # LSP features
  EditorColorPairIndex.inlayHint: makeColorPairDefaultBg("#636d83"),
  EditorColorPairIndex.inlineValue: makeColorPairDefaultBg("#636d83"),
  EditorColorPairIndex.codeLens: makeColorPairDefaultBg("#636d83"),

  # Filer mode
  EditorColorPairIndex.currentFile: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.file: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.dir: makeColorPair("#61afef", "#000000"),
  EditorColorPairIndex.pcLink: makeColorPair("#008080", "#000000"),

  # Popup window
  EditorColorPairIndex.popupWindow: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.popupWinCurrentLine: makeColorPair("#61afef", "#000000"),

  # Highlighting
  EditorColorPairIndex.replaceText: makeColorPair("#ffffff", "#be5046"),
  EditorColorPairIndex.parenPair: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.currentWord: makeColorPair("#ffffff", "#808080"),
  EditorColorPairIndex.highlightFullWidthSpace: makeColorPair("#dde1e8", "#ff0000"),
  EditorColorPairIndex.highlightTrailingSpaces: makeColorPair("#dde1e8", "#ff0000"),
  EditorColorPairIndex.reservedWord: makeColorPair("#ffffff", "#808080"),

  # Syntax checker
  EditorColorPairIndex.syntaxCheckInfo: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckHint: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckWarn: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckErr: makeColorPair("#e06c75", "#000000"),

  # Git
  EditorColorPairIndex.gitConflict: makeColorPair("#98c379", "#000000"),

  # Backup manager
  EditorColorPairIndex.backupManagerCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Diff viewer
  EditorColorPairIndex.diffViewerAddedLine: makeColorPair("#98c379", "#000000"),
  EditorColorPairIndex.diffViewerDeletedLine: makeColorPair("#e06c75", "#000000"),

  # Configuration mode
  EditorColorPairIndex.configModeCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Current line background
  EditorColorPairIndex.currentLineBg: makeColorPair("#dde1e8", "#3e4452"),
  EditorColorPairIndex.currentColumnBg: makeColorPair("#dde1e8", "#3e4452"),
  EditorColorPairIndex.foldingLine: makeColorPair("#808080", "#3f3f3f"),

  # Side bar
  EditorColorPairIndex.sidebarGitAddedSign: makeColorPair("#98c379", "#000000"),
  EditorColorPairIndex.sidebarGitDeletedSign: makeColorPair("#e06c75", "#000000"),
  EditorColorPairIndex.sidebarGitChangedSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckInfoSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckHintSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckWarnSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckErrSign: makeColorPair("#e06c75", "#000000"),

  # Viewer common colors
  EditorColorPairIndex.viewerHeader: makeColorPair("#ffd700", "#000000"),
  EditorColorPairIndex.viewerSelectedLine: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.viewerEmptyMessage: makeColorPair("#878787", "#000000"),

  # Filer mode specific
  EditorColorPairIndex.filerDirectory: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.filerSymlink: makeColorPairDefaultBg("#00ffff"),
  EditorColorPairIndex.filerSymlinkDir: makeColorPairDefaultBg("#af5fff"),
  EditorColorPairIndex.filerHiddenFile: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.filerExecutable: makeColorPairDefaultBg("#5fff5f"),

  # Buffer manager specific
  EditorColorPairIndex.bufferManagerActive: makeColorPairDefaultBg("#5fff5f"),
  EditorColorPairIndex.bufferManagerModified: makeColorPairDefaultBg("#ff8700"),

  # Configuration mode specific
  EditorColorPairIndex.configModeSection: makeColorPair("#5fff5f", "#000000"),
  EditorColorPairIndex.configModeEditMode: makeColorPair("#000000", "#ffd700"),
  EditorColorPairIndex.configModePopupBg: makeColorPair("#ffffff", "#303030"),
  EditorColorPairIndex.configModePopupSelected: makeColorPair("#ffffff", "#005faf"),

  # Diff viewer specific
  EditorColorPairIndex.diffViewerHeader: makeColorPairDefaultBg("#00d7ff"),
  EditorColorPairIndex.diffViewerMeta: makeColorPairDefaultBg("#ffd700"),

  # Other viewers
  EditorColorPairIndex.recentFileMissing: makeColorPairDefaultBg("#606060"),
  EditorColorPairIndex.debugViewerSectionHeader: makeColorPairDefaultBg("#87afff"),
  EditorColorPairIndex.referencesViewerHeader: makeColorPairDefaultBg("#00afff"),
  EditorColorPairIndex.documentSymbolViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.callHierarchyViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.helpViewerSectionHeader: makeColorPairDefaultBg("#5fafff"),
]

proc initDefaultTheme*() =
  ## Initialize the theme with default colors.
  setThemeColors(DefaultColors)
