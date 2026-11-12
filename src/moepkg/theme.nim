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
## This module provides the default dark theme and the bundled light theme.

import color

proc makeColorPair(fg, bg: string): ColorPair =
  ## Helper to create a ColorPair from two hex color strings
  ColorPair(foreground: ThemeColor(rgb: rgb(fg)), background: ThemeColor(rgb: rgb(bg)))

proc makeColorPairDefaultBg(fg: string): ColorPair =
  ## Helper to create a ColorPair with default background (#000000)
  makeColorPair(fg, "#000000")

proc makeColorPairTermDefaultFg(bg: string): ColorPair =
  ## Helper to create a ColorPair with terminal-default foreground and a fixed
  ## background. Used for highlight tints that keep the underlying text's
  ## terminal-default foreground (e.g. LSP document highlight).
  ColorPair(
    foreground: ThemeColor(rgb: TerminalDefaultRgb),
    background: ThemeColor(rgb: rgb(bg)),
  )

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

  # Status line - Recovery manager mode
  EditorColorPairIndex.statusLineRecoveryManagerMode:
    makeColorPair("#ffffff", "#61afef"),
  EditorColorPairIndex.statusLineRecoveryManagerModeLabel:
    makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.statusLineRecoveryManagerModeInactive:
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

  # Recovery manager
  EditorColorPairIndex.recoveryManagerCurrentLine: makeColorPair("#ffffff", "#008080"),

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
  EditorColorPairIndex.sidebarBookmarkSign: makeColorPair("#56b6c2", "#000000"),

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
  EditorColorPairIndex.diffViewerAddedWord: makeColorPairTermDefaultFg("#2f6b3a"),
  EditorColorPairIndex.diffViewerDeletedWord: makeColorPairTermDefaultFg("#74323a"),
  EditorColorPairIndex.diffViewerAddedLineBg: makeColorPairTermDefaultFg("#17301c"),
  EditorColorPairIndex.diffViewerDeletedLineBg: makeColorPairTermDefaultFg("#331a1d"),
  EditorColorPairIndex.diffViewerFiller: makeColorPair("#585858", "#1c1c1c"),

  # Other viewers
  EditorColorPairIndex.recentFileMissing: makeColorPairDefaultBg("#606060"),
  EditorColorPairIndex.debugViewerSectionHeader: makeColorPairDefaultBg("#87afff"),
  EditorColorPairIndex.referencesViewerHeader: makeColorPairDefaultBg("#0087ff"),
  EditorColorPairIndex.documentSymbolViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.callHierarchyViewerHeader: makeColorPairDefaultBg("#afd700"),
  EditorColorPairIndex.helpViewerSectionHeader: makeColorPairDefaultBg("#5f87ff"),

  # Indentation guide
  EditorColorPairIndex.indentationLine: makeColorPairDefaultBg("#464646"),
  EditorColorPairIndex.invalidByte: makeColorPairDefaultBg("#d75f5f"),

  # Scroll bar
  EditorColorPairIndex.scrollBarThumb: makeColorPair("#787878", "#787878"),
  EditorColorPairIndex.scrollBarTrack: makeColorPairDefaultBg("#323232"),

  # LSP document highlight
  EditorColorPairIndex.documentHighlightText: makeColorPairTermDefaultFg("#3c3c50"),
  EditorColorPairIndex.documentHighlightRead: makeColorPairTermDefaultFg("#284628"),
  EditorColorPairIndex.documentHighlightWrite: makeColorPairTermDefaultFg("#503232"),

  # Temporary message area
  EditorColorPairIndex.tempMessageBorder: makeColorPairTermDefaultFg("#ffffff"),
]

# The bundled light theme, for theme sources that leave colors unset on a light
# surface. It sets every entry: one it left out would stay dark. A test checks
# it against example/themes/light.toml.
const LightColors*: ThemeColors = [
  # Basic
  EditorColorPairIndex.default: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.lineNum: makeColorPair("#8a8a8a", "#000000"),
  EditorColorPairIndex.currentLineNum: makeColorPair("#ffffff", "#000000"),
  EditorColorPairIndex.sidebarSessionModifiedSign: makeColorPair("#b8860b", "#ffffff"),
  EditorColorPairIndex.sidebarSessionInsertedSign: makeColorPair("#008000", "#ffffff"),

  # Status line - Normal mode
  EditorColorPairIndex.statusLineNormalMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineNormalModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineNormalModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Insert mode
  EditorColorPairIndex.statusLineInsertMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineInsertModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineInsertModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Visual mode
  EditorColorPairIndex.statusLineVisualMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineVisualModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineVisualModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Replace mode
  EditorColorPairIndex.statusLineReplaceMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineReplaceModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineReplaceModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Filer mode
  EditorColorPairIndex.statusLineFilerMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineFilerModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineFilerModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Command mode
  EditorColorPairIndex.statusLineExMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineExModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineExModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Log viewer mode
  EditorColorPairIndex.statusLineLogViewerMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineLogViewerModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineLogViewerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Help mode
  EditorColorPairIndex.statusLineHelpMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineHelpModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineHelpModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Buffer manager mode
  EditorColorPairIndex.statusLineBufferManagerMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineBufferManagerModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineBufferManagerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Bookmark manager mode
  EditorColorPairIndex.statusLineBookmarkManagerMode:
    makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineBookmarkManagerModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineBookmarkManagerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Backup manager mode
  EditorColorPairIndex.statusLineBackupManagerMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineBackupManagerModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineBackupManagerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Recovery manager mode
  EditorColorPairIndex.statusLineRecoveryManagerMode:
    makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineRecoveryManagerModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineRecoveryManagerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Diff viewer mode
  EditorColorPairIndex.statusLineDiffViewerMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineDiffViewerModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineDiffViewerModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Recent file mode
  EditorColorPairIndex.statusLineRecentFileMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineRecentFileModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineRecentFileModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Debug mode
  EditorColorPairIndex.statusLineDebugMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineDebugModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineDebugModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Configuration mode
  EditorColorPairIndex.statusLineConfigMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineConfigModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineConfigModeInactive: makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - References mode
  EditorColorPairIndex.statusLineReferencesMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineReferencesModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineReferencesModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Document symbol mode
  EditorColorPairIndex.statusLineDocumentSymbolMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineDocumentSymbolModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineDocumentSymbolModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Call hierarchy mode
  EditorColorPairIndex.statusLineCallHierarchyMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineCallHierarchyModeLabel:
    makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineCallHierarchyModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Terminal mode
  EditorColorPairIndex.statusLineTerminalMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineTerminalModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineTerminalModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - File tree mode
  EditorColorPairIndex.statusLineFileTreeMode: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineFileTreeModeLabel: makeColorPair("#ffffff", "#09aefa"),
  EditorColorPairIndex.statusLineFileTreeModeInactive:
    makeColorPair("#8a8a8a", "#f8f5d5"),

  # Status line - Git info
  EditorColorPairIndex.statusLineGitChangedLines: makeColorPair("#ffffff", "#8a8a8a"),
  EditorColorPairIndex.statusLineGitBranch: makeColorPair("#ffffff", "#8a8a8a"),

  # Tab line
  EditorColorPairIndex.tab: makeColorPair("#09aefa", "#8a8a8a"),
  EditorColorPairIndex.currentTab: makeColorPair("#ffffff", "#09aefa"),

  # Command line
  EditorColorPairIndex.commandLine: makeColorPair("#ff0000", "#ffffff"),

  # Messages
  EditorColorPairIndex.errorMessage: makeColorPair("#ff0000", "#ffffff"),
  EditorColorPairIndex.warnMessage: makeColorPair("#ffff00", "#ffffff"),

  # Search result
  EditorColorPairIndex.searchResult: makeColorPair("#000000", "#ff0000"),
  EditorColorPairIndex.findCharMatch: makeColorPair("#000000", "#ff5500"),

  # Visual mode selection
  EditorColorPairIndex.selectArea: makeColorPair("#000000", "#800080"),

  # Syntax highlighting - Core
  EditorColorPairIndex.keyword: makeColorPair("#00b16b", "#ffffff"),
  EditorColorPairIndex.functionName: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.typeName: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.boolean: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.specialVar: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.builtin: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.charLit: makeColorPair("#800080", "#ffffff"),
  EditorColorPairIndex.stringLit: makeColorPair("#800080", "#ffffff"),
  EditorColorPairIndex.binNumber: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.decNumber: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.floatNumber: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.hexNumber: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.octNumber: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.comment: makeColorPair("#808080", "#ffffff"),
  EditorColorPairIndex.longComment: makeColorPair("#808080", "#ffffff"),
  EditorColorPairIndex.docComment: makeColorPair("#606060", "#ffffff"),
  EditorColorPairIndex.docLongComment: makeColorPair("#606060", "#ffffff"),
  EditorColorPairIndex.whitespace: makeColorPair("#808080", "#ffffff"),
  EditorColorPairIndex.preprocessor: makeColorPair("#808080", "#ffffff"),
  EditorColorPairIndex.pragma: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.identifier: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.table: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.date: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.logError: makeColorPair("#cc0000", "#ffffff"),
  EditorColorPairIndex.logWarning: makeColorPair("#b8860b", "#ffffff"),
  EditorColorPairIndex.logInfo: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.logUuid: makeColorPair("#008080", "#ffffff"),
  EditorColorPairIndex.operator: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.property: makeColorPair("#00b7ce", "#ffffff"),

  # Syntax highlighting - Markdown
  EditorColorPairIndex.markdownCodeBlock: makeColorPair("#1e1e1e", "#e8e8e8"),

  # Syntax highlighting - Extended (LSP semantic tokens)
  EditorColorPairIndex.namespace: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.className: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.enumName: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.enumMember: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.interfaceName: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.typeParameter: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.parameter: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.variable: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.lspString: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.event: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.function: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.`method`: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.`macro`: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.regexp: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.decorator: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.angle: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.arithmetic: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.attribute: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.attributeBracket: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.bitwise: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.brace: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.bracket: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.builtinAttribute: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.builtinType: makeColorPair("#00ffff", "#ffffff"),
  EditorColorPairIndex.colon: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.comma: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.comparison: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.constParameter: makeColorPair("#0087af", "#ffffff"),
  EditorColorPairIndex.derive: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.deriveHelper: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.dot: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.escapeSequence: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.invalidEscapeSequence: makeColorPair("#ff0000", "#ffffff"),
  EditorColorPairIndex.formatSpecifier: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.generic: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.label: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.lifetime: makeColorPair("#0087af", "#ffffff"),
  EditorColorPairIndex.logical: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.macroBang: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.parenthesis: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.punctuation: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.selfKeyword: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.selfTypeKeyword: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.semicolon: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.typeAlias: makeColorPair("#add8e6", "#ffffff"),
  EditorColorPairIndex.toolModule: makeColorPair("#f8f5d5", "#ffffff"),
  EditorColorPairIndex.union: makeColorPair("#00b7ce", "#ffffff"),
  EditorColorPairIndex.unresolvedReference: makeColorPair("#f8f5d5", "#ffffff"),

  # LSP features
  EditorColorPairIndex.inlayHint: makeColorPair("#808080", "#ffffff"),
  EditorColorPairIndex.codeLens: makeColorPair("#808080", "#ffffff"),

  # Filer mode
  EditorColorPairIndex.currentFile: makeColorPair("#000000", "#09aefa"),
  EditorColorPairIndex.file: makeColorPair("#000000", "#ffffff"),
  EditorColorPairIndex.dir: makeColorPair("#09aefa", "#ffffff"),
  EditorColorPairIndex.pcLink: makeColorPair("#008080", "#ffffff"),

  # Popup window
  EditorColorPairIndex.popupWindow: makeColorPair("#000000", "#808080"),
  EditorColorPairIndex.popupWinCurrentLine: makeColorPair("#ffffff", "#444444"),
  EditorColorPairIndex.popupWindowBorder: makeColorPair("#4d4d4d", "#808080"),
  EditorColorPairIndex.popupWindowDetail: makeColorPair("#4d4d4d", "#808080"),
  EditorColorPairIndex.popupWindowScrollBar: makeColorPair("#ffff00", "#808080"),
  EditorColorPairIndex.popupWindowActiveParameter: makeColorPair("#ffff00", "#808080"),

  # Notification popup
  EditorColorPairIndex.notificationPopupInfo: makeColorPair("#000000", "#d0d0d0"),
  EditorColorPairIndex.notificationPopupInfoBorder: makeColorPair("#808080", "#d0d0d0"),
  EditorColorPairIndex.notificationPopupWarning: makeColorPair("#000000", "#d0d0d0"),
  EditorColorPairIndex.notificationPopupWarningBorder:
    makeColorPair("#b8860b", "#d0d0d0"),
  EditorColorPairIndex.notificationPopupError: makeColorPair("#000000", "#d0d0d0"),
  EditorColorPairIndex.notificationPopupErrorBorder: makeColorPair("#cc0000", "#d0d0d0"),

  # Highlighting
  EditorColorPairIndex.replaceText: makeColorPair("#000000", "#ff0000"),
  EditorColorPairIndex.parenPair: makeColorPair("#000000", "#808080"),
  EditorColorPairIndex.currentWord: makeColorPair("#000000", "#808080"),
  EditorColorPairIndex.snippetTabStop: makeColorPair("#000000", "#800080"),
  EditorColorPairIndex.highlightFullWidthSpace: makeColorPair("#ffffff", "#ff0000"),
  EditorColorPairIndex.highlightTrailingSpaces: makeColorPair("#ffffff", "#ff0000"),
  EditorColorPairIndex.reservedWord: makeColorPair("#ffffff", "#808080"),

  # Syntax checker
  EditorColorPairIndex.syntaxCheckInfo: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.syntaxCheckHint: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.syntaxCheckWarn: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.syntaxCheckErr: makeColorPair("#ff0000", "#ffffff"),

  # Git
  EditorColorPairIndex.gitConflict: makeColorPair("#000000", "#ffdcdc"),
  EditorColorPairIndex.gitConflictMarker: makeColorPair("#ffffff", "#d73a49"),
  EditorColorPairIndex.gitConflictOurs: makeColorPair("#000000", "#f2dfff"),
  EditorColorPairIndex.gitConflictBase: makeColorPair("#000000", "#fff5d7"),
  EditorColorPairIndex.gitConflictTheirs: makeColorPair("#000000", "#dcefff"),

  # Backup manager
  EditorColorPairIndex.backupManagerCurrentLine: makeColorPair("#000000", "#ff0087"),

  # Recovery manager
  EditorColorPairIndex.recoveryManagerCurrentLine: makeColorPair("#000000", "#ff0087"),

  # Diff viewer
  EditorColorPairIndex.diffViewerAddedLine: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.diffViewerDeletedLine: makeColorPair("#ff0000", "#ffffff"),

  # Configuration mode
  EditorColorPairIndex.configModeCurrentLine: makeColorPair("#000000", "#ff0087"),

  # Current line background
  EditorColorPairIndex.currentLineBg: makeColorPair("#dadada", "#eeeeee"),
  EditorColorPairIndex.currentColumnBg: makeColorPair("#dadada", "#eeeeee"),
  EditorColorPairIndex.foldingLine: makeColorPair("#808080", "#ededed"),

  # Side bar
  EditorColorPairIndex.sidebarGitAddedSign: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.sidebarGitDeletedSign: makeColorPair("#ff0000", "#ffffff"),
  EditorColorPairIndex.sidebarGitChangedSign: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.sidebarGitConflictSign: makeColorPair("#d73a49", "#ffffff"),
  EditorColorPairIndex.sidebarSyntaxCheckInfoSign: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.sidebarSyntaxCheckHintSign: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.sidebarSyntaxCheckWarnSign: makeColorPair("#ffff00", "#ffffff"),
  EditorColorPairIndex.sidebarSyntaxCheckErrSign: makeColorPair("#ff0000", "#ffffff"),
  EditorColorPairIndex.sidebarBookmarkSign: makeColorPair("#0087af", "#ffffff"),

  # Viewer common colors
  EditorColorPairIndex.viewerHeader: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.viewerSelectedLine: makeColorPair("#ffffff", "#0067c0"),
  EditorColorPairIndex.viewerEmptyMessage: makeColorPair("#808080", "#ffffff"),

  # Filer mode specific
  EditorColorPairIndex.filerDirectory: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.filerSymlink: makeColorPair("#008080", "#ffffff"),
  EditorColorPairIndex.filerSymlinkDir: makeColorPair("#800080", "#ffffff"),
  EditorColorPairIndex.filerHiddenFile: makeColorPair("#a0a0a0", "#ffffff"),
  EditorColorPairIndex.filerExecutable: makeColorPair("#008000", "#ffffff"),

  # Buffer manager specific
  EditorColorPairIndex.bufferManagerActive: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.bufferManagerModified: makeColorPair("#ff8700", "#ffffff"),

  # Configuration mode specific
  EditorColorPairIndex.configModeSection: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.configModeEditMode: makeColorPair("#000000", "#d7af00"),
  EditorColorPairIndex.configModePopupBg: makeColorPair("#000000", "#e0e0e0"),
  EditorColorPairIndex.configModePopupSelected: makeColorPair("#ffffff", "#0067c0"),

  # Diff viewer specific
  EditorColorPairIndex.diffViewerHeader: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.diffViewerMeta: makeColorPair("#805000", "#ffffff"),
  EditorColorPairIndex.diffViewerAddedWord: makeColorPairTermDefaultFg("#a8f0b8"),
  EditorColorPairIndex.diffViewerDeletedWord: makeColorPairTermDefaultFg("#ffc4c9"),
  EditorColorPairIndex.diffViewerAddedLineBg: makeColorPairTermDefaultFg("#e6ffec"),
  EditorColorPairIndex.diffViewerDeletedLineBg: makeColorPairTermDefaultFg("#ffebe9"),
  EditorColorPairIndex.diffViewerFiller: makeColorPair("#808080", "#ededed"),

  # Other viewers
  EditorColorPairIndex.recentFileMissing: makeColorPair("#a0a0a0", "#ffffff"),
  EditorColorPairIndex.debugViewerSectionHeader: makeColorPair("#0040ff", "#ffffff"),
  EditorColorPairIndex.referencesViewerHeader: makeColorPair("#0067c0", "#ffffff"),
  EditorColorPairIndex.documentSymbolViewerHeader: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.callHierarchyViewerHeader: makeColorPair("#008000", "#ffffff"),
  EditorColorPairIndex.helpViewerSectionHeader: makeColorPair("#0040ff", "#ffffff"),

  # Indentation guide
  EditorColorPairIndex.indentationLine: makeColorPair("#bcbcbc", "#ffffff"),
  EditorColorPairIndex.invalidByte: makeColorPair("#cc0000", "#ffffff"),

  # Scroll bar
  EditorColorPairIndex.scrollBarThumb: makeColorPair("#9e9e9e", "#9e9e9e"),
  EditorColorPairIndex.scrollBarTrack: makeColorPair("#d0d0d0", "#ffffff"),

  # LSP document highlight
  EditorColorPairIndex.documentHighlightText: makeColorPairTermDefaultFg("#dbe6f6"),
  EditorColorPairIndex.documentHighlightRead: makeColorPairTermDefaultFg("#d6efd6"),
  EditorColorPairIndex.documentHighlightWrite: makeColorPairTermDefaultFg("#f6dcdc"),

  # Temporary message area
  EditorColorPairIndex.tempMessageBorder: makeColorPairTermDefaultFg("#8a8a8a"),
]

const DiffViewerTints = [
  EditorColorPairIndex.diffViewerAddedWord, EditorColorPairIndex.diffViewerDeletedWord,
  EditorColorPairIndex.diffViewerAddedLineBg,
  EditorColorPairIndex.diffViewerDeletedLineBg, EditorColorPairIndex.diffViewerFiller,
]

proc isLightColor*(c: Rgb): bool =
  ## W3C perceived-brightness test.
  (c.red.int * 299 + c.green.int * 587 + c.blue.int * 114) div 1000 > 128

proc drawsOnLightSurface(colors: ThemeColors): bool =
  ## Whether the editor paints on a light surface. With a `termDefault`
  ## background the terminal color is unknown, so a dark explicit foreground is
  ## the only remaining signal. With both at the default, assume dark.
  let
    bg = colors[EditorColorPairIndex.default].background.rgb
    fg = colors[EditorColorPairIndex.default].foreground.rgb
  if bg != TerminalDefaultRgb:
    return isLightColor(bg)
  if fg != TerminalDefaultRgb:
    return not isLightColor(fg)
  false

proc adaptDiffTintsToBackground*(colors: var ThemeColors) =
  ## The diff viewer marks lines with a background alone, so the bundled dark
  ## tints are unreadable on a light theme. Take the bundled light theme's when
  ## the theme draws on a light surface and left the tints at their defaults.
  if not colors.drawsOnLightSurface():
    return
  for index in DiffViewerTints:
    if colors[index] == DefaultColors[index]:
      colors[index] = LightColors[index]

proc initDefaultTheme*() =
  ## Initialize the theme with default colors.
  setThemeColors(DefaultColors)

# Initialize the global theme to the bundled defaults at module load. The
# `themeColors` global lives in `color.nim`, which cannot reference
# `DefaultColors` here without an import cycle, so it is zero-initialized
# (every channel 0 -> all-black `#000000`). Any code path that serializes
# `themeColors` before `initTheme`/`setThemeColors` runs (e.g. tooling or a
# test using a default `EditorConfig`, whose `theme.path` points at the real
# `~/.config/moe/themes/dark.toml`) would otherwise overwrite that file with an
# all-black theme. Seeding the global here makes such a stray save write a
# valid dark theme instead.
setThemeColors(DefaultColors)
