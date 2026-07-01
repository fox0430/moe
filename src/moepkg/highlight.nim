#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import
  std/[sequtils, os, strutils, strformat, unicode, algorithm, options, tables, json]

import pkg/celina

import color, unicode_utils
import syntax/tokenizer
import lsp/protocol/types

export SourceLanguage, EditorColorPairIndex

type
  # Runes type alias for sequence of Unicode characters
  Runes* = seq[Rune]

  ColorSegment* = object
    firstRow*, firstColumn*, lastRow*, lastColumn*: int
    color*: EditorColorPairIndex
    style*: Style # Changed from attribute to style

  SemanticOverlayToken* = object
    ## LSP semantic token resolved to a colour, sorted by `firstColumn` per row.
    firstColumn*: int
    length*: int
    color*: EditorColorPairIndex
    style*: Style

  SemanticOverlayLine* = object
    ## Overlay tokens for one row. Invariant: `tokens` is sorted by
    ## `firstColumn` ascending, and every pair of tokens is disjoint
    ## (`t[i].firstColumn + t[i].length <= t[i+1].firstColumn`).
    ## `findOverlayToken`'s binary search relies on both properties.
    ## Maintained by `addOverlayToken`, which truncates or drops any prior
    ## token whose range would overlap a newly-appended one.
    tokens*: seq[SemanticOverlayToken]

  Highlight* = ref object
    colorSegments*: seq[ColorSegment]
    semantic*: Table[int, SemanticOverlayLine]
      ## Residual LSP semantic overlay, composed with `colorSegments` at render.
    semanticContentVersion*: int = -1
      ## `buffer.contentVersion` of the last successful `applySemanticTokens`.
      ## `-1` is the sentinel for "no overlay applied yet"; a legitimate
      ## `contentVersion=0` (fresh newTextBuffer) would otherwise alias with
      ## the post-drop reset state and mask a real version mismatch. The
      ## Nim 2 field default keeps every `Highlight(colorSegments: ...)`
      ## construction site correct without repetition.
    semanticLegend*: SemanticTokensLegend
      ## Legend under which the current overlay entries were decoded. When a
      ## later apply arrives with a different legend (dynamic re-registration),
      ## the overlay is wiped BEFORE the new tokens are added so range-scoped
      ## applies do not leave stale-legend colours on the rows they don't touch.

  ReservedWord* = object
    word*: string
    color*: EditorColorPairIndex

  # Incremental highlighting support
  TokenizerState* = object
    ## Tokenizer state at the start of a line
    ## Used for incremental re-parsing
    state*: TokenClass
    templateLiteralDepth*: int
    braceDepthStack*: seq[int]
    commentDepth*: int
    inJsxMode*: bool
    jsxTagDepth*: int
    inComment*: bool
    inScript*: bool
    inStyle*: bool
    astroInFrontmatter*: bool
    astroFirstLine*: bool
    yamlIsKey*: bool
    mdInCodeBlock*: bool
    # NOTE: `mdInIndentedCode` is intentionally NOT tracked here. It is a
    # per-line transient flag (set while consuming a line's leading indent and
    # cleared at the line's content), so it is always false at a line boundary.
    # Persisting it would let a cached boundary state restore it as true and
    # produce an empty token on reparse; the normal path re-detects each line's
    # indentation instead.
    mdInMathMode*: bool
    mdInDisplayMath*: bool
    mdInFrontmatter*: bool
    mdFirstLine*: bool
    latexInMathMode*: bool
    latexInDisplayMath*: bool
    rustRawStringHashCount*: int
    rustInByteString*: bool
    rustInRawString*: bool
    rustAttrBracketDepth*: int

  LineStateCache* = object ## Cache of tokenizer states for each line
    states*: seq[TokenizerState]
    version*: int # Synchronized with buffer changeSeq for invalidation

  IncrementalHighlight* = ref object ## Incremental highlighting information
    segments*: seq[ColorSegment]
    lineStates*: LineStateCache
    parsedUpTo*: int ## Last line parsed during initial load. -1 = not started.

  Position = tuple[row, column: int]
    ## Module-private alias used by segment-splitting helpers (overwrite,
    ## addModifier, addUnderlineRanges). Disambiguates from celina's geometry
    ## Position and lsp/protocol/types Position.

  SemanticTypeColorTable* = ref object
    ## Precomputed `(tokenType, modifiers) -> (colour, style)` cache for one
    ## legend. The zero-modifier row is a dense seq (fast path — the common
    ## case); modifier-bearing tokens fall through to a lazy Table keyed by
    ## `(tokenType shl 32) or modifiers`, resolved on first use via the
    ## stored legend. Cached per language server on `LspIntegration`.
    baseColors*: seq[EditorColorPairIndex]
    legend*: SemanticTokensLegend
    resolved*:
      Table[uint64, tuple[color: EditorColorPairIndex, style: set[StyleModifier]]]

  SemanticApplyOutcome* = enum
    saoDone
    saoRejectedCap # response exceeded `MaxSemanticTokens`
    saoRejectedMalformed # missing/invalid `data` array, length not %5, etc.
    saoRejectedNoLegend # legend transiently missing; prior overlay preserved

const
  DefaultMaxHighlightLineLength* = 3000
    ## Default per-line tokenization cap (in runes). A single huge line (e.g.
    ## minified JS collapsed onto one line) would otherwise stall a frame, since
    ## the chunk drivers budget by line count, not bytes within a line. Beyond
    ## this column the line is rendered as plain text. `<= 0` disables the cap.
    ## Mirrors vim's `synmaxcol` (default 3000).
    ##
    ## Tradeoff (same as vim): a multi-line construct (block comment, triple-quoted
    ## string) that opens before the cap but *closes past it* on the same line is
    ## seen as still-open, bleeding its color onto following lines until the next
    ## real close. Detecting this needs tokenizing past the cap — the work it avoids.

  MaxSemanticTokens* = 200_000
    ## Hard cap on tokens per response. Above this, `applySemanticTokens` rejects
    ## the response before parsing (see design/semantic_tokens_overlay_design.md).

let defaultStyle* =
  Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})
  ## Default style for highlighting

proc captureTokenizerState*(g: GeneralTokenizer): TokenizerState =
  ## Capture the current state of a tokenizer
  ## Used to save state at line boundaries for incremental re-parsing
  result = TokenizerState(
    state: g.state,
    templateLiteralDepth: g.templateLiteralDepth,
    braceDepthStack: g.braceDepthStack,
    commentDepth: g.commentDepth,
    inJsxMode: g.inJsxMode,
    jsxTagDepth: g.jsxTagDepth,
    inComment: g.inComment,
    inScript: g.inScript,
    inStyle: g.inStyle,
    astroInFrontmatter: g.astroInFrontmatter,
    astroFirstLine: g.astroFirstLine,
    yamlIsKey: g.yamlIsKey,
    mdInCodeBlock: g.mdInCodeBlock,
    mdInMathMode: g.mdInMathMode,
    mdInDisplayMath: g.mdInDisplayMath,
    mdInFrontmatter: g.mdInFrontmatter,
    mdFirstLine: g.mdFirstLine,
    latexInMathMode: g.latexInMathMode,
    latexInDisplayMath: g.latexInDisplayMath,
    rustRawStringHashCount: g.rustRawStringHashCount,
    rustInByteString: g.rustInByteString,
    rustInRawString: g.rustInRawString,
    rustAttrBracketDepth: g.rustAttrBracketDepth,
  )

proc restoreTokenizerState*(g: var GeneralTokenizer, state: TokenizerState) =
  ## Restore tokenizer state from a saved state
  ## Used to resume tokenization from a cached line boundary
  g.state = state.state
  g.templateLiteralDepth = state.templateLiteralDepth
  g.braceDepthStack = state.braceDepthStack
  g.commentDepth = state.commentDepth
  g.inJsxMode = state.inJsxMode
  g.jsxTagDepth = state.jsxTagDepth
  g.inComment = state.inComment
  g.inScript = state.inScript
  g.inStyle = state.inStyle
  g.astroInFrontmatter = state.astroInFrontmatter
  g.astroFirstLine = state.astroFirstLine
  g.yamlIsKey = state.yamlIsKey
  g.mdInCodeBlock = state.mdInCodeBlock
  g.mdInMathMode = state.mdInMathMode
  g.mdInDisplayMath = state.mdInDisplayMath
  g.mdInFrontmatter = state.mdInFrontmatter
  g.mdFirstLine = state.mdFirstLine
  g.latexInMathMode = state.latexInMathMode
  g.latexInDisplayMath = state.latexInDisplayMath
  g.rustRawStringHashCount = state.rustRawStringHashCount
  g.rustInByteString = state.rustInByteString
  g.rustInRawString = state.rustInRawString
  g.rustAttrBracketDepth = state.rustAttrBracketDepth

proc `$`*(highlight: Highlight): string =
  result = "Highlight: ["
  for i, s in highlight.colorSegments:
    result &=
      fmt"ColorSegment(firstRow: {$s.firstRow}, firstColumn: {$s.firstColumn}, lastRow: {$s.lastRow}, lastColumn: {$s.lastColumn}, color: {s.color})"
    if i < highlight.colorSegments.high:
      result.add ", "
  result.add "]"
  if highlight.semantic.len > 0:
    result.add fmt" semantic(v={$highlight.semanticContentVersion}): {{"
    # Table iteration order is unspecified; sort rows for reproducible output.
    var rows: seq[int]
    for row in highlight.semantic.keys:
      rows.add(row)
    rows.sort()
    for i, row in rows:
      if i > 0:
        result.add ", "
      result.add fmt"{$row}: ["
      for j, t in highlight.semantic[row].tokens:
        if j > 0:
          result.add ", "
        result.add fmt"({$t.firstColumn}+{$t.length}={t.color})"
      result.add "]"
    result.add "}"

proc len*(highlight: Highlight): int {.inline.} =
  highlight.colorSegments.len

proc high*(highlight: Highlight): int {.inline.} =
  highlight.colorSegments.high

proc `[]`*(highlight: Highlight, i: int): ColorSegment {.inline.} =
  highlight.colorSegments[i]

proc `[]`*(highlight: Highlight, i: BackwardsIndex): ColorSegment {.inline.} =
  highlight.colorSegments[highlight.colorSegments.len - int(i)]

proc indexOf*(highlight: Highlight, row, column: int): int =
  ## Calculate the index of the color segment which the pair (row, column) belongs to.
  ## Uses binary search for O(log n) performance.

  # Return early if position is outside highlighted range (e.g. during
  # progressive initial highlighting where not all lines are parsed yet).
  if highlight.colorSegments.len == 0:
    return 0
  if (row, column) < (highlight[0].firstRow, highlight[0].firstColumn) or
      (row, column) > (highlight[^1].lastRow, highlight[^1].lastColumn):
    return 0

  var
    lb = 0
    ub = highlight.len
  while ub - lb > 1:
    let mid = (lb + ub) div 2
    if (row, column) >= (highlight[mid].firstRow, highlight[mid].firstColumn):
      lb = mid
    else:
      ub = mid

  return lb

proc findOverlayToken(tokens: openArray[SemanticOverlayToken], col: int): int =
  ## Index of the token containing `col`, or -1. Tokens are sorted and disjoint.
  ## Takes `openArray` so callers can pass a seq borrowed from a Table entry
  ## without a per-cell value copy on the hot render path.
  if tokens.len == 0:
    return -1
  var lo = 0
  var hi = tokens.len - 1
  var idx = -1
  while lo <= hi:
    let mid = (lo + hi) div 2
    if tokens[mid].firstColumn <= col:
      idx = mid
      lo = mid + 1
    else:
      hi = mid - 1
  if idx < 0:
    return -1
  let t = tokens[idx]
  if col < t.firstColumn + t.length:
    return idx
  return -1

proc getColorPair*(highlight: Highlight, line, col: int): EditorColorPairIndex =
  ## Color at (line, col). Semantic overlay wins over `colorSegments` on a hit.
  if highlight.semantic.len > 0:
    # `withValue` aliases the stored entry via a pointer, avoiding the seq
    # ref-count bump that `getOrDefault` would incur on this per-cell path.
    var hitColor = EditorColorPairIndex.default
    var hit = false
    highlight.semantic.withValue(line, lineOv):
      let ovIdx = findOverlayToken(lineOv.tokens, col)
      if ovIdx >= 0:
        hitColor = lineOv.tokens[ovIdx].color
        hit = true
    if hit:
      return hitColor

  if highlight.colorSegments.len == 0:
    return EditorColorPairIndex.default

  if (line, col) < (highlight[0].firstRow, highlight[0].firstColumn) or
      (line, col) > (highlight[^1].lastRow, highlight[^1].lastColumn):
    return EditorColorPairIndex.default

  let idx = highlight.indexOf(line, col)
  return highlight[idx].color

proc getSegmentModifiers*(highlight: Highlight, line, col: int): set[StyleModifier] =
  ## Modifiers at (line, col). Syntax and overlay modifiers are unioned so
  ## e.g. URI underline survives a semantic-token colour hit.
  var mods: set[StyleModifier] = {}

  if highlight.colorSegments.len > 0 and
      (line, col) >= (highlight[0].firstRow, highlight[0].firstColumn) and
      (line, col) <= (highlight[^1].lastRow, highlight[^1].lastColumn):
    let idx = highlight.indexOf(line, col)
    mods = highlight[idx].style.modifiers

  if highlight.semantic.len > 0:
    highlight.semantic.withValue(line, lineOv):
      let ovIdx = findOverlayToken(lineOv.tokens, col)
      if ovIdx >= 0:
        mods = mods + lineOv.tokens[ovIdx].style.modifiers

  return mods

template isIntersect(s, t: ColorSegment): bool =
  not (
    (t.lastRow, t.lastColumn) < (s.firstRow, s.firstColumn) or
    (s.lastRow, s.lastColumn) < (t.firstRow, t.firstColumn)
  )

template contains(s, t: ColorSegment): bool =
  (
    (s.firstRow, s.firstColumn) <= (t.firstRow, t.firstColumn) and
    (t.lastRow, t.lastColumn) <= (s.lastRow, s.lastColumn)
  )

proc overwrite(s, t: ColorSegment): seq[ColorSegment] =
  ## Overwrite `s` with t

  proc prev(pos: Position): Position =
    if pos.column > 0:
      (pos.row, pos.column - 1)
    else:
      (pos.row - 1, high(int))

  proc next(pos: Position): Position =
    (pos.row, pos.column + 1)

  if not s.isIntersect(t):
    return @[s]

  if t.contains(s):
    return @[
      ColorSegment(
        firstRow: s.firstRow,
        firstColumn: s.firstColumn,
        lastRow: s.lastRow,
        lastColumn: s.lastColumn,
        color: t.color,
        style: t.style,
      )
    ]

  if s.contains(t):
    if (s.firstRow, s.firstColumn) < (t.firstRow, t.firstColumn):
      let last = prev((t.firstRow, t.firstColumn))
      result.add(
        ColorSegment(
          firstRow: s.firstRow,
          firstColumn: s.firstColumn,
          lastRow: last.row,
          lastColumn: last.column,
          color: s.color,
          style: s.style,
        )
      )

    result.add(t)

    if (t.lastRow, t.lastColumn) < (s.lastRow, s.lastColumn):
      let first = next((t.lastRow, t.lastColumn))
      result.add(
        ColorSegment(
          firstRow: first.row,
          firstColumn: first.column,
          lastRow: s.lastRow,
          lastColumn: s.lastColumn,
          color: s.color,
          style: s.style,
        )
      )

    return result

  if (t.firstRow, t.firstColumn) < (s.firstRow, s.firstColumn):
    let first = next((t.lastRow, t.lastColumn))
    result.add(
      ColorSegment(
        firstRow: s.firstRow,
        firstColumn: s.firstColumn,
        lastRow: t.lastRow,
        lastColumn: t.lastColumn,
        color: t.color,
        style: t.style,
      )
    )

    result.add(
      ColorSegment(
        firstRow: first.row,
        firstColumn: first.column,
        lastRow: s.lastRow,
        lastColumn: s.lastColumn,
        color: s.color,
        style: s.style,
      )
    )
  else:
    let last = prev((t.firstRow, t.firstColumn))
    result.add(
      ColorSegment(
        firstRow: s.firstRow,
        firstColumn: s.firstColumn,
        lastRow: last.row,
        lastColumn: last.column,
        color: s.color,
        style: s.style,
      )
    )

    result.add(
      ColorSegment(
        firstRow: t.firstRow,
        firstColumn: t.firstColumn,
        lastRow: s.lastRow,
        lastColumn: s.lastColumn,
        color: t.color,
        style: t.style,
      )
    )

proc overwrite*(highlight: var Highlight, colorSegment: ColorSegment) =
  ## Overwrite `highlight` with colorSegment.
  ##
  ## Segments are sorted by (firstRow, firstColumn), so the affected window
  ## is found via binary search on `firstRow`/`lastRow`; segments fully
  ## before or after `colorSegment` are copied without inspection. Same
  ## pattern as [[addModifier]] / [[addUnderlineRanges]]. This brings
  ## per-call cost from O(N) to O(log N + affected), which matters for
  ## large files (40k-line JSON → hundreds of thousands of segments) where
  ## overwrite is hot: visual block selection, diagnostic application,
  ## semantic-token apply, filetree search.

  let segs = highlight.colorSegments
  if segs.len == 0:
    return

  # First segment that could overlap: one whose lastRow >= colorSegment.firstRow.
  let startIdx = segs.lowerBound(colorSegment.firstRow) do(
    seg: ColorSegment, row: int
  ) -> int:
    if seg.lastRow < row: -1 else: 1

  # First segment fully after colorSegment: one whose firstRow > colorSegment.lastRow.
  let endIdx = segs.lowerBound(colorSegment.lastRow) do(
    seg: ColorSegment, row: int
  ) -> int:
    if seg.firstRow <= row: -1 else: 1

  if startIdx >= endIdx:
    # No segment overlaps the row range — nothing to do.
    return

  # Worst case: each affected segment splits into 3 (s contains t).
  var newSegments = newSeqOfCap[ColorSegment](segs.len + (endIdx - startIdx) * 2)
  for i in 0 ..< startIdx:
    newSegments.add(segs[i])
  for i in startIdx ..< endIdx:
    newSegments.add(segs[i].overwrite(colorSegment))
  for i in endIdx ..< segs.len:
    newSegments.add(segs[i])

  highlight.colorSegments = newSegments

proc addModifier*(
    highlight: var Highlight,
    firstRow, firstCol, lastRow, lastCol: int,
    modifier: StyleModifier,
) =
  ## Add a style modifier to segments overlapping the given range,
  ## splitting segments at boundaries so only the overlapping portion
  ## receives the modifier.
  ##
  ## Segments are sorted by (firstRow, firstColumn), so the affected window
  ## is found via binary search: segments fully before or after the range
  ## are skipped without inspection. This brings per-call cost from
  ## O(segment count) to O(log N + affected), which matters for large files
  ## (40k-line JSON → hundreds of thousands of segments) where many
  ## modifier calls happen per frame during URI scans.

  let rangeFirst: Position = (firstRow, firstCol)
  let rangeLast: Position = (lastRow, lastCol)

  let segs = highlight.colorSegments

  # First segment that could overlap: one whose lastRow >= firstRow.
  # lowerBound returns the first index where cmp(seg, key) is not < 0.
  let startIdx = segs.lowerBound(firstRow) do(seg: ColorSegment, row: int) -> int:
    if seg.lastRow < row: -1 else: 1

  # First segment fully after the range: one whose firstRow > lastRow.
  let endIdx = segs.lowerBound(lastRow) do(seg: ColorSegment, row: int) -> int:
    if seg.firstRow <= row: -1 else: 1

  if startIdx >= endIdx:
    # No segment overlaps the row range — nothing to do.
    return

  var newSegments = newSeqOfCap[ColorSegment](segs.len + 2)
  for i in 0 ..< startIdx:
    newSegments.add(segs[i])

  for i in startIdx ..< endIdx:
    let cs = segs[i]
    let csFirst: Position = (cs.firstRow, cs.firstColumn)
    let csLast: Position = (cs.lastRow, cs.lastColumn)

    if csLast < rangeFirst or csFirst > rangeLast:
      # No overlap (possible for column-range checks within the same row).
      newSegments.add(cs)
    elif csFirst >= rangeFirst and csLast <= rangeLast:
      # Fully contained — add modifier to whole segment
      var modified = cs
      modified.style.modifiers.incl(modifier)
      newSegments.add(modified)
    else:
      # Partial overlap — split the segment
      if csFirst < rangeFirst:
        # Part before the range: no modifier
        if rangeFirst.column > 0:
          newSegments.add(
            ColorSegment(
              firstRow: cs.firstRow,
              firstColumn: cs.firstColumn,
              lastRow: rangeFirst.row,
              lastColumn: rangeFirst.column - 1,
              color: cs.color,
              style: cs.style,
            )
          )
        elif cs.firstRow < rangeFirst.row:
          # Range starts at column 0 on a later row. End the before-segment
          # at the previous row using the segment's own lastColumn as an
          # estimate (exact line length is unavailable here).
          newSegments.add(
            ColorSegment(
              firstRow: cs.firstRow,
              firstColumn: cs.firstColumn,
              lastRow: rangeFirst.row - 1,
              lastColumn: cs.lastColumn,
              color: cs.color,
              style: cs.style,
            )
          )

      # Overlapping part: add modifier
      let overlapFirst = if csFirst > rangeFirst: csFirst else: rangeFirst
      let overlapLast = if csLast < rangeLast: csLast else: rangeLast
      var modifiedStyle = cs.style
      modifiedStyle.modifiers.incl(modifier)
      newSegments.add(
        ColorSegment(
          firstRow: overlapFirst.row,
          firstColumn: overlapFirst.column,
          lastRow: overlapLast.row,
          lastColumn: overlapLast.column,
          color: cs.color,
          style: modifiedStyle,
        )
      )

      if csLast > rangeLast:
        # Part after the range: no modifier
        newSegments.add(
          ColorSegment(
            firstRow: rangeLast.row,
            firstColumn: rangeLast.column + 1,
            lastRow: cs.lastRow,
            lastColumn: cs.lastColumn,
            color: cs.color,
            style: cs.style,
          )
        )

  for i in endIdx ..< segs.len:
    newSegments.add(segs[i])

  highlight.colorSegments = newSegments

proc addUnderlineRanges*(
    highlight: var Highlight, ranges: openArray[tuple[row, firstCol, lastCol: int]]
) =
  ## Batch-apply the Underline modifier to the given single-row column
  ## ranges in a single pass over `highlight.colorSegments`. Ranges MUST be
  ## sorted by (row, firstCol) and non-overlapping.
  ##
  ## Equivalent to repeatedly calling `addModifier(..., Underline)` for each
  ## range, but rebuilds the segment seq **once** instead of per-range. URI
  ## scanning over a 1000-line chunk in a 40k-line file typically hits ~140
  ## URIs against ~300k segments; the per-range rebuild is O(N) memcpy of
  ## several MB, so per-call addModifier adds hundreds of ms per chunk. A
  ## batched rebuild brings that down to a single O(N + M) pass.
  if ranges.len == 0:
    return

  let segs = highlight.colorSegments
  # Allocate for the worst case: each range can split a segment into 3 parts.
  var newSegs = newSeqOfCap[ColorSegment](segs.len + ranges.len * 2)
  var rIdx = 0

  for cs in segs:
    let csFirst: Position = (cs.firstRow, cs.firstColumn)
    let csLast: Position = (cs.lastRow, cs.lastColumn)

    # Skip ranges fully before this segment.
    while rIdx < ranges.len:
      let r = ranges[rIdx]
      if r.row < cs.firstRow:
        inc rIdx
        continue
      if r.row == cs.firstRow and r.lastCol < cs.firstColumn:
        inc rIdx
        continue
      break

    # Find the first range past this segment.
    var endRange = rIdx
    while endRange < ranges.len:
      let r = ranges[endRange]
      if r.row > cs.lastRow:
        break
      if r.row == cs.lastRow and r.firstCol > cs.lastColumn:
        break
      inc endRange

    if endRange == rIdx:
      # No overlapping range — keep segment as-is.
      newSegs.add(cs)
      continue

    # Walk the segment left-to-right, emitting unmodifed parts interleaved
    # with modifier-applied overlap parts.
    var curStart = csFirst
    var modStyle = cs.style
    modStyle.modifiers.incl(StyleModifier.Underline)

    for k in rIdx ..< endRange:
      let r = ranges[k]
      let rFirst: Position = (r.row, r.firstCol)
      let rLast: Position = (r.row, r.lastCol)

      # Plain part before this range (curStart .. rFirst-1), if any.
      if curStart < rFirst:
        if rFirst.column > 0:
          newSegs.add(
            ColorSegment(
              firstRow: curStart.row,
              firstColumn: curStart.column,
              lastRow: rFirst.row,
              lastColumn: rFirst.column - 1,
              color: cs.color,
              style: cs.style,
            )
          )
        elif curStart.row < rFirst.row:
          newSegs.add(
            ColorSegment(
              firstRow: curStart.row,
              firstColumn: curStart.column,
              lastRow: rFirst.row - 1,
              lastColumn: cs.lastColumn,
              color: cs.color,
              style: cs.style,
            )
          )

      # Overlap part with modifier.
      let overlapFirst = if rFirst > csFirst: rFirst else: csFirst
      let overlapLast = if rLast < csLast: rLast else: csLast
      newSegs.add(
        ColorSegment(
          firstRow: overlapFirst.row,
          firstColumn: overlapFirst.column,
          lastRow: overlapLast.row,
          lastColumn: overlapLast.column,
          color: cs.color,
          style: modStyle,
        )
      )

      curStart = (overlapLast.row, overlapLast.column + 1)

    # Tail part after the last overlapping range.
    if curStart <= csLast:
      newSegs.add(
        ColorSegment(
          firstRow: curStart.row,
          firstColumn: curStart.column,
          lastRow: csLast.row,
          lastColumn: csLast.column,
          color: cs.color,
          style: cs.style,
        )
      )

    rIdx = endRange

  highlight.colorSegments = newSegs

proc addColorSegment*(
    h: var Highlight,
    line, length: int,
    color: EditorColorPairIndex,
    style = defaultStyle,
) =
  ## Add a colorSegment to end of the line.
  ## Ignore If need to overwrite.

  var position = -1
  for i in 0 .. h.colorSegments.high:
    if h.colorSegments[i].lastRow == line:
      position = i
    elif position > -1 and h.colorSegments[i].lastRow > line:
      break

  if position > -1:
    template beforeSegment(): ColorSegment =
      h.colorSegments[position]

    if beforeSegment.firstColumn > beforeSegment.lastColumn:
      beforeSegment.lastColumn = beforeSegment.firstColumn

    h.colorSegments.insert(
      ColorSegment(
        firstRow: line,
        firstColumn: beforeSegment.lastColumn + 1,
        lastRow: line,
        lastColumn: beforeSegment.lastColumn + 1 + length,
        color: color,
        style: style,
      ),
      position + 1,
    )

iterator parseReservedWord(
    buffer: string, reservedWords: seq[ReservedWord], color: EditorColorPairIndex
): (string, EditorColorPairIndex) =
  var buffer = buffer
  while true:
    var
      found: bool
      pos = int.high
      reservedWord: ReservedWord

    # search minimum pos
    for r in reservedWords:
      let p = buffer.find(r.word)
      if p < 0:
        continue
      if p <= pos:
        pos = p
        reservedWord = r
      found = true
    if not found:
      yield (buffer[0 ..^ 1], color)
      break

    const First = 0
    let last = pos + reservedWord.word.len
    yield (buffer[First ..< pos], color)
    yield (buffer[pos ..< last], reservedWord.color)
    buffer = buffer[last ..^ 1]

proc getEditorColorPair(
    kind: TokenClass, language: SourceLanguage
): EditorColorPairIndex =
  # Markdown language uses dedicated color pair for code blocks
  if language == langMarkdown:
    case kind
    of gtLongStringLit:
      return EditorColorPairIndex.markdownCodeBlock
    else:
      discard # Fall through to default mapping

  # Diff language uses dedicated color pairs
  if language == langDiff:
    return
      case kind
      of gtStringLit: EditorColorPairIndex.diffViewerAddedLine
      of gtComment: EditorColorPairIndex.diffViewerDeletedLine
      of gtPreprocessor: EditorColorPairIndex.diffViewerHeader
      of gtKeyword: EditorColorPairIndex.diffViewerMeta
      else: EditorColorPairIndex.default

  case kind
  of gtOperator:
    EditorColorPairIndex.operator
  of gtBuiltin:
    EditorColorPairIndex.builtin
  of gtKeyword:
    EditorColorPairIndex.keyword
  of gtBoolean:
    EditorColorPairIndex.boolean
  of gtSpecialVar:
    EditorColorPairIndex.specialVar
  of gtCharLit:
    EditorColorPairIndex.charLit
  of gtStringLit:
    EditorColorPairIndex.stringLit
  of gtLongStringLit:
    EditorColorPairIndex.stringLit
  # XML CDATA is raw character data — color the whole section (delimiters
  # included) like a long string so it stands out from parsed markup.
  of gtCData:
    EditorColorPairIndex.stringLit
  of gtBinNumber:
    EditorColorPairIndex.binNumber
  of gtDecNumber:
    EditorColorPairIndex.decNumber
  of gtFloatNumber:
    EditorColorPairIndex.floatNumber
  of gtHexNumber:
    EditorColorPairIndex.hexNumber
  of gtOctNumber:
    EditorColorPairIndex.octNumber
  of gtComment:
    EditorColorPairIndex.comment
  of gtLongComment:
    EditorColorPairIndex.longComment
  of gtDocComment:
    EditorColorPairIndex.docComment
  of gtDocLongComment:
    EditorColorPairIndex.docLongComment
  of gtPreprocessor:
    EditorColorPairIndex.preprocessor
  of gtFunctionName:
    EditorColorPairIndex.functionName
  of gtTypeName:
    EditorColorPairIndex.typeName
  of gtWhitespace:
    EditorColorPairIndex.whitespace
  of gtPragma:
    EditorColorPairIndex.pragma
  of gtIdentifier:
    EditorColorPairIndex.identifier
  of gtTable:
    EditorColorPairIndex.table
  of gtDate:
    EditorColorPairIndex.date
  of gtLogError:
    EditorColorPairIndex.logError
  of gtLogWarning:
    EditorColorPairIndex.logWarning
  of gtLogInfo:
    EditorColorPairIndex.logInfo
  of gtLogUuid:
    EditorColorPairIndex.logUuid
  of gtKey:
    EditorColorPairIndex.property
  else:
    EditorColorPairIndex.default

func tokenizerLeftBuffer(first, last: int): bool =
  ## True when the tokenizer left the buffer (start past the end, or a
  ## negative length) — slicing would raise RangeDefect. The class was fixed
  ## point-wise in the YAML tokenizer, but most language tokenizers are
  ## unaudited; callers truncate to end-of-input instead of crashing. A
  ## zero-length in-bounds token is `first == last + 1` and harmlessly
  ## continues. Shared by the full and incremental consumer loops so the two
  ## cannot drift on truncation behavior; loud under `debugHighlight` so the
  ## next tokenizer bounds bug fails a fuzz run with a trace instead of
  ## silently un-highlighting the rest of the chunk.
  result = first > last + 1
  when defined(debugHighlight):
    doAssert not result, "tokenizer left the buffer: first=" & $first & " last=" & $last

proc initHighlight*(
    buffer: seq[Runes] = @[], color = EditorColorPairIndex.default
): Highlight {.inline.} =
  ## Return highlighting for the plain text.

  var colorSegments: seq[ColorSegment]
  for i in 0 .. buffer.high:
    let lastColumn =
      if buffer[i].len > 0:
        buffer[i].high
      else:
        -1
    colorSegments.add ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: lastColumn,
      color: color,
      style: defaultStyle,
    )

  return Highlight(colorSegments: colorSegments)

proc initHighlight*(
    buffer: seq[Runes], reservedWords: seq[ReservedWord], language: SourceLanguage
): Highlight =
  if language == SourceLanguage.langNone:
    return initHighlight(buffer)

  var totalLen = 0
  for i in 0 .. buffer.high:
    totalLen += buffer[i].len
    if i < buffer.high:
      inc totalLen # '\n'
  var bufferStr = newStringOfCap(totalLen)
  for i in 0 .. buffer.high:
    bufferStr.add $buffer[i]
    if i < buffer.high:
      bufferStr.add '\n'

  var
    currentRow, currentColumn: int
    colorSegments: seq[ColorSegment]

  template splitByNewline(str, c: typed) =
    const Newline = Rune('\n')
    var
      cs = ColorSegment(
        firstRow: currentRow,
        firstColumn: currentColumn,
        lastRow: currentRow,
        lastColumn: currentColumn,
        color: c,
        style: defaultStyle,
      )
      empty = true
    for r in runes(str):
      if r == Newline:
        # push an empty segment
        if empty:
          let color = EditorColorPairIndex.default
          colorSegments.add(
            ColorSegment(
              firstRow: currentRow,
              firstColumn: currentColumn,
              lastRow: currentRow,
              lastColumn: currentColumn - 1,
              color: color,
              style: defaultStyle,
            )
          )
        else:
          colorSegments.add(cs)
        inc(currentRow)
        currentColumn = 0
        cs.firstRow = currentRow
        cs.firstColumn = currentColumn
        cs.lastRow = currentRow
        cs.lastColumn = currentColumn
        empty = true
      else:
        cs.lastColumn = currentColumn
        inc(currentColumn)
        empty = false
    if not empty:
      colorSegments.add(cs)

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(bufferStr)

  while true:
    token.getNextToken(language)

    if token.kind == gtEof:
      break

    let
      first = token.start

      # Make it complete even if it's incomplete.
      last =
        if first + token.length - 1 > bufferStr.high:
          bufferStr.high
        else:
          first + token.length - 1

    if tokenizerLeftBuffer(first, last):
      break

    block:
      # Increment `currentRow` if newlines only.
      let str = bufferStr[first .. last]
      if str != "" and
          all(
            str,
            proc(x: char): bool =
              x == '\n',
          ):
        currentRow += last - first + 1
        currentColumn = 0
        continue

    let color = getEditorColorPair(token.kind, language)

    if token.kind == gtComment:
      for r in bufferStr[first .. last].parseReservedWord(reservedWords, color):
        if r[0] == "":
          continue
        splitByNewline(r[0], r[1])
      continue

    splitByNewline(bufferStr[first .. last], color)

  return Highlight(colorSegments: colorSegments)

func capturedBoundaryState(
    token: GeneralTokenizer, language: SourceLanguage
): TokenClass =
  ## The state stored at a line boundary INSIDE `token`. Multi-line token
  ## kinds force the kind itself so an incremental reparse entering one of
  ## the spanned lines resumes the construct (the tokenizer's post-state is
  ## the value after the token completes, not the per-line value). `gtCData`
  ## (XML CDATA, emitted by no other tokenizer) resumes mid-section directly
  ## through the tokenizer's `g.state == gtCData` branch — forced here, but
  ## deliberately NOT in `MultiLineKinds` (no rewind needed; see the comment
  ## there). Lisp strings span lines and resume via `state == gtStringLit`
  ## (unlike Rust, which parks `gtLongStringLit` at the boundary and uses
  ## `gtStringLit` only for a mid-line pending escape). Everything else
  ## resumes from the tokenizer's own state. Shared by the boundary capture
  ## and the `debugHighlight` resumability assertion so the two cannot drift.
  if token.kind in {gtLongStringLit, gtLongComment, gtDocLongComment, gtCData} or
      (token.kind == gtStringLit and language == SourceLanguage.langLisp):
    token.kind
  else:
    token.state

proc initHighlightIncrementalFromStr*(
    bufferStr: string,
    startLine: int,
    endLine: int,
    initialState: TokenizerState,
    reservedWords: seq[ReservedWord],
    language: SourceLanguage,
    tailSegments: seq[ColorSegment] = @[],
): tuple[segments: seq[ColorSegment], lineStates: seq[TokenizerState]] =
  ## Core implementation that works directly with a pre-built buffer string.
  ##
  ## Guarantees `lineStates.len == endLine - startLine + 1` — one entry per
  ## line in the range, where `lineStates[i]` is the state entering line
  ## `startLine + i + 1` — even when the tokenizer stops before the end of
  ## the buffer (interior NUL, defensive break). Consumers index into it
  ## positionally and must be able to rely on this.

  var
    currentRow = startLine
    currentColumn: int
    colorSegments: seq[ColorSegment]
    lineStates: seq[TokenizerState]

  # Template to split tokens by newlines and track line boundaries
  template splitByNewlineWithState(str, c: typed) =
    const Newline = Rune('\n')
    var
      cs = ColorSegment(
        firstRow: currentRow,
        firstColumn: currentColumn,
        lastRow: currentRow,
        lastColumn: currentColumn,
        color: c,
        style: defaultStyle,
      )
      empty = true
    for r in runes(str):
      if r == Newline:
        # push an empty segment
        if empty:
          let color = EditorColorPairIndex.default
          colorSegments.add(
            ColorSegment(
              firstRow: currentRow,
              firstColumn: currentColumn,
              lastRow: currentRow,
              lastColumn: currentColumn - 1,
              color: color,
              style: defaultStyle,
            )
          )
        else:
          colorSegments.add(cs)

        # Capture tokenizer state at line boundary, forcing a resumable
        # state for multi-line tokens — see `capturedBoundaryState`.
        let savedState = token.state
        token.state = capturedBoundaryState(token, language)
        lineStates.add(captureTokenizerState(token))
        token.state = savedState

        inc(currentRow)
        currentColumn = 0
        cs.firstRow = currentRow
        cs.firstColumn = currentColumn
        cs.lastRow = currentRow
        cs.lastColumn = currentColumn
        empty = true
      else:
        cs.lastColumn = currentColumn
        inc(currentColumn)
        empty = false
    if not empty:
      colorSegments.add(cs)

    if str.len > 0 and str[^1] == '\n' and lineStates.len > 0:
      # When a token ends on a newline, the next line is OUTSIDE it, so its
      # entering state is the token's real post-state — not the multi-line
      # continuation kind the boundary capture above forced. Re-capture it. Matters
      # for tokens that eat their trailing newline (a YAML block scalar `|`/`>`
      # ending at the dedent, back in `gtOther`); a no-op otherwise.
      lineStates[^1] = captureTokenizerState(token)

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(bufferStr)

  # Restore initial tokenizer state
  token.restoreTokenizerState(initialState)

  if startLine == 0:
    # `astroFirstLine`/`mdFirstLine`'s fresh-start value is `true`, unlike every
    # other field (zero-value `false`), so the zero-valued seed `TokenizerState()`
    # restores them as `false` and the frontmatter `---` fence is missed.
    # Re-assert at file line 0; captured states for `startLine > 0` are always
    # `false`.
    token.astroFirstLine = true
    token.mdFirstLine = true

  while true:
    token.getNextToken(language)

    if token.kind == gtEof:
      break

    let
      first = token.start
      # Make it complete even if it's incomplete
      last =
        if first + token.length - 1 > bufferStr.high:
          bufferStr.high
        else:
          first + token.length - 1

    if tokenizerLeftBuffer(first, last):
      break

    block:
      # Increment `currentRow` if newlines only
      let str = bufferStr[first .. last]
      if str != "" and
          all(
            str,
            proc(x: char): bool =
              x == '\n',
          ):
        # Save states for each newline
        for i in 0 ..< (last - first + 1):
          lineStates.add(captureTokenizerState(token))
        currentRow += last - first + 1
        currentColumn = 0
        continue

    when defined(debugHighlight):
      block:
        # Invariant: a token carrying an interior newline must be resumable at
        # every line boundary it spans — the boundary capture below stores
        # either the token kind (forced multi-line set, incl. the Lisp string
        # case) or the tokenizer's post-state, and if that value is a plain
        # gtOther/gtNone an incremental reparse entering one of those lines
        # loses the construct and diverges from a full parse (the bug class
        # behind the YAML chunk-boundary fixes). Newlines-only tokens are
        # handled by the dedicated branch above.
        # gtWhitespace runs legitimately span blank lines in a neutral state:
        # resuming a fresh parse at a blank line reproduces them, so they are
        # exempt (YAML's blank-line-after-header hazard is handled by the
        # drivers' rewind, not by state).
        let txt = bufferStr[first .. last]
        let nl = txt.find('\n')
        if token.kind != gtWhitespace and nl >= 0 and nl < txt.high:
          let captured = capturedBoundaryState(token, language)
          doAssert captured notin {gtOther, gtNone},
            "non-resumable multi-line token: kind=" & $token.kind & " state=" &
              $token.state & " lang=" & $language

    let color = getEditorColorPair(token.kind, language)

    if token.kind == gtComment:
      for r in bufferStr[first .. last].parseReservedWord(reservedWords, color):
        if r[0] == "":
          continue
        splitByNewlineWithState(r[0], r[1])
      continue

    splitByNewlineWithState(bufferStr[first .. last], color)

  # Capture final state for the last line. When the tokenizer stopped early
  # (gtEof at an interior NUL byte, or the defensive out-of-bounds break
  # above), this also pads the remaining line boundaries with the stop state:
  # consumers rely on one state per line in [startLine, endLine] — a short
  # array would index out of bounds in the chunked drivers' handoff scans and
  # desynchronize `parsedUpTo` from the cache (see `continueInitialHighlight`).
  # The padded lines carry no segments (un-highlighted) and resume from the
  # stop state — degraded but stable, matching the break's intent.
  while currentRow <= endLine:
    lineStates.add(captureTokenizerState(token))
    inc currentRow

  when defined(debugHighlight):
    # The padding above only fixes the short direction; over-length would mean
    # a tokenizer emitted overlapping tokens re-covering a newline, silently
    # desynchronizing the consumers' positional indexing. Pin the documented
    # guarantee in both directions.
    doAssert lineStates.len == endLine - startLine + 1,
      "lineStates length contract violated: " & $lineStates.len & " states for " &
        $(endLine - startLine + 1) & " lines"

  if tailSegments.len == 0:
    return (segments: colorSegments, lineStates: lineStates)

  # Merge default-colored tail segments (for cap-truncated lines) into the
  # produced segments, preserving the sorted-by-(row, column) invariant consumers
  # rely on. `tailSegments` rows are 0-based relative to `startLine`; absolutize
  # them to match `colorSegments`. A tail's column is the cap, past every token
  # on its row, so a stable merge places it correctly.
  var tails = tailSegments
  for k in 0 ..< tails.len:
    tails[k].firstRow += startLine
    tails[k].lastRow += startLine

  var merged = newSeqOfCap[ColorSegment](colorSegments.len + tails.len)
  var
    i = 0
    j = 0
  while i < colorSegments.len and j < tails.len:
    if (colorSegments[i].firstRow, colorSegments[i].firstColumn) <=
        (tails[j].firstRow, tails[j].firstColumn):
      merged.add colorSegments[i]
      inc i
    else:
      merged.add tails[j]
      inc j
  while i < colorSegments.len:
    merged.add colorSegments[i]
    inc i
  while j < tails.len:
    merged.add tails[j]
    inc j

  return (segments: merged, lineStates: lineStates)

proc buildBufferStrCapped*(
    lines: seq[string], startLine, endLine, maxLineLen: int
): tuple[str: string, tails: seq[ColorSegment]] =
  ## Join `lines[startLine..endLine]` with newlines, truncating any line longer
  ## than `maxLineLen` runes so the tokenizer never sees the excess (bounds
  ## per-line work to O(cap)). Each truncated line emits a default-colored "tail"
  ## segment over the dropped remainder so it renders as plain text instead of
  ## inheriting the last token's color. `maxLineLen <= 0` disables capping. Tail
  ## rows are 0-based relative to `startLine`, matching how
  ## `initHighlightIncrementalFromStr` maps every other row.
  let rangeEnd = min(endLine, lines.high)
  let capping = maxLineLen > 0
  # Upper bound on a capped line's byte contribution (maxLineLen runes <=
  # maxLineLen*4 UTF-8 bytes); summing full lengths would reserve O(full line)
  # for a huge truncated line. newStringOfCap only takes a hint, so an upper
  # bound is fine. Saturate the *4 so an absurdly large cap can't overflow to a
  # negative capacity.
  let capBytesHint =
    if not capping or maxLineLen > high(int) div 4:
      high(int)
    else:
      maxLineLen * 4
  var totalLen = 0
  for i in startLine .. rangeEnd:
    let contrib = min(lines[i].len, capBytesHint)
    totalLen += contrib
    if i < rangeEnd:
      inc totalLen # '\n'
  result.str = newStringOfCap(totalLen)
  for i in startLine .. rangeEnd:
    let line = lines[i]
    # Quick reject: byteLen <= cap implies runeLen <= cap, so no capping. Only
    # genuinely long lines pay for the rune scan.
    if capping and line.len > maxLineLen:
      # runeSubStr scans at most `maxLineLen` runes and returns the whole string
      # when the line has <= maxLineLen runes, so `head.len < line.len` exactly
      # means it was truncated.
      let head = line.runeSubStr(0, maxLineLen)
      if head.len < line.len:
        result.str.add head
        # lastColumn over-estimates the real rune column (byte length is an
        # upper bound); safe because the renderer queries getColorPair per real
        # character, so columns past the line end are never looked up.
        result.tails.add ColorSegment(
          firstRow: i - startLine,
          firstColumn: maxLineLen,
          lastRow: i - startLine,
          lastColumn: line.len - 1,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      else:
        result.str.add line
    else:
      result.str.add line
    if i < rangeEnd:
      result.str.add '\n'

proc initHighlightIncremental*(
    lines: seq[string],
    startLine: int,
    endLine: int,
    initialState: TokenizerState,
    reservedWords: seq[ReservedWord],
    language: SourceLanguage,
    maxLineLen: int = 0,
): tuple[segments: seq[ColorSegment], lineStates: seq[TokenizerState]] =
  ## Parse lines[startLine..endLine] and produce color segments with matching
  ## row numbers. `lines` must contain entries at indices startLine..endLine.
  ## `maxLineLen` caps per-line tokenization (see `buildBufferStrCapped`).
  if language == SourceLanguage.langNone or lines.len == 0:
    return (segments: @[], lineStates: @[])
  let (bufferStr, tails) = buildBufferStrCapped(lines, startLine, endLine, maxLineLen)
  initHighlightIncrementalFromStr(
    bufferStr,
    startLine,
    min(endLine, lines.high),
    initialState,
    reservedWords,
    language,
    tails,
  )

proc segmentCutIndex*(segs: openArray[ColorSegment], row: int): int =
  ## Index `i` such that `segs[0 ..< i]` keeps every segment on rows below
  ## `row` and drops the rest. `segs` must be sorted by `firstRow` (the
  ## parsers emit single-row segments in row order). The same "first index
  ## with `firstRow >= row`" query as the splice search in
  ## `updateHighlightIncremental`, kept named for the cut semantics.
  segs.lowerBound(row) do(seg: ColorSegment, line: int) -> int:
    cmp(seg.firstRow, line)

proc yamlLineNeedsContextAbove(line: string): bool =
  ## A YAML block scalar's extent depends on lines BELOW its header but is
  ## resolved by scanning ABOVE it, which a saved state cannot express:
  ##   * blank lines after a header carry plain `gtOther`, so a parse starting
  ##     at the first indented content has nothing pointing back to the header;
  ##   * an alone header (`|`/`>` on its own line) takes its indentation from
  ##     the nearest non-blank line above, missing if a parse starts on the
  ##     header.
  var firstNonSpace = '\0'
  for ch in line:
    if ch notin {' ', '\t'}:
      firstNonSpace = ch
      break
  # Blank line (no non-space char) or an alone block-scalar header.
  firstNonSpace in {'\0', '|', '>'}

proc chunkHandoffUnsafe*(
    language: SourceLanguage, state: TokenClass, nextLine: string
): bool =
  ## True when a chunked parse must not hand `state` to a fresh chunk starting
  ## at `nextLine`. The single dispatch point for all chunked drivers (the
  ## entry rewind and the internal handoff scan in `updateHighlightIncremental`,
  ## the resume rewind in `continueInitialHighlight`): a language whose
  ## constructs resolve against lines above the resume point gets an arm here,
  ## not a new predicate wired into each driver.
  case language
  of SourceLanguage.langYaml:
    # YAML block scalars resume by re-reading the header and parent lines
    # ABOVE the resume point — context a fresh buffer does not contain — so a
    # handoff inside a scalar (gtLongStringLit), right after a header
    # (gtCommand), or onto a line that itself resolves against lines above
    # must rewind to a safe line instead. Quoted-string states are safe to
    # hand off: their resume is position-independent (the state alone
    # suffices).
    state in {gtLongStringLit, gtCommand} or yamlLineNeedsContextAbove(nextLine)
  else:
    false

proc updateHighlightIncremental*(
    lineCount: int,
    getLine: proc(i: int): string,
    incrHighlight: var IncrementalHighlight,
    changedStartLine: int,
    bufferChangeSeq: int,
    reservedWords: seq[ReservedWord],
    language: SourceLanguage,
    maxLineLen: int = 0,
) =
  ## Update highlighting incrementally for a changed region.
  ## Re-parses from the changed line in chunks, stopping early when the
  ## tokenizer state converges with the cached state (meaning all subsequent
  ## lines would produce the same result as before). Falls back to parsing
  ## the entire rest of the file when convergence cannot be detected (e.g.
  ## when the line count has changed).

  const ChunkSize = 100

  let lastLine = lineCount - 1

  # Start re-parsing from the changed line.
  # A small backward margin accounts for tokens that may span the boundary.
  var reparseStart = max(0, changedStartLine - 2)

  # Get initial state for the re-parse range
  var initialState: TokenizerState
  if reparseStart > 0 and reparseStart - 1 < incrHighlight.lineStates.states.len:
    initialState = incrHighlight.lineStates.states[reparseStart - 1]
  else:
    initialState = TokenizerState()

  # Per-line state captures inside a single multi-line token (long comment or
  # long string) all read the same `commentDepth` / hash count — the value at
  # the moment the token completes, not the per-line value. Restarting parse
  # from mid-token therefore restores a stale depth and can confuse nested
  # constructs (Rust `/* /* */ */`, Nim `#[ #[ ]# ]#`). To stay correct,
  # rewind to the line where the multi-line token actually opens, which is
  # the first line whose preceding state is NOT a multi-line continuation.
  #
  # `gtStringLit`/`gtKey`/`gtCharLit` cover tokenizers whose string literals span
  # lines and resume via these states (YAML `"..."` scalars/keys, its `'...'`
  # scalars parked in `gtCharLit`, Lisp strings); a reparse starting mid-string
  # must rewind to its opening line. Single-line strings never leave these states
  # at a boundary, so the rewind never fires for them.
  #
  # `gtCData` (XML CDATA) is considered and deliberately excluded: CDATA
  # carries no auxiliary per-line state, so resuming mid-section via the
  # tokenizer's `g.state == gtCData` branch is always correct without a
  # rewind. A future multi-line construct that parks `gtCData` AND needs
  # auxiliary state (depth, delimiter length, ...) must be added here.
  const MultiLineKinds =
    {gtLongComment, gtDocLongComment, gtLongStringLit, gtStringLit, gtKey, gtCharLit}

  # Also rewind across chunk-handoff hazards (YAML mid-scalar states, blank
  # lines, alone headers — see chunkHandoffUnsafe). Rewinding too early is
  # always safe: the reparse restarts from a cached, correct state.
  while reparseStart > 0 and (
    initialState.state in MultiLineKinds or
    chunkHandoffUnsafe(language, initialState.state, getLine(reparseStart))
  )
  :
    dec reparseStart
    if reparseStart > 0 and reparseStart - 1 < incrHighlight.lineStates.states.len:
      initialState = incrHighlight.lineStates.states[reparseStart - 1]
    else:
      initialState = TokenizerState()

  # State convergence detection is only valid when the line count has not
  # changed; otherwise cached states at the same index refer to different lines.
  let canConverge = lineCount == incrHighlight.lineStates.states.len

  # Parse in chunks, checking for state convergence after each chunk
  var
    currentStart = reparseStart
    currentState = initialState
    allNewSegments: seq[ColorSegment]
    allNewLineStates: seq[TokenizerState]
    reparseEnd = reparseStart - 1
    chunkLen = ChunkSize

  while currentStart <= lastLine:
    let chunkEnd = min(currentStart + chunkLen - 1, lastLine)

    # Build buffer string only for this chunk
    var chunkLines = newSeq[string](chunkEnd - currentStart + 1)
    for i in currentStart .. chunkEnd:
      chunkLines[i - currentStart] = getLine(i)
    let (bufferStr, tails) =
      buildBufferStrCapped(chunkLines, 0, chunkLines.high, maxLineLen)

    let (newSegments, newLineStates) = initHighlightIncrementalFromStr(
      bufferStr, currentStart, chunkEnd, currentState, reservedWords, language, tails
    )

    # `newLineStates[i]` is the state entering line `currentStart + i + 1`, so
    # the last entry is what the next chunk would start with (the producer
    # pads on early tokenizer stops, so the positional indexing never goes out
    # of bounds). A handoff inside a YAML block scalar — or onto a line that
    # resolves against lines above — must move back to a safe line: the
    # rewound lines are re-parsed by the next iteration together with their
    # context (the scalar's header and parent lines) in one buffer. The final
    # chunk has no handoff to protect, so `handoff` stays past it and the
    # slices below keep the whole chunk.
    var handoff = chunkEnd + 1
    if chunkEnd < lastLine:
      while handoff > currentStart and
          chunkHandoffUnsafe(
            language, newLineStates[handoff - currentStart - 1].state, getLine(handoff)
          )
      :
        dec handoff

      if handoff == currentStart:
        # The whole chunk sits inside one construct. Re-parse it with a larger
        # window until a safe handoff (or the end of the buffer) fits inside;
        # geometric growth keeps the total re-parse cost linear.
        chunkLen *= 2
        continue

    # Keep only lines currentStart .. handoff - 1.
    allNewSegments.add(newSegments[0 ..< newSegments.segmentCutIndex(handoff)])
    allNewLineStates.add(newLineStates[0 ..< (handoff - currentStart)])
    reparseEnd = handoff - 1

    if chunkEnd >= lastLine:
      break

    currentState = allNewLineStates[^1]
    chunkLen = ChunkSize

    # Check for convergence: if the tokenizer state entering the next line
    # matches the old cached state, all subsequent lines will produce the same
    # segments as before — no need to continue parsing.
    #
    # Only sound once the reparse has passed the changed line: the
    # MultiLineKinds rewind can move reparseStart more than a chunk above
    # `changedStartLine` (a construct opening far above the edit). The first
    # chunk then re-parses identical pre-edit content, so its end state
    # always matches the cache and an unguarded break would stop BEFORE
    # reaching the change, leaving stale segments at and below it.
    if canConverge and reparseEnd >= changedStartLine and
        currentState == incrHighlight.lineStates.states[handoff - 1]:
      break

    currentStart = handoff

  # Find the splice range in the sorted segments using binary search.
  # Remove segments that overlap [reparseStart, reparseEnd] or exceed buffer,
  # then insert new segments in place.
  let spliceStart = incrHighlight.segments.lowerBound(reparseStart) do(
    seg: ColorSegment, line: int
  ) -> int:
    cmp(seg.firstRow, line)

  var spliceEnd = spliceStart
  while spliceEnd < incrHighlight.segments.len:
    let seg = incrHighlight.segments[spliceEnd]
    if seg.firstRow > reparseEnd:
      # Also skip segments beyond buffer bounds
      if seg.firstRow < lineCount and seg.lastRow < lineCount:
        break
    inc spliceEnd

  # Splice: replace [spliceStart..spliceEnd) with allNewSegments
  let oldLen = incrHighlight.segments.len
  let removeCount = spliceEnd - spliceStart
  let newLen = oldLen - removeCount + allNewSegments.len

  if newLen != oldLen or removeCount > 0:
    var result = newSeq[ColorSegment](newLen)
    for i in 0 ..< spliceStart:
      result[i] = incrHighlight.segments[i]
    for i in 0 ..< allNewSegments.len:
      result[spliceStart + i] = allNewSegments[i]
    for i in spliceEnd ..< oldLen:
      result[spliceStart + allNewSegments.len + i - spliceEnd] =
        incrHighlight.segments[i]
    incrHighlight.segments = result

  # Update line state cache - resize to match buffer
  incrHighlight.lineStates.states.setLen(lineCount)

  # Replace states for re-parsed lines only
  if allNewLineStates.len > 0:
    var stateIdx = 0
    for lineIdx in reparseStart .. reparseEnd:
      if stateIdx < allNewLineStates.len and lineIdx < lineCount:
        incrHighlight.lineStates.states[lineIdx] = allNewLineStates[stateIdx]
        inc stateIdx

  incrHighlight.lineStates.version = bufferChangeSeq

proc detectLanguage*(filename: string): SourceLanguage =
  # Check basename for special files (no extension)
  let basename = filename.extractFilename
  case basename
  of "COMMIT_EDITMSG":
    return SourceLanguage.langCommitEditMsg
  of "git-rebase-todo":
    return SourceLanguage.langGitRebaseTodo
  of ".gitignore":
    return SourceLanguage.langGitignore
  of "nimble.lock":
    return SourceLanguage.langJson
  of "hyprland.conf":
    return SourceLanguage.langHyprland
  else:
    # Check for Dockerfile variants (Dockerfile, Dockerfile.prod, etc.)
    if basename.startsWith("Dockerfile"):
      return SourceLanguage.langDockerfile

  # TODO: use settings file
  case filename.splitFile.ext
  of ".astro":
    return SourceLanguage.langAstro
  of ".c", ".dox", ".h", ".i":
    return SourceLanguage.langC
  of ".C", ".CPP", ".H", ".HPP", ".c++", ".cc", ".cp", ".cpp", ".cxx", ".h++", ".hh",
      ".hp", ".hpp", ".hxx", ".ii", ".tcc":
    return SourceLanguage.langCpp
  of ".cs":
    return SourceLanguage.langCsharp
  of ".dockerfile":
    return SourceLanguage.langDockerfile
  of ".cabal", ".hs":
    return SourceLanguage.langHaskell
  of ".html":
    return SourceLanguage.langHtml
  of ".java":
    return SourceLanguage.langJava
  of ".js":
    return SourceLanguage.langJavaScript
  of ".jsx":
    return SourceLanguage.langJsx
  of ".ts":
    return SourceLanguage.langTypeScript
  of ".tsx":
    return SourceLanguage.langTsx
  of ".markdown", ".md":
    return SourceLanguage.langMarkdown
  of ".nim", ".nimble", ".nims":
    return SourceLanguage.langNim
  of ".py", ".pyw", ".pyx":
    return SourceLanguage.langPython
  of ".rs":
    return SourceLanguage.langRust
  of ".bash", ".sh":
    return SourceLanguage.langShell
  of ".fish":
    return SourceLanguage.langFish
  of ".zsh", ".zshrc", ".zshenv", ".zlogin", ".zlogout", ".zprofile":
    return SourceLanguage.langZsh
  of ".tcl", ".tk", ".itcl", ".itk":
    return SourceLanguage.langTcl
  of ".toml":
    return SourceLanguage.langToml
  of ".cff", ".yaml", ".yml":
    return SourceLanguage.langYaml
  of ".json":
    return SourceLanguage.langJson
  of ".jsonc":
    return SourceLanguage.langJsonc
  of ".tex", ".sty", ".cls", ".ltx", ".dtx":
    return SourceLanguage.langLatex
  of ".lisp", ".lsp", ".cl", ".el", ".scm", ".ss", ".rkt", ".asd", ".fasl":
    return SourceLanguage.langLisp
  of ".log":
    return SourceLanguage.langLog
  of ".hl":
    return SourceLanguage.langHyprland
  of ".xml", ".svg", ".xsd", ".xsl", ".xslt", ".rss", ".atom", ".plist":
    return SourceLanguage.langXml
  else:
    return SourceLanguage.langNone

# LSP Semantic Tokens Support

proc semanticTokenTypeToColor*(
    typeName: string, modifiers: seq[string] = @[]
): EditorColorPairIndex =
  ## Convert semantic token type name to EditorColorPairIndex.
  ## Supports both LSP standard types and rust-analyzer specific types.
  ##
  ## Standard LSP token types (LSP 3.16+):
  ##   namespace, type, class, enum, interface, struct, typeParameter,
  ##   parameter, variable, property, enumMember, event, function,
  ##   method, macro, keyword, modifier, comment, string, number,
  ##   regexp, operator, decorator
  ##
  ## Rust-analyzer specific types:
  ##   lifetime, attribute, derive, union, typeAlias, builtinType,
  ##   selfKeyword, selfTypeKeyword, formatSpecifier, escapeSequence,
  ##   label, generic, constParameter, unresolvedReference, punctuation,
  ##   angle, arithmetic, bitwise, brace, bracket, colon, comma,
  ##   comparison, dot, logical, macroBang, parenthesis, semicolon,
  ##   attributeBracket, builtinAttribute, deriveHelper, toolModule,
  ##   invalidEscapeSequence

  # Check for deprecated modifier first (can affect any type)
  # Deprecated items typically use a strike-through style but we return
  # the base color here - style handling should be done separately

  case typeName
  # Standard LSP token types
  of "namespace":
    EditorColorPairIndex.namespace
  of "type":
    EditorColorPairIndex.typeName
  of "class":
    EditorColorPairIndex.className
  of "enum":
    EditorColorPairIndex.enumName
  of "interface":
    EditorColorPairIndex.interfaceName
  of "struct":
    EditorColorPairIndex.typeName
  of "typeParameter":
    EditorColorPairIndex.typeParameter
  of "parameter":
    EditorColorPairIndex.parameter
  of "variable":
    # Check for specific modifiers
    if "readonly" in modifiers or "static" in modifiers:
      EditorColorPairIndex.constParameter
    else:
      EditorColorPairIndex.variable
  of "property":
    EditorColorPairIndex.property
  of "enumMember":
    EditorColorPairIndex.enumMember
  of "event":
    EditorColorPairIndex.event
  of "function":
    EditorColorPairIndex.function
  of "method":
    EditorColorPairIndex.`method`
  of "macro":
    EditorColorPairIndex.`macro`
  of "keyword":
    EditorColorPairIndex.keyword
  of "modifier":
    EditorColorPairIndex.keyword
  of "comment":
    EditorColorPairIndex.comment
  of "string":
    EditorColorPairIndex.lspString
  of "number":
    EditorColorPairIndex.decNumber
  of "regexp":
    EditorColorPairIndex.regexp
  of "operator":
    EditorColorPairIndex.operator
  of "decorator":
    EditorColorPairIndex.decorator

  # Rust-analyzer specific token types
  of "lifetime":
    EditorColorPairIndex.lifetime
  of "attribute":
    EditorColorPairIndex.attribute
  of "derive":
    EditorColorPairIndex.derive
  of "union":
    EditorColorPairIndex.union
  of "typeAlias":
    EditorColorPairIndex.typeAlias
  of "builtinType":
    EditorColorPairIndex.builtinType
  of "selfKeyword":
    EditorColorPairIndex.selfKeyword
  of "selfTypeKeyword":
    EditorColorPairIndex.selfTypeKeyword
  of "formatSpecifier":
    EditorColorPairIndex.formatSpecifier
  of "escapeSequence":
    EditorColorPairIndex.escapeSequence
  of "invalidEscapeSequence":
    EditorColorPairIndex.invalidEscapeSequence
  of "label":
    EditorColorPairIndex.label
  of "generic":
    EditorColorPairIndex.generic
  of "constParameter":
    EditorColorPairIndex.constParameter
  of "unresolvedReference":
    EditorColorPairIndex.unresolvedReference
  of "punctuation":
    EditorColorPairIndex.punctuation
  of "angle":
    EditorColorPairIndex.angle
  of "arithmetic":
    EditorColorPairIndex.arithmetic
  of "bitwise":
    EditorColorPairIndex.bitwise
  of "brace":
    EditorColorPairIndex.brace
  of "bracket":
    EditorColorPairIndex.bracket
  of "colon":
    EditorColorPairIndex.colon
  of "comma":
    EditorColorPairIndex.comma
  of "comparison":
    EditorColorPairIndex.comparison
  of "dot":
    EditorColorPairIndex.dot
  of "logical":
    EditorColorPairIndex.logical
  of "macroBang":
    EditorColorPairIndex.macroBang
  of "parenthesis":
    EditorColorPairIndex.parenthesis
  of "semicolon":
    EditorColorPairIndex.semicolon
  of "attributeBracket":
    EditorColorPairIndex.attributeBracket
  of "builtinAttribute":
    EditorColorPairIndex.builtinAttribute
  of "deriveHelper":
    EditorColorPairIndex.deriveHelper
  of "toolModule":
    EditorColorPairIndex.toolModule
  else:
    # Unknown token type - use default
    EditorColorPairIndex.default

proc buildSemanticTypeColorTable*(
    legend: SemanticTokensLegend
): SemanticTypeColorTable =
  result = SemanticTypeColorTable(legend: legend)
  result.baseColors = newSeq[EditorColorPairIndex](legend.tokenTypes.len)
  for i, name in legend.tokenTypes:
    result.baseColors[i] = semanticTokenTypeToColor(name, @[])

proc semanticModifierStyle(modifiers: seq[string]): set[StyleModifier] =
  ## Map LSP standard token modifiers to celina text-attribute set. Only the
  ## text-attribute modifiers are honoured here; `readonly`/`static` shifts
  ## the base colour instead (see `semanticTokenTypeToColor`).
  for m in modifiers:
    case m
    of "deprecated":
      result.incl StyleModifier.Crossed
    of "abstract":
      result.incl StyleModifier.Italic
    of "definition", "declaration":
      result.incl StyleModifier.Bold
    else:
      discard

proc resolveTokenColor*(
    tab: SemanticTypeColorTable, tokenType: int, modBitmask: int
): tuple[color: EditorColorPairIndex, style: set[StyleModifier]] {.inline.} =
  ## Resolve `(colour, style)` from `(tokenType, modBitmask)`, lazily decoding
  ## modifier names on the first sighting of each unique combination.
  if tokenType < 0 or tokenType >= tab.baseColors.len:
    return (EditorColorPairIndex.default, {})
  # Zero-modifier fast path. Callers must pre-filter negatives (a negative
  # bitmask is a spec violation; applySemanticTokens rejects the whole
  # response). Defensive fallback for direct callers of this API: bail to
  # default rather than folding into base colour or poisoning the cache via
  # `.uint32` sign-extension.
  if modBitmask == 0:
    return (tab.baseColors[tokenType], {})
  if modBitmask < 0:
    return (EditorColorPairIndex.default, {})
  let key = (uint64(tokenType) shl 32) or uint64(uint32(modBitmask))
  if key in tab.resolved:
    return tab.resolved[key]
  # First hit for this (type, mods) pair; decode names and cache.
  var mods: seq[string]
  var m = modBitmask
  var idx = 0
  while m != 0 and idx < tab.legend.tokenModifiers.len:
    if (m and 1) != 0:
      mods.add(tab.legend.tokenModifiers[idx])
    m = m shr 1
    inc idx
  let entry = (
    color: semanticTokenTypeToColor(tab.legend.tokenTypes[tokenType], mods),
    style: semanticModifierStyle(mods),
  )
  tab.resolved[key] = entry
  return entry

type
  LineRuneCountFn* = proc(row: int): int {.gcsafe, raises: [].}
    ## Row -> rune count callback used by `applySemanticTokens` for multi-line
    ## token splitting. Return the number of Unicode characters (runes) on
    ## `row`, or `-1` if `row` is out of buffer bounds (signals the splitter
    ## to stop advancing). Must be pure and non-raising.

  LineTextFn* = proc(row: int): string {.gcsafe, raises: [].}
    ## Row -> line text callback used by `applySemanticTokens` to convert
    ## LSP UTF-16 code-unit positions into rune indices. Return "" when
    ## `row` is out of buffer bounds (OOB detection stays with
    ## `LineRuneCountFn`); callers with only ASCII content can omit this
    ## callback to skip the per-token conversion pass. Must be pure and
    ## non-raising.

proc deleteRowsInRange(
    overlay: var Table[int, SemanticOverlayLine], firstRow, lastRow: int
): tuple[deleted: int, outside: int] =
  ## Delete overlay rows in `[firstRow, lastRow]`. Iterates the range rather
  ## than the whole key-set: viewport-sized range applies (~60 rows) stay
  ## cheap even when the overlay covers thousands of populated rows.
  let beforeLen = overlay.len
  for row in firstRow .. lastRow:
    if overlay.hasKey(row):
      overlay.del(row)
  result.deleted = beforeLen - overlay.len
  result.outside = overlay.len

proc addOverlayToken(
    overlay: var Table[int, SemanticOverlayLine],
    row, col, length: int,
    color: EditorColorPairIndex,
    modifiers: set[StyleModifier] = {},
) =
  ## Insert a token into `overlay[row].tokens` while preserving the
  ## sorted-AND-disjoint invariant `SemanticOverlayLine` documents. The
  ## multi-line splitter's per-row unroll can collide with later single-line
  ## tokens on the same row; the new token wins over every overlapping prior,
  ## but each overlapping prior keeps its own head (up to `col`) and tail
  ## (past `col + length`) as separate segments so colours don't leak.
  let tokStyle = Style(
    fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: modifiers
  )
  let newTok = SemanticOverlayToken(
    firstColumn: col, length: length, color: color, style: tokStyle
  )
  if not overlay.hasKey(row):
    overlay[row] = SemanticOverlayLine(tokens: @[newTok])
    return

  let prior = overlay[row].tokens
  # Fast path: LSP delta encoding is monotonically increasing per row, so most
  # additions land past the last token with no overlap. Skip the rebuild.
  if prior.len == 0 or prior[^1].firstColumn + prior[^1].length <= col:
    overlay[row].tokens.add(newTok)
    return

  # Slow path: rebuild the row. A back-walk cannot correctly handle the case
  # where an inner prior (e.g. a single-line token nested inside a multi-line
  # wrap's carved-out tail) extends past `newEnd` at the same time as a
  # further-right prior — the tail's colour must come from the inner prior at
  # position `newEnd`, not from the outermost prior that gets walked first.
  let newEnd = col + length
  var newTokens: seq[SemanticOverlayToken] = @[]
  var inserted = false
  for t in prior:
    let tEnd = t.firstColumn + t.length
    if tEnd <= col:
      # Entirely before the new token; keep intact.
      newTokens.add(t)
      continue
    if t.firstColumn >= newEnd:
      # Entirely past the new token; keep intact, insert new token before it.
      if not inserted:
        newTokens.add(newTok)
        inserted = true
      newTokens.add(t)
      continue
    # Overlaps: split into head (kept), overlap (replaced), tail (kept).
    if t.firstColumn < col:
      newTokens.add(
        SemanticOverlayToken(
          firstColumn: t.firstColumn,
          length: col - t.firstColumn,
          color: t.color,
          style: t.style,
        )
      )
    if not inserted:
      newTokens.add(newTok)
      inserted = true
    if tEnd > newEnd:
      newTokens.add(
        SemanticOverlayToken(
          firstColumn: newEnd, length: tEnd - newEnd, color: t.color, style: t.style
        )
      )
  if not inserted:
    newTokens.add(newTok)
  overlay[row].tokens = newTokens

proc applySemanticTokens*(
    highlight: Highlight,
    resp: JsonNode,
    colorTab: SemanticTypeColorTable,
    contentVersion: int,
    getLineRuneCount: LineRuneCountFn = nil,
    updateFirstRow: int = -1,
    updateLastRow: int = -1,
    getLineText: LineTextFn = nil,
): SemanticApplyOutcome =
  ## Build a semantic overlay from an LSP `textDocument/semanticTokens` response
  ## and swap it into `highlight.semantic`. Never touches `colorSegments`.
  ##
  ## `updateFirstRow`/`updateLastRow`: when non-negative, the response is
  ## treated as authoritative over that inclusive row range only; entries on
  ## rows outside the range are preserved from prior responses. Use for
  ## `semanticTokens/range` replies. Leave at `-1` for a full-document reply
  ## (full replace).
  if resp.isNil or resp.kind != JObject or not resp.hasKey("data"):
    return saoRejectedMalformed
  let dataNode = resp["data"]
  if dataNode.kind != JArray:
    return saoRejectedMalformed

  # Range apply requires BOTH bounds set; a partial pair (one -1, one >=0)
  # is a caller bug that used to be silently treated as full-doc replace.
  # An inverted range (first > last) is likewise a caller bug — it would
  # silently no-op (empty Nim slice iteration + filter-none merge) and the
  # caller would stamp the cache as valid.
  if (updateFirstRow < 0) != (updateLastRow < 0):
    return saoRejectedMalformed
  if updateFirstRow >= 0 and updateFirstRow > updateLastRow:
    return saoRejectedMalformed

  # No legend means we cannot trust ANY server assertion for this stream,
  # including "empty" replies. Check BEFORE the mod-5/cap branches so the
  # actionable "legend not yet available" outcome is not shadowed by a
  # simultaneously malformed-length response.
  if colorTab.baseColors.len == 0:
    return saoRejectedNoLegend

  let dataLen = dataNode.len
  if dataLen mod 5 != 0:
    return saoRejectedMalformed
  if dataLen > MaxSemanticTokens * 5:
    return saoRejectedCap
  # Deferred legend-swap: a server dynamically re-registered with a different
  # legend invalidates every existing overlay entry (their stored colour was
  # resolved against the prior legend). Compute the intent up front but only
  # apply it AFTER parsing succeeds, so a mid-parse malformed byte does not
  # wipe the prior overlay across the whole buffer.
  # Only fire on a real legend change (both sides non-empty).
  let needsLegendWipe =
    highlight.semantic.len > 0 and colorTab.legend.tokenTypes.len > 0 and
    highlight.semanticLegend.tokenTypes.len > 0 and
    highlight.semanticLegend != colorTab.legend
  if dataLen == 0:
    # Empty range reply = "no tokens in this range"; clear just that range.
    if needsLegendWipe:
      highlight.semantic.clear()
      highlight.semanticContentVersion = -1
    highlight.semanticLegend = colorTab.legend
    if updateFirstRow >= 0 and updateLastRow >= 0:
      discard deleteRowsInRange(highlight.semantic, updateFirstRow, updateLastRow)
      # Range reply: rows outside the range retain their prior stamp, so
      # advance semanticContentVersion only when the overlay is empty (no
      # older rows survive to be mis-labelled as fresh).
      if highlight.semantic.len == 0:
        highlight.semanticContentVersion = contentVersion
    else:
      # Full-doc empty reply = "no tokens in this document" per LSP spec.
      # Clearing the whole overlay honours that; the earlier design that
      # preserved it left ghost tokens visible after config changes /
      # semantic-tokens teardown.
      highlight.semantic.clear()
      highlight.semanticContentVersion = contentVersion
    return saoDone

  var overlay = initTable[int, SemanticOverlayLine]()
  var currentLine = 0
  var currentChar = 0
  var i = 0
  # Per-row memoization for `getLineText`. Clustered tokens (dozens per row is
  # typical) would otherwise fetch and re-walk the same line's text once per
  # token; cache it across adjacent tokens on the same row.
  var cachedTextRow = -1
  var cachedText = ""

  while i < dataLen:
    # Non-JInt entries would getInt-fallthrough to 0 and corrupt the delta
    # chain silently.
    if dataNode[i].kind != JInt or dataNode[i + 1].kind != JInt or
        dataNode[i + 2].kind != JInt or dataNode[i + 3].kind != JInt or
        dataNode[i + 4].kind != JInt:
      return saoRejectedMalformed
    let deltaLine = dataNode[i].getInt
    let deltaStart = dataNode[i + 1].getInt
    let length = dataNode[i + 2].getInt
    let tokenType = dataNode[i + 3].getInt
    let tokenModifiers = dataNode[i + 4].getInt
    i += 5

    # LSP spec: deltaLine/deltaStart/length/tokenModifiers are uinteger. A
    # negative from a buggy server would silently corrupt the delta chain or
    # poison the (type,mods) cache; reject the whole response so the caller
    # can retry cleanly instead of painting a scrambled overlay. Also reject
    # tokenModifiers above uint32 so the (type<<32)|mods cache key cannot
    # silently collide (LSP spec caps at uint32; would need >=33 modifiers
    # in a legend, but the truncation would be silent).
    if deltaLine < 0 or deltaStart < 0 or tokenModifiers < 0 or
        tokenModifiers > int(high(uint32)):
      return saoRejectedMalformed

    if deltaLine > 0:
      currentLine += deltaLine
      currentChar = deltaStart
    else:
      currentChar += deltaStart

    if length <= 0 or currentLine < 0 or currentChar < 0:
      continue
    # Range-scoped reply: `deltaLine` is monotonically non-negative per LSP
    # spec, so once `currentLine` passes `updateLastRow` no later token can
    # land inside the range. Break early to skip utf16 conversion +
    # resolveTokenColor + addOverlayToken for the tail.
    if updateLastRow >= 0 and currentLine > updateLastRow:
      break
    let (color, style) = resolveTokenColor(colorTab, tokenType, tokenModifiers)
    if color == EditorColorPairIndex.default and style == {}:
      continue

    # LSP positions are UTF-16 code units by default (positionEncoding); the
    # overlay stores rune indices. Convert per-row so wrap rows with non-BMP
    # runes are counted correctly.
    var applyCol = currentChar
    var startRowRunes = length # rune count for the start row's portion
    var utf16Remaining = 0 # UTF-16 units left to distribute over wrap rows
    if getLineText != nil:
      if cachedTextRow != currentLine:
        cachedText = getLineText(currentLine)
        cachedTextRow = currentLine
      let (startRune, _) = utf16OffsetToRune(cachedText, currentChar)
      let (endRune, endUtf16Walked) =
        utf16OffsetToRune(cachedText, currentChar + length)
      applyCol = startRune
      startRowRunes = endRune - startRune
      utf16Remaining = max(0, (currentChar + length) - endUtf16Walked)

    if getLineRuneCount == nil:
      # No splitter callback: paint only the start-row portion. Stamping a
      # phantom oversized overlay entry pinned to `currentLine` would violate
      # the SemanticOverlayLine invariant.
      overlay.addOverlayToken(currentLine, applyCol, startRowRunes, color, style)
    else:
      # Multi-line token split; buffer-end break bounds the loop.
      # Range-scoped replies: the splitter stops at `updateLastRow`; rows past
      # the request range would be dropped by the merge below, so unrolling
      # into them is wasted work AND would risk stomping a subsequent same-row
      # token via `addOverlayToken`'s truncation.
      let firstRowLen = getLineRuneCount(currentLine)
      # Drop stale-position tokens whose start is at or past current EOL.
      # `>=` (not `>`) so a token starting exactly at EOL is dropped instead
      # of spilling onto the next row with a wrong colour.
      if firstRowLen < 0 or applyCol >= firstRowLen:
        continue
      # If the token starts outside a range apply, drop it entirely.
      if updateLastRow >= 0 and currentLine > updateLastRow:
        continue

      # Paint the start row (rune-based split when no getLineText; else the
      # UTF-16-derived rune count clipped to the row).
      let startAvail = max(0, firstRowLen - applyCol)
      var startPaint = min(startRowRunes, startAvail)
      var runeOverflow = 0
      if getLineText == nil:
        # Positions treated as runes: split the total length rune-by-rune.
        if length <= startAvail:
          overlay.addOverlayToken(currentLine, applyCol, length, color, style)
          continue
        startPaint = startAvail
        runeOverflow = length - startAvail
      overlay.addOverlayToken(currentLine, applyCol, startPaint, color, style)
      if utf16Remaining == 0 and runeOverflow == 0:
        continue

      # Wrap rows: distribute the UTF-16 remainder precisely when getLineText
      # is wired, else fall back to rune-based distribution.
      var row = currentLine + 1
      while utf16Remaining > 0 or runeOverflow > 0:
        if updateLastRow >= 0 and row > updateLastRow:
          break
        let rowLen = getLineRuneCount(row)
        if rowLen < 0:
          break
        if getLineText != nil:
          # Convert this row's UTF-16 length once, then consume up to it.
          let rowText = getLineText(row)
          let (rowRunes, rowUtf16) = utf16OffsetToRune(rowText, high(int32))
          if utf16Remaining >= rowUtf16:
            if rowRunes > 0:
              overlay.addOverlayToken(row, 0, rowRunes, color, style)
            utf16Remaining -= rowUtf16
            inc row
          else:
            let (partialRunes, _) = utf16OffsetToRune(rowText, utf16Remaining)
            if partialRunes > 0:
              overlay.addOverlayToken(row, 0, partialRunes, color, style)
            utf16Remaining = 0
        else:
          if rowLen == 0:
            inc row
            continue
          if runeOverflow <= rowLen:
            overlay.addOverlayToken(row, 0, runeOverflow, color, style)
            runeOverflow = 0
          else:
            overlay.addOverlayToken(row, 0, rowLen, color, style)
            runeOverflow -= rowLen
            inc row

  # LSP delta encoding is monotonically increasing per row (deltaLine and
  # deltaStart are uinteger by spec), so tokens land in order without a sort.

  # Parse succeeded: now apply the deferred legend-swap wipe and legend
  # adoption, so a rejected parse above leaves the prior overlay intact.
  if needsLegendWipe:
    highlight.semantic.clear()
    highlight.semanticContentVersion = -1
  highlight.semanticLegend = colorTab.legend

  if updateFirstRow < 0 or updateLastRow < 0:
    # Full-doc reply: every row is fresh at this contentVersion. `swap` avoids
    # copying every bucket + per-row token seq that `=` would incur.
    swap(highlight.semantic, overlay)
    highlight.semanticContentVersion = contentVersion
  else:
    # Range reply: drop existing entries in the request range, then merge.
    # `deleteRowsInRange` also tells us if any outside-range rows survived
    # (their older resolved colours must keep the older stamp).
    let (_, outsideRows) =
      deleteRowsInRange(highlight.semantic, updateFirstRow, updateLastRow)
    for row, line in overlay.pairs:
      if row >= updateFirstRow and row <= updateLastRow:
        highlight.semantic[row] = line
    if outsideRows == 0:
      highlight.semanticContentVersion = contentVersion
  return saoDone
