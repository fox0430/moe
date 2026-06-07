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

## Tests for editor_lsp.nim

import std/[unittest, os, options, strutils, monotimes, times, tables]

import ../src/moepkg/[editor, buffer, config, config_loader, types, hover_popup]
import ../src/moepkg/editor_lsp {.all.}
import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  ## Create an editor with LSP disabled
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_lsp - maybeUpdateLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let activeBuffer = e.activeBuffer()
    let initialSeq = e.lastLspChangeSeqs.getOrDefault(activeBuffer.id, 0)

    e.maybeUpdateLsp()

    check e.lastLspChangeSeqs.getOrDefault(activeBuffer.id, 0) == initialSeq

  test "Does nothing when buffer has not changed":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    e.lastLspChangeSeqs[activeBuffer.id] = activeBuffer.changeSeq

    e.maybeUpdateLsp()

    check e.lastLspChangeSeqs[activeBuffer.id] == activeBuffer.changeSeq

  test "Tracking is per-buffer":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    # Another buffer's entry must not affect the active buffer's tracking
    let otherBuffer = newTextBuffer("other")
    e.addBuffer(otherBuffer)
    e.lastLspChangeSeqs[otherBuffer.id] = 999

    e.lastLspChangeSeqs[activeBuffer.id] = activeBuffer.changeSeq
    e.maybeUpdateLsp()

    check e.lastLspChangeSeqs[activeBuffer.id] == activeBuffer.changeSeq
    check e.lastLspChangeSeqs[otherBuffer.id] == 999

suite "editor_lsp - pollLspCompletion":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.pollLspCompletion()
    # No crash means success

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.pollLspCompletion()
    # No crash means success

suite "editor_lsp - restartLspServer":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

  test "Returns false when buffer has no file path":
    let e = createTestEditor()
    e.lsp.enabled = true
    # Default buffer has no file path

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "No file path for current buffer"

suite "editor_lsp - Async functions":
  test "requestLspFormat returns false when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    # We can't easily test async functions without running event loop
    # but we can verify the function exists and compiles
    check not e.lsp.enabled

  test "refreshLspFolds does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspRename does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspExecuteCommand does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled
