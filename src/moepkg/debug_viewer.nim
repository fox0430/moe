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

import std/[strutils, options, times]

import modes, buffer/core, list_viewer

import types/debug_viewer_types
export debug_viewer_types, list_viewer

proc newDebugViewerState*(): DebugViewerState =
  DebugViewerState(items: @[], selectedIndex: 0)

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

proc generateWindowNodeInfo*(
    lines: var seq[string],
    currentWindow: bool,
    index: int,
    windowIndex: int,
    bufferIndex: int,
    parentIndex: int,
    childLen: int,
    splitType: string,
    isActualWin: bool,
    y, x, h, w: int,
    currentLine: int,
    currentColumn: int,
    expandedColumn: int,
    cursor: string,
    config:
      tuple[
        enable: bool,
        currentWindow: bool,
        index: bool,
        windowIndex: bool,
        bufferIndex: bool,
        parentIndex: bool,
        childLen: bool,
        splitType: bool,
        haveCursesWin: bool,
        y: bool,
        x: bool,
        h: bool,
        w: bool,
        currentLine: bool,
        currentColumn: bool,
        expandedColumn: bool,
        cursor: bool,
      ],
) =
  ## Generate debug info for a WindowNode (with full config support)
  if not config.enable:
    return

  lines.addSection("WindowNode")

  if config.currentWindow:
    lines.addField("currentWindow", formatBool(currentWindow))
  if config.index:
    lines.addField("index", $index)
  if config.windowIndex:
    lines.addField("windowIndex", $windowIndex)
  if config.bufferIndex:
    lines.addField("bufferIndex", $bufferIndex)
  if config.parentIndex:
    lines.addField("parentIndex", $parentIndex)
  if config.childLen:
    lines.addField("child length", $childLen)
  if config.splitType:
    lines.addField("splitType", splitType)
  if config.haveCursesWin:
    lines.addField("IsActualWin", formatBool(isActualWin))
  if config.y:
    lines.addField("y", $y)
  if config.x:
    lines.addField("x", $x)
  if config.h:
    lines.addField("h", $h)
  if config.w:
    lines.addField("w", $w)
  if config.currentLine:
    lines.addField("currentLine", $currentLine)
  if config.currentColumn:
    lines.addField("currentColumn", $currentColumn)
  if config.expandedColumn:
    lines.addField("expandedColumn", $expandedColumn)
  if config.cursor:
    lines.addField("cursor", cursor)

# EditorView info (with full config support for original moe compatibility)

proc generateEditorViewInfo*(
    lines: var seq[string],
    widthOfLineNum: int,
    height: int,
    width: int,
    originalLine: seq[int],
    start: seq[int],
    length: seq[int],
    config:
      tuple[
        enable: bool,
        widthOfLineNum: bool,
        height: bool,
        width: bool,
        originalLine: bool,
        start: bool,
        length: bool,
      ],
) =
  ## Generate debug info for EditorView (with full config support)
  if not config.enable:
    return

  lines.addSection("editorview")

  if config.widthOfLineNum:
    lines.addField("widthOfLineNum", $widthOfLineNum)
  if config.height:
    lines.addField("height", $height)
  if config.width:
    lines.addField("width", $width)
  if config.originalLine:
    lines.addField("originalLine", $originalLine)
  if config.start:
    lines.addField("start", $start)
  if config.length:
    lines.addField("length", $length)

proc generateBufferStatusInfo*(
    lines: var seq[string],
    bufferIndex: int,
    path: string,
    openDir: string,
    currentMode: string,
    prevMode: string,
    language: string,
    encoding: string,
    countChange: int,
    cmdLoop: int,
    lastSaveTime: DateTime,
    bufferLen: int,
    config:
      tuple[
        enable: bool,
        bufferIndex: bool,
        path: bool,
        openDir: bool,
        currentMode: bool,
        prevMode: bool,
        language: bool,
        encoding: bool,
        countChange: bool,
        cmdLoop: bool,
        lastSaveTime: bool,
        bufferLen: bool,
      ],
) =
  ## Generate debug info for BufferStatus (with full config support)
  if not config.enable:
    return

  if bufferIndex == 0:
    lines.addSection("bufStatus")

  if config.bufferIndex:
    lines.addField("bufferIndex", $bufferIndex)
  if config.path:
    lines.addField("path", path)
  if config.openDir:
    lines.addField("openDir", openDir)
  if config.currentMode:
    lines.addField("currentMode", currentMode)
  if config.prevMode:
    lines.addField("prevMode", prevMode)
  if config.language:
    lines.addField("language", language)
  if config.encoding:
    lines.addField("encoding", encoding)
  if config.countChange:
    lines.addField("countChange", $countChange)
  if config.cmdLoop:
    lines.addField("cmdLoop", $cmdLoop)
  if config.lastSaveTime:
    lines.addField("lastSaveTime", $lastSaveTime)
  if config.bufferLen:
    lines.addField("buffer length", $bufferLen)

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
    scrollbarWidth: int,
    showModifiedLines: bool,
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
  lines.addField("scrollbarWidth", $scrollbarWidth)
  lines.addField("showModifiedLines", formatBool(showModifiedLines))
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

proc createDebugTextBuffer*(state: DebugViewerState): TextBuffer =
  ## Create a TextBuffer from debug lines for rendering via the normal view path
  var content = ""
  for i, line in state.items:
    if i > 0:
      content.add('\n')
    content.add(line)
  result = newTextBuffer(content)
  result.readOnly = true
