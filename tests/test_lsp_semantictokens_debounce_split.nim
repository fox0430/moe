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

## Phase D regression (docs §10.7): after the DebouncedLspPoll split, the
## debounce timer and the pending-context table must not perturb each other.

import std/[options, monotimes, os, tables, times, unittest]

import pkg/results

import ../src/moepkg/[editor, config, types, buffer]
import ../src/moepkg/editor_codelens {.all.}

proc createTestEditor(): Editor =
  let cfg = newEditorConfig()
  result = newEditor(cfg)
  result.activeBuffer.filePath = some(getTempDir() / "semtok_debounce.nim")

suite "DebouncedLspPoll x LspRequestContext independence":
  test "Populating pending Table does not touch the debounce timer":
    let e = createTestEditor()
    let stamped = getMonoTime() - initDuration(seconds = 1)
    e.state.lspCache.semanticTokensPoll.lastUpdate = stamped
    e.state.lspCache.semanticTokensPoll.rejectStreak = 3
    e.state.lspCache.semanticTokensPoll.interval = 500

    e.state.lspCache.pending[lrfSemanticTokens] = LspRequestContext(
      requestId: 42,
      feature: lrfSemanticTokens,
      bufferId: e.activeBuffer.id,
      contentVersion: e.activeBuffer.contentVersion,
      path: e.activeBuffer.filePath.get(""),
    )

    check e.state.lspCache.semanticTokensPoll.lastUpdate == stamped
    check e.state.lspCache.semanticTokensPoll.rejectStreak == 3
    check e.state.lspCache.semanticTokensPoll.interval == 500

  test "Dropping the pending entry does not touch the debounce timer":
    let e = createTestEditor()
    let stamped = getMonoTime() - initDuration(seconds = 2)
    e.state.lspCache.semanticTokensPoll.lastUpdate = stamped
    e.state.lspCache.semanticTokensPoll.rejectStreak = 4

    e.state.lspCache.pending[lrfSemanticTokens] =
      LspRequestContext(requestId: 7, feature: lrfSemanticTokens)
    e.state.lspCache.pending.del(lrfSemanticTokens)

    check e.state.lspCache.semanticTokensPoll.lastUpdate == stamped
    check e.state.lspCache.semanticTokensPoll.rejectStreak == 4

  test "invalidateSemanticTokensCache resets rejectStreak AND drops pending":
    # The one intentional coupling — explicit invalidation is a fresh start.
    let e = createTestEditor()
    e.state.lspCache.semanticTokensPoll.rejectStreak = 5
    e.state.lspCache.pending[lrfSemanticTokens] =
      LspRequestContext(requestId: 99, feature: lrfSemanticTokens)

    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)

    check e.state.lspCache.semanticTokensPoll.rejectStreak == 0
    check not e.state.lspCache.pending.hasKey(lrfSemanticTokens)

  test "cancelPendingRequest is a no-op on the debounce timer":
    let e = createTestEditor()
    let stamped = getMonoTime() - initDuration(milliseconds = 750)
    e.state.lspCache.semanticTokensPoll.lastUpdate = stamped
    e.state.lspCache.semanticTokensPoll.rejectStreak = 2

    e.state.lspCache.pending[lrfSemanticTokens] =
      LspRequestContext(requestId: 21, feature: lrfSemanticTokens)
    cancelPendingRequest(e.lsp, e.state.lspCache, lrfSemanticTokens)

    check not e.state.lspCache.pending.hasKey(lrfSemanticTokens)
    check e.state.lspCache.semanticTokensPoll.lastUpdate == stamped
    check e.state.lspCache.semanticTokensPoll.rejectStreak == 2
