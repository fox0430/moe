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

## Tests for editor_hover.nim

import std/[unittest, monotimes, times, json, options, importutils]

import ../src/moepkg/[editor, buffer, config, config_loader, types, hover_popup]
import ../src/moepkg/editor_hover
import ../src/moepkg/lsp_service

privateAccess(LspService)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

proc createTestEditorForAutoHover(): Editor =
  ## Create an editor with LSP and autoHover enabled, debounce set to 0
  let config = newEditorConfig()
  config.lsp.diagnostics.enable = true
  config.lsp.diagnostics.autoHover = true
  config.lsp.diagnostics.autoHoverDelay = 0
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = true
  # Force lastAutoHoverUpdate to the past so debounce doesn't block
  result.state.lspCache.lastAutoHoverUpdate = getMonoTime() - initDuration(seconds = 10)

suite "editor_hover - startLspHover":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspHover()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_hover - requestLspHover":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspHover()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_hover - pollLspHover":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspHover()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingHoverRequestId = 0

    e.pollLspHover()
    # No crash means success

  test "Shows popup when the response buffer still matches":
    let e = createTestEditor()
    e.lsp.enabled = true

    const reqId = 42
    e.lsp.service.pendingResponses[reqId] = (
      result: some(%*{"contents": {"kind": "plaintext", "value": "hover text"}}),
      error: none(string),
    )
    e.state.lspCache.pendingHoverRequestId = reqId
    e.state.lspCache.pendingHoverBufferId = e.activeBuffer().id
    e.state.lspCache.pendingHoverCursorLine = 0
    e.state.lspCache.pendingHoverCursorCol = 0

    e.pollLspHover()

    check e.state.lspCache.pendingHoverRequestId == 0
    check e.state.lspCache.hoverPopup.isActive

  test "Discards response when the active buffer changed while waiting":
    let e = createTestEditor()
    e.lsp.enabled = true

    const reqId = 43
    e.lsp.service.pendingResponses[reqId] = (
      result: some(%*{"contents": {"kind": "plaintext", "value": "hover text"}}),
      error: none(string),
    )
    e.state.lspCache.pendingHoverRequestId = reqId
    # Request was made for a different buffer than the current active one.
    e.state.lspCache.pendingHoverBufferId = BufferId(int(e.activeBuffer().id) + 1)
    e.state.lspCache.pendingHoverCursorLine = 0
    e.state.lspCache.pendingHoverCursorCol = 0

    e.pollLspHover()

    check e.state.lspCache.pendingHoverRequestId == 0
    check not e.state.lspCache.hoverPopup.isActive

suite "editor_hover - hideHoverPopup":
  test "Hides the hover popup":
    let e = createTestEditor()

    e.hideHoverPopup()
    # No crash means success

suite "editor_hover - hoverPopupScrollDown":
  test "Scrolls hover popup down":
    let e = createTestEditor()

    e.hoverPopupScrollDown()
    # No crash means success

suite "editor_hover - hoverPopupScrollUp":
  test "Scrolls hover popup up":
    let e = createTestEditor()

    e.hoverPopupScrollUp()
    # No crash means success

suite "editor_hover - hoverPopupScrollRight":
  test "Scrolls hover popup right":
    let e = createTestEditor()

    e.hoverPopupScrollRight()
    # No crash means success

suite "editor_hover - hoverPopupScrollLeft":
  test "Scrolls hover popup left":
    let e = createTestEditor()

    e.hoverPopupScrollLeft()
    # No crash means success

suite "editor_hover - maybeAutoHoverDiagnostic":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorForAutoHover()
    e.lsp.enabled = false
    e.cursor = BufferPosition(line: 0, column: 1)

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Does nothing when diagnostics.enable is false":
    let e = createTestEditorForAutoHover()
    e.config.lsp.diagnostics.enable = false
    e.cursor = BufferPosition(line: 0, column: 1)

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Does nothing when autoHover is false":
    let e = createTestEditorForAutoHover()
    e.config.lsp.diagnostics.autoHover = false
    e.cursor = BufferPosition(line: 0, column: 1)

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Does nothing in Insert mode":
    let e = createTestEditorForAutoHover()
    e.state.mode = EditorMode.Insert
    e.cursor = BufferPosition(line: 0, column: 1)

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Does nothing when cursor has not moved":
    let e = createTestEditorForAutoHover()
    # Set tracked position to match current cursor
    e.state.lspCache.autoHoverCursorLine = 0
    e.state.lspCache.autoHoverCursorCol = 0

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Shows popup when cursor is on diagnostic":
    let e = createTestEditorForAutoHover()
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsError,
        message: "test error",
      )
    ]
    # Force cursor position change detection
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    check e.state.lspCache.hoverPopup.isActive
    check e.state.lspCache.hoverPopup.display.lines[0] == "[Error] test error"

  test "Hides popup when cursor moves off diagnostic":
    let e = createTestEditorForAutoHover()
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 5,
        severity: bdsError,
        message: "test error",
      )
    ]
    # Show popup first
    e.state.lspCache.hoverPopup.show("[Error] test error", 0, 0)
    check e.state.lspCache.hoverPopup.isActive

    # Move cursor to line 1 (outside diagnostic range)
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 1, column: 0)

    e.maybeAutoHoverDiagnostic()

    check not e.state.lspCache.hoverPopup.isActive

  test "Shows multiple diagnostics at same position":
    let e = createTestEditorForAutoHover()
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsError,
        message: "error msg",
      ),
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsWarning,
        message: "warning msg",
      ),
    ]
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    check e.state.lspCache.hoverPopup.isActive
    check e.state.lspCache.hoverPopup.display.lines.len == 2
    check e.state.lspCache.hoverPopup.display.lines[0] == "[Error] error msg"
    check e.state.lspCache.hoverPopup.display.lines[1] == "[Warning] warning msg"

  test "Debounce blocks rapid updates":
    let e = createTestEditorForAutoHover()
    e.config.lsp.diagnostics.autoHoverDelay = 999_999
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsError,
        message: "test error",
      )
    ]
    # Set lastAutoHoverUpdate to now (within debounce window)
    e.state.lspCache.lastAutoHoverUpdate = getMonoTime()
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    # Popup should NOT show because debounce blocks it
    check not e.state.lspCache.hoverPopup.isActive

  test "Works in Visual mode":
    let e = createTestEditorForAutoHover()
    e.state.mode = EditorMode.Visual
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsWarning,
        message: "visual warning",
      )
    ]
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    check e.state.lspCache.hoverPopup.isActive

  test "Auto-hover sets isAutoHover flag":
    let e = createTestEditorForAutoHover()
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsError,
        message: "test error",
      )
    ]
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    check e.state.lspCache.hoverPopup.isActive
    check e.state.lspCache.hoverPopup.isAutoHover

  test "Manual show() resets isAutoHover to false":
    let e = createTestEditorForAutoHover()
    # Simulate auto-hover first
    e.state.lspCache.hoverPopup.show("diag text", 0, 0)
    e.state.lspCache.hoverPopup.isAutoHover = true
    check e.state.lspCache.hoverPopup.isAutoHover

    # Manual show() (as done by pollLspHover) resets the flag
    e.state.lspCache.hoverPopup.show("hover text", 0, 0)
    check not e.state.lspCache.hoverPopup.isAutoHover

  test "Debounce resets tracked position for retry":
    let e = createTestEditorForAutoHover()
    e.config.lsp.diagnostics.autoHoverDelay = 999_999
    e.activeBuffer().diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 10,
        severity: bdsError,
        message: "test error",
      )
    ]
    e.state.lspCache.lastAutoHoverUpdate = getMonoTime()
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    e.cursor = BufferPosition(line: 0, column: 3)

    e.maybeAutoHoverDiagnostic()

    # Debounce blocked, but tracked position should be reset for retry
    check not e.state.lspCache.hoverPopup.isActive
    check e.state.lspCache.autoHoverCursorLine == -1
    check e.state.lspCache.autoHoverCursorCol == -1
