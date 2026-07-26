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

import std/[json, options, tables]

import pkg/results

import
  types/editor_types,
  viewer_mode,
  editor_lsp,
  lsp_integration,
  callhierarchy_viewer,
  editor_navigation
import lsp/protocol/types as lspTypes

const CallHierarchyFeatures = {
  lrfCallHierarchyPrepareIncoming, lrfCallHierarchyPrepareOutgoing,
  lrfCallHierarchyIncoming, lrfCallHierarchyOutgoing,
}

proc cancelAllCallHierarchy*(e: Editor) =
  for f in CallHierarchyFeatures:
    cancelIfPending(e, f)

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

  cancelAllCallHierarchy(e)

  let feature =
    if kind == chrkPrepareIncoming:
      lrfCallHierarchyPrepareIncoming
    else:
      lrfCallHierarchyPrepareOutgoing
  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column

  let ctxRes = e.startContextualRequest(
    feature,
    proc(): Result[int, string] =
      e.lsp.startCallHierarchyPrepareRequest(activeBuffer, line, col),
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & ctxRes.error
    return false
  return true

proc enterCallHierarchyMode(
    e: Editor, items: seq[lspTypes.CallHierarchyItem], viewKind: CallHierarchyViewKind
) =
  ## Enter or refresh CallHierarchy mode. Re-entry (Incoming ↔ Outgoing) keeps
  ## the origin snapshot via `enterViewerMode`.
  let chState = newCallHierarchyViewerState(items, viewKind)
  discard e.enterViewerMode(
    EditorMode.CallHierarchy,
    ModeState(kind: mskCallHierarchy, callHierarchy: chState),
    chState.createCallHierarchyTextBuffer(),
    vpInPlace,
  )

  let
    direction = if viewKind == chvkIncoming: "incoming" else: "outgoing"
    noun = if items.len == 1: "call" else: "calls"
  e.state.statusMessage = $items.len & " " & direction & " " & noun & " found"

proc handlePrepareResponse(
    e: Editor, prepareFeature: LspRequestFeature, resultOpt: Option[JsonNode]
) =
  ## Prepare completed: parse items, fire the second-stage request. The
  ## `del(prepareFeature)` already happened at the call site.
  if resultOpt.isNone:
    e.state.statusMessage = "No callable symbol at cursor"
    return

  let prepareItems = parseCallHierarchyPrepareResponse(resultOpt.get)
  if prepareItems.len == 0:
    e.state.statusMessage = "No callable symbol at cursor"
    return

  let item = prepareItems[0]
  let nextFeature =
    if prepareFeature == lrfCallHierarchyPrepareIncoming:
      lrfCallHierarchyIncoming
    else:
      lrfCallHierarchyOutgoing
  let ctxRes = e.startContextualRequest(
    nextFeature,
    proc(): Result[int, string] =
      if nextFeature == lrfCallHierarchyIncoming:
        e.lsp.startCallHierarchyIncomingCallsRequest(item)
      else:
        e.lsp.startCallHierarchyOutgoingCallsRequest(item),
    # Stage 2 targets item.uri, not the active buffer. Match the item-driven
    # semantics of requestCallHierarchy{Incoming,Outgoing}ForItem so a
    # mid-flight buffer switch doesn't silently drop the response.
    isItemDriven = true,
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & ctxRes.error

proc handleCallsResponse(
    e: Editor, feature: LspRequestFeature, resultOpt: Option[JsonNode]
) =
  ## Incoming/outgoing completed: convert items and enter CallHierarchy mode.
  # CallHierarchy re-entry (viewer toggling between Incoming and Outgoing) is
  # not covered by validModes because CallHierarchy mode itself is a valid
  # target; keep the manual guard.
  if e.state.overlay.isSome or (
    not e.state.mode.isNormalOrVisualMode and e.state.mode != EditorMode.CallHierarchy
  ):
    return

  let (viewKind, emptyMsg) =
    if feature == lrfCallHierarchyIncoming:
      (chvkIncoming, "No incoming calls found")
    else:
      (chvkOutgoing, "No outgoing calls found")

  if resultOpt.isNone:
    e.state.statusMessage = emptyMsg
    return

  var items: seq[lspTypes.CallHierarchyItem] = @[]
  if feature == lrfCallHierarchyIncoming:
    let calls = parseCallHierarchyIncomingCallsResponse(resultOpt.get)
    if calls.len == 0:
      e.state.statusMessage = emptyMsg
      return
    for call in calls:
      items.add(call.`from`)
  else:
    let calls = parseCallHierarchyOutgoingCallsResponse(resultOpt.get)
    if calls.len == 0:
      e.state.statusMessage = emptyMsg
      return
    for call in calls:
      items.add(call.to)

  e.enterCallHierarchyMode(items, viewKind)

proc pollLspCallHierarchy*(e: Editor) =
  ## Poll for pending call hierarchy request response
  ## Handles 2-stage request: prepare -> incoming/outgoing
  ##
  ## classifyResponse honours ctx.isItemDriven: for item-driven requests it
  ## skips the buffer/version guard (the viewer's synthetic buffer would
  ## otherwise trigger lrsGone) and the inline mode-hijack check in
  ## handleCallsResponse remains the sole gate.
  e.pollOneShotLspResponse(CallHierarchyFeatures, "call hierarchy"):
    if feature in {lrfCallHierarchyPrepareIncoming, lrfCallHierarchyPrepareOutgoing}:
      handlePrepareResponse(e, feature, resultOpt)
    else:
      handleCallsResponse(e, feature, resultOpt)

proc requestLspCallHierarchyIncoming*(e: Editor): bool =
  ## Request LSP incoming calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareIncoming)

proc requestLspCallHierarchyOutgoing*(e: Editor): bool =
  ## Request LSP outgoing calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareOutgoing)

proc storeItemDrivenPending(e: Editor, feature: LspRequestFeature, requestId: int) =
  ## Populate pending[feature] for a request that targets item.uri rather than
  ## the active buffer. The active buffer here is often the synthetic viewer
  ## buffer (no path), so classifyResponse's buffer/version guard doesn't
  ## apply; the mode-hijack check inside handleCallsResponse is sufficient.
  storeContextualRequest(
    e.state.lspCache, feature, e.activeBuffer, requestId, isItemDriven = true
  )

proc requestCallHierarchyIncomingForItem*(
    e: Editor, item: lspTypes.CallHierarchyItem
): bool =
  ## Request incoming calls for a specific CallHierarchyItem (async)
  ## Used from CallHierarchy mode when user presses 'i'
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  cancelAllCallHierarchy(e)
  let reqRes = e.lsp.startCallHierarchyIncomingCallsRequest(item)
  if reqRes.isErr:
    e.state.statusMessage = "LSP incoming calls failed: " & reqRes.error
    return false
  storeItemDrivenPending(e, lrfCallHierarchyIncoming, reqRes.get)
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

  cancelAllCallHierarchy(e)
  let reqRes = e.lsp.startCallHierarchyOutgoingCallsRequest(item)
  if reqRes.isErr:
    e.state.statusMessage = "LSP outgoing calls failed: " & reqRes.error
    return false
  storeItemDrivenPending(e, lrfCallHierarchyOutgoing, reqRes.get)
  return true

proc jumpToCallHierarchyItem*(e: Editor, item: lspTypes.CallHierarchyItem): bool =
  ## Jump to a CallHierarchyItem location
  ## Returns true if successful
  let loc = lspTypes.Location(uri: item.uri, range: item.selectionRange)
  return e.jumpToLspLocation(loc, "Call Hierarchy")
