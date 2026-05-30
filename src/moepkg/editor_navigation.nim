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

## LSP navigation: definition / declaration / references / type-definition /
## implementation requests, plus the shared jump-list, buffer-switch, and
## location-jump helpers that other LSP feature modules (call hierarchy,
## document link) depend on.

import std/[options, strutils]

import pkg/results

import
  editor_types, editor_window, editor_window_state, lsp_service, lsp_integration,
  references_viewer, buffer, unicode_utils, editorconfig_helper
import lsp/protocol/types as lspTypes

proc switchToBufferForLsp*(e: Editor, index: int) =
  ## Switch to buffer at given index (simplified version for LSP jumps)
  if index < 0 or index >= e.buffers.len:
    return

  let targetBuffer = e.buffers[index]
  let activeWindow = e.activeWindow

  if activeWindow.buffer == targetBuffer:
    return

  activeWindow.buffer = targetBuffer
  activeWindow.cursor = BufferPosition(line: 0, column: 0)
  activeWindow.viewport.topLine = 0
  activeWindow.viewport.leftColumn = 0

  # Re-sync executor, motion controller, jump-list anchor and per-buffer
  # EditorConfig now that the active window's buffer changed.
  e.syncActiveWindow()

proc openFileInActiveWindow*(e: Editor, path: string): Result[TextBuffer, string] =
  ## Open `path` in the active window and return the buffer now shown there.
  ##
  ## If a buffer already holds this file, switch the active window to it.
  ## Otherwise create a new buffer, load the file, apply EditorConfig and
  ## reserved-word highlighting, register it, switch to it, and notify the LSP.
  ##
  ## Shared by the LSP/jump/document-link navigation paths so they all open
  ## files into the *active* window's buffer with identical setup. Unlike the
  ## legacy `e.loadFile`, content is loaded into a freshly registered buffer
  ## rather than mutating the stale initial `e.textBuffer` in place.
  for i, buf in e.buffers:
    if buf.filePath.isSome and buf.filePath.get == path:
      e.switchToBufferForLsp(i)
      return ok(buf)

  let newBuffer = newTextBuffer()
  let loadResult = newBuffer.loadFile(path)
  if loadResult.isErr:
    return err(loadResult.error)

  applyEditorConfigToBuffer(newBuffer, e.config)
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  e.addBuffer(newBuffer)
  e.switchToBufferForLsp(e.buffers.high)

  # Notify LSP about the newly opened file (best-effort; failure is non-fatal,
  # but record it so the resulting feature degradation is not silent)
  if e.lsp.enabled:
    let openResult = e.lsp.onBufferOpen(newBuffer)
    if openResult.isErr:
      logLspDegraded("didOpen", openResult.error)

  ok(newBuffer)

proc addToJumpList*(e: Editor) =
  ## Add current cursor position to jump list before a jump
  let jumpPos = JumpPosition(
    bufferId: e.state.windowDisplay.currentBufferId,
    line: e.activeWindow.cursor.line,
    column: e.activeWindow.cursor.column,
  )

  # Don't add if same as last position (same buffer, line, and column)
  if e.state.jumpList.len > 0:
    let lastPos = e.state.jumpList[^1]
    if lastPos.bufferId == jumpPos.bufferId and lastPos.line == jumpPos.line and
        lastPos.column == jumpPos.column:
      return

  e.state.jumpList.add(jumpPos)
  # Keep jump list at reasonable size (max 100 entries)
  if e.state.jumpList.len > 100:
    e.state.jumpList.delete(0)
  # Reset jump list index when adding new position
  e.state.jumpListIndex = -1

proc moveCursorToLspPosition(e: Editor, buffer: TextBuffer, lspLine, lspColumn: int) =
  ## Move the active window's cursor to an LSP location within `buffer`,
  ## clamped to the buffer/line bounds.
  ##
  ## `lspLine`/`lspColumn` are LSP coordinates: a 0-based line and a UTF-16
  ## code unit offset, which is converted to a character column here.
  let targetLine = min(lspLine, max(0, buffer.len - 1))
  let lineText =
    if buffer.len > 0:
      buffer.getLine(targetLine)
    else:
      ""
  # Convert LSP UTF-16 character offset to character index
  let utf8Col = utf16OffsetToUtf8(lineText, lspColumn)
  let charCol = byteToCharPos(lineText, utf8Col)
  let targetCol = min(charCol, max(0, lineText.charLen - 1))
  e.activeWindow.cursor.line = targetLine
  e.activeWindow.cursor.column = max(0, targetCol)

proc jumpToLspLocation*(e: Editor, loc: lspTypes.Location, resultKind: string): bool =
  ## Jump to a single LSP location
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()
  let path = lsp_service.uriToPath(loc.uri)

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    e.moveCursorToLspPosition(
      activeBuffer, loc.range.start.line, loc.range.start.character
    )
    e.state.statusMessage = resultKind & " at line " & $(e.activeWindow.cursor.line + 1)
  else:
    # Different file - open it in a new buffer (or switch to existing)
    let opened = e.openFileInActiveWindow(path)
    if opened.isErr:
      e.state.statusMessage = "Failed to open file: " & opened.error
      return false

    # Set cursor with boundary checks against the now-active buffer
    e.moveCursorToLspPosition(
      e.activeBuffer(), loc.range.start.line, loc.range.start.character
    )
    e.state.statusMessage = resultKind & " in " & path

  # Update viewport to follow cursor
  e.state.windowDisplay.needsFullRedraw = true
  return true

proc handleLspLocations*(
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
      let path = lsp_service.uriToPath(loc.uri)
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
    e.setMode(EditorMode.References)
    let refState = newReferencesViewerState(items, title)
    let activeWin = e.activeWindow
    activeWin.saveOriginalBuffer()
    activeWin.buffer = refState.createReferencesTextBuffer()
    activeWin.cursor = BufferPosition(line: 0, column: 0)
    activeWin.viewport.topLine = 0
    activeWin.viewport.leftColumn = 0
    activeWin.modeState = ModeState(kind: mskReferences, references: refState)
    e.state.statusMessage = $locations.len & " " & title.toLowerAscii() & " found"
    return true

proc openFileAndJumpTo*(e: Editor, path: string, line, column: int): bool =
  ## Open a file and jump to a specific location
  ## Note: column is expected to be LSP UTF-16 code unit offset
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    e.moveCursorToLspPosition(activeBuffer, line, column)
  else:
    # Different file - open it in a new buffer (or switch to existing)
    let opened = e.openFileInActiveWindow(path)
    if opened.isErr:
      e.state.statusMessage = "Failed to open file: " & opened.error
      return false
    # Set cursor with boundary checks against the now-active buffer
    e.moveCursorToLspPosition(e.activeBuffer(), line, column)

  # Update viewport to follow cursor
  e.state.windowDisplay.needsFullRedraw = true
  return true

proc startLspLocationRequest(e: Editor, kind: LspLocationRequestKind): bool =
  ## Start an async LSP location request (definition, declaration, references, etc.)
  ## Returns true if request was started successfully
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending location request
  if e.state.lspCache.pendingLocationRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingLocationRequestId)
    e.state.lspCache.pendingLocationRequestId = 0
  e.state.lspCache.pendingLocationRequestKind = lrkNone

  let activeBuffer = e.activeBuffer()
  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column

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

  # Check for response (events were already polled at the top of tick())
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

proc requestLspTypeDefinition*(e: Editor): bool =
  ## Request LSP goto type definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkTypeDefinition)

proc requestLspImplementation*(e: Editor): bool =
  ## Request LSP goto implementation at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkImplementation)
