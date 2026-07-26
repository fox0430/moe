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
import ../syntax/tokenizer
import core, markers

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

proc continueInitialHighlight*(b: TextBuffer): bool =
  ## Continue progressive initial highlighting if incomplete.
  ## Returns true if work was done (caller should update the display).
  const ChunkSize = 1000

  if b.incrementalHighlight == nil or b.isUtilityBuffer:
    return false

  let parsedUpTo = b.incrementalHighlight.parsedUpTo
  if parsedUpTo >= b.len - 1:
    return false

  var startLine = parsedUpTo + 1

  # The stored boundary state may sit inside a construct that cannot enter a
  # fresh buffer (a YAML block scalar resumes by re-reading the header and
  # parent lines above the resume point), or the next line may itself resolve
  # against lines above (blank line, alone header). Rewind to a safe line and
  # re-parse the tail of the previous chunk together with the new one.
  while startLine > 0 and
      chunkHandoffUnsafe(
        b.language,
        b.incrementalHighlight.lineStates.states[startLine - 1].state,
        b.getLine(startLine),
      )
  :
    dec startLine

  # Grow the window past the old frontier proportionally to the rewound
  # prefix: inside a construct spanning many chunks every tick rewinds to its
  # header, so a fixed window advances the frontier only ChunkSize per tick
  # and re-parses the growing prefix every time — quadratic total. Doubling
  # makes the construct converge in O(log) ticks (linear total), the same
  # geometric idea as the `chunkLen *= 2` retry in
  # `updateHighlightIncremental`; like there, the last tick still pays one
  # near-construct-sized parse, which is what an edit inside the construct
  # costs anyway.
  let reparsedLines = parsedUpTo + 1 - startLine
  let endLine = min(startLine + max(ChunkSize, 2 * reparsedLines) - 1, b.len - 1)

  var lastState = TokenizerState()
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

  return true

proc continueUriScan*(b: TextBuffer): bool =
  ## Continue progressive URI scanning if incomplete.
  ## Works for all file types (plain text and syntax-highlighted).
  ## Returns true if work was done (caller should update the display).
  const ChunkSize = 1000

  if b.isUtilityBuffer or b.uriScanParsedUpTo >= b.len - 1:
    return false

  # For syntax-highlighted files, don't scan ahead of the syntax highlight
  # progress — addModifier requires color segments to exist for the target
  # lines.
  if b.incrementalHighlight != nil and
      b.uriScanParsedUpTo >= b.incrementalHighlight.parsedUpTo:
    return false

  let startLine = b.uriScanParsedUpTo + 1
  var endLine = min(startLine + ChunkSize - 1, b.len - 1)

  # Clamp to syntax highlight progress.
  if b.incrementalHighlight != nil:
    endLine = min(endLine, b.incrementalHighlight.parsedUpTo)

  let modified = scanAndApplyUriUnderlines(b, startLine, endLine)
  b.uriScanParsedUpTo = endLine

  return modified

proc updateHighlight*(b: TextBuffer) =
  ## Update syntax highlighting if needed
  ## This should be called before rendering
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

    if b.language != SourceLanguage.langNone:
      # Empty `segments` is a valid cached state (all-blank buffer). Gating on
      # it would force a full rebuild every edit.
      let cacheValid =
        b.incrementalHighlight != nil and
        b.incrementalHighlight.lineStates.states.len > 0

      if cacheValid:
        # Use incremental highlighting for better performance.
        # Only fetches lines for the chunks that need re-parsing.
        let buf = b
        updateHighlightIncremental(
          b.len,
          proc(i: int): string =
            buf.getLine(i),
          b.incrementalHighlight,
          b.lastChangedLines,
          b.reservedWords,
          b.language,
          b.maxHighlightLineLength,
        )

        b.highlight.colorSegments = b.incrementalHighlight.segments
        highlightRebuilt = false
      else:
        # Cache invalid or first time - parse once with incremental
        if b.len > 0:
          # Single backend traversal instead of b.len getLine calls, which
          # are O(n log n) total for tree-based backends.
          var lines = newSeqOfCap[string](b.len)
          for line in b.lines:
            lines.add(line)

          let (segments, lineStates) = initHighlightIncremental(
            lines,
            0,
            lines.high,
            TokenizerState(), # Default initial state
            b.reservedWords,
            b.language,
            b.maxHighlightLineLength,
          )

          b.highlight.colorSegments = segments
          b.incrementalHighlight = IncrementalHighlight(
            segments: segments,
            lineStates: LineStateCache(states: lineStates),
            parsedUpTo: b.len - 1,
          )
        else:
          b.highlight.colorSegments = @[]
          b.incrementalHighlight = nil
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

    # URI underlines around the change point; the rest is handled progressively
    # by continueUriScan. When the highlight was rebuilt from scratch the cache
    # is fresh and `uriScanParsedUpTo` is reset below, so the progressive scan
    # will re-cover this range — skip the cache mirror to avoid redundant work.
    let uriStart = max(0, b.lastChangedLines)
    let uriEnd = min(uriStart + 1000, b.len) - 1
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
    else:
      # Incremental update: unchanged segments kept their URI modifiers. Only
      # the re-parsed region (around lastChangedLines) lost them. Rewind just
      # past the change point so the progressive scan re-covers that region,
      # instead of re-scanning the entire file on every edit. The -3 margin
      # matches updateHighlightIncremental's reparseStart backward margin (-2)
      # plus one so lineIdx = uriScanParsedUpTo + 1 lands at reparseStart.
      let rewindTo = max(-1, b.lastChangedLines - 3)
      if b.uriScanParsedUpTo > rewindTo:
        b.uriScanParsedUpTo = rewindTo

    b.highlightNeedsUpdate = false

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
