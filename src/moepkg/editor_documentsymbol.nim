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

import std/[options, tables]

import pkg/results

import
  types/editor_types, viewer_mode, editor_lsp, lsp_integration, documentsymbol_viewer

const DocumentSymbolValidModes* =
  {EditorMode.Normal, EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

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

  let ctxRes = e.startContextualRequest(
    lrfDocumentSymbol,
    proc(): Result[int, string] =
      e.lsp.startDocumentSymbolsRequest(activeBuffer),
    validModes = DocumentSymbolValidModes,
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP document symbols failed: " & ctxRes.error
    return false
  return true

proc pollLspDocumentSymbols*(e: Editor) =
  ## Poll for pending document symbols response
  e.pollOneShotLspResponse({lrfDocumentSymbol}, "document symbols"):
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

      discard e.enterViewerMode(
        EditorMode.DocumentSymbol,
        ModeState(kind: mskDocumentSymbol, documentSymbol: viewerState),
        viewerState.createDocumentSymbolTextBuffer(),
        vpInPlace,
      )
      e.state.statusMessage = $symbolCount & " symbols found"
    else:
      e.state.statusMessage = "No symbols found"

proc requestDocumentSymbols*(e: Editor): bool =
  ## Request document symbols (async)
  ## Returns true if request was started
  e.startLspDocumentSymbols()
