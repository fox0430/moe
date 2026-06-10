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

## LSP Document Symbols request / poll orchestration

import std/options

import editor_types, editor_window_state, lsp_integration, documentsymbol_viewer

proc startLspDocumentSymbols*(e: Editor): bool =
  ## Start async document symbols request
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  if not e.config.lsp.documentSymbol.enable:
    e.state.statusMessage = "LSP document symbol is disabled"
    return false

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.state.statusMessage = "No file path for current buffer"
    return false

  # Check if document symbol is supported
  if not e.lsp.hasDocumentSymbolSupport(activeBuffer):
    e.state.statusMessage = "Document symbols not supported"
    return false

  # Cancel any pending request
  if e.state.lspCache.pendingDocumentSymbolsRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingDocumentSymbolsRequestId)
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0

  let reqResult = e.lsp.startDocumentSymbolsRequest(activeBuffer)
  if reqResult.isErr:
    e.state.statusMessage = "LSP document symbols failed: " & reqResult.error
    return false

  e.state.lspCache.pendingDocumentSymbolsRequestId = reqResult.get
  return true

proc pollLspDocumentSymbols*(e: Editor) =
  ## Poll for pending document symbols response
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingDocumentSymbolsRequestId
  if requestId == 0:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    if resultOpt.isSome:
      let activeBuffer = e.activeBuffer()
      if activeBuffer.filePath.isNone:
        return

      let path = activeBuffer.filePath.get
      let symResult = parseDocumentSymbolsResponse(resultOpt.get)
      let viewerState = newDocumentSymbolViewerState(symResult, path)
      let symbolCount = viewerState.itemCount()

      if symbolCount == 0:
        e.state.statusMessage = "No symbols found"
        return

      # Enter DocumentSymbol mode
      e.state.previousMode = e.state.mode
      e.setMode(EditorMode.DocumentSymbol)
      let activeWin = e.activeWindow

      # Capture the current position so quitting the viewer can restore it.
      viewerState.originCursor = activeWin.cursor
      viewerState.originTopLine = activeWin.viewport.topLine
      viewerState.originLeftColumn = activeWin.viewport.leftColumn

      activeWin.saveOriginalBuffer()
      activeWin.buffer = viewerState.createDocumentSymbolTextBuffer()
      activeWin.cursor = BufferPosition(line: 0, column: 0)
      activeWin.viewport.topLine = 0
      activeWin.viewport.leftColumn = 0
      activeWin.modeState =
        ModeState(kind: mskDocumentSymbol, documentSymbol: viewerState)
      e.state.statusMessage = $symbolCount & " symbols found"
    else:
      e.state.statusMessage = "No symbols found"
  of lrsError:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP document symbols failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    e.state.statusMessage = "LSP document symbols timed out"

proc requestDocumentSymbols*(e: Editor): bool =
  ## Request document symbols (async)
  ## Returns true if request was started
  e.startLspDocumentSymbols()
