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

## Phase E regression: signatureHelp and completionResolve share the common
## LspRequestContext pending table, so consecutive requests advance the per-
## feature generation and evict the prior context.

import std/[options, os, tables, unittest]

import pkg/results

import ../src/moepkg/[editor, config, config_loader, types, buffer]
import ../src/moepkg/editor_lsp

proc createTestEditor(): Editor =
  let cfg = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(cfg, vr)
  result.activeBuffer.filePath = some(getTempDir() / "sighelp_ctx.nim")

suite "LspRequestContext - signatureHelp / completionResolve":
  test "signatureHelp: consecutive requests replace the stored context":
    let e = createTestEditor()
    var reqId = 500
    proc issue(): Result[int, string] =
      inc reqId
      ok(reqId)

    let firstRes = e.startContextualRequest(
      lrfSignatureHelp,
      issue,
      validModes = {EditorMode.Insert},
      cursor = some(BufferPosition(line: 0, column: 0)),
    )
    check firstRes.isOk
    let firstCtx = firstRes.get
    check e.state.lspCache.pending.hasKey(lrfSignatureHelp)
    check e.state.lspCache.pending[lrfSignatureHelp].requestId == firstCtx.requestId

    let secondRes = e.startContextualRequest(
      lrfSignatureHelp,
      issue,
      validModes = {EditorMode.Insert},
      cursor = some(BufferPosition(line: 0, column: 3)),
    )
    check secondRes.isOk
    let secondCtx = secondRes.get

    check e.state.lspCache.pending[lrfSignatureHelp].requestId == secondCtx.requestId
    check e.state.lspCache.pending[lrfSignatureHelp].requestId != firstCtx.requestId
    check e.state.lspCache.pending[lrfSignatureHelp].cursorCol == 3

  test "completionResolve: consecutive requests replace the stored context":
    let e = createTestEditor()
    var reqId = 700
    proc issue(): Result[int, string] =
      inc reqId
      ok(reqId)

    let firstRes = e.startContextualRequest(
      lrfCompletionResolve, issue, validModes = {EditorMode.Insert}
    )
    check firstRes.isOk
    let firstCtx = firstRes.get
    check e.state.lspCache.pending[lrfCompletionResolve].requestId == firstCtx.requestId

    let secondRes = e.startContextualRequest(
      lrfCompletionResolve, issue, validModes = {EditorMode.Insert}
    )
    check secondRes.isOk
    let secondCtx = secondRes.get

    check e.state.lspCache.pending[lrfCompletionResolve].requestId == secondCtx.requestId
    check e.state.lspCache.pending[lrfCompletionResolve].requestId != firstCtx.requestId

  test "storeContextualRequest without Editor writes the same shape":
    # Cache-scoped variant is used by insert_handler.nim where the caller does
    # not have an Editor handle. Ensure it populates the pending table with the
    # same fields startContextualRequest does. Start does NOT bump
    # featureGeneration — only response-processing sites (codeLens) do.
    let e = createTestEditor()
    let ctx = storeContextualRequest(
      e.state.lspCache,
      lrfSignatureHelp,
      e.activeBuffer,
      requestId = 4321,
      validModes = {EditorMode.Insert},
      cursor = some(BufferPosition(line: 2, column: 5)),
    )
    check ctx.requestId == 4321
    check ctx.feature == lrfSignatureHelp
    check ctx.bufferId == e.activeBuffer.id
    check ctx.contentVersion == e.activeBuffer.contentVersion
    check ctx.cursorLine == 2 and ctx.cursorCol == 5
    check EditorMode.Insert in ctx.validModes
    check e.state.lspCache.pending[lrfSignatureHelp].requestId == 4321
    check e.state.lspCache.featureGeneration[lrfSignatureHelp] == 0
