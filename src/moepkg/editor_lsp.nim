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

## LSP-related procedures for the editor

import std/[options, strutils, json]

import pkg/results

import
  editor_types, editor_file, signaturehelp, documentsymbol_viewer, references_viewer,
  lspservice, lspintegration, buffer
import lsp/protocol/types as lspTypes

proc maybeUpdateLsp*(e: Editor) =
  ## Update LSP if buffer was modified
  ## This notifies the LSP server of document changes for real-time diagnostics
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()

  # Only notify LSP if buffer has changed since last notification
  if activeBuffer.changeSeq != e.lastLspChangeSeq:
    let lspResult = e.lsp.onBufferChange(activeBuffer)
    if lspResult.isOk:
      e.lastLspChangeSeq = activeBuffer.changeSeq

proc requestSignatureHelpFromLsp*(e: Editor) =
  ## Request signature help from LSP if in insert mode with paren depth > 0
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
  if sigHelpMgr.parenDepth == 0 and not sigHelpMgr.isActive():
    return

  let activeBuffer = e.activeBuffer()

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSignatureHelpRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingSignatureHelpRequestId)
    case status
    of lrsPending:
      # Still waiting for response, continue
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      if resultOpt.isSome:
        let sigHelpOpt = parseSignatureHelpResponse(resultOpt.get)
        if sigHelpOpt.isSome:
          sigHelpMgr.show(sigHelpOpt.get, e.state.cursor.line, e.state.cursor.column)
        else:
          if sigHelpMgr.parenDepth == 0:
            sigHelpMgr.hide()
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and try again next time
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      return

  # Start a new request
  let reqResult = e.lsp.startSignatureHelpRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingSignatureHelpRequestId = reqResult.get

proc pollLspCompletion*(e: Editor) =
  ## Poll for pending LSP completion responses
  ## This should be called from the main event loop
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  # Call the insert handler's poll function
  e.handlerManager.insertHandler.pollLspCompletion()

proc switchToBufferForLsp(e: Editor, index: int) =
  ## Switch to buffer at given index (simplified version for LSP jumps)
  if index < 0 or index >= e.buffers.len:
    return

  let targetBuffer = e.buffers[index]

  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    if activeWindow.buffer == targetBuffer:
      return
    activeWindow.buffer = targetBuffer
    activeWindow.cursor = BufferPosition(line: 0, column: 0)
    activeWindow.viewport.topLine = 0
    activeWindow.viewport.leftColumn = 0
    # Sync executor and motion controller
    e.executer.buffer = targetBuffer
    e.executer.motionController.executor.buffer = targetBuffer
  else:
    e.textBuffer = targetBuffer
    e.executer.buffer = targetBuffer
    e.executer.motionController.executor.buffer = targetBuffer
    e.state.cursor = BufferPosition(line: 0, column: 0)
    e.viewport.topLine = 0
    e.viewport.leftColumn = 0

  e.state.currentBufferIndex = index
  e.state.needsFullRedraw = true

proc addToJumpList(e: Editor) =
  ## Add current cursor position to jump list before a jump
  let jumpPos = JumpPosition(
    bufferIndex: e.state.currentBufferIndex,
    line: e.state.cursor.line,
    column: e.state.cursor.column,
  )

  # Don't add if same as last position (same buffer, line, and column)
  if e.state.jumpList.len > 0:
    let lastPos = e.state.jumpList[^1]
    if lastPos.bufferIndex == jumpPos.bufferIndex and lastPos.line == jumpPos.line and
        lastPos.column == jumpPos.column:
      return

  e.state.jumpList.add(jumpPos)
  # Keep jump list at reasonable size (max 100 entries)
  if e.state.jumpList.len > 100:
    e.state.jumpList.delete(0)
  # Reset jump list index when adding new position
  e.state.jumpListIndex = -1

proc jumpToLspLocation(e: Editor, loc: lspTypes.Location, resultKind: string): bool =
  ## Jump to a single LSP location
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()
  let path = lspservice.uriToPath(loc.uri)

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    let targetLine = min(loc.range.start.line, max(0, activeBuffer.len - 1))
    let lineLen =
      if activeBuffer.len > 0:
        activeBuffer[targetLine].len
      else:
        0
    let targetCol = min(loc.range.start.character, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
    e.state.statusMessage = resultKind & " at line " & $(targetLine + 1)
  else:
    # Different file - open it in a new buffer (or switch to existing)
    # Check if buffer already exists in the buffer list
    var existingIndex = -1
    for i, buf in e.buffers:
      if buf.filePath.isSome and buf.filePath.get == path:
        existingIndex = i
        break

    if existingIndex >= 0:
      # Buffer already exists, switch to it
      e.switchToBufferForLsp(existingIndex)
    else:
      # Create new buffer and load file
      let newBuffer = newTextBuffer()
      let loadResult = newBuffer.loadFile(path)
      if loadResult.isErr:
        e.state.statusMessage = "Failed to open file: " & loadResult.error
        return false
      e.buffers.add(newBuffer)
      e.switchToBufferForLsp(e.buffers.high)

    # Set cursor with boundary checks
    let newActiveBuffer = e.activeBuffer()
    let targetLine = min(loc.range.start.line, max(0, newActiveBuffer.len - 1))
    let lineLen =
      if newActiveBuffer.len > 0:
        newActiveBuffer[targetLine].len
      else:
        0
    let targetCol = min(loc.range.start.character, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
    e.state.statusMessage = resultKind & " in " & path

  # Update viewport to follow cursor
  e.state.needsFullRedraw = true
  return true

proc handleLspLocations(
    e: Editor, locations: seq[lspTypes.Location], title: string, singularName: string
): bool =
  ## Handle LSP location results (shared by definition and references)
  ## Returns true if successful
  if locations.len == 0:
    e.state.statusMessage = "No " & title.toLowerAscii() & " found"
    return false

  if locations.len == 1:
    # Single location - jump directly
    return e.jumpToLspLocation(locations[0], singularName)
  else:
    # Multiple locations - open References viewer mode
    var items: seq[ReferenceItem] = @[]
    for loc in locations:
      let path = lspservice.uriToPath(loc.uri)
      items.add(
        ReferenceItem(
          path: path,
          line: loc.range.start.line,
          column: loc.range.start.character,
          text: "",
        )
      )

    # Enter References mode
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.References
    e.state.referencesViewerState = some(newReferencesViewerState(items, title))
    e.state.statusMessage = $locations.len & " " & title.toLowerAscii() & " found"
    return true

proc openFileAndJumpTo*(e: Editor, path: string, line, column: int): bool =
  ## Open a file and jump to a specific location
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    let targetLine = min(line, max(0, activeBuffer.len - 1))
    let lineLen =
      if activeBuffer.len > 0:
        activeBuffer[targetLine].len
      else:
        0
    let targetCol = min(column, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
  else:
    # Different file - open it
    let loadResult = e.loadFile(path)
    if loadResult.isErr:
      e.state.statusMessage = "Failed to open file: " & loadResult.error
      return false
    # Set cursor with boundary checks (loadFile already loaded into e.textBuffer)
    let targetLine = min(line, max(0, e.textBuffer.len - 1))
    let lineLen =
      if e.textBuffer.len > 0:
        e.textBuffer[targetLine].len
      else:
        0
    let targetCol = min(column, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)

  # Update viewport to follow cursor
  e.state.needsFullRedraw = true
  return true

proc startLspLocationRequest(e: Editor, kind: LspLocationRequestKind): bool =
  ## Start an async LSP location request (definition, declaration, references, etc.)
  ## Returns true if request was started successfully
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending location request
  e.state.lspCache.pendingLocationRequestId = 0
  e.state.lspCache.pendingLocationRequestKind = lrkNone

  let activeBuffer = e.activeBuffer()
  let line = e.state.cursor.line
  let col = e.state.cursor.column

  let reqResult =
    case kind
    of lrkDefinition:
      e.lsp.startDefinitionRequest(activeBuffer, line, col)
    of lrkDeclaration:
      e.lsp.startDeclarationRequest(activeBuffer, line, col)
    of lrkReferences:
      e.lsp.startReferencesRequest(activeBuffer, line, col)
    of lrkTypeDefinition:
      e.lsp.startTypeDefinitionRequest(activeBuffer, line, col)
    of lrkImplementation:
      e.lsp.startImplementationRequest(activeBuffer, line, col)
    of lrkNone:
      return false

  if reqResult.isErr:
    let kindName =
      case kind
      of lrkDefinition: "definition"
      of lrkDeclaration: "declaration"
      of lrkReferences: "references"
      of lrkTypeDefinition: "type definition"
      of lrkImplementation: "implementation"
      of lrkNone: ""
    e.state.statusMessage = "LSP " & kindName & " failed: " & reqResult.error
    return false

  e.state.lspCache.pendingLocationRequestId = reqResult.get
  e.state.lspCache.pendingLocationRequestKind = kind
  return true

proc pollLspLocationRequest*(e: Editor) =
  ## Poll for pending LSP location request response
  ## This should be called from the main event loop (tick function)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingLocationRequestId
  if requestId == 0:
    return

  let kind = e.state.lspCache.pendingLocationRequestKind
  if kind == lrkNone:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    if resultOpt.isSome:
      let locations = parseLocationsResponse(resultOpt.get)
      let (pluralName, singularName) =
        case kind
        of lrkDefinition:
          ("Definitions", "Definition")
        of lrkDeclaration:
          ("Declarations", "Declaration")
        of lrkReferences:
          ("References", "Reference")
        of lrkTypeDefinition:
          ("Type Definitions", "Type Definition")
        of lrkImplementation:
          ("Implementations", "Implementation")
        of lrkNone:
          ("", "")
      discard e.handleLspLocations(locations, pluralName, singularName)
    else:
      e.state.statusMessage = "No results found"
  of lrsError:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    if errorOpt.isSome:
      e.state.statusMessage = "LSP request failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    e.state.statusMessage = "LSP request timed out"

proc requestLspGotoDefinition*(e: Editor): bool =
  ## Request LSP goto definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDefinition)

proc requestLspGotoDeclaration*(e: Editor): bool =
  ## Request LSP goto declaration at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDeclaration)

proc requestLspReferences*(e: Editor): bool =
  ## Request LSP find references at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkReferences)

proc startCallHierarchyRequest(e: Editor, kind: CallHierarchyRequestKind): bool =
  ## Start an async call hierarchy request (2-stage: prepare -> incoming/outgoing)
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()

  if not e.lsp.hasCallHierarchySupport(activeBuffer):
    e.state.statusMessage = "Call hierarchy not supported"
    return false

  # Cancel any pending call hierarchy request
  e.state.lspCache.pendingCallHierarchyRequestId = 0
  e.state.lspCache.pendingCallHierarchyKind = chrkNone
  e.state.lspCache.pendingCallHierarchyPrepareResult = none(JsonNode)

  # Start with prepare request
  let reqResult = e.lsp.startCallHierarchyPrepareRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & reqResult.error
    return false

  e.state.lspCache.pendingCallHierarchyRequestId = reqResult.get
  e.state.lspCache.pendingCallHierarchyKind = kind
  return true

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

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    let activeBuffer = e.activeBuffer()

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
            e.lsp.startCallHierarchyIncomingCallsRequest(activeBuffer, item)
          else:
            e.lsp.startCallHierarchyOutgoingCallsRequest(activeBuffer, item)

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
      # Second stage complete - show incoming calls
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyIncomingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No incoming calls found"
          return

        var locations: seq[lspTypes.Location] = @[]
        for call in calls:
          locations.add(
            lspTypes.Location(uri: call.`from`.uri, range: call.`from`.selectionRange)
          )
        discard e.handleLspLocations(locations, "Incoming Calls", "Caller")
      else:
        e.state.statusMessage = "No incoming calls found"
    of chrkOutgoingCalls:
      # Second stage complete - show outgoing calls
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyOutgoingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No outgoing calls found"
          return

        var locations: seq[lspTypes.Location] = @[]
        for call in calls:
          locations.add(
            lspTypes.Location(uri: call.to.uri, range: call.to.selectionRange)
          )
        discard e.handleLspLocations(locations, "Outgoing Calls", "Callee")
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

proc requestLspTypeDefinition*(e: Editor): bool =
  ## Request LSP goto type definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkTypeDefinition)

proc requestLspImplementation*(e: Editor): bool =
  ## Request LSP goto implementation at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkImplementation)

proc startLspHover*(e: Editor): bool =
  ## Start async LSP hover request at current cursor position
  ## Returns true if request was started successfully
  ## Results will be polled by pollLspHover in the tick function
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending hover request
  e.state.lspCache.pendingHoverRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult =
    e.lsp.startHoverRequest(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if reqResult.isErr:
    e.state.statusMessage = "LSP hover failed: " & reqResult.error
    return false

  e.state.lspCache.pendingHoverRequestId = reqResult.get
  return true

proc pollLspHover*(e: Editor) =
  ## Poll for pending LSP hover response
  ## This should be called from the main event loop (tick function)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingHoverRequestId
  if requestId == 0:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingHoverRequestId = 0
    if resultOpt.isSome:
      let hoverOpt = parseHoverResponse(resultOpt.get)
      if hoverOpt.isSome:
        let hoverText = getHoverText(hoverOpt.get)
        if hoverText.len > 0:
          e.state.lspCache.hoverPopup.show(
            hoverText, e.state.cursor.line, e.state.cursor.column
          )
        else:
          e.state.statusMessage = "No hover information available"
      else:
        e.state.statusMessage = "No hover information available"
    else:
      e.state.statusMessage = "No hover information available"
  of lrsError:
    e.state.lspCache.pendingHoverRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP hover failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingHoverRequestId = 0
    e.state.statusMessage = "LSP hover timed out"

proc requestLspHover*(e: Editor): bool =
  ## Request LSP hover information at current cursor position (async)
  ## Returns true if request was started
  ## The hover popup will be shown when the response arrives
  e.startLspHover()

proc hideHoverPopup*(e: Editor) =
  ## Hide the hover popup
  e.state.lspCache.hoverPopup.hide()

proc hoverPopupScrollDown*(e: Editor) =
  ## Scroll hover popup down
  e.state.lspCache.hoverPopup.scrollDown()

proc hoverPopupScrollUp*(e: Editor) =
  ## Scroll hover popup up
  e.state.lspCache.hoverPopup.scrollUp()

proc hoverPopupScrollRight*(e: Editor) =
  ## Scroll hover popup right
  e.state.lspCache.hoverPopup.scrollRight()

proc hoverPopupScrollLeft*(e: Editor) =
  ## Scroll hover popup left
  e.state.lspCache.hoverPopup.scrollLeft()

proc startLspSelectionRange*(e: Editor): bool =
  ## Start async LSP selection range request at current cursor position
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending selection range request
  e.state.lspCache.pendingSelectionRangeRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult = e.lsp.startSelectionRangeRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
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

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
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
        # Enter visual mode and set selection to the range
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Visual
        e.state.visualSelection = VisualSelection(
          kind: vskChar,
          start: BufferPosition(
            line: selRange.range.start.line, column: selRange.range.start.character
          ),
          current: BufferPosition(
            line: selRange.range.`end`.line, column: selRange.range.`end`.character
          ),
          active: true,
        )
        e.state.cursor = BufferPosition(
          line: selRange.range.`end`.line, column: selRange.range.`end`.character
        )
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

proc startLspDocumentSymbols*(e: Editor): bool =
  ## Start async document symbols request
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
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

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
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
      e.state.mode = EditorMode.DocumentSymbol
      e.state.documentSymbolViewerState = some(viewerState)
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

proc requestLspFormat*(e: Editor): Future[bool] {.async: (raises: [CancelledError]).} =
  ## Request LSP document formatting and apply edits
  ## Returns true if successful
  {.cast(raises: [CancelledError]).}:
    {.cast(gcsafe).}:
      if not e.lsp.enabled:
        e.state.statusMessage = "LSP not enabled"
        return false

      let activeBuffer = e.activeBuffer()

      # Get formatting result from LSP
      let formatResult = await e.lsp.requestFormatting(activeBuffer)
      if formatResult.isErr:
        e.state.statusMessage = "LSP format failed: " & formatResult.error
        return false

      let edits = formatResult.get
      if edits.len == 0:
        e.state.statusMessage = "No formatting changes"
        return true

      # Apply the text edits to the buffer
      let applyResult = applyTextEdits(activeBuffer, edits)
      if applyResult.isErr:
        e.state.statusMessage = "Failed to apply edits: " & applyResult.error
        return false

      e.state.statusMessage =
        "Formatted (" & $edits.len & " edit" & (if edits.len > 1: "s" else: "") & ")"
      e.state.needsFullRedraw = true
      return true

proc refreshLspFolds*(e: Editor): Future[void] {.async: (raises: []).} =
  ## Request LSP folding ranges and update buffer fold markers
  try:
    if not e.lsp.enabled:
      e.state.statusMessage = "LSP not enabled"
      return

    let activeBuffer = e.activeBuffer()

    # Use lspintegration's refreshLspFolds
    let foldResult = await lspintegration.refreshLspFolds(e.lsp, activeBuffer)
    if foldResult.isErr:
      e.state.statusMessage = "LSP fold failed: " & foldResult.error
      return

    e.state.statusMessage = "Updated fold markers"
    e.state.needsFullRedraw = true
  except CancelledError:
    discard
