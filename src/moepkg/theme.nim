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
  EditorColorPairIndex.default: makeColorPair("#dadada", "#000000"),
  EditorColorPairIndex.lineNum: makeColorPair("#636d83", "#000000"),
  EditorColorPairIndex.currentLineNum: makeColorPair("#56b6c2", "#000000"),
  EditorColorPairIndex.sidebarSessionModifiedSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSessionInsertedSign: makeColorPair("#98c379", "#000000"),

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

  # Status line - QuickRun mode
  EditorColorPairIndex.statusLineQuickRunMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineQuickRunModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineQuickRunModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Log viewer mode
  EditorColorPairIndex.statusLineLogViewerMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineLogViewerModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineLogViewerModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Help mode
  EditorColorPairIndex.statusLineHelpMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineHelpModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineHelpModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Buffer manager mode
  EditorColorPairIndex.statusLineBufferManagerMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineBufferManagerModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineBufferManagerModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Bookmark manager mode
  EditorColorPairIndex.statusLineBookmarkManagerMode:
    makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineBookmarkManagerModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineBookmarkManagerModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Backup manager mode
  EditorColorPairIndex.statusLineBackupManagerMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineBackupManagerModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineBackupManagerModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Diff viewer mode
  EditorColorPairIndex.statusLineDiffViewerMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineDiffViewerModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineDiffViewerModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Recent file mode
  EditorColorPairIndex.statusLineRecentFileMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineRecentFileModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineRecentFileModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Debug mode
  EditorColorPairIndex.statusLineDebugMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineDebugModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineDebugModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - Configuration mode
  EditorColorPairIndex.statusLineConfigMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineConfigModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineConfigModeInactive: makeColorPair("#61afef", "#ffffff"),

  # Status line - References mode
  EditorColorPairIndex.statusLineReferencesMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineReferencesModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineReferencesModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Document symbol mode
  EditorColorPairIndex.statusLineDocumentSymbolMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineDocumentSymbolModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineDocumentSymbolModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Call hierarchy mode
  EditorColorPairIndex.statusLineCallHierarchyMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineCallHierarchyModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineCallHierarchyModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Terminal mode
  EditorColorPairIndex.statusLineTerminalMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineTerminalModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineTerminalModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - File tree mode
  EditorColorPairIndex.statusLineFileTreeMode: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineFileTreeModeLabel: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineFileTreeModeInactive:
    makeColorPair("#61afef", "#ffffff"),

  # Status line - Git info
  EditorColorPairIndex.statusLineGitChangedLines: makeColorPair("#ffffff", "#3d59a1"),
  EditorColorPairIndex.statusLineGitBranch: makeColorPair("#ffffff", "#3d59a1"),

  # Tab line
  EditorColorPairIndex.tab: makeColorPair("#949494", "#262626"),
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
  EditorColorPairIndex.keyword: makeColorPairDefaultBg("#5fd7ff"),
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
  EditorColorPairIndex.docComment: makeColorPairDefaultBg("#7a8a99"),
  EditorColorPairIndex.docLongComment: makeColorPairDefaultBg("#7a8a99"),
  EditorColorPairIndex.whitespace: makeColorPairDefaultBg("#4b5263"),
  EditorColorPairIndex.preprocessor: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.pragma: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.identifier: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.table: makeColorPairDefaultBg("#0087af"),
  EditorColorPairIndex.date: makeColorPairDefaultBg("#0087af"),
  EditorColorPairIndex.logError: makeColorPairDefaultBg("#e06c75"),
  EditorColorPairIndex.logWarning: makeColorPairDefaultBg("#e5c07b"),
  EditorColorPairIndex.logInfo: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.logUuid: makeColorPairDefaultBg("#56b6c2"),
  EditorColorPairIndex.operator: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.property: makeColorPairDefaultBg("#61afef"),

  # Syntax highlighting - Markdown
  EditorColorPairIndex.markdownCodeBlock: makeColorPair("#dadada", "#1a1a2e"),

  # Syntax highlighting - Extended (LSP semantic tokens)
  EditorColorPairIndex.namespace: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.className: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.enumName: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.enumMember: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.interfaceName: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.typeParameter: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.parameter: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.variable: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.lspString: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.event: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.function: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.`method`: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.`macro`: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.regexp: makeColorPairDefaultBg("#98c379"),
  EditorColorPairIndex.decorator: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.angle: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.arithmetic: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.attribute: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.attributeBracket: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.bitwise: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.brace: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.bracket: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.builtinAttribute: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.builtinType: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.colon: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.comma: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.comparison: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.constParameter: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.derive: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.deriveHelper: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.dot: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.escapeSequence: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.invalidEscapeSequence: makeColorPairDefaultBg("#e06c75"),
  EditorColorPairIndex.formatSpecifier: makeColorPairDefaultBg("#d19a66"),
  EditorColorPairIndex.generic: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.label: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.lifetime: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.logical: makeColorPairDefaultBg("#89ddff"),
  EditorColorPairIndex.macroBang: makeColorPairDefaultBg("#c678dd"),
  EditorColorPairIndex.parenthesis: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.punctuation: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.selfKeyword: makeColorPairDefaultBg("#e06c75"),
  EditorColorPairIndex.selfTypeKeyword: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.semicolon: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.typeAlias: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.toolModule: makeColorPairDefaultBg("#dadada"),
  EditorColorPairIndex.union: makeColorPairDefaultBg("#2ac3de"),
  EditorColorPairIndex.unresolvedReference: makeColorPairDefaultBg("#dadada"),

  # LSP features
  EditorColorPairIndex.inlayHint: makeColorPairDefaultBg("#636d83"),
  EditorColorPairIndex.codeLens: makeColorPairDefaultBg("#636d83"),

  # Filer mode
  EditorColorPairIndex.currentFile: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.file: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.dir: makeColorPair("#61afef", "#000000"),
  EditorColorPairIndex.pcLink: makeColorPair("#008080", "#000000"),

  # Popup window
  EditorColorPairIndex.popupWindow: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.popupWinCurrentLine: makeColorPair("#ffffff", "#3e4452"),
  EditorColorPairIndex.popupWindowBorder: makeColorPair("#636d83", "#000000"),
  EditorColorPairIndex.popupWindowDetail: makeColorPair("#636d83", "#000000"),
  EditorColorPairIndex.popupWindowScrollBar: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.popupWindowActiveParameter: makeColorPair("#e5c07b", "#000000"),

  # Notification popup
  EditorColorPairIndex.notificationPopupInfo: makeColorPair("#ffffff", "#323232"),
  EditorColorPairIndex.notificationPopupInfoBorder: makeColorPair("#808080", "#323232"),
  EditorColorPairIndex.notificationPopupWarning: makeColorPair("#ffffff", "#323232"),
  EditorColorPairIndex.notificationPopupWarningBorder:
    makeColorPair("#ffff00", "#323232"),
  EditorColorPairIndex.notificationPopupError: makeColorPair("#ffffff", "#323232"),
  EditorColorPairIndex.notificationPopupErrorBorder: makeColorPair("#ff0000", "#323232"),

  # Highlighting
  EditorColorPairIndex.replaceText: makeColorPair("#ffffff", "#be5046"),
  EditorColorPairIndex.parenPair: makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.currentWord: makeColorPair("#ffffff", "#808080"),
  EditorColorPairIndex.snippetTabStop: makeColorPair("#ffffff", "#5c3d6e"),
  EditorColorPairIndex.highlightFullWidthSpace: makeColorPair("#dadada", "#ff0000"),
  EditorColorPairIndex.highlightTrailingSpaces: makeColorPair("#dadada", "#ff0000"),
  EditorColorPairIndex.reservedWord: makeColorPair("#ffffff", "#808080"),

  # Syntax checker
  EditorColorPairIndex.syntaxCheckInfo: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckHint: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckWarn: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.syntaxCheckErr: makeColorPair("#e06c75", "#000000"),

  # Git
  EditorColorPairIndex.gitConflict: makeColorPair("#ffffff", "#3a1e1e"),
  EditorColorPairIndex.gitConflictMarker: makeColorPair("#ffffff", "#be5046"),
  EditorColorPairIndex.gitConflictOurs: makeColorPair("#ffffff", "#2f2540"),
  EditorColorPairIndex.gitConflictBase: makeColorPair("#dadada", "#3a2f1a"),
  EditorColorPairIndex.gitConflictTheirs: makeColorPair("#ffffff", "#1a2f3a"),

  # Backup manager
  EditorColorPairIndex.backupManagerCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Diff viewer
  EditorColorPairIndex.diffViewerAddedLine: makeColorPair("#98c379", "#000000"),
  EditorColorPairIndex.diffViewerDeletedLine: makeColorPair("#e06c75", "#000000"),

  # Configuration mode
  EditorColorPairIndex.configModeCurrentLine: makeColorPair("#ffffff", "#008080"),

  # Current line background
  EditorColorPairIndex.currentLineBg: makeColorPair("#dadada", "#3e4452"),
  EditorColorPairIndex.currentColumnBg: makeColorPair("#dadada", "#3e4452"),
  EditorColorPairIndex.foldingLine: makeColorPair("#808080", "#3f3f3f"),

  # Side bar
  EditorColorPairIndex.sidebarGitAddedSign: makeColorPair("#98c379", "#000000"),
  EditorColorPairIndex.sidebarGitDeletedSign: makeColorPair("#e06c75", "#000000"),
  EditorColorPairIndex.sidebarGitChangedSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarGitConflictSign: makeColorPair("#e06c75", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckInfoSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckHintSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckWarnSign: makeColorPair("#e5c07b", "#000000"),
  EditorColorPairIndex.sidebarSyntaxCheckErrSign: makeColorPair("#e06c75", "#000000"),

  # Viewer common colors
  EditorColorPairIndex.viewerHeader: makeColorPair("#d7af00", "#000000"),
  EditorColorPairIndex.viewerSelectedLine: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.viewerEmptyMessage: makeColorPair("#8a8a8a", "#000000"),

  # Filer mode specific
  EditorColorPairIndex.filerDirectory: makeColorPairDefaultBg("#61afef"),
  EditorColorPairIndex.filerSymlink: makeColorPairDefaultBg("#00ffff"),
  EditorColorPairIndex.filerSymlinkDir: makeColorPairDefaultBg("#875fd7"),
  EditorColorPairIndex.filerHiddenFile: makeColorPairDefaultBg("#808080"),
  EditorColorPairIndex.filerExecutable: makeColorPairDefaultBg("#5fff5f"),

  # Buffer manager specific
  EditorColorPairIndex.bufferManagerActive: makeColorPairDefaultBg("#5fff5f"),
  EditorColorPairIndex.bufferManagerModified: makeColorPairDefaultBg("#ff8700"),

  # Configuration mode specific
  EditorColorPairIndex.configModeSection: makeColorPair("#5fff5f", "#000000"),
  EditorColorPairIndex.configModeEditMode: makeColorPair("#000000", "#d7af00"),
  EditorColorPairIndex.configModePopupBg: makeColorPair("#ffffff", "#323232"),
  EditorColorPairIndex.configModePopupSelected: makeColorPair("#ffffff", "#005faf"),

  # Diff viewer specific
  EditorColorPairIndex.diffViewerHeader: makeColorPairDefaultBg("#00afaf"),
  EditorColorPairIndex.diffViewerMeta: makeColorPairDefaultBg("#d7af00"),

  # Other viewers
  EditorColorPairIndex.recentFileMissing: makeColorPairDefaultBg("#606060"),
  EditorColorPairIndex.debugViewerSectionHeader: makeColorPairDefaultBg("#87afff"),
  EditorColorPairIndex.referencesViewerHeader: makeColorPairDefaultBg("#0087ff"),
  EditorColorPairIndex.documentSymbolViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.callHierarchyViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.helpViewerSectionHeader: makeColorPairDefaultBg("#5f87ff"),
]

proc initDefaultTheme*() =
  ## Initialize the theme with default colors.
  setThemeColors(DefaultColors)
