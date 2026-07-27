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

## Consecutive requests replace the stored context so an older reply cannot
## revive after the pending slot has been reused. `featureGeneration` is bumped
## only when a response is processed (see `updateCodeLensCache`), not on
## request start — start-time bumps would cause the in-tick fall-through to
## invalidate the just-spawned async handler.

import std/[options, os, tables, unittest]

import pkg/results

import ../src/moepkg/[editor, config, config_loader, types]
import ../src/moepkg/buffer/core
import ../src/moepkg/editor_lsp

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  # Give the active buffer a file path so startContextualRequest does not
  # reject it as unwritten scratch.
  result.activeBuffer.filePath = some(getTempDir() / "hover_gen.nim")

suite "LspRequestContext consecutive starts":
  test "Consecutive requests replace the stored context (pending eviction)":
    let e = createTestEditor()
    var reqId = 100
    proc issue(): Result[int, string] =
      inc reqId
      ok(reqId)

    let firstRes = e.startContextualRequest(
      lrfHover,
      issue,
      validModes = {EditorMode.Normal},
      cursor = some(BufferPosition(line: 0, column: 0)),
    )
    check firstRes.isOk
    let firstCtx = firstRes.get
    check e.state.lspCache.pending.hasKey(lrfHover)
    check e.state.lspCache.pending[lrfHover].requestId == firstCtx.requestId

    let secondRes = e.startContextualRequest(
      lrfHover,
      issue,
      validModes = {EditorMode.Normal},
      cursor = some(BufferPosition(line: 0, column: 1)),
    )
    check secondRes.isOk
    let secondCtx = secondRes.get

    # Old context evicted (cancelIfPending inside startContextualRequest); the
    # newer one replaces it.
    check e.state.lspCache.pending[lrfHover].requestId == secondCtx.requestId
    check e.state.lspCache.pending[lrfHover].requestId != firstCtx.requestId

  test "Request start does NOT bump featureGeneration":
    # Regression: bumping on start caused updateCodeLensCache's fall-through
    # `doUpdate` to invalidate the just-spawned async handler in the same tick
    # on slow servers, dropping every response.
    let e = createTestEditor()
    var reqId = 200
    proc issue(): Result[int, string] =
      inc reqId
      ok(reqId)

    discard e.startContextualRequest(lrfHover, issue)
    discard e.startContextualRequest(lrfHover, issue)
    discard e.startContextualRequest(lrfSelectionRange, issue)

    check e.state.lspCache.featureGeneration[lrfHover] == 0
    check e.state.lspCache.featureGeneration[lrfSelectionRange] == 0

  test "ctx.generation captures current featureGeneration at store-time":
    let e = createTestEditor()
    var reqId = 300
    proc issue(): Result[int, string] =
      inc reqId
      ok(reqId)

    # Simulate a codeLens response that bumped featureGeneration to 3.
    e.state.lspCache.featureGeneration[lrfCodeLens] = 3

    let res = e.startContextualRequest(lrfCodeLens, issue)
    check res.isOk
    # ctx.generation reflects the *current* counter, so a follow-up asyncSpawn
    # can be superseded by later response-driven bumps but not by peer starts.
    check res.get.generation == 3
    check e.state.lspCache.featureGeneration[lrfCodeLens] == 3
