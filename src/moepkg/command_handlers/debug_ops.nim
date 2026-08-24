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

## Debug-viewer side effects for hrDebug, split out of result_processor.nim so
## the debug info generation lives next to debug_viewer.nim.

import std/[monotimes, tables]

import pkg/results

import ../[debug_viewer, editor, types, viewer_mode]

import handler_result

proc processDebugResult*(e: Editor, r: HandlerResult): bool =
  ## Open or focus the debug viewer. Returns true to continue.
  case r.kind
  of hrDebug:
    if e.focusExistingViewerWindow(EditorMode.Debug):
      return true
    var debugLines: seq[string] = @[]
    let debugConfig = e.config.debug
    for i, window in e.windowManager.windows:
      generateWindowInfo(
        debugLines,
        i,
        i == e.windowManager.activeWindowIndex,
        e.bufferIndexById(window.buffer.id),
        window.viewport.x,
        window.viewport.y,
        window.viewport.width,
        window.viewport.height,
        window.viewport.topLine,
        window.viewport.leftColumn,
        window.cursor.line,
        window.cursor.column,
        debugConfig.windowNode.enable,
      )
    for i, buf in e.buffers:
      generateBufferInfo(
        debugLines,
        i,
        buf.filePath,
        buf.isModified,
        buf.readOnly,
        $buf.language,
        $buf.encoding,
        buf.len,
        buf.changeSeq,
        debugConfig.bufferStatus.enable,
      )
    generateEditorStateInfo(
      debugLines, e.state.mode, e.state.previousMode, e.activeWindow.cursor.line,
      e.activeWindow.cursor.column, e.state.input.commandText, e.state.statusMessage,
      debugConfig.editorView.enable,
    )
    generateSearchInfo(
      debugLines,
      e.state.input.search.text,
      e.state.input.search.lastText,
      $e.state.input.search.direction,
      e.state.input.search.history.len,
      e.state.input.search.ignorecase,
      e.state.input.search.smartcase,
      e.state.input.search.incsearch,
      e.state.input.search.hlsearch,
      debugConfig.search.enable,
    )
    generateDisplayInfo(
      debugLines, e.showStatusLine, e.multiStatusLine, e.showLineNumbers,
      e.showCursorLine, e.showSyntax, e.showIndentationLines, e.showSidebar,
      e.scrollbarWidth, e.showModifiedLines, e.lineWrap, e.tabStop,
      debugConfig.editorView.enable,
    )
    generateMacroInfo(
      debugLines, e.state.pendingInput.macroState.isRecording,
      e.state.pendingInput.macroState.register,
      e.state.pendingInput.macroState.registers.len,
      e.state.pendingInput.macroState.playbackDepth, debugConfig.macroState.enable,
    )
    generateVisualInfo(
      debugLines,
      e.state.visualSelection.active,
      $e.state.visualSelection.kind,
      e.state.visualSelection.start.line,
      e.state.visualSelection.start.column,
      e.state.visualSelection.current.line,
      e.state.visualSelection.current.column,
      debugConfig.visual.enable,
    )
    generateJumpListInfo(
      debugLines, e.state.jumpList.list.len, e.state.jumpList.index,
      debugConfig.jumpList.enable,
    )
    generateLspInfo(
      debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
      e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
      debugConfig.lsp.enable,
    )
    let debugState = newDebugViewerState()
    debugState.items = debugLines
    let debugBuffer = debugState.createDebugTextBuffer()
    let enterResult = e.enterViewerMode(
      EditorMode.Debug,
      ModeState(kind: mskDebug, debug: debugState),
      debugBuffer,
      vpVSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open debug: " & enterResult.error
    else:
      e.state.statusMessage = "Debug info (auto-refresh)"
      e.state.windowDisplay.debugBuffer = debugBuffer
      e.state.timing.lastDebugUpdate = getMonoTime()
      if e.state.timing.debugUpdateInterval == 0:
        e.state.timing.debugUpdateInterval = 500
    return true
  of hrDebugViewerQuit:
    e.leaveViewerMode(EditorMode.Debug)
    e.state.windowDisplay.debugBuffer = nil
    return true
  else:
    return true # Not the debug kind; caller misrouted (defensive)
