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

## Lightweight LSP integration state.
##
## Split from `lsp_integration` so `Editor.lsp` does not pull in its handlers.
## Exported fields are for `lsp_integration` internals, not public API.

import std/[monotimes, options, tables]

import ../lsp_service
import ../highlight
import ../lsp/worker
import ../buffer/core
import ../message_log

type
  LspParticipation* = enum
    ## Whether a server takes part in a buffer. Answered by inspection only.
    lpDisabled ## LSP is off for the whole editor.
    lpNoPath ## The buffer has no file path, so there is no URI to name.
    lpRawBuffer ## Undecodable bytes cannot cross the JSON wire.
    lpNoServer ## No language server is configured for this file's extension.
    lpParticipates ## The server wants this document.

  SyncBlocker* = enum
    ## Why a change was not handed over; the dedup key for the degrade log.
    sbNoServer ## No server process is there to receive it.
    sbTransport ## The notification could not be handed to the server.
    sbEnvironment ## The working directory the path resolves against is gone.
    sbInternal ## A bug on the sync path, not an outage.

  SyncVerdictKind* = enum
    ## How a sync attempt ended; `svSynced` means handed over, not provably equal.
    svSynced ## Takes part, and every change to this buffer was handed over.
    svNotApplicable ## Takes no part: LSP is off, no path, or undecodable bytes.
    svNoServer ## No server is configured for this file, so there is nobody to ask.
    svBehind ## Takes part, a change was not handed over, and a retry may fix that.
    svUnsyncable
      ## Takes part but accepts no changes; only didSave with text can catch it up.

  SyncVerdict* = object ## Result of a document sync attempt.
    case kind*: SyncVerdictKind
    of svBehind:
      blocker*: SyncBlocker
      detail*: string ## What the fixed wording cannot name; never the dedup key.
    else:
      discard

  LspStaleTolerance* = enum
    ## What to do when the server copy is behind the buffer.
    lstRefuse ## The answer would edit or move; a wrong one costs work to undo.
    lstTolerate ## The answer only decorates; a slightly old one beats none.

  LspRequestTrigger* = enum
    ## What set a request off; supplied by the call site.
    lrtAutomatic ## Frame or keystroke; never restarts a dead server nor forces a retry.
    lrtUserAction ## One deliberate key press; restarts once and retries immediately.

  LspSyncAttempt* = object
    ## Last sync attempt for a document, kept beside the shadow it describes.
    bufferId*: BufferId ## Attempted buffer; two buffers can share one path.
    contentVersion*: int ## Covered buffer version.
    at*: MonoTime ## When made; read only when stale.
    verdict*: SyncVerdict ## How that attempt ended.

  LspDocumentState* = object
    ## What the server holds for one document, plus the last attempt.
    version*: int ## Monotonic counter for didChange (last queued version).
    shadow: string ## Text the server holds. Written only by `noteServerHolds`.
    delivered: bool ## Whether the server holds a copy under this URI.
    generation*: int
      ## Document epoch bumped on invalidation; only (generation, version) identify a write.
    ackedVersion: int ## Last version confirmed on the wire within `generation`.
    attempt: Option[LspSyncAttempt]
      ## Last memo; none until the first attempt. Written only by `recordSyncAttempt`.

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
    # path -> sync state; shadow and memo share one record.
    documents*: Table[string, LspDocumentState]
    # URI each buffer handed the server, so a moved buffer still names the document it left behind.
    openedPaths*: Table[BufferId, string]
    pendingMessages*: seq[string]
    activeProgress*: Table[string, LspProgressState]
    lastProgressCleanupTime*: float
    serverStatus*: Table[string, LspStatusState]
    # Per-language colour table cache, built lazily to avoid per-token lookup.
    semanticTypeColorTables*: Table[string, SemanticTypeColorTable]

  WorkspaceEditResult* = object ## Outcome of applyWorkspaceEdit
    modifiedCount*: int ## Total buffers modified
    modifiedBufferIndexes*: seq[int] ## Indexes into `buffers` that were modified

const UnsyncableLogTag = "Unsyncable"
  ## Streak tag for the one failing verdict that carries no blocker.

proc syncLogTag(verdict: SyncVerdict): Option[string] =
  ## Streak tag for a verdict, or none when nothing failed.
  case verdict.kind
  of svSynced, svNotApplicable, svNoServer:
    none(string)
  of svUnsyncable:
    some(UnsyncableLogTag)
  of svBehind:
    some($verdict.blocker)

iterator syncLogTags(): string =
  ## Every tag `syncLogTag` can produce; keep total with `syncLogTag`.
  for kind in SyncVerdictKind:
    case kind
    of svSynced, svNotApplicable, svNoServer:
      discard
    of svUnsyncable:
      yield UnsyncableLogTag
    of svBehind:
      for blocker in SyncBlocker:
        yield $blocker

proc syncLogKey(id: BufferId, tag: string): string =
  ## Streak key per buffer and failure kind; kind-keyed so outages never silence each other.
  "sync:" & $id.int & ":" & tag

proc syncLogKey*(id: BufferId, verdict: SyncVerdict): Option[string] =
  ## Streak key for a verdict, or none when there is nothing to report.
  let tag = verdict.syncLogTag
  if tag.isNone:
    none(string)
  else:
    some(syncLogKey(id, tag.get))

proc forgetSyncReport*(id: BufferId) =
  ## Forget every streak for a buffer, whatever failed last.
  for tag in syncLogTags():
    clearLspMessageLogStreak(syncLogKey(id, tag))

proc initLspDocumentState*(
    version: int, shadow: string, delivered: bool
): LspDocumentState =
  ## Record with no memo; delivered implies already acked.
  LspDocumentState(
    version: version,
    shadow: shadow,
    delivered: delivered,
    ackedVersion: if delivered: version else: 0,
  )

proc syncSettled*(verdict: SyncVerdict): bool =
  ## Whether the hand-over is finished for now.
  verdict.kind in {svSynced, svNotApplicable, svNoServer}

proc reason*(verdict: SyncVerdict): string =
  ## Wording for log and refusal; kind stays the dedup key, `detail` carries the rest.
  case verdict.kind
  of svSynced, svNotApplicable:
    ""
  of svNoServer:
    # Same as `sbNoServer`; the distinction is not the user's to make.
    "no running language server for this file"
  of svUnsyncable:
    "the language server accepts no document changes"
  of svBehind:
    let base =
      case verdict.blocker
      of sbNoServer: "no running language server for this file"
      of sbTransport: "the edit could not be sent to the language server"
      of sbEnvironment: "the working directory this file resolves against is gone"
      of sbInternal: "internal error on the document sync path"
    if verdict.detail.len == 0:
      base
    else:
      base & ": " & verdict.detail

proc refusalMessage*(verdict: SyncVerdict): string =
  ## Refusal wording; each names the act that lifts it.
  case verdict.kind
  of svUnsyncable:
    "the language server has not seen your edits; save the file first"
  else:
    verdict.reason

proc logLspDegradedOnce*(key, feature, reason: string) =
  ## Log once per degradation; keyed by failure kind.
  addLspMessageLogForKey(key, "[LSP] " & feature & ": " & reason)

proc syncAttempt*(doc: LspDocumentState): Option[LspSyncAttempt] =
  ## Reader for the memo. Writers go through `recordSyncAttempt`.
  doc.attempt

proc shadow*(doc: LspDocumentState): lent string =
  ## Reader for the server text; borrowed for per-keystroke diff.
  doc.shadow

proc delivered*(doc: LspDocumentState): bool =
  ## Whether the server holds a copy under this URI.
  doc.delivered

proc ackedVersion*(doc: LspDocumentState): int =
  ## Last version the worker confirmed on the wire within the generation.
  doc.ackedVersion

proc noteServerHolds*(doc: var LspDocumentState, text: string) =
  ## Record that the server has `text`. Call only after a successful hand-over.
  doc.shadow = text
  doc.delivered = true

proc retractDelivery*(doc: var LspDocumentState) =
  ## Forget what the server holds; its process is gone.
  doc.delivered = false
  doc.shadow = ""

proc forgetSyncAttempt*(doc: var LspDocumentState) =
  ## Drop the memo so the next sync re-derives it.
  doc.attempt = none(LspSyncAttempt)

proc nextGeneration*(doc: var LspDocumentState) =
  ## Start a new epoch; old-generation acks are dropped.
  inc doc.generation
  doc.ackedVersion = 0
  doc.retractDelivery()
  doc.forgetSyncAttempt()

proc resetAckedVersion*(doc: var LspDocumentState) =
  ## Clear the confirmed version for a same-generation re-open.
  doc.ackedVersion = 0

proc noteSyncAcked*(doc: var LspDocumentState, version, generation: int) =
  ## Confirm `version` on the wire; FIFO and monotonic within `generation`.
  if generation != doc.generation:
    return
  if version > doc.ackedVersion:
    doc.ackedVersion = version

proc noteSyncNacked*(doc: var LspDocumentState, version, generation: int): bool =
  ## Record that `version` never reached the wire; equality counts for didSave.
  if generation != doc.generation:
    return false
  if version <= 0:
    # Version 0 names no write (unknown at save time). Never retract on it.
    return false
  if version >= doc.ackedVersion:
    doc.retractDelivery()
    doc.forgetSyncAttempt()
    return true
  false

proc recordSyncAttempt*(
    doc: var LspDocumentState,
    bufferId: BufferId,
    contentVersion: int,
    verdict: SyncVerdict,
    label: string,
) =
  ## Stamp the memo and report the verdict together, so outages log once.
  doc.attempt = some(
    LspSyncAttempt(
      bufferId: bufferId,
      contentVersion: contentVersion,
      at: getMonoTime(),
      verdict: verdict,
    )
  )
  let key = syncLogKey(bufferId, verdict)
  if key.isSome:
    logLspDegradedOnce(key.get, label, verdict.reason)
  elif verdict.kind == svSynced:
    # A landed sync clears every streak, whatever kind failed last.
    forgetSyncReport(bufferId)
  # svNotApplicable / svNoServer prove no delivery, so leave other streaks alone.
