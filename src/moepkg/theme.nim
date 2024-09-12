#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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
  DefaultColors*: ThemeColors = [
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

    # Warning message
    EditorColorPairIndex.warnMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.warnMessage,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.warnMessageBg,
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
    EditorColorPairIndex.selectArea: ColorPair(
      foreground: Color(
        index: EditorColorIndex.selectArea,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.selectAreaBg,
        rgb: "#800080".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#87d7ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.charLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.charLit,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.identifier: ColorPair(
      foreground: Color(
        index: EditorColorIndex.identifier,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.table: ColorPair(
      foreground: Color(
        index: EditorColorIndex.table,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.date: ColorPair(
      foreground: Color(
        index: EditorColorIndex.date,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.operator: ColorPair(
      foreground: Color(
        index: EditorColorIndex.operator,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.namespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.namespace,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.className: ColorPair(
      foreground: Color(
        index: EditorColorIndex.className,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.enumName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.enumName,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    # Semantic tokens
    EditorColorPairIndex.enumMember: ColorPair(
      foreground: Color(
        index: EditorColorIndex.enumMember,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.interfaceName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.interfaceName,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.typeParameter: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeParameter,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.parameter: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parameter,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.variable: ColorPair(
      foreground: Color(
        index: EditorColorIndex.variable,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.property: ColorPair(
      foreground: Color(
        index: EditorColorIndex.property,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.string: ColorPair(
      foreground: Color(
        index: EditorColorIndex.string,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.event: ColorPair(
      foreground: Color(
        index: EditorColorIndex.event,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.function: ColorPair(
      foreground: Color(
        index: EditorColorIndex.function,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.`method`: ColorPair(
      foreground: Color(
        index: EditorColorIndex.`method`,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.`macro`: ColorPair(
      foreground: Color(
        index: EditorColorIndex.`macro`,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.regexp: ColorPair(
      foreground: Color(
        index: EditorColorIndex.regexp,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.decorator: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decorator,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.angle: ColorPair(
      foreground: Color(
        index: EditorColorIndex.angle,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.arithmetic: ColorPair(
      foreground: Color(
        index: EditorColorIndex.arithmetic,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.attribute: ColorPair(
      foreground: Color(
        index: EditorColorIndex.attribute,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.attributeBracket: ColorPair(
      foreground: Color(
        index: EditorColorIndex.attributeBracket,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.bitwise: ColorPair(
      foreground: Color(
        index: EditorColorIndex.bitwise,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.brace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.brace,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.bracket: ColorPair(
      foreground: Color(
        index: EditorColorIndex.bracket,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.builtinAttribute: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtinAttribute,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.builtinType: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtinType,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.colon: ColorPair(
      foreground: Color(
        index: EditorColorIndex.colon,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.comma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comma,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.comparison: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comparison,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.constParameter: ColorPair(
      foreground: Color(
        index: EditorColorIndex.constParameter,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.derive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.derive,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.deriveHelper: ColorPair(
      foreground: Color(
        index: EditorColorIndex.deriveHelper,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.dot: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dot,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.escapeSequence: ColorPair(
      foreground: Color(
        index: EditorColorIndex.escapeSequence,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.invalidEscapeSequence: ColorPair(
      foreground: Color(
        index: EditorColorIndex.invalidEscapeSequence,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.formatSpecifier: ColorPair(
      foreground: Color(
        index: EditorColorIndex.formatSpecifier,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.generic: ColorPair(
      foreground: Color(
        index: EditorColorIndex.generic,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.label: ColorPair(
      foreground: Color(
        index: EditorColorIndex.label,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.lifetime: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lifetime,
        rgb: "#0090a8".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.logical: ColorPair(
      foreground: Color(
        index: EditorColorIndex.logical,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.macroBang: ColorPair(
      foreground: Color(
        index: EditorColorIndex.macroBang,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.parenthesis: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenthesis,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.punctuation: ColorPair(
      foreground: Color(
        index: EditorColorIndex.punctuation,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.selfKeyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.selfKeyword,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.selfTypeKeyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.selfTypeKeyword,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.semicolon: ColorPair(
      foreground: Color(
        index: EditorColorIndex.semicolon,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.typeAlias: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeAlias,
        rgb: "#add8e6".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.toolModule: ColorPair(
      foreground: Color(
        index: EditorColorIndex.toolModule,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.union: ColorPair(
      foreground: Color(
        index: EditorColorIndex.union,
        rgb: "#00b7ce".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.unresolvedReference: ColorPair(
      foreground: Color(
        index: EditorColorIndex.unresolvedReference,
        rgb: "#f8f5e3".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.inlayHint: ColorPair(
      foreground: Color(
        index: EditorColorIndex.inlayHint,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.inlineValue: ColorPair(
      foreground: Color(
        index: EditorColorIndex.inlineValue,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: "#000000".hexToRgb.get)),

    EditorColorPairIndex.codeLens: ColorPair(
      foreground: Color(
        index: EditorColorIndex.codeLens,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
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
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
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

    EditorColorPairIndex.foldingLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foldingLine,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.foldingLineBg,
        rgb: "#3f3f3f".hexToRgb.get)),

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

var themeColors*: ThemeColors = DefaultColors

proc foregroundRgb*(pairIndex: EditorColorPairIndex): Rgb {.inline.} =
  themeColors[pairIndex].foreground.rgb

proc backgroundRgb*(pairIndex: EditorColorPairIndex): Rgb {.inline.} =
  themeColors[pairIndex].background.rgb

proc rgbPairFromEditorColorPair*(
  pairIndex: EditorColorPairIndex): RgbPair {.inline.} =
    ## Return a RGB pair from ColorThemeTable.

    RgbPair(
      foreground: themeColors[pairIndex].foreground.rgb,
      background: themeColors[pairIndex].background.rgb)

proc setForegroundIndex*(
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =
    ## Set a EditorColorIndex to ColorThemeTable.

    themeColors[pairIndex].foreground.index = colorIndex.EditorColorIndex

proc setBackgroundIndex*(
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =
    ## Set a EditorColorIndex to ColorThemeTable.

    themeColors[pairIndex].background.index = colorIndex.EditorColorIndex

proc setForegroundRgb*(
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} =
    ## Set a Rgb to ColorThemeTable.

    themeColors[pairIndex].foreground.rgb = rgb

proc setBackgroundRgb*(
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} =
    ## Set a Rgb to ColorThemeTable.

    themeColors[pairIndex].background.rgb = rgb

proc downgrade*(mode: ColorMode) =
  ## Downgrade theme colors to 256 or 16 or 8.
  ## Do nothing if greater than 256.

  if mode.int > 256: return

  for pairIndex, pair in themeColors:
    case mode:
      of ColorMode.c8:
       setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor8.rgb)
       setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor8.rgb)
      of ColorMode.c16:
       setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor16.rgb)
       setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor16.rgb)
      of ColorMode.c256:
       setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor256.rgb)
       setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor256.rgb)
      else:
        discard

proc initEditrorColor*(
  colors: ThemeColors,
  colorMode: ColorMode): Result[(), string] =
    ## Init Ncurses colors and color pairs.

    themeColors = colors

    if colorMode >= ColorMode.c24bit:
      # Override Ncurses default color definitions if TrueColor is supported.
      for _, colorPair in themeColors:
        # Init all color defines.
        let r = colorPair.initColor
        if r.isErr: return Result[(), string].err r.error

    for pairIndex, colorPair in themeColors:
      let r = pairIndex.initColorPair(colorMode, colorPair)
      if r.isErr: return r

    return Result[(), string].ok ()
