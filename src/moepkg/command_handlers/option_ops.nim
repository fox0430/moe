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

proc processSetOptionResult*(e: Editor, r: HandlerResult): bool =
  ## Apply hrSetBoolOption / hrSetIntOption / hrSetFloatOption.
  ## Returns true to continue.
  case r.kind
  of hrSetBoolOption:
    let opt = r.boolOption
    let val = r.boolValue
    case opt
    of bsoNumber:
      e.config.standard.number = val
      e.state.statusMessage = "number = " & $val
    of bsoRelativeNumber:
      e.config.standard.relativeNumber = val
      e.state.statusMessage = "relativenumber = " & $val
    of bsoCursorLine:
      e.config.highlight.currentLine = val
      e.state.statusMessage = "cursorline = " & $val
    of bsoCursorColumn:
      e.config.highlight.currentColumn = val
      e.state.statusMessage = "cursorcolumn = " & $val
    of bsoStatusLine:
      e.config.standard.statusLine = val
      e.state.statusMessage = "statusline = " & $val
    of bsoSyntax:
      e.config.standard.syntax = val
      e.state.statusMessage = "syntax = " & $val
    of bsoIndentationLines:
      e.config.standard.indentationLines = val
      e.state.statusMessage = "indentationlines = " & $val
    of bsoAutoIndent:
      e.config.standard.autoIndent = val
      e.state.statusMessage = "autoindent = " & $val
    of bsoAutoCloseParen:
      e.config.standard.autoCloseParen = val
      e.state.statusMessage = "autocloseparen = " & $val
    of bsoAutoDeleteParen:
      e.config.standard.autoDeleteParen = val
      e.state.statusMessage = "autodeleteparen = " & $val
    of bsoClipboard:
      e.config.clipboard.enable = val
      e.state.statusMessage = "clipboard = " & $val
    of bsoSmoothScroll:
      e.config.smoothScroll.enable = val
      e.state.statusMessage = "smoothscroll = " & $val
    of bsoLiveReloadOfConf:
      e.config.standard.liveReloadOfConf = val
      e.state.statusMessage = "livereload = " & $val
    of bsoShowIcons:
      e.config.filer.showIcons = val
      e.state.statusMessage = "icon = " & $val
    of bsoHighlightCurrentLine:
      e.config.highlight.currentLine = val
      e.state.statusMessage = "highlightcurrentline = " & $val
    of bsoHighlightCurrentWord:
      e.config.highlight.currentWord = val
      e.state.statusMessage = "highlightcurrentword = " & $val
    of bsoHighlightFullWidthSpace:
      e.config.highlight.fullWidthSpace = val
      e.state.statusMessage = "highlightfullspace = " & $val
    of bsoHighlightPairOfParen:
      e.config.highlight.pairOfParen = val
      e.state.statusMessage = "highlightparen = " & $val
    of bsoHighlightFindChar:
      e.config.highlight.findCharHighlight = val
      e.state.statusMessage = "highlightfindchar = " & $val
    of bsoHighlightColorCode:
      e.config.highlight.colorCodeHighlight = val
      e.state.statusMessage = "highlightcolorcode = " & $val
    of bsoHighlightGitConflict:
      e.config.highlight.gitConflict = val
      e.state.statusMessage = "highlightgitconflict = " & $val
    of bsoHighlightGitConflictTwoColor:
      e.config.highlight.gitConflictTwoColor = val
      e.state.statusMessage = "highlightgitconflicttwocolor = " & $val
    of bsoMultipleStatusLine:
      e.config.statusLine.multipleStatusLine = val
      e.state.statusMessage = "multiplestatusline = " & $val
    of bsoIgnoreCase:
      e.state.ignorecase = val
      e.state.statusMessage = "ignorecase = " & $val
    of bsoSmartCase:
      e.state.smartcase = val
      e.state.statusMessage = "smartcase = " & $val
    of bsoIncSearch:
      e.state.incsearch = val
      e.state.statusMessage = "incsearch = " & $val
    of bsoHlSearch:
      e.state.input.search.hlsearch = val
      e.state.statusMessage = "hlsearch = " & $val
    of bsoBuildOnSave:
      e.config.buildOnSave.enable = val
      e.state.statusMessage = "buildonsave = " & $val
    of bsoShowGitInactive:
      e.config.statusLine.showGitInactive = val
      e.state.statusMessage = "showgitinactive = " & $val
    of bsoLineWrap:
      e.config.standard.lineWrap = val
      e.state.statusMessage = "wrap = " & $val
    of bsoExpandTab:
      e.state.expandTab = val
      e.state.statusMessage = "expandtab = " & $e.state.expandTab
    of bsoScrollbar:
      e.config.standard.scrollbar = val
      e.state.statusMessage = "scrollbar = " & $val
    return true
  of hrSetIntOption:
    let opt = r.intOption
    let val = r.intValue
    case opt
    of isoTabStop:
      e.state.tabStop = val
      e.state.statusMessage = "tabstop = " & $e.state.tabStop
    of isoShiftWidth:
      e.state.shiftWidth = val
      e.state.statusMessage = "shiftwidth = " & $e.state.shiftWidth
    of isoSoftTabStop:
      e.config.standard.softTabStop = val
      e.state.statusMessage = "softtabstop = " & $val
    of isoScrollbarWidth:
      e.config.standard.scrollbarWidth = val
      e.state.statusMessage = "scrollbarwidth = " & $val
    return true
  of hrSetFloatOption:
    let opt = r.floatOption
    let val = r.floatValue
    case opt
    of fsoScrollFriction:
      e.config.smoothScroll.friction = val
      e.state.statusMessage = "scrollfriction = " & $val
    of fsoScrollAirDrag:
      e.config.smoothScroll.airDrag = val
      e.state.statusMessage = "scrollairdrag = " & $val
    return true
  else:
    return true # Not a set-option kind; caller misrouted (defensive)
