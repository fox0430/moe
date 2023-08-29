#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import pkg/results
import rgb, ui, color

type
 ColorTheme* {.pure.} = enum
    dark
    light
    vivid
    config
    vscode

const
  DarkTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitChangedLines: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitChangedLines,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitChangedLinesBg,
        rgb: "#0040ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#0040ff".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#09aefa".hexToRgb.get)),

    # Command line
    EditorColorPairIndex.commandLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.errorMessageBg,
        rgb: "#000000".hexToRgb.get)),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#800080".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#87d7ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longCommentBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: "#000000".hexToRgb.get)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#09aefa".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: "#000000".hexToRgb.get)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Pair of paren highlighting
    EditorColorPairIndex.parenPair: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenPair,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenPairBg,
        rgb: "#09aefa".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#808080".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckInfo: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckInfo,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckInfoBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckHint: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckHint,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckHintBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckWarn: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckWarn,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckWarnBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckErr: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckErr,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckErrBg,
        rgb: "#000000".hexToRgb.get)),

    # Git config background
    EditorColorPairIndex.gitConflict: ColorPair(
      foreground: Color(
        index: EditorColorIndex.gitConflict,
        rgb: "#00ff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.gitConflictBg,
        rgb: "#000000".hexToRgb.get)),

    # Backup manager
    EditorColorPairIndex.backupManagerCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.backupManagerCurrentLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.backupManagerCurrentLineBg,
        rgb: "#008080".hexToRgb.get)),

    # Diff viewer
    EditorColorPairIndex.diffViewerAddedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerAddedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerAddedLineBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.diffViewerDeletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerDeletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerDeletedLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Configuration mode
    EditorColorPairIndex.configModeCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.configModeCurrentLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.configModeCurrentLineBg,
        rgb: "#008080".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#444444".hexToRgb.get)),

    # Side bar
    EditorColorPairIndex.sidebarGitAddedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitAddedSign,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitAddedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitDeletedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitDeletedSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitDeletedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitChangedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitChangedSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitChangedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckInfoSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckHintSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckWarnSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckErrSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSignBg,
        rgb: "#000000".hexToRgb.get))
  ]

  LightTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeLabel,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeLabelBg,
        rgb: "#09aefa".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#f8f5e3".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitChangedLines: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitChangedLines,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitChangedLinesBg,
        rgb: "#8a8a8a".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#8a8a8a".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: "#8a8a8a".hexToRgb.get)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#09aefa".hexToRgb.get)),

    # Command line
    EditorColorPairIndex.commandLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandLine,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandLineBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.errorMessageBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#800080".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#00b16b".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#0040ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#0067C0".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#0067C0".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#800080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumberBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longCommentBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#0067C0".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: "#ffffff".hexToRgb.get)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#09aefa".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#808080".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#09aefa".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#808080".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Pair of paren highlighting
    EditorColorPairIndex.parenPair: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenPair,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenPairBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#808080".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckInfo: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckInfo,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckInfoBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckHint: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckHint,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckHintBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckWarn: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckWarn,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckWarnBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckErr: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckErr,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckErrBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Git config background
    EditorColorPairIndex.gitConflict: ColorPair(
      foreground: Color(
        index: EditorColorIndex.gitConflict,
        rgb: "#00ff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.gitConflictBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Backup manager
    EditorColorPairIndex.backupManagerCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.backupManagerCurrentLine,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.backupManagerCurrentLineBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Diff viewer
    EditorColorPairIndex.diffViewerAddedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerAddedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerAddedLineBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.diffViewerDeletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerDeletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerDeletedLineBg,
        rgb: "#ffffff".hexToRgb.get)),

    # Configuration mode
    EditorColorPairIndex.configModeCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.configModeCurrentLine,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.configModeCurrentLineBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#d3d3d3".hexToRgb.get)),

    # Side bar
    EditorColorPairIndex.sidebarGitAddedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitAddedSign,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitAddedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitDeletedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitDeletedSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitDeletedSign,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitChangedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitChangedSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitChangedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckInfoSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckHintSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckWarnSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckErrSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSignBg,
        rgb: "#000000".hexToRgb.get))
  ]

  VividTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeLabel: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeLabel,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeLabelBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitChangedLines: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitChangedLines,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitChangedLinesBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#000000".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Command line
    EditorColorPairIndex.commandLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.errorMessageBg,
        rgb: "#000000".hexToRgb.get)),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longCommentBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: "#000000".hexToRgb.get)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: "#000000".hexToRgb.get)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Pair of paren highlighting
    EditorColorPairIndex.parenPair: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenPair,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenPairBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckInfo: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckInfo,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckInfoBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckHint: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckHint,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckHintBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckWarn: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckWarn,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckWarnBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.syntaxCheckErr: ColorPair(
      foreground: Color(
        index: EditorColorIndex.syntaxCheckErr,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.syntaxCheckErrBg,
        rgb: "#000000".hexToRgb.get)),

    # Git config background
    EditorColorPairIndex.gitConflict: ColorPair(
      foreground: Color(
        index: EditorColorIndex.gitConflict,
        rgb: "#00ff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.gitConflictBg,
        rgb: "#000000".hexToRgb.get)),

    # Backup manager
    EditorColorPairIndex.backupManagerCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.backupManagerCurrentLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.backupManagerCurrentLineBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Diff viewer
    EditorColorPairIndex.diffViewerAddedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerAddedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerAddedLineBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.diffViewerDeletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.diffViewerDeletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.diffViewerDeletedLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Configuration mode
    EditorColorPairIndex.configModeCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.configModeCurrentLine,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.configModeCurrentLineBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#444444".hexToRgb.get)),

    # Side bar
    EditorColorPairIndex.sidebarGitAddedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitAddedSign,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitAddedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitDeletedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitDeletedSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitDeletedSign,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarGitChangedSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarGitChangedSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarGitChangedSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckInfoSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckInfoSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckHintSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckHintSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckWarnSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSign,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckWarnSignBg,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.sidebarSyntaxCheckErrSign: ColorPair(
      foreground: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSign,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.sidebarSyntaxCheckErrSignBg,
        rgb: "#000000".hexToRgb.get))
  ]

var
  ColorThemeTable*: array[ColorTheme, ThemeColors] = [
    dark: DarkTheme,
    light: LightTheme,
    vivid: VividTheme,
    config: DarkTheme,
    vscode: DarkTheme
  ]

proc foregroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): Rgb {.inline.} =

    ColorThemeTable[theme][pairIndex].foreground.rgb

proc backgroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): Rgb {.inline.} =

    ColorThemeTable[theme][pairIndex].background.rgb

proc rgbPairFromEditorColorPair*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): RgbPair =
    ## Return a RGB pair from ColorThemeTable.

    return RgbPair(
      foreground: ColorThemeTable[theme][pairIndex].foreground.rgb,
      background: ColorThemeTable[theme][pairIndex].background.rgb)

proc setForegroundIndex*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =
    ## Set a EditorColorIndex to ColorThemeTable.

    ColorThemeTable[theme][pairIndex].foreground.index =
      colorIndex.EditorColorIndex

proc setBackgroundIndex*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =
    ## Set a EditorColorIndex to ColorThemeTable.

    ColorThemeTable[theme][pairIndex].background.index =
      colorIndex.EditorColorIndex

proc setForegroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} =
    ## Set a Rgb to ColorThemeTable.

    ColorThemeTable[theme][pairIndex].foreground.rgb = rgb

proc setBackgroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} =
    ## Set a Rgb to ColorThemeTable.

    ColorThemeTable[theme][pairIndex].background.rgb = rgb

proc downgrade*(theme: ColorTheme, mode: ColorMode) =
  ## Donwgrade theme colors to 256 or 16 or 8.
  ## Do nothing if greater than 256.

  if mode.int > 256: return

  for pairIndex, pair in ColorThemeTable[theme]:
    case mode:
      of ColorMode.c8:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor8.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor8.rgb)
      of ColorMode.c16:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor16.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor16.rgb)
      of ColorMode.c256:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor256.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor256.rgb)
      else:
        discard

proc initEditrorColor*(
  theme: ColorTheme,
  colorMode: ColorMode): Result[(), string] =
    ## Init Ncurses colors and color pairs.

    if colorMode >= ColorMode.c24bit:
      # Override Ncurses default color definitions if TrueColor is supported.
      for _, colorPair in ColorThemeTable[theme]:
        # Init all color defines.
        let r = colorPair.initColor
        if r.isErr: return Result[(), string].err r.error

    for pairIndex, colorPair in ColorThemeTable[theme]:
      let r = pairIndex.initColorPair(colorMode, colorPair)
      if r.isErr: return r

    return Result[(), string].ok ()
