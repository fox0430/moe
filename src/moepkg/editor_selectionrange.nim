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
##
## Selection Range expands the visual selection outward through the syntactic
## structure (Ctrl-s). For a single position the language server returns a
## chain of nested ranges linked by `parent` (innermost first). We flatten that
## chain once and cache it; each subsequent Ctrl-s walks one level outward
## without re-querying the server. A fresh request is only sent when the
## selection no longer sits on the cached chain (e.g. the cursor moved or the
## user adjusted the selection by hand), and expansion stops at the outermost
## level instead of collapsing back to the innermost range.

import std/options

import types/editor_types, lsp_integration

proc normalizedSelection(sel: VisualSelection): tuple[first, last: BufferPosition] =
  ## Order the selection endpoints so `first` precedes `last`.
  let
    a = sel.start
    b = sel.current
  if a.line < b.line or (a.line == b.line and a.column <= b.column):
    (a, b)
  else:
    (b, a)

proc toRuneRange(e: Editor, r: Range): tuple[first, last: BufferPosition] =
  ## Convert an LSP (UTF-16) range into rune-index buffer positions.
  let buf = e.activeBuffer()
  let startLine = r.start.line
  let startText =
    if startLine >= 0 and startLine < buf.len:
      buf.getLine(startLine)
    else:
      ""
  let endLine = r.`end`.line
  let endText =
    if endLine >= 0 and endLine < buf.len:
      buf.getLine(endLine)
    else:
      ""
  (
    BufferPosition(
      line: startLine, column: utf16ToRuneIndex(startText, r.start.character)
    ),
    BufferPosition(line: endLine, column: utf16ToRuneIndex(endText, r.`end`.character)),
  )

proc flattenSelectionChain(
    e: Editor, sr: SelectionRange
): seq[tuple[first, last: BufferPosition]] =
  ## Walk the `parent` links into a flat innermost -> outermost list.
  var cur = sr
  while cur != nil:
    result.add(e.toRuneRange(cur.range))
    cur = cur.parent

proc applySelectionRange(e: Editor, level: tuple[first, last: BufferPosition]) =
  ## Enter Visual mode (if not already) and select the given range.
  if e.state.mode != EditorMode.Visual:
    e.state.previousMode = e.state.mode
    e.setMode(EditorMode.Visual)
  e.state.visualSelection = VisualSelection(
    kind: vskChar, start: level.first, current: level.last, active: true
  )
  e.cursor = level.last

proc selectionChainPosition(e: Editor): int =
  ## Index of the cached chain level that matches the current selection, or -1
  ## if the selection no longer sits on the chain.
  let c = e.state.lspCache
  if c.selectionRangeChain.len == 0:
    return -1
  if e.state.mode != EditorMode.Visual or not e.state.visualSelection.active:
    return -1
  if c.selectionRangeIndex < 0 or c.selectionRangeIndex >= c.selectionRangeChain.len:
    return -1
  let cur = normalizedSelection(e.state.visualSelection)
  let lvl = c.selectionRangeChain[c.selectionRangeIndex]
  if cur.first == lvl.first and cur.last == lvl.last:
    return c.selectionRangeIndex
  return -1

proc startLspSelectionRange*(e: Editor): bool =
  ## Expand the cached selection range chain one level outward, or start a new
  ## LSP selection range request at the cursor when there is no usable chain.
  ## Returns true if a request was started or the selection was expanded.
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  if not e.config.lsp.selectionRange.enable:
    e.state.statusMessage = "LSP selection range is disabled"
    return false

  # Already on the chain: expand outward without re-querying, and stop (do
  # nothing) once the outermost level is reached.
  let pos = e.selectionChainPosition()
  if pos >= 0:
    if pos + 1 < e.state.lspCache.selectionRangeChain.len:
      e.state.lspCache.selectionRangeIndex = pos + 1
      e.applySelectionRange(e.state.lspCache.selectionRangeChain[pos + 1])
    return true

  # Fresh request: drop any stale chain and query at the cursor position.
  e.state.lspCache.selectionRangeChain = @[]
  e.state.lspCache.selectionRangeIndex = 0

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
  ## Poll for a pending selection range response and seed the expansion chain.
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
    var applied = false
    if resultOpt.isSome:
      let ranges = parseSelectionRangeResponse(resultOpt.get)
      if ranges.len > 0 and ranges[0] != nil:
        # Flatten the parent chain (innermost -> outermost) and select the
        # innermost range. Repeated Ctrl-s walks outward over this cache.
        let chain = e.flattenSelectionChain(ranges[0])
        if chain.len > 0:
          e.state.lspCache.selectionRangeChain = chain
          e.state.lspCache.selectionRangeIndex = 0
          e.applySelectionRange(chain[0])
          applied = true
    if not applied:
      e.state.statusMessage = "No selection range available"
  of lrsError:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP selection range failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    e.state.statusMessage = "LSP selection range timed out"

proc requestLspSelectionRange*(e: Editor): bool =
  ## Request LSP selection range (or expand) at the current cursor position.
  ## Returns true if a request was started or the selection was expanded.
  e.startLspSelectionRange()
