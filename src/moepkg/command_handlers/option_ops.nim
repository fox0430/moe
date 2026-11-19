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

## Option-setting side effects for `:set`/`:setlocal` results, split out of
## result_processor.nim so the set-option arms live next to setting_options.

import ../[editor, setting_options, types]

import handler_result

proc boolOptionValue(e: Editor, option: BoolSettingOption): bool =
  case option
  of bsoNumber: e.config.standard.number
  of bsoRelativeNumber: e.config.standard.relativeNumber
  of bsoCursorLine: e.config.highlight.currentLine
  of bsoCursorColumn: e.config.highlight.currentColumn
  of bsoStatusLine: e.config.standard.statusLine
  of bsoSyntax: e.config.standard.syntax
  of bsoIndentationLines: e.config.standard.indentationLines
  of bsoAutoIndent: e.config.standard.autoIndent
  of bsoAutoCloseParen: e.config.standard.autoCloseParen
  of bsoAutoDeleteParen: e.config.standard.autoDeleteParen
  of bsoClipboard: e.config.clipboard.enable
  of bsoSmoothScroll: e.config.smoothScroll.enable
  of bsoLiveReloadOfConf: e.config.standard.liveReloadOfConf
  of bsoShowIcons: e.config.filer.showIcons
  of bsoHighlightCurrentLine: e.config.highlight.currentLine
  of bsoHighlightCurrentWord: e.config.highlight.currentWord
  of bsoHighlightFullWidthSpace: e.config.highlight.fullWidthSpace
  of bsoHighlightPairOfParen: e.config.highlight.pairOfParen
  of bsoHighlightFindChar: e.config.highlight.findCharHighlight
  of bsoHighlightColorCode: e.config.highlight.colorCodeHighlight
  of bsoHighlightGitConflict: e.config.highlight.gitConflict
  of bsoHighlightGitConflictTwoColor: e.config.highlight.gitConflictTwoColor
  of bsoMultipleStatusLine: e.config.statusLine.multipleStatusLine
  of bsoIgnoreCase: e.state.ignorecase
  of bsoSmartCase: e.state.smartcase
  of bsoIncSearch: e.state.incsearch
  of bsoHlSearch: e.state.input.search.hlsearch
  of bsoBuildOnSave: e.config.buildOnSave.enable
  of bsoShowGitInactive: e.config.statusLine.showGitInactive
  of bsoLineWrap: e.config.standard.lineWrap
  of bsoExpandTab: e.state.expandTab
  of bsoScrollbar: e.config.standard.scrollbar

proc setBoolOption(e: Editor, option: BoolSettingOption, value: bool) =
  case option
  of bsoNumber:
    e.config.standard.number = value
  of bsoRelativeNumber:
    e.config.standard.relativeNumber = value
  of bsoCursorLine:
    e.config.highlight.currentLine = value
  of bsoCursorColumn:
    e.config.highlight.currentColumn = value
  of bsoStatusLine:
    e.config.standard.statusLine = value
  of bsoSyntax:
    e.config.standard.syntax = value
  of bsoIndentationLines:
    e.config.standard.indentationLines = value
  of bsoAutoIndent:
    e.config.standard.autoIndent = value
  of bsoAutoCloseParen:
    e.config.standard.autoCloseParen = value
  of bsoAutoDeleteParen:
    e.config.standard.autoDeleteParen = value
  of bsoClipboard:
    e.config.clipboard.enable = value
  of bsoSmoothScroll:
    e.config.smoothScroll.enable = value
  of bsoLiveReloadOfConf:
    e.config.standard.liveReloadOfConf = value
  of bsoShowIcons:
    e.config.filer.showIcons = value
  of bsoHighlightCurrentLine:
    e.config.highlight.currentLine = value
  of bsoHighlightCurrentWord:
    e.config.highlight.currentWord = value
  of bsoHighlightFullWidthSpace:
    e.config.highlight.fullWidthSpace = value
  of bsoHighlightPairOfParen:
    e.config.highlight.pairOfParen = value
  of bsoHighlightFindChar:
    e.config.highlight.findCharHighlight = value
  of bsoHighlightColorCode:
    e.config.highlight.colorCodeHighlight = value
  of bsoHighlightGitConflict:
    e.config.highlight.gitConflict = value
  of bsoHighlightGitConflictTwoColor:
    e.config.highlight.gitConflictTwoColor = value
  of bsoMultipleStatusLine:
    e.config.statusLine.multipleStatusLine = value
  of bsoIgnoreCase:
    e.state.ignorecase = value
  of bsoSmartCase:
    e.state.smartcase = value
  of bsoIncSearch:
    e.state.incsearch = value
  of bsoHlSearch:
    e.state.input.search.hlsearch = value
    e.state.showSearchMatches()
  of bsoBuildOnSave:
    e.config.buildOnSave.enable = value
  of bsoShowGitInactive:
    e.config.statusLine.showGitInactive = value
  of bsoLineWrap:
    e.config.standard.lineWrap = value
  of bsoExpandTab:
    e.state.expandTab = value
  of bsoScrollbar:
    e.config.standard.scrollbar = value

proc intOptionValue(e: Editor, option: IntSettingOption): int =
  case option
  of isoTabStop: e.state.tabStop
  of isoShiftWidth: e.state.shiftWidth
  of isoSoftTabStop: e.config.standard.softTabStop
  of isoScrollbarWidth: e.config.standard.scrollbarWidth

proc setIntOption(e: Editor, option: IntSettingOption, value: int) =
  case option
  of isoTabStop:
    e.state.tabStop = value
  of isoShiftWidth:
    e.state.shiftWidth = value
  of isoSoftTabStop:
    e.config.standard.softTabStop = value
  of isoScrollbarWidth:
    e.config.standard.scrollbarWidth = value

proc floatOptionValue(e: Editor, option: FloatSettingOption): float =
  case option
  of fsoScrollFriction: e.config.smoothScroll.friction
  of fsoScrollAirDrag: e.config.smoothScroll.airDrag

proc setFloatOption(e: Editor, option: FloatSettingOption, value: float) =
  case option
  of fsoScrollFriction:
    e.config.smoothScroll.friction = value
  of fsoScrollAirDrag:
    e.config.smoothScroll.airDrag = value

proc shownValue(e: Editor, spec: SetOptionSpec): string =
  ## Vim's `:set X?` wording: `  number`, `nonumber`, `  tabstop=4`.
  case spec.kind
  of sokBool:
    (if e.boolOptionValue(spec.boolOption): "  " else: "no") & spec.longName
  of sokInt:
    "  " & spec.longName & "=" & $e.intOptionValue(spec.intOption)
  of sokFloat:
    "  " & spec.longName & "=" & $e.floatOptionValue(spec.floatOption)

proc processSetOptionResult*(e: Editor, r: HandlerResult): bool =
  ## Apply hrSetBoolOption / hrSetIntOption / hrSetFloatOption /
  ## hrToggleBoolOption / hrShowOption. Returns true to continue.
  case r.kind
  of hrSetBoolOption:
    e.setBoolOption(r.boolOption, r.boolValue)
    e.state.statusMessage = r.boolOption.longName & " = " & $r.boolValue
  of hrToggleBoolOption:
    let value = not e.boolOptionValue(r.toggledOption)
    e.setBoolOption(r.toggledOption, value)
    e.state.statusMessage = r.toggledOption.longName & " = " & $value
  of hrSetIntOption:
    e.setIntOption(r.intOption, r.intValue)
    e.state.statusMessage = r.intOption.longName & " = " & $r.intValue
  of hrSetFloatOption:
    e.setFloatOption(r.floatOption, r.floatValue)
    e.state.statusMessage = r.floatOption.longName & " = " & $r.floatValue
  of hrShowOption:
    e.state.statusMessage = e.shownValue(r.shownOption)
  else:
    discard # Not a set-option kind; caller misrouted (defensive)
  true
