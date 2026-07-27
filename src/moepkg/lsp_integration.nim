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

## LSP Integration with Editor
## Connects LspService to Editor, TextBuffer, and UI components

import std/[options, json, strutils, algorithm, sequtils, tables, times, unicode]
from std/os import absolutePath, normalizedPath

import pkg/[results, chronos]

import buffer, types, lsp_service, message_log, unicode_utils, highlight
import lsp/protocol/types as lspTypes

import types/lsp_integration_types
export lsp_integration_types

export lsp_service
export lspTypes.WorkDoneProgress, lspTypes.WorkDoneProgressKind
export lspTypes.WorkDoneProgressBegin, lspTypes.WorkDoneProgressReport
export lspTypes.WorkDoneProgressEnd, lspTypes.WorkspaceEdit
export worker.ServerHealth, worker.LspEventKind

const MaxProgressTextLen* = 50 ## Maximum display width for progress text

const ProgressCleanupIntervalSeconds* = 1.0 ## Interval between stale progress checks

proc canonicalPath(path: string): string {.inline.} =
  ## Collapse relative/absolute forms of the same file so `lsp.documents`
  ## and the notify* wire share one key.
  normalizedPath(absolutePath(path))

proc lspDegradeReason*(status: LspResponseStatus, detail = ""): string =
  ## Human-readable reason for a failed or timed-out LSP response.
  case status
  of lrsTimeout:
    "timed out"
  of lrsError:
    if detail.len > 0:
      "failed: " & detail
    else:
      "failed"
  else:
    # lrsPending/lrsSuccess are not failures; describe defensively.
    "failed"

proc logLspDegraded*(feature, reason: string) =
  ## Record a degraded LSP feature to the LSP message log so the degradation
  ## stays visible in the LSP log viewer even when file logging is disabled.
  ## Use for background features where interrupting the user is undesirable;
  ## for user-initiated features also set `statusMessage` at the call site.
  addLspMessageLog("[LSP] " & feature & ": " & reason)

proc logLspDegraded*(feature: string, status: LspResponseStatus, detail = "") =
  ## Overload taking an LspResponseStatus (and optional error detail) directly.
  logLspDegraded(feature, lspDegradeReason(status, detail))

proc newLspIntegration*(workspaceRoot: string = ""): LspIntegration =
  ## Create a new LSP integration
  let svc = newLspService(workspaceRoot)

  result = LspIntegration(
    service: svc,
    enabled: true,
    documents: initTable[string, tuple[version: int, shadow: string]](),
    pendingMessages: @[],
    activeProgress: initTable[string, LspProgressState](),
    lastProgressCleanupTime: 0.0,
    serverStatus: initTable[string, LspStatusState](),
    semanticTypeColorTables: initTable[string, SemanticTypeColorTable](),
  )

  # Set up internal callback to collect LSP log messages for display
  let lsp = result
  svc.onLogMessage = proc(
      langId: string, msgType: MessageType, message: string
  ) {.gcsafe.} =
    let prefix =
      case msgType
      of mtError: "[LSP Error] "
      of mtWarning: "[LSP Warning] "
      of mtInfo: "[LSP Info] "
      of mtLog: "[LSP Log] "
    if msgType == mtLog:
      addLspMessageLog(message)
    else:
      lsp.pendingMessages.add(prefix & langId & ": " & message)

  # Set up progress callback to track active progress operations
  svc.onProgress = proc(
      langId: string, token: string, progress: WorkDoneProgress
  ) {.gcsafe.} =
    case progress.kind
    of wdpkBegin:
      let state = LspProgressState(
        token: token,
        langId: langId,
        title: progress.begin.title,
        message: progress.begin.message,
        percentage: progress.begin.percentage,
        cancellable: progress.begin.cancellable.get(false),
        startTime: epochTime(),
      )
      lsp.activeProgress[token] = state
    of wdpkReport:
      if token in lsp.activeProgress:
        var state = lsp.activeProgress[token]
        if progress.report.message.isSome:
          state.message = progress.report.message
        if progress.report.percentage.isSome:
          state.percentage = progress.report.percentage
        if progress.report.cancellable.isSome:
          state.cancellable = progress.report.cancellable.get
        lsp.activeProgress[token] = state
      else:
        # Handle report without prior begin (create new state)
        let state = LspProgressState(
          token: token,
          langId: langId,
          title: "Progress",
          message: progress.report.message,
          percentage: progress.report.percentage,
          cancellable: progress.report.cancellable.get(false),
          startTime: epochTime(),
        )
        lsp.activeProgress[token] = state
    of wdpkEnd:
      lsp.activeProgress.del(token)

  # Set up status update callback to track server status
  svc.onStatusUpdate = proc(
      langId: string, health: ServerHealth, quiescent: bool, message: Option[string]
  ) {.gcsafe.} =
    lsp.serverStatus[langId] =
      LspStatusState(health: health, quiescent: quiescent, message: message)

proc getAndClearMessages*(lsp: LspIntegration): seq[string] =
  ## Get all pending status messages and clear them
  result = lsp.pendingMessages
  lsp.pendingMessages = @[]

proc hasActiveProgress*(lsp: LspIntegration): bool =
  ## Check if there are any active progress operations
  lsp.activeProgress.len > 0

proc getServerStatus*(lsp: LspIntegration, langId: string): Option[LspStatusState] =
  ## Get the current status for a language server
  if langId in lsp.serverStatus:
    some(lsp.serverStatus[langId])
  else:
    none(LspStatusState)

proc hasServerStatus*(lsp: LspIntegration, langId: string): bool =
  ## Check if we have status information for a language server
  langId in lsp.serverStatus

proc isServerQuiescent*(lsp: LspIntegration, langId: string): bool =
  ## Check if the server is quiescent (no pending background work)
  if langId in lsp.serverStatus:
    lsp.serverStatus[langId].quiescent
  else:
    true # Default to true if no status

proc getServerHealth*(lsp: LspIntegration, langId: string): ServerHealth =
  ## Get the health status for a language server
  if langId in lsp.serverStatus:
    lsp.serverStatus[langId].health
  else:
    shOk # Default to ok if no status

proc clearStatusForLanguage*(lsp: LspIntegration, langId: string) =
  ## Clear status for a specific language server
  ## Called when a server is stopped
  lsp.serverStatus.del(langId)

proc getStatusText*(state: LspStatusState): string =
  ## Format status state as a display string
  ## Returns empty string if status is ok and quiescent
  if state.health == shOk and state.quiescent:
    return ""

  result =
    case state.health
    of shOk:
      if not state.quiescent: "Loading" else: ""
    of shWarning:
      "Warning"
    of shError:
      "Error"

  if state.message.isSome and state.message.get.len > 0:
    if result.len > 0:
      result &= ": " & state.message.get
    else:
      result = state.message.get

proc clearProgressForLanguage*(lsp: LspIntegration, langId: string) =
  ## Clear all progress operations for a specific language server
  ## Called when a server is stopped or crashes
  var tokensToRemove: seq[string] = @[]
  for token, state in lsp.activeProgress:
    if state.langId == langId:
      tokensToRemove.add(token)
  for token in tokensToRemove:
    lsp.activeProgress.del(token)

const ProgressTimeoutSeconds* = 300.0 ## 5 minutes timeout for stale progress

proc cleanupStaleProgress*(lsp: LspIntegration) =
  ## Remove progress entries that have been active for too long
  ## This handles cases where 'end' notification was never received
  ## Only runs cleanup at most once per ProgressCleanupIntervalSeconds
  let now = epochTime()

  # Rate limit cleanup checks
  if now - lsp.lastProgressCleanupTime < ProgressCleanupIntervalSeconds:
    return
  lsp.lastProgressCleanupTime = now

  var tokensToRemove: seq[string] = @[]
  for token, state in lsp.activeProgress:
    if now - state.startTime > ProgressTimeoutSeconds:
      tokensToRemove.add(token)
  for token in tokensToRemove:
    lsp.activeProgress.del(token)

proc getActiveProgressList*(lsp: LspIntegration): seq[LspProgressState] =
  ## Get all active progress operations
  result = @[]
  for state in lsp.activeProgress.values:
    result.add(state)

proc getLatestActiveProgress*(lsp: LspIntegration): Option[LspProgressState] =
  ## Get the most recently started active progress operation
  ## Returns the progress with the latest startTime for consistent display
  if lsp.activeProgress.len == 0:
    return none(LspProgressState)

  var latest: LspProgressState
  var found = false
  for state in lsp.activeProgress.values:
    if not found or state.startTime > latest.startTime:
      latest = state
      found = true
  if found:
    return some(latest)
  return none(LspProgressState)

proc getProgressText*(state: LspProgressState): string =
  ## Format progress state as a display string with length limit
  result = state.title
  if state.message.isSome:
    result &= ": " & state.message.get
  if state.percentage.isSome:
    result &= " (" & $state.percentage.get & "%)"

  # Truncate if too long
  result = truncateToWidthWithSuffix(result, MaxProgressTextLen)

proc setDiagnosticsCallback*(
    lsp: LspIntegration,
    callback:
      proc(uri: string, diagnostics: seq[Diagnostic], version: Option[int]) {.gcsafe.},
) =
  ## Set callback for diagnostics updates
  lsp.service.onDiagnosticsUpdate = callback

proc setLogCallback*(
    lsp: LspIntegration,
    callback: proc(langId: string, msgType: MessageType, message: string) {.gcsafe.},
) =
  ## Set callback for log messages
  lsp.service.onLogMessage = callback

proc setServerRestartCallback*(
    lsp: LspIntegration, callback: proc(langId: string) {.gcsafe.}
) =
  ## Set callback invoked when a language server re-initializes after a crash.
  ## The editor uses it to re-open buffers so diagnostics/completion recover
  ## without a manual `:lspRestart`.
  lsp.service.onServerRestart = callback

proc setApplyEditCallback*(
    lsp: LspIntegration,
    callback: proc(edit: WorkspaceEdit): ApplyWorkspaceEditResult {.gcsafe.},
) =
  ## Set callback for server-initiated workspace/applyEdit requests (e.g.
  ## rust-analyzer refactors delivered through executeCommand). The callback
  ## applies the edit to the editor's buffers and reports whether it succeeded.
  lsp.service.onApplyWorkspaceEdit = callback

# Buffer lifecycle operations
proc onBufferOpen*(
    lsp: LspIntegration, buffer: TextBuffer, serverIsFresh: bool = false
): Result[void, string] =
  ## Called when a buffer is opened/loaded.
  ## If the path is already tracked, sends didClose first: the version reset
  ## below would otherwise send a second didOpen at v1 while the server still
  ## holds a higher version, causing later didChange to be dropped as stale.
  ## `serverIsFresh` skips the didClose on the restart path where the worker
  ## just started and knows nothing about the document.
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = canonicalPath(buffer.filePath.get)
  let text = buffer.getTextString()

  if path in lsp.documents and not serverIsFresh:
    discard lsp.service.notifyDocumentClosed(path)

  lsp.documents[path] = (version: 1, shadow: text)

  return lsp.service.notifyDocumentOpened(path, text)

proc onBufferClose*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer is closed
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = canonicalPath(buffer.filePath.get)

  # Remove from tracking
  lsp.documents.del(path)

  return lsp.service.notifyDocumentClosed(path)

# UTF-16 position conversion helpers
# LSP uses UTF-16 code units for character positions. Buffer columns are rune
# indexes (see BufferPosition), while some callers work with UTF-8 byte
# offsets. These functions convert between the representations.

proc utf16OffsetToUtf8*(line: string, utf16Offset: int): int =
  ## Convert LSP UTF-16 code unit offset to UTF-8 byte offset
  ## LSP uses UTF-16 code units for character positions
  ## Returns the UTF-8 byte offset, clamped to line length
  if utf16Offset <= 0:
    return 0
  if line.len == 0:
    return 0

  var utf16Count = 0
  var byteOffset = 0

  for rune in line.runes:
    if utf16Count >= utf16Offset:
      break
    # BMP characters (U+0000 to U+FFFF) use 1 UTF-16 code unit
    # Characters above U+FFFF (surrogate pairs) use 2 UTF-16 code units
    let codePoint = rune.int
    if codePoint >= 0x10000:
      utf16Count += 2 # Surrogate pair
    else:
      utf16Count += 1
    byteOffset += rune.size

  return min(byteOffset, line.len)

proc utf8OffsetToUtf16*(line: string, utf8Offset: int): int =
  ## Convert UTF-8 byte offset to LSP UTF-16 code unit offset
  ## Used when sending positions back to LSP server
  if utf8Offset <= 0:
    return 0
  if line.len == 0:
    return 0

  var utf16Count = 0
  var byteCount = 0

  for rune in line.runes:
    if byteCount >= utf8Offset:
      break
    let codePoint = rune.int
    if codePoint >= 0x10000:
      utf16Count += 2 # Surrogate pair
    else:
      utf16Count += 1
    byteCount += rune.size

  return utf16Count

proc runeStartByteBefore(s: string, pos: int): int =
  ## Byte offset where the rune ending just before `pos` begins, stepping back
  ## over UTF-8 continuation bytes.
  result = pos - 1
  while result > 0 and (s[result].uint8 and 0xC0'u8) == 0x80'u8:
    dec result

proc commonRunePrefixBytes(a, b: string): int =
  ## Byte length of the longest common prefix of `a` and `b` ending on a rune
  ## boundary.
  while result < a.len and result < b.len:
    let n = a.runeLenAt(result)
    # runeLenAt derives n from the lead byte alone; if the claimed rune runs
    # past either string (truncated/invalid UTF-8) stop here rather than read
    # out of bounds.
    if result + n > a.len or result + n > b.len:
      break
    if n != b.runeLenAt(result):
      break
    var eq = true
    for k in 0 ..< n:
      if a[result + k] != b[result + k]:
        eq = false
        break
    if not eq:
      break
    result += n

proc commonRuneSuffixBytes(a, b: string, floor: int): int =
  ## Byte length of the longest common suffix of `a` and `b` ending on a rune
  ## boundary, without reaching below `floor` bytes in either string.
  var
    ai = a.len
    bi = b.len
  while ai > floor and bi > floor:
    let
      ra = runeStartByteBefore(a, ai)
      rb = runeStartByteBefore(b, bi)
    if ai - ra != bi - rb or ra < floor or rb < floor:
      break
    var eq = true
    for k in 0 ..< (ai - ra):
      if a[ra + k] != b[rb + k]:
        eq = false
        break
    if not eq:
      break
    ai = ra
    bi = rb
  a.len - ai

proc computeIncrementalChange*(oldText, newText: string): Option[JsonNode] =
  ## Single contiguous line-range diff using character-0 (line-start) anchors,
  ## except an in-place single-line edit, which is narrowed to a UTF-16 column
  ## range so a one-character change on a long line ships only the changed run.
  ## Returns none when the delta cannot be localized this way (the caller then
  ## falls back to a full-text sync). Equivalent to a split('\n') line diff, but
  ## scans the two strings in place instead of allocating a seq[string] per call.
  let
    oldLen = oldText.len
    newLen = newText.len
    oldLines = oldText.count('\n') + 1 # split('\n') keeps the trailing empty line
    newLines = newText.count('\n') + 1

  # Longest common run of whole leading lines (p), walking both line by line.
  var
    p = 0
    oldP = 0
    newP = 0
  while p < oldLines and p < newLines:
    var oe = oldP
    while oe < oldLen and oldText[oe] != '\n':
      inc oe
    var ne = newP
    while ne < newLen and newText[ne] != '\n':
      inc ne
    if oe - oldP != ne - newP:
      break
    var same = true
    for t in 0 ..< (oe - oldP):
      if oldText[oldP + t] != newText[newP + t]:
        same = false
        break
    if not same:
      break
    inc p
    oldP = oe + 1
    newP = ne + 1

  if p == oldLines:
    # Every old line is a leading line of new, so oldText is a byte-prefix of
    # newText: either a no-op (equal) or a pure append at end-of-document. Emit
    # an empty-range insertion at the real last position {lastLine, its UTF-16
    # length} instead of falling back to a full re-send (covers EOF append and
    # adding a trailing newline, both common edits).
    if newLen == oldLen:
      return none(JsonNode) # no-op (also caught earlier by the shadow check)
    var lastStart = oldLen
    while lastStart > 0 and oldText[lastStart - 1] != '\n':
      dec lastStart
    let
      lastLine = oldText[lastStart ..< oldLen]
      endCol = utf8OffsetToUtf16(lastLine, lastLine.len)
    return some(
      %*[
        {
          "range": {
            "start": {"line": oldLines - 1, "character": endCol},
            "end": {"line": oldLines - 1, "character": endCol},
          },
          "text": newText[oldLen ..< newLen],
        }
      ]
    )

  # Longest common run of whole trailing lines (s), kept from overlapping the
  # prefix. newEnd tracks the byte offset where the matched suffix begins in
  # newText, i.e. the end of the replacement span.
  var
    s = 0
    oldEnd = oldLen
    newEnd = newLen
  while s < (oldLines - p) and s < (newLines - p):
    let oldContentEnd = (if s == 0: oldEnd else: oldEnd - 1)
    var oldStart = oldContentEnd
    while oldStart > 0 and oldText[oldStart - 1] != '\n':
      dec oldStart
    let newContentEnd = (if s == 0: newEnd else: newEnd - 1)
    var newStart = newContentEnd
    while newStart > 0 and newText[newStart - 1] != '\n':
      dec newStart
    if oldContentEnd - oldStart != newContentEnd - newStart:
      break
    var same = true
    for t in 0 ..< (oldContentEnd - oldStart):
      if oldText[oldStart + t] != newText[newStart + t]:
        same = false
        break
    if not same:
      break
    inc s
    oldEnd = oldStart
    newEnd = newStart

  # Single-line edit (exactly one old line replaced by one new line in place):
  # diff within the line and emit a UTF-16 column range so only the changed run
  # is sent. oldP/newP still point at line p's start; oldEnd/newEnd at line
  # (lines - s)'s start, so the '\n' is at *End - 1 unless line p is the last.
  if oldLines - s == p + 1 and newLines - s == p + 1:
    let
      oldLineEnd = (if s > 0: oldEnd - 1 else: oldEnd)
      newLineEnd = (if s > 0: newEnd - 1 else: newEnd)
      oldLine = oldText[oldP ..< oldLineEnd]
      newLine = newText[newP ..< newLineEnd]
      cp = commonRunePrefixBytes(oldLine, newLine)
      cs = commonRuneSuffixBytes(oldLine, newLine, cp)
      startCol = utf8OffsetToUtf16(oldLine, cp)
      endCol = utf8OffsetToUtf16(oldLine, oldLine.len - cs)
      replacement = newLine[cp ..< newLine.len - cs]
    return some(
      %*[
        {
          "range": {
            "start": {"line": p, "character": startCol},
            "end": {"line": p, "character": endCol},
          },
          "text": replacement,
        }
      ]
    )

  if s == 0 and p > 0:
    # Deleting/replacing the file tail with no common-suffix line to anchor the
    # trailing newline: back the start anchor up one already-common line so the
    # newline preceding the changed tail is consumed inside the range. Keeps
    # character-0 anchors (no UTF-16 column-encoding hazard).
    dec p

  proc lineStartByteOffset(text: string, lineIdx, lineCount: int): int =
    ## Byte offset where line `lineIdx` begins (== text.len for the one-past-last
    ## line index), mirroring the clamping of the old seq-based lineStartOffset.
    if lineIdx >= lineCount:
      return text.len
    if lineIdx <= 0:
      return 0
    var seen = 0
    for i in 0 ..< text.len:
      if text[i] == '\n':
        inc seen
        if seen == lineIdx:
          return i + 1
    text.len

  let
    # newEnd already equals lineStartByteOffset(newText, newLines - s); only the
    # start anchor needs the post-dec recompute.
    replacement = newText[lineStartByteOffset(newText, p, newLines) ..< newEnd]

  # End anchor. For s > 0 the trailing common line gives an in-range character-0
  # anchor. For s == 0 the replacement runs to end-of-document; emit the real
  # last position {lastLine, its UTF-16 length} instead of {lineCount, 0} (one
  # past the last line), which strict servers that do not clamp out-of-range
  # line indices would reject or mis-apply.
  var
    endLine = oldLines - s
    endCol = 0
  if s == 0:
    endLine = oldLines - 1
    let lastLine =
      oldText[lineStartByteOffset(oldText, oldLines - 1, oldLines) ..< oldLen]
    endCol = utf8OffsetToUtf16(lastLine, lastLine.len)

  # Emit the contentChanges entry directly so the optional/deprecated rangeLength
  # is omitted: a typed TextDocumentContentChangeEvent would serialize its `none`
  # rangeLength as JSON null, which strict servers reject.
  return some(
    %*[
      {
        "range": {
          "start": {"line": p, "character": 0},
          "end": {"line": endLine, "character": endCol},
        },
        "text": replacement,
      }
    ]
  )

proc onBufferChange*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer content changes
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = canonicalPath(buffer.filePath.get)
  let text = buffer.getTextString()

  # Untracked -> didOpen fallback (version 1), seed shadow.
  if path notin lsp.documents:
    lsp.documents[path] = (version: 1, shadow: text)
    let openResult = lsp.service.notifyDocumentOpened(path, text)
    if openResult.isErr:
      lsp.documents.del(path)
      return openResult
    return ok()

  # no-op: server already holds this exact text (insert+delete bumped changeSeq).
  # The path is present here (the untracked branch above already returned).
  if lsp.documents[path].shadow == text:
    return ok()

  let kind = lsp.service.documentSyncKind(path)
  if kind == tdskNone:
    return ok()

  # Resolve running-ness once: it gates incremental below, and a running worker
  # is live by definition, so the `or` short-circuits the hasLiveWorkerForPath
  # lookup in the steady-state running path.
  let running = lsp.service.isWorkerRunningForPath(path)

  # No worker would receive this change (absent/crashed). Skip without bumping
  # the version or advancing the shadow: nothing is sent or coalesced, so
  # advancing would desync the shadow from what the server actually holds. After
  # a server crash that followed a successful init, onServerRestart re-sends
  # didOpen and re-seeds the shadow, so the skip self-heals (a crash during the
  # very first init is the exception: the buffer stays unsynced until reopened).
  # A starting worker still counts because a full change coalesces into the
  # pending didOpen; incremental is sent only once the worker is running.
  if not (running or lsp.service.hasLiveWorkerForPath(path)):
    return ok()

  # LSP requires the version to increase with every change. Use a dedicated
  # monotonic counter: buffer.changeSeq is unsuitable because undo rolls it
  # back, and servers ignore didChange notifications with stale versions.
  inc lsp.documents[path].version
  let version = lsp.documents[path].version

  # notifyDocumentChanged* are fire-and-forget to a ready worker (they never
  # return err here), so the shadow advances to the just-sent text.
  # Only send incremental when the worker is already running. A starting worker
  # must receive full sync so the change can coalesce into the pending didOpen;
  # sending incremental to a starting worker drops it and desyncs the shadow.
  if kind == tdskIncremental and running:
    let changes = computeIncrementalChange(lsp.documents[path].shadow, text)
    if changes.isSome:
      discard lsp.service.notifyDocumentChangedIncremental(path, version, $changes.get)
      lsp.documents[path].shadow = text
      return ok()

  # Full sync (tdskFull / diff fallback / starting worker).
  discard lsp.service.notifyDocumentChanged(path, version, text)
  lsp.documents[path].shadow = text
  return ok()

proc flushPendingBufferChange*(lsp: LspIntegration, buffer: TextBuffer) {.raises: [].} =
  ## Send any queued didChange for `buffer` now, before an out-of-band request
  ## puts a positional request ahead of the edit on the wire. No-op when the
  ## server's shadow already matches (self-gated by `onBufferChange`). Best-
  ## effort: transport errors are swallowed so callers on any raises contract
  ## stay stable.
  try:
    discard lsp.onBufferChange(buffer)
  except Exception:
    discard

proc sentDocumentVersion*(lsp: LspIntegration, path: string): Option[int] =
  ## The last didOpen/didChange version sent to the server for `path`,
  ## or `none` if the document is not tracked as open. Exposed for tests.
  let key = canonicalPath(path)
  if key in lsp.documents:
    some(lsp.documents[key].version)
  else:
    none(int)

proc onBufferSave*(lsp: LspIntegration, buffer: TextBuffer): Result[void, string] =
  ## Called when a buffer is saved
  if not lsp.enabled:
    return ok()

  if buffer.filePath.isNone:
    return ok()

  let path = canonicalPath(buffer.filePath.get)
  let text = some(buffer.getTextString())
  return lsp.service.notifyDocumentSaved(path, text)

# Polling for server messages
proc poll*(lsp: LspIntegration, timeoutMs: int = 0) =
  ## Poll for LSP server messages
  if lsp.enabled:
    lsp.service.poll(timeoutMs)

proc runeIndexToUtf16*(line: string, runeIndex: int): int =
  ## Convert a rune (character) index to a UTF-16 code unit offset.
  ## Buffer columns are rune indexes; LSP positions are UTF-16 code units.
  ## Clamped to the number of UTF-16 units in the line.
  if runeIndex <= 0 or line.len == 0:
    return 0

  var runeCount = 0
  for rune in line.runes:
    if runeCount >= runeIndex:
      break
    # BMP characters (U+0000 to U+FFFF) use 1 UTF-16 code unit
    # Characters above U+FFFF (surrogate pairs) use 2 UTF-16 code units
    if rune.int >= 0x10000:
      result += 2 # Surrogate pair
    else:
      result.inc
    runeCount.inc

proc toUtf16Column(buffer: TextBuffer, line, column: int): int =
  ## Helper to convert a buffer position (rune index) to a UTF-16 code unit offset
  let lineText =
    if line >= 0 and line < buffer.len:
      buffer.getLine(line)
    else:
      ""
  runeIndexToUtf16(lineText, column)

template requireBufferPath(lsp: LspIntegration, buffer: TextBuffer): string =
  ## Guard for sync LSP request wrappers: checks `enabled` and `filePath`,
  ## returning an `err` Result from the caller on failure. Evaluates to the
  ## file path.
  ##
  ## Sync-only: chronos `{.async.}` procs cannot use this template because the
  ## embedded `return err(...)` is not transformed into `complete(...)` by the
  ## async macro. Async procs should call `resolveLspPath` instead and bind
  ## the Result themselves.
  if not lsp.enabled:
    return err("LSP disabled")
  if buffer.filePath.isNone:
    return err("Buffer has no file path")
  buffer.filePath.get

proc resolveLspPath(lsp: LspIntegration, buffer: TextBuffer): Result[string, string] =
  ## Async-safe counterpart to `requireBufferPath`: returns the buffer's path
  ## or an error as a Result, without performing an early return in the caller.
  if not lsp.enabled:
    return err("LSP disabled")
  if buffer.filePath.isNone:
    return err("Buffer has no file path")
  ok(buffer.filePath.get)

proc resolveLspPathForRequest(
    lsp: LspIntegration, buffer: TextBuffer
): Result[string, string] {.raises: [].} =
  ## `resolveLspPath` + flush pending didChange before a positional request.
  let pathRes = resolveLspPath(lsp, buffer)
  if pathRes.isErr:
    return pathRes
  lsp.flushPendingBufferChange(buffer)
  pathRes

proc requireLangId(lsp: LspIntegration, buffer: TextBuffer): Option[string] =
  ## Resolve the language ID for a buffer when LSP is enabled and the buffer
  ## has a path. Returns `none` when any precondition fails.
  if not lsp.enabled or buffer.filePath.isNone:
    return none(string)
  lsp.service.getLanguageIdFromPath(buffer.filePath.get)

template defineSupportCheck(name: untyped) =
  ## Generate a buffer-level capability predicate: resolve the buffer's language
  ## and delegate to the `LspService` check of the same name. Used for the many
  ## `hasXxxSupport` wrappers that differ only by the delegated proc.
  proc name*(lsp: LspIntegration, buffer: TextBuffer): bool =
    let langId = requireLangId(lsp, buffer)
    langId.isSome and lsp.service.name(langId.get)

template definePositionRequest(name: untyped) =
  ## Generate a position-based request wrapper: resolve the buffer path, convert
  ## the rune column to UTF-16, and delegate to the `LspService` proc of the same
  ## name. Returns the request ID.
  proc name*(
      lsp: LspIntegration, buffer: TextBuffer, line, column: int
  ): Result[int, string] =
    let path = requireBufferPath(lsp, buffer)
    lsp.service.name(path, line, buffer.toUtf16Column(line, column))

template defineDocumentRequest(name: untyped) =
  ## Generate a whole-document request wrapper: resolve the buffer path and
  ## delegate to the `LspService` proc of the same name. Returns the request ID.
  proc name*(lsp: LspIntegration, buffer: TextBuffer): Result[int, string] =
    let path = requireBufferPath(lsp, buffer)
    lsp.service.name(path)

# Async (non-blocking) feature requests
# These return immediately with a request ID. Use poll() and checkResponse() to get results.
# Note: All position-based requests convert rune-index columns to UTF-16 for LSP protocol compliance.

definePositionRequest(startCompletionRequest)

proc startCompletionResolveRequest*(
    lsp: LspIntegration, buffer: TextBuffer, itemJson: JsonNode
): Result[int, string] =
  ## Start a completionItem/resolve request (non-blocking). Returns request ID.
  let path = requireBufferPath(lsp, buffer)
  lsp.service.startCompletionResolveRequest(path, itemJson)

definePositionRequest(startHoverRequest)
definePositionRequest(startDefinitionRequest)
definePositionRequest(startDeclarationRequest)
definePositionRequest(startReferencesRequest)
definePositionRequest(startTypeDefinitionRequest)
definePositionRequest(startImplementationRequest)
definePositionRequest(startSignatureHelpRequest)

defineSupportCheck(hasCompletionSupport)
defineSupportCheck(hasSignatureHelpSupport)
defineSupportCheck(hasDocumentHighlightSupport)
defineSupportCheck(hasHoverSupport)
defineSupportCheck(hasDefinitionSupport)
defineSupportCheck(hasDeclarationSupport)
defineSupportCheck(hasReferencesSupport)
defineSupportCheck(hasTypeDefinitionSupport)
defineSupportCheck(hasImplementationSupport)

definePositionRequest(startDocumentHighlightRequest)
defineDocumentRequest(startCodeLensRequest)
definePositionRequest(startCallHierarchyPrepareRequest)

proc startCallHierarchyIncomingCallsRequest*(
    lsp: LspIntegration, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy incoming calls request (non-blocking). Returns request ID.
  ## The worker is resolved from `item.uri` rather than the active buffer, so the
  ## request routes correctly even when the call hierarchy viewer (a synthetic,
  ## path-less buffer) is active or the item lives in a different file.
  if not lsp.enabled:
    return err("LSP disabled")
  let path = uriToPath(item.uri)
  lsp.service.startCallHierarchyIncomingCallsRequest(path, item)

proc startCallHierarchyOutgoingCallsRequest*(
    lsp: LspIntegration, item: CallHierarchyItem
): Result[int, string] =
  ## Start a call hierarchy outgoing calls request (non-blocking). Returns request ID.
  ## See `startCallHierarchyIncomingCallsRequest` for why the path comes from
  ## `item.uri` instead of the active buffer.
  if not lsp.enabled:
    return err("LSP disabled")
  let path = uriToPath(item.uri)
  lsp.service.startCallHierarchyOutgoingCallsRequest(path, item)

defineDocumentRequest(startDocumentSymbolsRequest)
defineDocumentRequest(startDocumentLinkRequest)

proc startDocumentLinkResolveRequest*(
    lsp: LspIntegration, buffer: TextBuffer, link: DocumentLink
): Result[int, string] =
  ## Start a document link resolve request (non-blocking). Returns request ID.
  let path = requireBufferPath(lsp, buffer)
  lsp.service.startDocumentLinkResolveRequest(path, link)

definePositionRequest(startSelectionRangeRequest)

proc checkResponse*(
    lsp: LspIntegration, requestId: int
): tuple[status: LspResponseStatus, result: Option[JsonNode], error: Option[string]] =
  ## Non-blocking check if a response has arrived
  return lsp.service.checkResponse(requestId)

proc checkResponseRaw*(
    lsp: LspIntegration, requestId: int
): tuple[status: LspResponseStatus, raw: Option[string], error: Option[string]] =
  ## Non-blocking check that returns the unparsed result JSON string for a
  ## typed (jsony) consumer.
  return lsp.service.checkResponseRaw(requestId)

proc hasPendingRequests*(lsp: LspIntegration): bool =
  ## Check if there are any pending requests
  lsp.service.hasPendingRequests()

proc cancelRequest*(lsp: LspIntegration, requestId: int) =
  ## Cancel a pending LSP request and clean up tracking state
  lsp.service.cancelRequest(requestId)

proc cleanupTimedOutRequests*(lsp: LspIntegration) =
  ## Clean up any timed out requests
  lsp.service.cleanupTimedOutRequests()

proc getSemanticTokensLegend*(
    lsp: LspIntegration, buffer: TextBuffer
): Option[SemanticTokensLegend] =
  ## Get the semantic tokens legend for a buffer's language
  let langId = requireLangId(lsp, buffer)
  if langId.isNone:
    return none(SemanticTokensLegend)
  lsp.service.getSemanticTokensLegend(langId.get)

proc getSemanticTypeColorTable*(
    lsp: LspIntegration, buffer: TextBuffer
): Option[SemanticTypeColorTable] =
  ## Cached `tokenType -> colour` table for the buffer's language. Rebuilt if
  ## the server dynamically re-registered a different legend.
  let langId = requireLangId(lsp, buffer)
  if langId.isNone:
    return none(SemanticTypeColorTable)
  let legendOpt = lsp.service.getSemanticTokensLegend(langId.get)
  if legendOpt.isNone:
    return none(SemanticTypeColorTable)
  let currentLegend = legendOpt.get
  if lsp.semanticTypeColorTables.hasKey(langId.get):
    let cached = lsp.semanticTypeColorTables[langId.get]
    if cached.legend == currentLegend:
      return some(cached)
  let tab = buildSemanticTypeColorTable(currentLegend)
  lsp.semanticTypeColorTables[langId.get] = tab
  return some(tab)

proc startSemanticTokensRequest*(
    lsp: LspIntegration, buffer: TextBuffer, firstLine, lastLine: int
): Result[int, string] =
  ## Start a semantic tokens request (non-blocking). Returns request ID.
  ## Uses range request if supported, otherwise falls back to full document.
  let path = requireBufferPath(lsp, buffer)
  if buffer.len == 0:
    return err("Buffer is empty")

  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return err("No LSP support for file: " & path)

  # Check if range request is supported, fall back to full if not
  if lsp.service.hasSemanticTokensRangeSupport(langIdOpt.get):
    # Clamp line numbers to valid range
    let actualLastLine = min(lastLine, buffer.len - 1)
    let actualFirstLine = min(firstLine, actualLastLine)
    let endChar =
      buffer.toUtf16Column(actualLastLine, buffer.getLine(actualLastLine).charLen)
    return lsp.service.startSemanticTokensRangeRequest(
      path, actualFirstLine, 0, actualLastLine, endChar
    )
  elif lsp.service.hasSemanticTokensFullSupport(langIdOpt.get):
    # Fall back to full document request
    return lsp.service.startSemanticTokensFullRequest(path)
  else:
    return err("Semantic tokens not supported")

defineSupportCheck(hasInlayHintSupport)

proc startInlayHintRequest*(
    lsp: LspIntegration, buffer: TextBuffer, firstLine, lastLine: int
): Result[int, string] =
  ## Start an inlay hint request for a viewport line range (non-blocking).
  ## Returns request ID. The range is clamped to the buffer bounds.
  let path = requireBufferPath(lsp, buffer)
  if buffer.len == 0:
    return err("Buffer is empty")

  let actualLastLine = min(lastLine, buffer.len - 1)
  let actualFirstLine = max(0, min(firstLine, actualLastLine))
  let endChar =
    buffer.toUtf16Column(actualLastLine, buffer.getLine(actualLastLine).charLen)
  lsp.service.startInlayHintRequest(path, actualFirstLine, 0, actualLastLine, endChar)

defineSupportCheck(hasDocumentLinkSupport)
defineSupportCheck(hasDocumentLinkResolveSupport)
defineSupportCheck(hasRenameSupport)
defineSupportCheck(hasFormattingSupport)
defineSupportCheck(hasSelectionRangeSupport)

# TextEdit application helpers
proc compareTextEditReverse(a, b: (int, TextEdit)): int =
  ## Order (originalIndex, edit) pairs for back-to-front application.
  ## Later document positions sort first. For edits at the *same* start
  ## position, the LSP spec says they appear in the document in array order;
  ## applying back-to-front, the later array element must be applied first so
  ## the earlier one ends up before it. Hence the original index is the
  ## tiebreaker, in descending order.
  let ea = a[1]
  let eb = b[1]
  if ea.range.start.line != eb.range.start.line:
    return eb.range.start.line - ea.range.start.line
  if ea.range.start.character != eb.range.start.character:
    return eb.range.start.character - ea.range.start.character
  return b[0] - a[0]

proc applyTextEdits*(buffer: TextBuffer, edits: seq[TextEdit]): Result[void, string] =
  ## Apply a sequence of TextEdits to the buffer
  ## Edits are applied in reverse order (back to front) to preserve positions
  ## Note: LSP TextEdit.range.end is exclusive, buffer.deleteRange is inclusive
  ## Note: LSP character positions are in UTF-16 code units, converted to rune indexes
  ## Edits are wrapped in a single undo entry. If the caller already opened a
  ## transaction (e.g. Insert mode completion, workspace edit), we join that
  ## one; otherwise we open and commit our own so a single Ctrl-r/u reverts
  ## the whole edit group instead of one TextEdit at a time.
  ##
  ## Failure semantics:
  ## - Self-managed (no outer transaction): on partial failure we rollback
  ##   the transaction we opened, so the buffer is left at its pre-call state.
  ## - Joined an outer transaction: on partial failure we return err WITHOUT
  ##   rolling back — the outer transaction is left dirty with whichever inner
  ##   edits already applied. The caller is responsible for rollback because
  ##   it may want to keep earlier work in the same transaction.
  if edits.len == 0:
    return ok()

  let ownTransaction = not buffer.inTransaction
  if ownTransaction:
    let txr = buffer.beginTransaction("LSP TextEdits")
    if txr.isErr:
      return err("Failed to begin transaction: " & txr.error)

  # Sort edits in reverse order (back to front), keeping the original index
  # as a tiebreaker for same-position edits (see compareTextEditReverse)
  var indexed = newSeq[(int, TextEdit)](edits.len)
  for i, e in edits:
    indexed[i] = (i, e)
  indexed.sort(compareTextEditReverse)
  var sortedEdits = newSeq[TextEdit](edits.len)
  for i in 0 ..< indexed.len:
    sortedEdits[i] = indexed[i][1]

  template failEdit(msg: string): untyped =
    if ownTransaction:
      discard buffer.rollbackTransaction()
    return err(msg)

  # Apply each edit
  for edit in sortedEdits:
    let startLine = edit.range.start.line
    let lspEndPos = edit.range.`end`

    # Convert UTF-16 character offset to rune index
    let startLineText =
      if startLine >= 0 and startLine < buffer.len:
        buffer.getLine(startLine)
      else:
        ""
    let startCol = utf16ToRuneIndex(startLineText, edit.range.start.character)
    let startPos = BufferPosition(line: startLine, column: startCol)

    # Check if range is empty (LSP exclusive end == start means empty range)
    let isEmptyRange =
      edit.range.start.line == lspEndPos.line and
      edit.range.start.character == lspEndPos.character

    # Malformed range where start > end (spec-compliant servers never send this).
    # Treat as empty so we skip deletion but still honor the insert at startPos.
    let isMalformedRange =
      lspEndPos.line < edit.range.start.line or (
        lspEndPos.line == edit.range.start.line and
        lspEndPos.character < edit.range.start.character
      )

    # Delete the range if it's not empty
    if not isEmptyRange and not isMalformedRange:
      # Convert LSP exclusive end to buffer inclusive end
      var adjustedEndPos: BufferPosition

      # Get end line text for UTF-16 conversion
      let endLineText =
        if lspEndPos.line >= 0 and lspEndPos.line < buffer.len:
          buffer.getLine(lspEndPos.line)
        else:
          ""

      if lspEndPos.character > 0:
        # Convert UTF-16 to a rune index and decrement by one rune for the
        # inclusive end
        if lspEndPos.line >= buffer.len:
          # End points past EOF: clamp to end of last line
          let last = buffer.len - 1
          adjustedEndPos =
            BufferPosition(line: last, column: buffer.getLine(last).charLen)
        else:
          let endRune = utf16ToRuneIndex(endLineText, lspEndPos.character)
          adjustedEndPos =
            BufferPosition(line: lspEndPos.line, column: max(endRune - 1, 0))
      else:
        # End is at start of a line (character == 0)
        # Need to point to end of previous line to include the newline
        # lspEndPos.line > 0 here: isMalformedRange rejected end at (0,0).
        let prevIdx = min(lspEndPos.line - 1, buffer.len - 1)
        adjustedEndPos =
          BufferPosition(line: prevIdx, column: buffer.getLine(prevIdx).charLen)

      # Only delete if we have a valid range
      if startPos.line < adjustedEndPos.line or (
        startPos.line == adjustedEndPos.line and startPos.column <= adjustedEndPos.column
      ):
        let deleteResult = buffer.deleteRange(startPos, adjustedEndPos)
        if deleteResult.isErr:
          failEdit("Failed to delete range: " & deleteResult.error)

    # Insert the new text if not empty
    if edit.newText.len > 0:
      let insertResult = buffer.insertText(startPos, edit.newText)
      if insertResult.isErr:
        failEdit("Failed to insert text: " & insertResult.error)

  if ownTransaction:
    let cr = buffer.commitTransaction()
    if cr.isErr:
      # Commit failed but we own the transaction. Attempt to rollback so the
      # buffer doesn't stay stuck in an in-progress transaction.
      discard buffer.rollbackTransaction()
      return err("Failed to commit transaction: " & cr.error)

  return ok()

proc samePath(a, b: string): bool =
  ## Compare two file paths after normalizing to absolute form.
  ## Buffers opened with a relative path (e.g. `moe foo.nim`) store that
  ## relative path verbatim, whereas WorkspaceEdit URIs always decode to an
  ## absolute path. Without normalization the two never match, so the open
  ## buffer is mistaken for an unopened file and its edits are written to disk
  ## instead of the in-memory buffer.
  normalizedPath(absolutePath(a)) == normalizedPath(absolutePath(b))

proc findBufferByPath(buffers: seq[TextBuffer], path: string): Option[int] =
  ## Find buffer index by file path
  for i, buffer in buffers:
    if buffer.filePath.isSome and samePath(buffer.filePath.get, path):
      return some(i)
  return none(int)

proc applyEditsToFile(path: string, edits: seq[TextEdit]): Result[void, string] =
  ## Apply edits to a file that is not currently open
  ## Loads the file, applies edits, and saves it back
  let tempBuffer = newTextBuffer()
  let loadResult = tempBuffer.loadFile(path)
  if loadResult.isErr:
    return err("Failed to load file: " & loadResult.error)

  let applyResult = applyTextEdits(tempBuffer, edits)
  if applyResult.isErr:
    return err(applyResult.error)

  let saveResult = tempBuffer.saveFile(path)
  if saveResult.isErr:
    return err("Failed to save file: " & saveResult.error)

  return ok()

proc collectWorkspaceEditPaths*(edit: WorkspaceEdit): seq[string] =
  ## All target file paths of a WorkspaceEdit, in application order.
  ## Mirrors applyWorkspaceEdit's precedence: documentChanges over changes.
  if edit.documentChanges.isSome:
    for docEdit in edit.documentChanges.get:
      result.add(uriToPath(docEdit.textDocument.uri))
  elif edit.changes.isSome:
    for uri, _ in edit.changes.get:
      result.add(uriToPath(uri))

proc hasStaleTargetBuffer*(
    buffers: seq[TextBuffer], edit: WorkspaceEdit, baseline: Table[BufferId, int]
): bool =
  ## True if any open buffer targeted by `edit` no longer matches the
  ## contentVersion recorded for it in `baseline`. The server positioned its
  ## edit against that state, so applying it onto newer text would corrupt the
  ## buffer.
  ##
  ## A buffer with no `baseline` entry counts as stale: nothing pins it to the
  ## text the server saw, so it cannot be verified.
  ##
  ## Keyed by buffer id, not path: two buffers can hold the same file (one
  ## opened relative, one absolute), and a path-keyed baseline would let one
  ## buffer's contentVersion shadow the other's.
  for path in collectWorkspaceEditPaths(edit):
    let absPath = normalizedPath(absolutePath(path))
    for buf in buffers:
      if buf.filePath.isSome and
          normalizedPath(absolutePath(buf.filePath.get)) == absPath:
        if not baseline.hasKey(buf.id) or buf.contentVersion != baseline[buf.id]:
          return true

  return false

proc hasStaleServerEditTarget*(
    lsp: LspIntegration,
    buffers: seq[TextBuffer],
    edit: WorkspaceEdit,
    syncedVersions: Table[BufferId, int],
): bool =
  ## True if applying a server-initiated `edit` would corrupt an open buffer,
  ## i.e. the buffer no longer holds the text the server positioned it against.
  ##
  ## Which text that is depends on whether the server holds the document:
  ##
  ## * Held (live worker + a recorded sync baseline): it sees what we last
  ##   sent, so compare contentVersion against `syncedVersions`.
  ## * Not held (no worker for this file type, or didOpen never succeeded): it
  ##   read the file from disk, so `isModified` is the test. contentVersion is
  ##   actively wrong here — maybeUpdateLsp records a baseline even when the
  ##   notification is dropped for want of a worker, so the versions match
  ##   while the texts do not.
  for path in collectWorkspaceEditPaths(edit):
    let absPath = normalizedPath(absolutePath(path))
    for buf in buffers:
      if buf.filePath.isSome and
          normalizedPath(absolutePath(buf.filePath.get)) == absPath:
        let serverHolds =
          syncedVersions.hasKey(buf.id) and
          lsp.service.hasLiveWorkerForPath(canonicalPath(buf.filePath.get))

        if serverHolds:
          if buf.contentVersion != syncedVersions[buf.id]:
            return true
        elif buf.isModified:
          return true

  return false

proc applyWorkspaceEdit*(
    buffers: var seq[TextBuffer],
    edit: WorkspaceEdit,
    transactionName: string = "Rename",
): Result[WorkspaceEditResult, string] =
  ## Apply a WorkspaceEdit to multiple buffers
  ## Returns which buffers/files were modified
  ## For open buffers: uses transactions for undo support
  ## For unopened files: loads, modifies, and saves directly
  ##
  ## Note: Per LSP spec, documentChanges takes precedence over changes.
  ## If both are present, only documentChanges is used.
  ##
  ## File operations (create/rename/delete) are not supported. Applying only
  ## the text edits of such a WorkspaceEdit would leave the workspace in a
  ## broken half-applied state, so the whole edit is refused instead.
  if edit.resourceOperations.len > 0:
    return err(
      "WorkspaceEdit contains unsupported file operations (" &
        edit.resourceOperations.deduplicate().join(", ") & "); no edits applied"
    )
  var modifiedCount = 0
  var openBuffersToModify: seq[tuple[bufferIdx: int, edits: seq[TextEdit]]] = @[]
  var unopenedFilesToModify: seq[tuple[path: string, edits: seq[TextEdit]]] = @[]

  # Per LSP specification, documentChanges takes precedence over changes
  if edit.documentChanges.isSome:
    # Handle documentChanges field (seq[TextDocumentEdit])
    for docEdit in edit.documentChanges.get:
      let path = uriToPath(docEdit.textDocument.uri)
      let bufferIdxOpt = findBufferByPath(buffers, path)
      if bufferIdxOpt.isSome:
        openBuffersToModify.add((bufferIdxOpt.get, docEdit.edits))
      else:
        unopenedFilesToModify.add((path, docEdit.edits))
  elif edit.changes.isSome:
    # Handle changes field (uri -> seq[TextEdit]) only if documentChanges is absent
    for uri, edits in edit.changes.get:
      let path = uriToPath(uri)
      let bufferIdxOpt = findBufferByPath(buffers, path)
      if bufferIdxOpt.isSome:
        openBuffersToModify.add((bufferIdxOpt.get, edits))
      else:
        unopenedFilesToModify.add((path, edits))

  # Track successfully modified files for error reporting
  var modifiedBufferPaths: seq[string] = @[]
  var modifiedBufferIndexes: seq[int] = @[]
  var modifiedFilePaths: seq[string] = @[]

  # Apply edits to open buffers with transactions for undo support
  for (bufferIdx, edits) in openBuffersToModify:
    let buffer = buffers[bufferIdx]

    let txr = withTransaction(buffer, transactionName):
      let applyResult = applyTextEdits(buffer, edits)
      if applyResult.isErr:
        if modifiedBufferPaths.len > 0:
          return err(
            "Failed to apply edits: " & applyResult.error & " (Warning: " &
              $modifiedBufferPaths.len & " buffer(s) already modified: " &
              modifiedBufferPaths.join(", ") & ")"
          )
        return err("Failed to apply edits: " & applyResult.error)
    if txr.isErr:
      if modifiedBufferPaths.len > 0:
        return err(
          "Transaction failed: " & txr.error & " (Warning: " & $modifiedBufferPaths.len &
            " buffer(s) already modified: " & modifiedBufferPaths.join(", ") & ")"
        )
      return err("Transaction failed: " & txr.error)

    modifiedCount += 1
    modifiedBufferIndexes.add(bufferIdx)
    if buffer.filePath.isSome:
      modifiedBufferPaths.add(buffer.filePath.get)

  # Apply edits to unopened files (load, modify, save)
  for (path, edits) in unopenedFilesToModify:
    let applyResult = applyEditsToFile(path, edits)
    if applyResult.isErr:
      let alreadyModified = modifiedBufferPaths.len + modifiedFilePaths.len
      if alreadyModified > 0:
        var modifiedList = modifiedBufferPaths & modifiedFilePaths
        return err(
          "Failed to modify " & path & ": " & applyResult.error & " (Warning: " &
            $alreadyModified & " file(s) already modified: " & modifiedList.join(", ") &
            ")"
        )
      return err("Failed to modify " & path & ": " & applyResult.error)
    modifiedCount += 1
    modifiedFilePaths.add(path)

  return ok(
    WorkspaceEditResult(
      modifiedCount: modifiedCount,
      modifiedBufferIndexes: modifiedBufferIndexes,
      modifiedFilePaths: modifiedFilePaths,
    )
  )

# Diagnostic helpers
proc applyDiagnosticsToBuffer*(buffer: TextBuffer, diagnostics: seq[Diagnostic]) =
  ## Apply LSP diagnostics to buffer's line markers
  ## Clears existing syntax markers and sets new ones

  # Clear existing syntax-related markers
  for i in 0 ..< buffer.lineMarkers.len:
    let marker = buffer.lineMarkers[i]
    if marker.isSome:
      let kind = marker.get
      if kind in {LineMarkerKind.SyntaxError, LineMarkerKind.SyntaxWarning}:
        buffer.lineMarkers[i] = none(LineMarkerKind)

  # Apply new diagnostics
  for diag in diagnostics:
    let line = diag.range.start.line
    if line >= 0 and line < buffer.len:
      let kind =
        if diag.severity.isSome:
          case diag.severity.get
          of dsError: LineMarkerKind.SyntaxError
          of dsWarning: LineMarkerKind.SyntaxWarning
          of dsInformation: LineMarkerKind.SyntaxWarning
          of dsHint: LineMarkerKind.SyntaxWarning
        else:
          LineMarkerKind.SyntaxError

      # Only set if no marker or lower priority marker exists
      let existing = buffer.getLineMarker(line)
      if existing.isNone or (
        existing.get != LineMarkerKind.SyntaxError and kind == LineMarkerKind.SyntaxError
      ):
        buffer.setLineMarker(line, kind)

  # Store full diagnostics for hover display
  buffer.diagnostics.setLen(0)
  for diag in diagnostics:
    let severity =
      if diag.severity.isSome:
        case diag.severity.get
        of dsError: bdsError
        of dsWarning: bdsWarning
        of dsInformation: bdsInformation
        of dsHint: bdsHint
      else:
        bdsError
    # LSP columns are UTF-16 code units; consumers (markers, highlights)
    # expect rune indexes. Convert using the referenced line's text; lines
    # outside the buffer fall back to "" so the columns clamp to 0.
    let startLineText =
      if diag.range.start.line >= 0 and diag.range.start.line < buffer.len:
        buffer.getLine(diag.range.start.line)
      else:
        ""
    let endLineText =
      if diag.range.`end`.line >= 0 and diag.range.`end`.line < buffer.len:
        buffer.getLine(diag.range.`end`.line)
      else:
        ""
    buffer.diagnostics.add(
      BufferDiagnostic(
        startLine: diag.range.start.line,
        startCol: utf16ToRuneIndex(startLineText, diag.range.start.character),
        endLine: diag.range.`end`.line,
        endCol: utf16ToRuneIndex(endLineText, diag.range.`end`.character),
        severity: severity,
        message: diag.message,
      )
    )

  # Trigger highlight regeneration so diagnostic underlines are applied
  buffer.highlightNeedsUpdate = true
  buffer.diagnosticsDirty = true

proc formatDiagnosticsForHover*(diagnostics: seq[BufferDiagnostic]): string =
  ## Format diagnostics for display in hover popup
  var lines: seq[string]
  for diag in diagnostics:
    let prefix =
      case diag.severity
      of bdsError: "[Error]"
      of bdsWarning: "[Warning]"
      of bdsInformation: "[Info]"
      of bdsHint: "[Hint]"
    lines.add(prefix & " " & diag.message)
  result = lines.join("\n")

# Signature help content helpers
proc getSignatureHelpText*(sigHelp: SignatureHelp): string =
  ## Extract formatted text from signature help response
  if sigHelp.signatures.len == 0:
    return ""

  # Get the active signature (default to first)
  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx < 0 or activeIdx >= sigHelp.signatures.len:
    return ""

  let sig = sigHelp.signatures[activeIdx]
  result = sig.label

  # Add documentation if available
  if sig.documentation.isSome:
    let doc = sig.documentation.get
    var docText = ""
    case doc.kind
    of JString:
      docText = doc.getStr
    of JObject:
      if doc.hasKey("value"):
        docText = doc["value"].getStr
    else:
      discard
    if docText.len > 0:
      result.add("\n\n" & docText)

proc getActiveParameterIndex*(sigHelp: SignatureHelp): int =
  ## Get the active parameter index from signature help
  # First check the top-level activeParameter
  if sigHelp.activeParameter.isSome:
    return sigHelp.activeParameter.get

  # Fall back to the active signature's activeParameter
  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx >= 0 and activeIdx < sigHelp.signatures.len:
    let sig = sigHelp.signatures[activeIdx]
    if sig.activeParameter.isSome:
      return sig.activeParameter.get

  return 0

proc findParameterLabel(
    sigLabel: string, paramIdx: int, params: seq[ParameterInformation]
): int =
  ## Locate the paramIdx-th parameter label inside sigLabel by scanning
  ## parameters in order with word-boundary awareness. Returns -1 if not found.
  template isIdentChar(c: char): bool =
    c == '_' or c.isAlphaNumeric

  proc findBoundary(hay, needle: string, start: int): int =
    var i = start
    while i <= hay.len - needle.len:
      let j = hay.find(needle, i)
      if j < 0:
        return -1
      let leftOk = j == 0 or not isIdentChar(hay[j - 1]) or not isIdentChar(needle[0])
      let rEnd = j + needle.len
      let rightOk =
        rEnd >= hay.len or not isIdentChar(hay[rEnd]) or not isIdentChar(needle[^1])
      if leftOk and rightOk:
        return j
      i = j + 1
    return -1

  var cursor = 0
  for i in 0 .. paramIdx:
    if params[i].labelOffsets.isSome:
      let (a, b) = params[i].labelOffsets.get
      if i == paramIdx:
        return a
      cursor = b
      continue
    let lbl = params[i].label
    if lbl.len == 0:
      return -1
    let pos = findBoundary(sigLabel, lbl, cursor)
    if pos < 0:
      if i == paramIdx:
        return sigLabel.find(lbl, cursor)
      return -1
    if i == paramIdx:
      return pos
    cursor = pos + lbl.len
  return -1

proc getParameterInfo*(sigHelp: SignatureHelp): tuple[label: string, start, stop: int] =
  ## Get the active parameter's highlighting range within the signature label
  ## Returns (full label, start position, end position) for highlighting
  result = ("", -1, -1)

  if sigHelp.signatures.len == 0:
    return

  let activeIdx = sigHelp.activeSignature.get(0)
  if activeIdx < 0 or activeIdx >= sigHelp.signatures.len:
    return

  let sig = sigHelp.signatures[activeIdx]
  result.label = sig.label

  if sig.parameters.isNone or sig.parameters.get.len == 0:
    return

  let paramIdx = getActiveParameterIndex(sigHelp)
  let params = sig.parameters.get

  if paramIdx < 0 or paramIdx >= params.len:
    return

  let param = params[paramIdx]
  if param.labelOffsets.isSome:
    let (a, b) = param.labelOffsets.get
    if a >= 0 and b <= sig.label.len and a <= b:
      result.start = a
      result.stop = b
      return
  if param.label.len > 0:
    let pos = findParameterLabel(sig.label, paramIdx, params)
    if pos >= 0:
      result.start = pos
      result.stop = pos + param.label.len

# Hover content helpers
proc getHoverText*(hover: Hover): string =
  ## Extract plain text from hover content
  let contents = hover.contents

  case contents.kind
  of JString:
    return contents.getStr
  of JObject:
    # MarkupContent
    if contents.hasKey("value"):
      return contents["value"].getStr
    elif contents.hasKey("contents"):
      return getHoverText(Hover(contents: contents["contents"]))
  of JArray:
    # Multiple MarkedString entries
    var lines: seq[string] = @[]
    for item in contents:
      case item.kind
      of JString:
        lines.add(item.getStr)
      of JObject:
        if item.hasKey("value"):
          lines.add(item["value"].getStr)
      else:
        discard
    return lines.join("\n")
  else:
    return ""

# Status helpers
proc isEnabled*(lsp: LspIntegration): bool =
  lsp.enabled

proc setEnabled*(lsp: LspIntegration, enabled: bool) =
  lsp.enabled = enabled
  lsp.service.enabled = enabled

proc getRunningServers*(lsp: LspIntegration): seq[string] =
  ## Get list of running language server IDs
  lsp.service.getRunningLanguages()

proc hasServerForPath*(lsp: LspIntegration, path: string): bool =
  ## Check if there's LSP support for a file path
  lsp.service.getLanguageIdFromPath(path).isSome

proc isServerRunningForPath*(lsp: LspIntegration, path: string): bool =
  ## Check if server is running for a file path
  let langIdOpt = lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return false
  lsp.service.getWorker(langIdOpt.get).isSome

# CodeLens support
defineSupportCheck(hasCodeLensSupport)
defineSupportCheck(hasCodeLensResolveSupport)
defineSupportCheck(hasDocumentSymbolSupport)
defineSupportCheck(hasCallHierarchySupport)

proc requestCodeLensResolve*(
    lsp: LspIntegration, buffer: TextBuffer, lens: CodeLens
): Future[Result[CodeLens, string]] {.async: (raises: [CancelledError]).} =
  ## Resolve a code lens to get its command
  ## Used when the initial codeLens response doesn't include the command
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestCodeLensResolve(pathRes.get, lens)

proc requestExecuteCommand*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    command: string,
    arguments: seq[JsonNode] = @[],
): Future[Result[JsonNode, string]] {.async: (raises: [CancelledError]).} =
  ## Execute a command on the LSP server (used for code lens commands)
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestExecuteCommand(pathRes.get, command, arguments)

defineSupportCheck(hasExecuteCommandSupport)

# Folding Range support
defineSupportCheck(hasFoldingRangeSupport)

proc applyLspFoldingRanges*(
    buffer: TextBuffer,
    ranges: seq[FoldingRange],
    clearExisting: bool = true,
    startCollapsed: bool = false,
): int =
  ## Apply LSP folding ranges to the buffer's FoldState.
  ## Returns the number of folds successfully added.
  ## LSP FoldingRange uses 0-based line numbers, which matches our FoldState.
  ##
  ## Nested ranges are preserved: every valid range is added as a fold tagged
  ## `fsLsp`. addFold rejects only crossing/duplicate folds, so a class, its
  ## methods, and their inner blocks all become folds.
  ##
  ## When `clearExisting` is true, only previously LSP-provided folds are
  ## removed; manual (`zf`) folds are kept so the two can coexist.
  ## When `startCollapsed` is true the folds are added collapsed (fold-all).
  if clearExisting:
    buffer.foldState.folds.keepItIf(it.source != fsLsp)

  var added = 0
  for range in ranges:
    # Skip invalid ranges.
    if range.endLine < range.startLine:
      continue
    # Skip degenerate single-line ranges: they hide no lines and would render
    # as a fold marker replacing the line's own content.
    if range.endLine == range.startLine:
      continue
    # Skip ranges outside the buffer bounds.
    if range.startLine < 0 or range.endLine >= buffer.len:
      continue
    # addFold tags the fold, keeps the list sorted, and rejects crossings.
    if buffer.foldState.addFold(
      range.startLine,
      range.endLine,
      collapsed = startCollapsed,
      collapsedText = range.collapsedText,
      source = fsLsp,
    ):
      inc added

  return added

# Cleanup
proc shutdown*(lsp: LspIntegration) =
  ## Shutdown all LSP servers
  lsp.service.stopAll()
  lsp.documents.clear()
  lsp.activeProgress.clear()
  lsp.serverStatus.clear()

proc requestFormatting*(
    lsp: LspIntegration, buffer: TextBuffer, tabSize: int = 2, insertSpaces: bool = true
): Future[Result[seq[TextEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Request formatting for a buffer
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestFormatting(pathRes.get, tabSize, insertSpaces)

proc requestRename*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int, newName: string
): Future[Result[Option[WorkspaceEdit], string]] {.async: (raises: [CancelledError]).} =
  ## Request rename at a position
  ## Note: column is expected to be a rune index, converted to UTF-16 for LSP
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestRename(
    pathRes.get, line, buffer.toUtf16Column(line, column), newName
  )

proc requestDefinition*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Request go to definition at a position
  ## Note: column is expected to be a rune index, converted to UTF-16 for LSP
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestDefinition(
    pathRes.get, line, buffer.toUtf16Column(line, column)
  )

proc requestReferences*(
    lsp: LspIntegration, buffer: TextBuffer, line, column: int
): Future[Result[seq[Location], string]] {.async: (raises: [CancelledError]).} =
  ## Request find references at a position
  ## Note: column is expected to be a rune index, converted to UTF-16 for LSP
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestReferences(
    pathRes.get, line, buffer.toUtf16Column(line, column)
  )

proc requestDocumentSymbols*(
    lsp: LspIntegration, buffer: TextBuffer
): Future[Result[DocumentSymbolResult, string]] {.async: (raises: [CancelledError]).} =
  ## Request document symbols
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestDocumentSymbols(pathRes.get)

proc requestFoldingRanges*(
    lsp: LspIntegration, buffer: TextBuffer
): Future[Result[seq[FoldingRange], string]] {.async: (raises: [CancelledError]).} =
  ## Request folding ranges for a buffer
  let pathRes = resolveLspPathForRequest(lsp, buffer)
  if pathRes.isErr:
    return err(pathRes.error)
  return await lsp.service.requestFoldingRange(pathRes.get)

proc refreshLspFolds*(
    lsp: LspIntegration,
    buffer: TextBuffer,
    clearExisting: bool = true,
    startCollapsed: bool = false,
): Future[Result[int, string]] {.async: (raises: [CancelledError]).} =
  ## Request folding ranges from LSP and apply them to buffer
  {.cast(raises: [CancelledError]).}:
    let rangesResult = await lsp.requestFoldingRanges(buffer)
    if rangesResult.isErr:
      return err(rangesResult.error)

    let count =
      buffer.applyLspFoldingRanges(rangesResult.get, clearExisting, startCollapsed)
    return ok(count)
