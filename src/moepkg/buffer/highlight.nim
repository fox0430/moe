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

## Buffer-side syntax highlighting management:
## - Progressive (chunked) initial highlight
## - Progressive URI underline scan
## - Incremental re-highlight on edit
## - Reserved-word configuration (TODO/NOTE/FIXME etc.)

import std/tables

import ../[highlight, uri_utils]
import ../types/highlight_types
import ../syntax/tokenizer
when defined(moe.matter):
  import ../syntax/matter_backend
import core, markers

proc matches*(pr: PendingReparse, b: TextBuffer): bool =
  ## TextBuffer-scoped overload of `PendingReparse.matches`.
  pr.matches(b.lastChangedLines, b.len, b.contentVersion, b.reservedWords)

proc setHighlightBackend*(b: TextBuffer, backend: HighlightBackend) =
  ## Change the requested syntax engine and invalidate every syntax-derived
  ## cache. URI styling is rebuilt; semantic and diagnostic overlays retain
  ## their identity and content version because the buffer text has not changed.
  if b.highlightBackend != backend:
    b.highlightBackend = backend
    b.incrementalHighlight = nil
    b.uriScanParsedUpTo = -1
    b.highlightNeedsUpdate = true

proc rewindUriScan(b: TextBuffer, to: int) =
  ## Move the URI-scan frontier back to `to` (clamped to -1); no-op if it is
  ## already at or below `to`.
  let target = max(-1, to)
  if b.uriScanParsedUpTo > target:
    b.uriScanParsedUpTo = target

proc isCodeBlockLine*(b: TextBuffer, line: int): bool =
  ## True if `line` sits inside a Markdown fenced code block or is one of its
  ## ``` fence lines. Consults the incremental highlight's per-line tokenizer
  ## state: a line is a code block line when either the state entering it or
  ## the state exiting it has `markdown.inCodeBlock` set. The exiting state
  ## covers the opening fence; the entering state covers the closing fence
  ## and every interior line.
  if b.language != SourceLanguage.langMarkdown or b.incrementalHighlight == nil:
    return false
  let states = b.incrementalHighlight.lineStates.states
  if line < 0 or line >= states.len:
    return false
  when defined(moe.matter):
    if states[line].backend == hbMatter:
      let enterInBlock = line >= 1 and isMatterCodeBlock(states[line - 1].matterState)
      return enterInBlock or isMatterCodeBlock(states[line].matterState)
  let enterInBlock = line >= 1 and states[line - 1].lang.markdown.inCodeBlock
  let exitInBlock = states[line].lang.markdown.inCodeBlock
  enterInBlock or exitInBlock

proc scanAndApplyUriUnderlines*(
    b: TextBuffer, startLine, endLine: int, applyToCache = true
): bool =
  ## Batch-apply URI Underline in `[startLine, endLine]` to `b.highlight` and
  ## (when `applyToCache`) to `b.incrementalHighlight.segments`. Applying to
  ## the cache directly, not via `b.highlight`, keeps transient diagnostic
  ## styling out of it. Returns true if any URI was applied.
  var ranges: seq[tuple[row, firstCol, lastCol: int]]
  for lineIdx in startLine .. endLine:
    let line = b.getLine(lineIdx)
    for m in findAllUris(line, b.maxHighlightLineLength):
      ranges.add((row: lineIdx, firstCol: m.start, lastCol: m.finish))
  if ranges.len == 0:
    return false
  if applyToCache and b.incrementalHighlight != nil:
    b.incrementalHighlight.segments.addUnderlineRanges(ranges)
  b.highlight.addUnderlineRanges(ranges)
  return true

proc continueIncrementalHighlight*(
    b: TextBuffer, budgetLines: int, parsedLines: var int
): bool =
  ## Resume a budgeted re-parse started by `updateHighlight`; returns true
  ## while work remains. `parsedLines` receives the actual lines consumed.
  parsedLines = 0
  let incr = b.incrementalHighlight
  if b.isUtilityBuffer or incr == nil or incr.pendingReparse == nil:
    return false
  if b.highlight == nil:
    b.highlight = Highlight(colorSegments: @[])
  let pr = incr.pendingReparse
  # A restart below rebuilds the segments without URI underlines, so rewind
  # the URI scan as `updateHighlight` does.
  let restarting = not pr.matches(b)
  let buf = b
  let ongoing = updateHighlightIncremental(
    b.len,
    proc(i: int): string =
      buf.getLine(i),
    b.incrementalHighlight,
    b.lastChangedLines,
    b.reservedWords,
    b.language,
    b.maxHighlightLineLength,
    budgetLines,
    b.contentVersion,
    parsedLines,
  )
  b.highlight.colorSegments = b.incrementalHighlight.segments
  if restarting:
    let newPr = b.incrementalHighlight.pendingReparse
    if newPr != nil:
      b.rewindUriScan(newPr.reparseStart - 1)
    else:
      # Restart completed within this call: rewind to the actual reparseStart,
      # clamped to the old flight's start.
      b.rewindUriScan(
        min(b.incrementalHighlight.lastReparseStart - 1, pr.reparseStart - 1)
      )
  ongoing

proc continueInitialHighlight*(
    b: TextBuffer, budgetLines: int, parsedLines: var int
): bool =
  ## Continue progressive initial highlighting if incomplete; returns true if
  ## work was done. `parsedLines` receives the lines parsed; `budgetLines`
  ## bounds the chunk (0 = default size).
  ##
  ## Advances a live re-parse flight instead of the initial load (a fresh
  ## chunk would drop the flight's accumulation).
  const ChunkSize = 1000

  parsedLines = 0
  if b.incrementalHighlight == nil or b.isUtilityBuffer:
    return false
  if b.incrementalHighlight.pendingReparse != nil:
    return b.continueIncrementalHighlight(budgetLines, parsedLines)

  let parsedUpTo = b.incrementalHighlight.parsedUpTo
  if parsedUpTo >= b.len - 1:
    return false

  var startLine = parsedUpTo + 1

  # The boundary state may not resume in a fresh chunk (YAML block scalars,
  # blank / alone-header lines), so rewind to a safe line and re-parse the
  # previous chunk's tail together with the new one.
  while startLine > 0 and
      b.incrementalHighlight.lineStates.states[startLine - 1].backend == hbBuiltin and
      chunkHandoffUnsafe(
        b.language,
        b.incrementalHighlight.lineStates.states[startLine - 1].state,
        b.getLine(startLine),
      )
  :
    dec startLine

  # Double the window past the rewound prefix; a fixed window would re-parse
  # the growing prefix every tick (quadratic total). Under a budget, cap the
  # growth at 4x it, floored at the rewind depth + one budget.
  let reparsedLines = parsedUpTo + 1 - startLine
  let endLine =
    if budgetLines > 0:
      let target = max(budgetLines, 2 * reparsedLines)
      let cap = max(budgetLines * 4, reparsedLines + budgetLines)
      min(startLine + min(target, cap) - 1, b.len - 1)
    else:
      min(startLine + max(ChunkSize, 2 * reparsedLines) - 1, b.len - 1)

  var lastState = newTokenizerState(b.highlightBackend, b.language)
  if startLine > 0:
    lastState = b.incrementalHighlight.lineStates.states[startLine - 1]

  if b.incrementalHighlight.lineStates.states.len > startLine:
    # Drop cached results from `startLine` on. Covers the rewound lines
    # (re-parsed below) and rows beyond the frontier: an edit during the
    # progressive load runs `updateHighlightIncremental`, which fills the
    # caches to EOF without advancing `parsedUpTo`, and the unconditional
    # appends below would then duplicate those rows — leaving `states` longer
    # than the buffer and `segments` unsorted, breaking the sorted-input
    # contracts of `segmentCutIndex` and the splice's binary search.
    b.incrementalHighlight.lineStates.states.setLen(startLine)
    b.incrementalHighlight.segments.setLen(
      b.incrementalHighlight.segments.segmentCutIndex(startLine)
    )
    b.highlight.colorSegments.setLen(
      b.highlight.colorSegments.segmentCutIndex(startLine)
    )
    # URI underlines on the dropped rows went with their segments; let the
    # progressive URI scan re-cover them.
    if b.uriScanParsedUpTo >= startLine:
      b.uriScanParsedUpTo = startLine - 1

  var chunkLines = newSeq[string](endLine - startLine + 1)
  for i in startLine .. endLine:
    chunkLines[i - startLine] = b.getLine(i)

  let (bufferStr, tails) =
    buildBufferStrCapped(chunkLines, 0, chunkLines.high, b.maxHighlightLineLength)
  let (newSegments, newLineStates) = initHighlightIncrementalFromStr(
    bufferStr, startLine, endLine, lastState, b.reservedWords, b.language, tails
  )

  b.incrementalHighlight.segments.add(newSegments)
  b.incrementalHighlight.lineStates.states.add(newLineStates)
  b.incrementalHighlight.parsedUpTo = endLine

  # Append new segments to the existing highlight (preserving earlier URI
  # underlines) rather than rebuilding from incrementalHighlight.segments.
  b.highlight.colorSegments.add(newSegments)

  parsedLines = endLine - startLine + 1

  return true

proc continueInitialHighlight*(b: TextBuffer, budgetLines: int = 0): bool =
  ## Overload without the parsed-line reporting.
  var parsedLines: int
  result = continueInitialHighlight(b, budgetLines, parsedLines)

proc continueUriScan*(b: TextBuffer, budgetLines: int, scannedLines: var int): bool =
  ## Continue progressive URI scanning if incomplete (all file types).
  ## Returns true if any URI underlines were applied (the caller should
  ## update the display then). `scannedLines` receives the number of lines
  ## scanned — the frame driver charges its shared budget by this count.
  ## `budgetLines` bounds the chunk (0 = the default chunk size).
  const ChunkSize = 1000

  scannedLines = 0
  # Skip raw buffers: URI scan would parse binary.
  if b.isUtilityBuffer or not b.allowsTextTransforms or b.uriScanParsedUpTo >= b.len - 1:
    return false

  let startLine = b.uriScanParsedUpTo + 1
  let chunkEnd =
    if budgetLines > 0:
      startLine + budgetLines - 1
    else:
      startLine + ChunkSize - 1
  var endLine = min(chunkEnd, b.len - 1)

  # For syntax-highlighted files, don't scan past the highlight progress
  # (addModifier needs segments on the target lines). While a re-parse is in
  # flight, the frontier is `reparseEnd`; but if the flight started below the
  # load frontier, the band between was never parsed, so clamp to
  # `parsedUpTo` instead.
  if b.incrementalHighlight != nil:
    let pr = b.incrementalHighlight.pendingReparse
    let frontier =
      if pr != nil:
        if pr.reparseStart <= b.incrementalHighlight.parsedUpTo + 1:
          pr.reparseEnd
        else:
          b.incrementalHighlight.parsedUpTo
      else:
        b.incrementalHighlight.parsedUpTo
    if b.uriScanParsedUpTo >= frontier:
      return false
    endLine = min(endLine, frontier)

  let modified = scanAndApplyUriUnderlines(b, startLine, endLine)
  b.uriScanParsedUpTo = endLine
  scannedLines = endLine - startLine + 1

  return modified

proc continueUriScan*(b: TextBuffer, budgetLines: int = 0): bool =
  ## Overload without the scanned-line reporting.
  var scannedLines: int
  result = continueUriScan(b, budgetLines, scannedLines)

proc updateHighlight*(b: TextBuffer, reparseBudget: int, parsedLines: var int): bool =
  ## Update syntax highlighting if needed; call before rendering.
  ##
  ## `reparseBudget` bounds the re-parse per call (0 = unlimited). Returns
  ## true while a budgeted re-parse is in progress: resume it on later frames
  ## via `continueIncrementalHighlight`. `parsedLines` receives the actual
  ## lines consumed.
  parsedLines = 0
  if b.highlightNeedsUpdate and not b.isUtilityBuffer:
    # Keep the Highlight ref alive across reparse so the LSP semantic overlay
    # (living in the same object) does not need saving. Only colorSegments
    # is rewritten below.
    if b.highlight == nil:
      b.highlight = Highlight(colorSegments: @[])

    # Fallback: drop a stale overlay when the forward-edit path (`pushUndoChange`
    # -> `emitRowColRemapEvents`) did not shift the overlay to the new
    # `contentVersion`. Catches undo/redo, NoUndo previews, reload, and the
    # ckSnapshot bail — the design doc §6 stale-but-close preservation lives
    # in `emitRowColRemapEvents`, not here.
    if b.highlight.semantic.len > 0 and
        b.highlight.semanticContentVersion != b.contentVersion:
      b.highlight.semantic.clear()
      b.highlight.semanticContentVersion = -1

    # Track whether the highlight was rebuilt from scratch. When true, all
    # previously-applied URI modifiers outside the inline scan range are lost
    # and the progressive scan must restart from the beginning. When false
    # (incremental update), unchanged segments keep their URI modifiers.
    var highlightRebuilt = true
    var reparseOngoing = false
    # The pre-call flight; a restart inside clears `pendingReparse`, so the
    # rewind below needs its start.
    var prevPr: PendingReparse

    if b.language != SourceLanguage.langNone:
      # An empty state cache is a valid transient flight state (a top
      # line-count change trims it), so gate on the live flight too, or the
      # next edit would fall back to a one-call full rebuild.
      let cacheValid =
        b.incrementalHighlight != nil and (
          b.incrementalHighlight.lineStates.states.len > 0 or
          b.incrementalHighlight.pendingReparse != nil
        )

      if cacheValid:
        # Use incremental highlighting for better performance.
        # Only fetches lines for the chunks that need re-parsing.
        let buf = b
        prevPr = b.incrementalHighlight.pendingReparse
        reparseOngoing = updateHighlightIncremental(
          b.len,
          proc(i: int): string =
            buf.getLine(i),
          b.incrementalHighlight,
          b.lastChangedLines,
          b.reservedWords,
          b.language,
          b.maxHighlightLineLength,
          reparseBudget,
          b.contentVersion,
          parsedLines,
        )

        b.highlight.colorSegments = b.incrementalHighlight.segments
        highlightRebuilt = false
      else:
        # Cache invalid or first time: with a budget, let
        # `continueInitialHighlight` chunk the parse; unlimited stays
        # synchronous for callers needing the whole file in one call.
        if b.len == 0:
          b.highlight.colorSegments = @[]
          b.incrementalHighlight = nil
        elif reparseBudget > 0:
          b.highlight.colorSegments = @[]
          b.incrementalHighlight = IncrementalHighlight(
            backend: effectiveHighlightBackend(b.highlightBackend, b.language),
            segments: @[],
            lineStates: LineStateCache(states: @[]),
            parsedUpTo: -1,
          )
          discard continueInitialHighlight(b, reparseBudget, parsedLines)
        else:
          # Single backend traversal instead of b.len getLine calls, which
          # are O(n log n) total for tree-based backends.
          var lines = newSeqOfCap[string](b.len)
          for line in b.lines:
            lines.add(line)

          let (segments, lineStates) = initHighlightIncremental(
            lines,
            0,
            lines.high,
            newTokenizerState(b.highlightBackend, b.language),
            b.reservedWords,
            b.language,
            b.maxHighlightLineLength,
          )

          b.highlight.colorSegments = segments
          b.incrementalHighlight = IncrementalHighlight(
            backend: effectiveHighlightBackend(b.highlightBackend, b.language),
            segments: segments,
            lineStates: LineStateCache(states: lineStates),
            parsedUpTo: b.len - 1,
          )
          # Charge the shared frame budget by the actual rebuild work.
          parsedLines = b.len
    else:
      # Plain text - single default segment covering all lines
      if b.len > 0:
        b.highlight.colorSegments = @[
          ColorSegment(
            firstRow: 0,
            firstColumn: 0,
            lastRow: b.len - 1,
            lastColumn: max(0, b.getLine(b.len - 1).len - 1),
            color: EditorColorPairIndex.default,
            style: defaultStyle,
          )
        ]
      else:
        b.highlight.colorSegments = @[]

    # URI underlines around the change point; the rest is handled by
    # continueUriScan. During a flight, clamp to `reparseEnd`: rows past it
    # have no segments, so addUnderlineRanges would silently drop them.
    # Skip for raw buffers.
    if b.allowsTextTransforms:
      let uriStart = max(0, b.lastChangedLines)
      var uriEnd = min(uriStart + 1000, b.len) - 1
      if reparseOngoing:
        let pr = b.incrementalHighlight.pendingReparse
        if pr != nil and uriEnd > pr.reparseEnd:
          uriEnd = pr.reparseEnd
      if uriEnd >= uriStart:
        discard scanAndApplyUriUnderlines(
          b, uriStart, uriEnd, applyToCache = not highlightRebuilt
        )

    # Diagnostics are only mutated by the LSP publish path / reset/clear paths;
    # a pure edit keeps them untouched, so the overlay rebuilt on the previous
    # tick is still current. Skip the O(D + R) clear+rebuild in that case.
    if b.diagnosticsDirty:
      b.highlight.diagnosticOverlay.clear()
      if b.diagnostics.len > 0:
        applyDiagnosticHighlights(b.highlight, b.diagnostics)
      b.diagnosticsDirty = false

    if highlightRebuilt:
      # Highlight was rebuilt from scratch, so all URI modifiers outside
      # uriStart..uriEnd were lost. Reset progressive scan to re-cover the
      # full file from the beginning.
      b.uriScanParsedUpTo = -1
    elif reparseOngoing:
      # The re-parse trimmed the cached segments (URI underlines included)
      # from `reparseStart` on; rewind the scan to re-cover them as chunks
      # are appended. Only when THIS call trimmed — a plain resume touches
      # no covered rows, so rewinding would re-crawl them on every trigger.
      let trimmed = prevPr == nil or not prevPr.matches(b)
      if trimmed:
        b.rewindUriScan(b.incrementalHighlight.pendingReparse.reparseStart - 1)
    else:
      # Rewind to just before the actual reparseStart (clamped to the old
      # flight's start); a plain resume-completion trimmed nothing, so skip
      # the rewind — mirroring the branch above.
      if prevPr == nil or not prevPr.matches(b):
        var rewindTo = b.incrementalHighlight.lastReparseStart - 1
        if prevPr != nil:
          rewindTo = min(rewindTo, prevPr.reparseStart - 1)
        b.rewindUriScan(rewindTo)

    b.highlightNeedsUpdate = false
    return reparseOngoing

  false

proc updateHighlight*(b: TextBuffer, reparseBudget: int = 0): bool {.discardable.} =
  ## Overload without the parsed-line reporting.
  var parsedLines: int
  result = updateHighlight(b, reparseBudget, parsedLines)

proc continueIncrementalHighlight*(b: TextBuffer, budgetLines: int = 0): bool =
  ## Overload without the parsed-line reporting.
  var parsedLines: int
  result = continueIncrementalHighlight(b, budgetLines, parsedLines)

proc setReservedWords*(b: TextBuffer, words: seq[ReservedWord]) =
  ## Set reserved words for syntax highlighting (e.g., TODO, NOTE, FIXME)
  ## This will trigger a re-highlight on the next update
  b.reservedWords = words
  b.highlightNeedsUpdate = true

proc setMaxHighlightLineLength*(b: TextBuffer, maxLineLen: int) =
  ## Set the per-line tokenization cap in runes (synmaxcol). 0 = unlimited.
  if b.maxHighlightLineLength != maxLineLen:
    b.maxHighlightLineLength = maxLineLen
    # Drop the incremental cache and force a full rebuild: an incremental update
    # reparses only from the last edit and stops at state convergence, so a
    # far-away long line would keep its stale old-cap segments.
    b.incrementalHighlight = nil
    b.highlightNeedsUpdate = true

proc toReservedWords*(words: seq[string]): seq[ReservedWord] =
  ## Convert a sequence of strings to ReservedWord objects
  ## Uses the default reservedWord color from the theme
  for word in words:
    result.add(ReservedWord(word: word, color: EditorColorPairIndex.reservedWord))
