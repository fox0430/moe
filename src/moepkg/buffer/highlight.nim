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
import ./core
import ./markers

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

  if b.diagnostics.len > 0:
    # Diagnostic styling lives only in the display highlight (applied by
    # `updateHighlight` behind `highlightNeedsUpdate`): the truncation above
    # drops it for the dropped rows and the plain re-append doesn't restore
    # it — unlike URI underlines (re-covered via `uriScanParsedUpTo`) and
    # semantic tokens (invalidated by the caller). Re-apply directly so
    # undercurls survive the progressive load; this also covers diagnostics
    # on the freshly parsed rows, which had no segments to style until now.
    # Only diagnostics touching [startLine, endLine] need it: rows below
    # startLine kept their styling (the truncation only drops rows >=
    # startLine), rows past endLine get theirs when a later tick parses them,
    # and re-applying an already-styled diagnostic rebuilds the whole segment
    # seq (O(segments) per diagnostic, every tick of a large-file load).
    var affected: seq[BufferDiagnostic]
    for d in b.diagnostics:
      if d.endLine >= startLine and d.startLine <= endLine:
        affected.add(d)
    if affected.len > 0:
      applyDiagnosticHighlights(b.highlight, affected)

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

  # Collect URI ranges across the whole chunk, then apply them in one
  # batched pass over the segment seq. Calling addModifier per URI rebuilds
  # the whole colorSegments seq each time (O(N) memcpy), which dominates
  # frame time for large files with many segments (e.g. 40k-line JSON:
  # ~300k segments × ~140 URIs/chunk → ~400ms). The batched apply is
  # O(N + M) total.
  var ranges: seq[tuple[row, firstCol, lastCol: int]]
  for lineIdx in startLine .. endLine:
    let line = b.getLine(lineIdx)
    for m in findAllUris(line, b.maxHighlightLineLength):
      ranges.add((row: lineIdx, firstCol: m.start, lastCol: m.finish))

  let modified = ranges.len > 0
  if modified:
    b.highlight.addUnderlineRanges(ranges)

  b.uriScanParsedUpTo = endLine

  # Persist URI modifiers into incrementalHighlight.segments so they survive
  # the next updateHighlight call (which assigns b.highlight from that seq).
  if modified and b.incrementalHighlight != nil:
    b.incrementalHighlight.segments = b.highlight.colorSegments

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

    # Drop a stale overlay: an edit advances contentVersion, so row/col
    # coords the server computed against the old snapshot would paint on
    # shifted positions until the next response.
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
      # Check if incremental cache is valid
      let cacheValid =
        b.incrementalHighlight != nil and
        b.incrementalHighlight.lineStates.states.len > 0 and
        b.incrementalHighlight.segments.len > 0

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
          b.changeSeq,
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
            lineStates: LineStateCache(states: lineStates, version: b.changeSeq),
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

    # Apply underline to URIs/URLs in a limited range around the change point.
    # Scanning all lines from the change point to EOF is O(n) and blocks
    # rendering for large files. Limit to a reasonable chunk; the rest will be
    # handled progressively by continueUriScan.
    # Applied BEFORE diagnostics so the URI modifiers can be synced into
    # incrementalHighlight.segments without mixing in transient diagnostic mods.
    # Batched to avoid per-range O(N) segment-seq rebuilds.
    let uriStart = max(0, b.lastChangedLines)
    let uriEnd = min(uriStart + 1000, b.len) - 1
    var inlineRanges: seq[tuple[row, firstCol, lastCol: int]]
    for lineIdx in uriStart .. uriEnd:
      let line = b.getLine(lineIdx)
      for m in findAllUris(line, b.maxHighlightLineLength):
        inlineRanges.add((row: lineIdx, firstCol: m.start, lastCol: m.finish))
    if inlineRanges.len > 0:
      b.highlight.addUnderlineRanges(inlineRanges)

    # Persist URI modifiers into incrementalHighlight.segments. Without this,
    # the next incremental update's `b.highlight.colorSegments = ...` reassign
    # would drop URI modifiers in the unchanged region, forcing a full rescan.
    if not highlightRebuilt and b.incrementalHighlight != nil:
      b.incrementalHighlight.segments = b.highlight.colorSegments

    if b.diagnostics.len > 0:
      applyDiagnosticHighlights(b.highlight, b.diagnostics)

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
