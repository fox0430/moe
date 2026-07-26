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

import std/[options, strutils, os, tables]

import pkg/results

import
  types/editor_types,
  editor_window,
  viewer_mode,
  editor_lsp,
  lsp_service,
  lsp_integration,
  references_viewer,
  buffer,
  unicode_utils,
  editorconfig_helper,
  highlight_config
import lsp/protocol/types as lspTypes

const
  LocationFeatures* =
    {lrfDefinition, lrfDeclaration, lrfReferences, lrfTypeDefinition, lrfImplementation}
  LocationValidModes* = {
    EditorMode.Normal, EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine
  }

func featureOfLocationKind*(kind: LspLocationRequestKind): LspRequestFeature =
  case kind
  of lrkDefinition: lrfDefinition
  of lrkDeclaration: lrfDeclaration
  of lrkReferences: lrfReferences
  of lrkTypeDefinition: lrfTypeDefinition
  of lrkImplementation: lrfImplementation
  of lrkNone: lrfDefinition
    # unreachable via startLspLocationRequest guards

func locationKindOfFeature*(f: LspRequestFeature): LspLocationRequestKind =
  case f
  of lrfDefinition: lrkDefinition
  of lrfDeclaration: lrkDeclaration
  of lrfReferences: lrkReferences
  of lrfTypeDefinition: lrkTypeDefinition
  of lrfImplementation: lrkImplementation
  else: lrkNone

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
  activeWindow.viewport.resetViewportTop()
  activeWindow.viewport.leftColumn = 0

  # Re-sync executor, motion controller, jump-list anchor and per-buffer
  # EditorConfig now that the active window's buffer changed.
  e.syncActiveWindow()

proc sameFilePath(a, b: string): bool =
  ## Compare two file paths by their normalized absolute form.
  ##
  ## A buffer opened with a relative path ("src/moe.nim") must match an
  ## LSP-provided absolute path ("/home/.../src/moe.nim") and vice versa.
  ## Without this, navigation (go-to-definition, references) opens a *second*
  ## buffer for a file that is already open under a differently-spelled path.
  ## Duplicate buffers desync edits and break LSP rename: its change-detection
  ## snapshot is keyed by absolute path, so the two same-file buffers collide
  ## and rename is wrongly rejected with "Buffer changed during rename".
  normalizedPath(absolutePath(a)) == normalizedPath(absolutePath(b))

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
  ## rather than mutating the active buffer in place.
  for i, buf in e.buffers:
    if buf.filePath.isSome and sameFilePath(buf.filePath.get, path):
      e.switchToBufferForLsp(i)
      return ok(buf)

  let newBuffer = newTextBuffer()
  # Seed the highlight cap before loadFile builds the first chunk, so the cap
  # is not changed afterwards (which would nil the progressive-load cache).
  newBuffer.applyHighlightCap(e.config)
  let loadResult = newBuffer.loadFile(path)
  if loadResult.isErr:
    return err(loadResult.error)

  applyEditorConfigToBuffer(newBuffer, e.config)
  applyHighlightConfig(newBuffer, e.config)
  e.addBuffer(newBuffer)
  e.switchToBufferForLsp(e.buffers.high)

  # Notify the LSP about the newly opened file and record its synced baseline
  # so the next didChange delta is computed against the right changeSeq.
  # Best-effort: openBufferWithLsp is a no-op when LSP is disabled / the buffer
  # has no path, and logs a degraded notice on failure.
  e.openBufferWithLsp(newBuffer)

  ok(newBuffer)

proc addToJumpList*(e: Editor) =
  ## Add current cursor position to jump list before a jump
  let jumpPos = JumpPosition(
    bufferId: e.state.windowDisplay.currentBufferId,
    line: e.activeWindow.cursor.line,
    column: e.activeWindow.cursor.column,
  )

  # Don't add if same as last position (same buffer, line, and column)
  if e.state.jumpList.list.len > 0:
    let lastPos = e.state.jumpList.list[^1]
    if lastPos.bufferId == jumpPos.bufferId and lastPos.line == jumpPos.line and
        lastPos.column == jumpPos.column:
      return

  e.state.jumpList.list.add(jumpPos)
  # Keep jump list at reasonable size (max 100 entries)
  if e.state.jumpList.list.len > 100:
    e.state.jumpList.list.delete(0)
  # Reset jump list index when adding new position
  e.state.jumpList.index = -1

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
  let charCol = utf16ToRuneIndex(lineText, lspColumn)
  # Insert mode allows cursor at charLen (append position)
  let maxCol =
    if e.state.mode == EditorMode.Insert:
      lineText.charLen
    else:
      max(0, lineText.charLen - 1)
  let targetCol = min(charCol, maxCol)
  e.activeWindow.cursor.line = targetLine
  e.activeWindow.cursor.column = max(0, targetCol)

proc splitWindowForJump(e: Editor): bool =
  ## Open a new vertical split window (showing the current buffer) so a
  ## subsequent jump lands in the new window instead of the current one.
  ## Returns false (with a status message) if the split fails.
  let splitResult = e.vsplit()
  if splitResult.isErr:
    e.state.statusMessage = "Failed to open window: " & splitResult.error
    return false
  true

proc jumpToLspLocation*(
    e: Editor, loc: lspTypes.Location, resultKind: string, openWindow: bool = false
): bool =
  ## Jump to a single LSP location. When `openWindow` is true, the jump
  ## happens in a new vertical split window instead of the current one.
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()
  let path = lsp_service.uriToPath(loc.uri)

  # Add current position to jump list before jumping
  e.addToJumpList()

  if openWindow and not e.splitWindowForJump():
    return false

  # Check if it's the same file
  if activeBuffer.filePath.isSome and sameFilePath(activeBuffer.filePath.get, path):
    # Same file - just move cursor with boundary checks
    e.moveCursorToLspPosition(
      activeBuffer, loc.range.start.line, loc.range.start.character
    )
    e.state.statusMessage = resultKind & " at line " & $(e.activeWindow.cursor.line + 1)
  else:
    # Different file - open it in a new buffer (or switch to existing)
    let opened = e.openFileInActiveWindow(path)
    if opened.isErr:
      if openWindow:
        # Don't leave the freshly split window behind on failure
        discard e.closeWindow()
      e.state.statusMessage = "Failed to open file: " & opened.error
      return false

    # Set cursor with boundary checks against the now-active buffer
    e.moveCursorToLspPosition(
      e.activeBuffer(), loc.range.start.line, loc.range.start.character
    )
    e.state.statusMessage = resultKind & " in " & path

  # Update viewport to follow cursor
  return true

proc handleLspLocations*(
    e: Editor,
    locations: seq[lspTypes.Location],
    title: string,
    singularName: string,
    openWindow: bool = false,
): bool =
  ## Handle LSP location results (shared by definition and references).
  ## `openWindow` makes the jump open a new vertical split window: directly
  ## for a single location, or on item selection in the References viewer
  ## when there are multiple.
  ## Returns true if successful
  if locations.len == 0:
    e.state.statusMessage = "No " & title.toLowerAscii() & " found"
    return false

  if locations.len == 1:
    # Single location - jump directly
    return e.jumpToLspLocation(locations[0], singularName, openWindow)
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
    let refState = newReferencesViewerState(items, title)
    refState.openWindowOnJump = openWindow
    discard e.enterViewerMode(
      EditorMode.References,
      ModeState(kind: mskReferences, references: refState),
      refState.createReferencesTextBuffer(),
      vpInPlace,
    )
    e.state.statusMessage = $locations.len & " " & title.toLowerAscii() & " found"
    return true

proc openFileAndJumpTo*(
    e: Editor, path: string, line, column: int, openWindow: bool = false
): bool =
  ## Open a file and jump to a specific location. When `openWindow` is true,
  ## the jump happens in a new vertical split window instead of the current one.
  ## Note: column is expected to be LSP UTF-16 code unit offset
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()

  # Add current position to jump list before jumping
  e.addToJumpList()

  if openWindow and not e.splitWindowForJump():
    return false

  # Check if it's the same file
  if activeBuffer.filePath.isSome and sameFilePath(activeBuffer.filePath.get, path):
    # Same file - just move cursor with boundary checks
    e.moveCursorToLspPosition(activeBuffer, line, column)
  else:
    # Different file - open it in a new buffer (or switch to existing)
    let opened = e.openFileInActiveWindow(path)
    if opened.isErr:
      if openWindow:
        # Don't leave the freshly split window behind on failure
        discard e.closeWindow()
      e.state.statusMessage = "Failed to open file: " & opened.error
      return false
    # Set cursor with boundary checks against the now-active buffer
    e.moveCursorToLspPosition(e.activeBuffer(), line, column)

  # Update viewport to follow cursor
  return true

proc startLspLocationRequest(e: Editor, kind: LspLocationRequestKind): bool =
  ## Start an async LSP location request (definition, declaration, references, etc.)
  ## Returns true if request was started successfully
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let kindName =
    case kind
    of lrkDefinition: "definition"
    of lrkDeclaration: "declaration"
    of lrkReferences: "references"
    of lrkTypeDefinition: "type definition"
    of lrkImplementation: "implementation"
    of lrkNone: ""

  let featureEnabled =
    case kind
    of lrkDefinition: e.config.lsp.definition.enable
    of lrkDeclaration: e.config.lsp.declaration.enable
    of lrkReferences: e.config.lsp.references.enable
    of lrkTypeDefinition: e.config.lsp.typeDefinition.enable
    of lrkImplementation: e.config.lsp.implementation.enable
    of lrkNone: false
  if not featureEnabled:
    e.state.statusMessage = "LSP " & kindName & " is disabled"
    return false

  let activeBuffer = e.activeBuffer()

  # Guard against unsupported servers so we report "not supported" immediately
  # instead of issuing a request that only fails after the response timeout.
  let supported =
    case kind
    of lrkDefinition:
      e.lsp.hasDefinitionSupport(activeBuffer)
    of lrkDeclaration:
      e.lsp.hasDeclarationSupport(activeBuffer)
    of lrkReferences:
      e.lsp.hasReferencesSupport(activeBuffer)
    of lrkTypeDefinition:
      e.lsp.hasTypeDefinitionSupport(activeBuffer)
    of lrkImplementation:
      e.lsp.hasImplementationSupport(activeBuffer)
    of lrkNone:
      false
  if not supported:
    e.state.statusMessage =
      "LSP " & kindName & " is not supported by the language server"
    return false

  # Only one location request in flight at a time: a new one supersedes any
  # of the five kinds already pending.
  for f in LocationFeatures:
    cancelIfPending(e, f)

  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column
  let feature = featureOfLocationKind(kind)

  let ctxRes = e.startContextualRequest(
    feature,
    proc(): Result[int, string] =
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
        err("invalid location kind"),
    validModes = LocationValidModes,
    # goto-* response is URI-anchored (handleLspLocations opens by path), so a
    # mid-flight buffer switch must not drop it.
    isItemDriven = true,
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP " & kindName & " failed: " & ctxRes.error
    return false
  return true

proc pollLspLocationRequest*(e: Editor) =
  ## Poll for pending LSP location request response
  ## This should be called from the main event loop (tick function)
  e.pollOneShotLspResponse(LocationFeatures, "request"):
    if resultOpt.isSome:
      let kind = locationKindOfFeature(feature)
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
      let openWindow =
        case kind
        of lrkDefinition: e.config.lsp.definition.openWindow
        of lrkDeclaration: e.config.lsp.declaration.openWindow
        of lrkTypeDefinition: e.config.lsp.typeDefinition.openWindow
        of lrkImplementation: e.config.lsp.implementation.openWindow
        of lrkReferences, lrkNone: false
      discard e.handleLspLocations(locations, pluralName, singularName, openWindow)
    else:
      e.state.statusMessage = "No results found"

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
