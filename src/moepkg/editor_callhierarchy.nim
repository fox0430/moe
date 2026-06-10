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

## LSP Call Hierarchy: three-stage cascade
## (prepare → incoming/outgoing) plus per-item incoming/outgoing requests
## driven from CallHierarchy mode.

import std/options

import
  editor_types, editor_window_state, lsp_integration, callhierarchy_viewer,
  editor_navigation
import lsp/protocol/types as lspTypes

proc startCallHierarchyRequest(e: Editor, kind: CallHierarchyRequestKind): bool =
  ## Start an async call hierarchy request (2-stage: prepare -> incoming/outgoing)
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  if not e.config.lsp.callHierarchy.enable:
    e.state.statusMessage = "LSP call hierarchy is disabled"
    return false

  let activeBuffer = e.activeBuffer()

  if not e.lsp.hasCallHierarchySupport(activeBuffer):
    e.state.statusMessage = "Call hierarchy not supported"
    return false

  # Cancel any pending call hierarchy request
  if e.state.lspCache.pendingCallHierarchyRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingCallHierarchyRequestId)
    e.state.lspCache.pendingCallHierarchyRequestId = 0
  e.state.lspCache.pendingCallHierarchyKind = chrkNone

  # Start with prepare request
  let reqResult = e.lsp.startCallHierarchyPrepareRequest(
    activeBuffer, e.activeWindow.cursor.line, e.activeWindow.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & reqResult.error
    return false

  e.state.lspCache.pendingCallHierarchyRequestId = reqResult.get
  e.state.lspCache.pendingCallHierarchyKind = kind
  return true

proc enterCallHierarchyMode(
    e: Editor, items: seq[lspTypes.CallHierarchyItem], viewKind: CallHierarchyViewKind
) =
  ## Enter (or refresh) CallHierarchy mode with the given items.
  ## Preserve originalBuffer from the previous CallHierarchy entry when
  ## switching between Incoming and Outgoing views; otherwise we are entering
  ## CallHierarchy fresh and should save the current buffer.
  let
    chState = newCallHierarchyViewerState(items, viewKind)
    activeWin = e.activeWindow

  if e.state.mode == EditorMode.CallHierarchy and
      activeWin.modeState.kind == mskCallHierarchy and activeWin.originalBuffer != nil:
    # Re-entering (incoming/outgoing switch): carry over the origin position
    # captured when the viewer was first opened.
    let prev = activeWin.modeState.callHierarchy
    chState.originCursor = prev.originCursor
    chState.originTopLine = prev.originTopLine
    chState.originLeftColumn = prev.originLeftColumn
  else:
    e.state.previousMode = e.state.mode
    # Capture the current position so quitting the viewer can restore it.
    chState.originCursor = activeWin.cursor
    chState.originTopLine = activeWin.viewport.topLine
    chState.originLeftColumn = activeWin.viewport.leftColumn
    activeWin.saveOriginalBuffer()

  e.setMode(EditorMode.CallHierarchy)
  activeWin.buffer = chState.createCallHierarchyTextBuffer()
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.topLine = 0
  activeWin.viewport.leftColumn = 0
  activeWin.modeState = ModeState(kind: mskCallHierarchy, callHierarchy: chState)

  let
    direction = if viewKind == chvkIncoming: "incoming" else: "outgoing"
    noun = if items.len == 1: "call" else: "calls"
  e.state.statusMessage = $items.len & " " & direction & " " & noun & " found"

proc pollLspCallHierarchy*(e: Editor) =
  ## Poll for pending call hierarchy request response
  ## Handles 2-stage request: prepare -> incoming/outgoing
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingCallHierarchyRequestId
  if requestId == 0:
    return

  let kind = e.state.lspCache.pendingCallHierarchyKind
  if kind == chrkNone:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    case kind
    of chrkPrepareIncoming, chrkPrepareOutgoing:
      # First stage complete - parse prepare result and start second stage
      if resultOpt.isSome:
        let prepareItems = parseCallHierarchyPrepareResponse(resultOpt.get)
        if prepareItems.len == 0:
          e.state.lspCache.pendingCallHierarchyRequestId = 0
          e.state.lspCache.pendingCallHierarchyKind = chrkNone
          e.state.statusMessage = "No callable symbol at cursor"
          return

        # Start second stage request
        let item = prepareItems[0]
        let secondReqResult =
          if kind == chrkPrepareIncoming:
            e.lsp.startCallHierarchyIncomingCallsRequest(item)
          else:
            e.lsp.startCallHierarchyOutgoingCallsRequest(item)

        if secondReqResult.isErr:
          e.state.lspCache.pendingCallHierarchyRequestId = 0
          e.state.lspCache.pendingCallHierarchyKind = chrkNone
          e.state.statusMessage = "LSP call hierarchy failed: " & secondReqResult.error
          return

        e.state.lspCache.pendingCallHierarchyRequestId = secondReqResult.get
        e.state.lspCache.pendingCallHierarchyKind =
          if kind == chrkPrepareIncoming: chrkIncomingCalls else: chrkOutgoingCalls
      else:
        e.state.lspCache.pendingCallHierarchyRequestId = 0
        e.state.lspCache.pendingCallHierarchyKind = chrkNone
        e.state.statusMessage = "No callable symbol at cursor"
    of chrkIncomingCalls:
      # Second stage complete - show incoming calls in CallHierarchy mode
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyIncomingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No incoming calls found"
          return

        # Convert incoming calls to CallHierarchyItem list
        var items: seq[lspTypes.CallHierarchyItem] = @[]
        for call in calls:
          items.add(call.`from`)

        e.enterCallHierarchyMode(items, chvkIncoming)
      else:
        e.state.statusMessage = "No incoming calls found"
    of chrkOutgoingCalls:
      # Second stage complete - show outgoing calls in CallHierarchy mode
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyOutgoingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No outgoing calls found"
          return

        # Convert outgoing calls to CallHierarchyItem list
        var items: seq[lspTypes.CallHierarchyItem] = @[]
        for call in calls:
          items.add(call.to)

        e.enterCallHierarchyMode(items, chvkOutgoing)
      else:
        e.state.statusMessage = "No outgoing calls found"
    of chrkNone:
      discard
  of lrsError:
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    if errorOpt.isSome:
      e.state.statusMessage = "LSP call hierarchy failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    e.state.statusMessage = "LSP call hierarchy timed out"

proc requestLspCallHierarchyIncoming*(e: Editor): bool =
  ## Request LSP incoming calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareIncoming)

proc requestLspCallHierarchyOutgoing*(e: Editor): bool =
  ## Request LSP outgoing calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareOutgoing)

proc requestCallHierarchyIncomingForItem*(
    e: Editor, item: lspTypes.CallHierarchyItem
): bool =
  ## Request incoming calls for a specific CallHierarchyItem (async)
  ## Used from CallHierarchy mode when user presses 'i'
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending call hierarchy request
  if e.state.lspCache.pendingCallHierarchyRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingCallHierarchyRequestId)
    e.state.lspCache.pendingCallHierarchyRequestId = 0
  e.state.lspCache.pendingCallHierarchyKind = chrkNone

  let reqResult = e.lsp.startCallHierarchyIncomingCallsRequest(item)
  if reqResult.isErr:
    e.state.statusMessage = "LSP incoming calls failed: " & reqResult.error
    return false

  e.state.lspCache.pendingCallHierarchyRequestId = reqResult.get
  e.state.lspCache.pendingCallHierarchyKind = chrkIncomingCalls
  return true

proc requestCallHierarchyOutgoingForItem*(
    e: Editor, item: lspTypes.CallHierarchyItem
): bool =
  ## Request outgoing calls for a specific CallHierarchyItem (async)
  ## Used from CallHierarchy mode when user presses 'o'
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending call hierarchy request
  if e.state.lspCache.pendingCallHierarchyRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingCallHierarchyRequestId)
    e.state.lspCache.pendingCallHierarchyRequestId = 0
  e.state.lspCache.pendingCallHierarchyKind = chrkNone

  let reqResult = e.lsp.startCallHierarchyOutgoingCallsRequest(item)
  if reqResult.isErr:
    e.state.statusMessage = "LSP outgoing calls failed: " & reqResult.error
    return false

  e.state.lspCache.pendingCallHierarchyRequestId = reqResult.get
  e.state.lspCache.pendingCallHierarchyKind = chrkOutgoingCalls
  return true

proc jumpToCallHierarchyItem*(e: Editor, item: lspTypes.CallHierarchyItem): bool =
  ## Jump to a CallHierarchyItem location
  ## Returns true if successful
  let loc = lspTypes.Location(uri: item.uri, range: item.selectionRange)
  return e.jumpToLspLocation(loc, "Call Hierarchy")
