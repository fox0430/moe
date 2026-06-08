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

## LSP Selection Range request / poll orchestration

import std/options

import editor_types, lsp_integration

proc startLspSelectionRange*(e: Editor): bool =
  ## Start async LSP selection range request at current cursor position
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending selection range request
  if e.state.lspCache.pendingSelectionRangeRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingSelectionRangeRequestId)
    e.state.lspCache.pendingSelectionRangeRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult = e.lsp.startSelectionRangeRequest(
    activeBuffer, e.activeWindow.cursor.line, e.activeWindow.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP selection range failed: " & reqResult.error
    return false

  e.state.lspCache.pendingSelectionRangeRequestId = reqResult.get
  return true

proc pollLspSelectionRange*(e: Editor) =
  ## Poll for pending selection range response
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingSelectionRangeRequestId
  if requestId == 0:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    if resultOpt.isSome:
      let ranges = parseSelectionRangeResponse(resultOpt.get)
      if ranges.len > 0:
        let selRange = ranges[0]
        let activeBuffer = e.activeBuffer()

        # Convert LSP UTF-16 positions to rune indexes (BufferPosition.column)
        let startLine = selRange.range.start.line
        let startLineText =
          if startLine >= 0 and startLine < activeBuffer.len:
            activeBuffer.getLine(startLine)
          else:
            ""
        let startCol = utf16ToRuneIndex(startLineText, selRange.range.start.character)

        let endLine = selRange.range.`end`.line
        let endLineText =
          if endLine >= 0 and endLine < activeBuffer.len:
            activeBuffer.getLine(endLine)
          else:
            ""
        let endCol = utf16ToRuneIndex(endLineText, selRange.range.`end`.character)

        # Enter visual mode and set selection to the range
        e.state.previousMode = e.state.mode
        e.setMode(EditorMode.Visual)
        e.state.visualSelection = VisualSelection(
          kind: vskChar,
          start: BufferPosition(line: startLine, column: startCol),
          current: BufferPosition(line: endLine, column: endCol),
          active: true,
        )
        e.cursor = BufferPosition(line: endLine, column: endCol)
      else:
        e.state.statusMessage = "No selection range available"
    else:
      e.state.statusMessage = "No selection range available"
  of lrsError:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP selection range failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    e.state.statusMessage = "LSP selection range timed out"

proc requestLspSelectionRange*(e: Editor): bool =
  ## Request LSP selection range at current cursor position (async)
  ## Returns true if request was started
  e.startLspSelectionRange()
