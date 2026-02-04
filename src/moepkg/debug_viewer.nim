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

## Debug mode viewer for displaying internal editor state
## Similar to the debug mode in the original moe editor

import std/[strutils, options]

import modes

type DebugViewerState* = ref object ## State for the debug mode viewer
  lines*: seq[string] # Debug information lines
  topLine*: int # Top visible line (for scrolling)
  selectedLine*: int # Currently selected line (for navigation)

proc newDebugViewerState*(): DebugViewerState =
  DebugViewerState(lines: @[], topLine: 0, selectedLine: 0)

proc formatBool(b: bool): string =
  if b: "true" else: "false"

proc formatOption[T](opt: Option[T]): string =
  if opt.isSome:
    $opt.get
  else:
    "none"

proc addSection(lines: var seq[string], title: string) =
  lines.add("")
  lines.add("-- " & title & " --")

proc addField(lines: var seq[string], name: string, value: string) =
  let paddedName = name.alignLeft(24)
  lines.add("  " & paddedName & " : " & value)

proc generateWindowInfo*(
    lines: var seq[string],
    windowIndex: int,
    isActive: bool,
    bufferIndex: int,
    viewportX, viewportY: int,
    viewportWidth, viewportHeight: int,
    viewportTopLine, viewportLeftColumn: int,
    cursorLine, cursorColumn: int,
    enabled: bool = true,
) =
  ## Generate debug info for a window
  if not enabled:
    return
  lines.addSection("Window " & $windowIndex)
  lines.addField("active", formatBool(isActive))
  lines.addField("bufferIndex", $bufferIndex)
  lines.addField("viewport.x", $viewportX)
  lines.addField("viewport.y", $viewportY)
  lines.addField("viewport.width", $viewportWidth)
  lines.addField("viewport.height", $viewportHeight)
  lines.addField("viewport.topLine", $viewportTopLine)
  lines.addField("viewport.leftColumn", $viewportLeftColumn)
  lines.addField("cursor.line", $cursorLine)
  lines.addField("cursor.column", $cursorColumn)

proc generateBufferInfo*(
    lines: var seq[string],
    bufferIndex: int,
    filePath: Option[string],
    isModified: bool,
    isReadOnly: bool,
    language: string,
    encoding: string,
    lineCount: int,
    changeSeq: int,
    enabled: bool = true,
) =
  ## Generate debug info for a buffer
  if not enabled:
    return
  lines.addSection("Buffer " & $bufferIndex)
  lines.addField("path", formatOption(filePath))
  lines.addField("isModified", formatBool(isModified))
  lines.addField("readOnly", formatBool(isReadOnly))
  lines.addField("language", language)
  lines.addField("encoding", encoding)
  lines.addField("lineCount", $lineCount)
  lines.addField("changeSeq", $changeSeq)

proc generateEditorStateInfo*(
    lines: var seq[string],
    mode: EditorMode,
    previousMode: EditorMode,
    cursorLine, cursorColumn: int,
    commandText: string,
    statusMessage: string,
    enabled: bool = true,
) =
  ## Generate debug info for editor state
  if not enabled:
    return
  lines.addSection("EditorState")
  lines.addField("mode", $mode)
  lines.addField("previousMode", $previousMode)
  lines.addField("cursor.line", $cursorLine)
  lines.addField("cursor.column", $cursorColumn)
  lines.addField("commandText", commandText)
  lines.addField("statusMessage", statusMessage)

proc generateSearchInfo*(
    lines: var seq[string],
    searchText: string,
    lastSearchText: string,
    searchDirection: string,
    historyLen: int,
    ignorecase: bool,
    smartcase: bool,
    incsearch: bool,
    hlsearch: bool,
    enabled: bool = true,
) =
  ## Generate debug info for search state
  if not enabled:
    return
  lines.addSection("SearchState")
  lines.addField("text", searchText)
  lines.addField("lastText", lastSearchText)
  lines.addField("direction", searchDirection)
  lines.addField("historyLen", $historyLen)
  lines.addField("ignorecase", formatBool(ignorecase))
  lines.addField("smartcase", formatBool(smartcase))
  lines.addField("incsearch", formatBool(incsearch))
  lines.addField("hlsearch", formatBool(hlsearch))

proc generateDisplayInfo*(
    lines: var seq[string],
    showStatusLine: bool,
    multiStatusLine: bool,
    showLineNumbers: bool,
    showCursorLine: bool,
    showSyntax: bool,
    showIndentationLines: bool,
    showSidebar: bool,
    lineWrap: bool,
    tabStop: int,
    enabled: bool = true,
) =
  ## Generate debug info for display settings
  if not enabled:
    return
  lines.addSection("DisplaySettings")
  lines.addField("showStatusLine", formatBool(showStatusLine))
  lines.addField("multiStatusLine", formatBool(multiStatusLine))
  lines.addField("showLineNumbers", formatBool(showLineNumbers))
  lines.addField("showCursorLine", formatBool(showCursorLine))
  lines.addField("showSyntax", formatBool(showSyntax))
  lines.addField("showIndentationLines", formatBool(showIndentationLines))
  lines.addField("showSidebar", formatBool(showSidebar))
  lines.addField("lineWrap", formatBool(lineWrap))
  lines.addField("tabStop", $tabStop)

proc generateMacroInfo*(
    lines: var seq[string],
    isRecording: bool,
    register: char,
    registersCount: int,
    playbackDepth: int,
    enabled: bool = true,
) =
  ## Generate debug info for macro state
  if not enabled:
    return
  lines.addSection("MacroState")
  lines.addField("isRecording", formatBool(isRecording))
  lines.addField("register", $register)
  lines.addField("registersCount", $registersCount)
  lines.addField("playbackDepth", $playbackDepth)

proc generateVisualInfo*(
    lines: var seq[string],
    active: bool,
    kind: string,
    startLine, startColumn: int,
    currentLine, currentColumn: int,
    enabled: bool = true,
) =
  ## Generate debug info for visual selection
  if not enabled:
    return
  lines.addSection("VisualSelection")
  lines.addField("active", formatBool(active))
  lines.addField("kind", kind)
  lines.addField("start.line", $startLine)
  lines.addField("start.column", $startColumn)
  lines.addField("current.line", $currentLine)
  lines.addField("current.column", $currentColumn)

proc generateJumpListInfo*(
    lines: var seq[string], jumpListLen: int, jumpListIndex: int, enabled: bool = true
) =
  ## Generate debug info for jump list
  if not enabled:
    return
  lines.addSection("JumpList")
  lines.addField("length", $jumpListLen)
  lines.addField("index", $jumpListIndex)

proc generateLspInfo*(
    lines: var seq[string],
    codeLensCount: int,
    hasLocations: bool,
    isValid: bool,
    enabled: bool = true,
) =
  ## Generate debug info for LSP state
  if not enabled:
    return
  lines.addSection("LspState")
  lines.addField("codeLensCount", $codeLensCount)
  lines.addField("hasLocations", formatBool(hasLocations))
  lines.addField("cacheValid", formatBool(isValid))

proc scrollUp*(state: DebugViewerState) =
  ## Scroll up one line
  if state.selectedLine > 0:
    state.selectedLine -= 1
    if state.selectedLine < state.topLine:
      state.topLine = state.selectedLine

proc scrollDown*(state: DebugViewerState, visibleHeight: int) =
  ## Scroll down one line
  if state.selectedLine < state.lines.len - 1:
    state.selectedLine += 1
    if state.selectedLine >= state.topLine + visibleHeight:
      state.topLine = state.selectedLine - visibleHeight + 1

proc scrollToTop*(state: DebugViewerState) =
  ## Scroll to the top
  state.selectedLine = 0
  state.topLine = 0

proc scrollToBottom*(state: DebugViewerState, visibleHeight: int) =
  ## Scroll to the bottom
  state.selectedLine = max(0, state.lines.len - 1)
  state.topLine = max(0, state.lines.len - visibleHeight)

proc pageUp*(state: DebugViewerState, visibleHeight: int) =
  ## Page up
  let pageSize = max(1, visibleHeight - 1)
  state.selectedLine = max(0, state.selectedLine - pageSize)
  state.topLine = max(0, state.topLine - pageSize)

proc pageDown*(state: DebugViewerState, visibleHeight: int) =
  ## Page down
  let pageSize = max(1, visibleHeight - 1)
  state.selectedLine = min(state.lines.len - 1, state.selectedLine + pageSize)
  let maxTopLine = max(0, state.lines.len - visibleHeight)
  state.topLine = min(maxTopLine, state.topLine + pageSize)
