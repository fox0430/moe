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

## Lightweight type definitions for LSP integration state.
##
## Split out from `lsp_integration` so modules that only need `LspIntegration`
## (notably `types/editor_types` for the `Editor.lsp` field) do not
## transitively pull in the 1700 lines of LSP request/response handlers,
## didChange diffing, workspaceEdit application, semantic tokens overlay,
## etc. Those procs stay in `lsp_integration`.
##
## `documents`, `lastProgressCleanupTime`, and `semanticTypeColorTables` are
## exported (`*`) so the procs in `lsp_integration` can operate on them from
## the implementation module; they are not part of the intended public API and
## outside callers should treat them as private.

import std/[options, tables]

import ../lsp_service
import ../highlight
import ../lsp/worker

type
  LspProgressState* = object ## State of an active LSP progress operation
    token*: string ## Progress token (unique identifier)
    langId*: string ## Language ID of the server
    title*: string ## Title of the operation (from begin)
    message*: Option[string] ## Current status message
    percentage*: Option[int] ## Progress percentage (0-100)
    cancellable*: bool ## Whether the operation can be cancelled
    startTime*: float ## Start time (epochTime) for ordering

  LspStatusState* = object ## Server status from experimental/serverStatus
    health*: ServerHealth ## Server health: ok, warning, or error
    quiescent*: bool ## True when no background work pending
    message*: Option[string] ## Explanatory message

  LspIntegration* = ref object ## Integration layer between LSP and Editor
    service*: LspService
    enabled*: bool
    # Open document tracking: path -> sync state.
    # version: monotonic counter for didChange, shadow: last sent text,
    # delivered: whether didOpen reached the server.
    documents*: Table[string, tuple[version: int, shadow: string, delivered: bool]]
    # Pending status messages to display in the editor
    pendingMessages*: seq[string]
    # Active progress operations (token -> state)
    activeProgress*: Table[string, LspProgressState]
    # Last time stale progress cleanup was performed
    lastProgressCleanupTime*: float
    # Server status per language (langId -> status)
    serverStatus*: Table[string, LspStatusState]
    # Per-language cache of SemanticTokensLegend -> colour table. Built lazily
    # on first apply so `applySemanticTokens` avoids per-token legend-name
    # string lookup + case dispatch.
    semanticTypeColorTables*: Table[string, SemanticTypeColorTable]

  WorkspaceEditResult* = object ## Outcome of applyWorkspaceEdit
    modifiedCount*: int ## Total buffers modified
    modifiedBufferIndexes*: seq[int] ## Indexes into `buffers` that were modified
