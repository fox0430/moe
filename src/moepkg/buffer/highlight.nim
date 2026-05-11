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

  let startLine = parsedUpTo + 1
  let endLine = min(startLine + ChunkSize - 1, b.len - 1)
  let lastState = b.incrementalHighlight.lineStates.states[^1]

  var chunkLines = newSeq[string](endLine - startLine + 1)
  for i in startLine .. endLine:
    chunkLines[i - startLine] = b.getLine(i)

  let bufferStr = buildBufferStr(chunkLines, 0, chunkLines.high)
  let (newSegments, newLineStates) = initHighlightIncrementalFromStr(
    bufferStr, startLine, endLine, lastState, b.reservedWords, b.language
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

  # Collect URI ranges across the whole chunk, then apply them in one
  # batched pass over the segment seq. Calling addModifier per URI rebuilds
  # the whole colorSegments seq each time (O(N) memcpy), which dominates
  # frame time for large files with many segments (e.g. 40k-line JSON:
  # ~300k segments × ~140 URIs/chunk → ~400ms). The batched apply is
  # O(N + M) total.
  var ranges: seq[tuple[row, firstCol, lastCol: int]]
  for lineIdx in startLine .. endLine:
    let line = b.getLine(lineIdx)
    for m in findAllUris(line):
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
        )

        # Convert IncrementalHighlight segments to Highlight
        b.highlight = Highlight(colorSegments: b.incrementalHighlight.segments)
        highlightRebuilt = false
      else:
        # Cache invalid or first time - parse once with incremental
        if b.len > 0:
          var lines = newSeq[string](b.len)
          for i in 0 ..< b.len:
            lines[i] = b.getLine(i)

          let (segments, lineStates) = initHighlightIncremental(
            lines,
            0,
            lines.high,
            TokenizerState(), # Default initial state
            b.reservedWords,
            b.language,
          )

          b.highlight = Highlight(colorSegments: segments)
          b.incrementalHighlight = IncrementalHighlight(
            segments: segments,
            lineStates: LineStateCache(states: lineStates, version: b.changeSeq),
            parsedUpTo: b.len - 1,
          )
        else:
          b.highlight = Highlight(colorSegments: @[])
          b.incrementalHighlight = nil
    else:
      # Plain text - single default segment covering all lines
      if b.len > 0:
        b.highlight = Highlight(
          colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: b.len - 1,
              lastColumn: max(0, b.getLine(b.len - 1).len - 1),
              color: EditorColorPairIndex.default,
              style: defaultStyle,
            )
          ]
        )
      else:
        b.highlight = Highlight(colorSegments: @[])

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
      for m in findAllUris(line):
        inlineRanges.add((row: lineIdx, firstCol: m.start, lastCol: m.finish))
    if inlineRanges.len > 0:
      b.highlight.addUnderlineRanges(inlineRanges)

    # Persist URI modifiers into incrementalHighlight.segments. Without this,
    # the next incremental update's `b.highlight = Highlight(...)` assignment
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

proc toReservedWords*(words: seq[string]): seq[ReservedWord] =
  ## Convert a sequence of strings to ReservedWord objects
  ## Uses the default reservedWord color from the theme
  for word in words:
    result.add(ReservedWord(word: word, color: EditorColorPairIndex.reservedWord))
