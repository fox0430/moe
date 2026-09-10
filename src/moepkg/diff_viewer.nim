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

## Diff Viewer module
## Provides a UI for viewing diffs between files

import std/[algorithm, osproc, strutils, os, unicode]

import pkg/results

import celina_backend as celina

import buffer/core, color, highlight, list_viewer
import syntax/tokenizer
import types/diff_viewer_types
import unicode_utils

export diff_viewer_types
export list_viewer

const SideBySideSeparator* = " │ "
  ## Column separator for side-by-side rendering (display width 3).

const MinSidePanelWidth* = 20
  ## Narrowest panel that still shows useful code. The viewer usually opens in
  ## a vertical split, so the budget is about half the terminal.

const SideBySideMinWidth* = MinSidePanelWidth * 2 + 3
  ## Text-area width below which side-by-side falls back to unified rendering.
  ## `+ 3` is the display width of `SideBySideSeparator`.

const MaxWordDiffTokens* = 300
  ## Word-diff LCS is O(N*M); skip it beyond this token count.

const MaxWordDiffRows* = 2000
  ## Whole-diff budget for the per-pair word diff. The other caps bound a
  ## single comparison, this one their total count.

const MaxWordDiffLineLength* = 4096
  ## Skip the word diff when either side is longer than this many bytes.
  ## Checked before tokenizing, so a minified line is rejected up front.

const DefaultDiffTabStop* = 2
  ## Fallback tab width for side-by-side rows; production callers pass
  ## e.tabStop.

const MaxSyntaxHighlightFileSize* = 512 * 1024
  ## Skip side-by-side syntax highlighting above this file size. Tokenizing
  ## runs synchronously in the frame that first shows two columns.

const MaxSyntaxHighlightLines* = 5_000
  ## Line-count companion to `MaxSyntaxHighlightFileSize`: many short lines are
  ## cheap to read but not to tokenize.

proc newDiffViewerState*(): DiffViewerState =
  DiffViewerState(
    items: @[],
    selectedIndex: 0,
    sourceFilePath: "",
    backupFilePath: "",
    errorMessage: "",
    viewMode: dvmUnified,
    wordHighlight: true,
    sideRows: @[],
    sideRowsWordHighlight: false,
    unifiedWordRanges: @[],
    renderedSideBySide: false,
    renderedWidth: 0,
    tabStop: DefaultDiffTabStop,
    syntaxComputed: false,
  )

proc classifyDiffLine(line: string): DiffLineKind =
  ## Classify a diff line based on its content
  if line.len == 0:
    return dlkNormal

  if line.startsWith("@@"):
    return dlkHeader
  elif line.startsWith("---") or line.startsWith("+++"):
    return dlkHeader
  elif line.startsWith("diff ") or line.startsWith("index ") or
      line.startsWith("new file") or line.startsWith("deleted file"):
    return dlkMeta
  elif line[0] == '+':
    return dlkAdded
  elif line[0] == '-':
    return dlkDeleted
  else:
    return dlkNormal

proc initDiffViewerBuffer*(
    sourceFilePath, backupFilePath: string
): Result[seq[DiffLine], string] =
  ## Generate diff between source file and backup file
  ## Uses the system `diff -u` command
  ##
  ## Note: Arguments order is (sourceFilePath, backupFilePath)
  ## This means: diff shows changes FROM backup TO source
  ## - Lines starting with '-' are in backup but not in source (removed)
  ## - Lines starting with '+' are in source but not in backup (added)
  let cmdResult = execCmdEx(
    "diff -u " & quoteShell(backupFilePath) & " " & quoteShell(sourceFilePath)
  )

  # diff command exit codes:
  # 0 = no differences
  # 1 = differences found
  # 2 = error (e.g., file not found)
  if cmdResult.exitCode == 2:
    return Result[seq[DiffLine], string].err "diff command failed: " & cmdResult.output

  var lines: seq[DiffLine] = @[]

  if cmdResult.output.len == 0:
    # No differences
    lines.add(DiffLine(text: "(No differences)", kind: dlkNormal))
  else:
    # `diff -u` opens with exactly one `---`/`+++` pair. Content lines
    # starting the same way (Lua comments, `++x`) are not headers, so only
    # the first pair is classified as one.
    var fileHeaders = 0
    for line in cmdResult.output.splitLines:
      var kind = classifyDiffLine(line)
      if kind == dlkHeader and not line.startsWith("@@"):
        if fileHeaders < 2:
          inc fileHeaders
        else:
          kind = if line[0] == '-': dlkDeleted else: dlkAdded
      lines.add(DiffLine(text: line, kind: kind))

  if lines.len > 1 and lines[^1].text.len == 0:
    # Rmove the last empty line
    return Result[seq[DiffLine], string].ok lines[0 .. lines.high - 1]

  return Result[seq[DiffLine], string].ok lines

proc parseHunkHeader*(line: string): tuple[oldStart, newStart: int, ok: bool] =
  ## Parse "@@ -oldStart[,oldCount] +newStart[,newCount] @@" into 1-based
  ## start lines. Returns ok=false when the line is not a hunk header.
  result = (1, 1, false)
  if not line.startsWith("@@"):
    return
  try:
    let rest = line[2 .. ^1].strip
    let parts = strutils.splitWhitespace(rest)
    if parts.len < 2:
      return
    let oldPart = parts[0]
    let newPart = parts[1]
    if oldPart.len < 2 or oldPart[0] != '-' or newPart.len < 2 or newPart[0] != '+':
      return
    let oldNums = oldPart[1 .. ^1].split(',')
    let newNums = newPart[1 .. ^1].split(',')
    result.oldStart = parseInt(oldNums[0])
    result.newStart = parseInt(newNums[0])
    result.ok = true
  except ValueError:
    result.ok = false

proc stripDiffPrefix*(line: string): string =
  ## Remove the leading unified-diff marker (' ', '+', '-') if present.
  if line.len > 0 and line[0] in {' ', '+', '-'}:
    line[1 .. ^1]
  else:
    line

proc expandTabsForDiff*(s: string, tabStop: int): string =
  ## Expand tabs to spaces with the same rule as the renderer, so the
  ## separator column stays aligned on rows containing tabs. Other characters
  ## are copied byte-exact so word-diff columns keep matching the text.
  let safeTabStop = if tabStop > 0: tabStop else: 1
  result = newStringOfCap(s.len)
  var displayX = 0
  var bytePos = 0
  for (r, size) in s.chars:
    if r == Rune(0x09):
      let spaces = safeTabStop - (displayX mod safeTabStop)
      for _ in 0 ..< spaces:
        result.add(' ')
      displayX += spaces
    else:
      result.add(s[bytePos ..< bytePos + size])
      displayX += r.charWidth
    bytePos += size

type WordToken = tuple[text: string, startCol, endCol: int]

proc tokenizeWordsWithPos*(s: string): seq[WordToken] =
  ## Split `s` into non-whitespace words with half-open char ranges.
  ## Punctuation stays inside words, so `foo(bar)` is one token.
  var i = 0 # byte offset
  var col = 0 # char offset
  let n = s.len
  while i < n:
    let (r, size) = s.charAtByte(i)
    if r.isWhiteSpace:
      i += size
      col += 1
      continue
    let startByte = i
    let startCol = col
    while i < n:
      let (r2, s2) = s.charAtByte(i)
      if r2.isWhiteSpace:
        break
      i += s2
      col += 1
    result.add((s[startByte ..< i], startCol, col))

proc computeWordRanges*(
    oldLine, newLine: string
): tuple[oldRanges, newRanges: seq[ColumnRange]] =
  ## Word-level diff between two lines via LCS over whitespace-split words.
  ## Returns half-open char ranges of changed words on each side.
  ## Identical lines yield empty ranges; oversized inputs are skipped.
  result = (@[], @[])
  if oldLine == newLine:
    return
  if oldLine.len > MaxWordDiffLineLength or newLine.len > MaxWordDiffLineLength:
    # Mark both sides fully changed rather than tokenizing a minified line.
    result.oldRanges.add(ColumnRange(startCol: 0, endCol: oldLine.charLen))
    result.newRanges.add(ColumnRange(startCol: 0, endCol: newLine.charLen))
    return
  let oldToks = tokenizeWordsWithPos(oldLine)
  let newToks = tokenizeWordsWithPos(newLine)
  if oldToks.len == 0 or newToks.len == 0:
    # Nothing to pair against, so mark whatever text each side has.
    # Whitespace-only sides still differ here (re-indentation).
    if oldLine.charLen > 0:
      result.oldRanges.add(ColumnRange(startCol: 0, endCol: oldLine.charLen))
    if newLine.charLen > 0:
      result.newRanges.add(ColumnRange(startCol: 0, endCol: newLine.charLen))
    return
  if max(oldToks.len, newToks.len) > MaxWordDiffTokens:
    result.oldRanges.add(ColumnRange(startCol: 0, endCol: oldLine.charLen))
    result.newRanges.add(ColumnRange(startCol: 0, endCol: newLine.charLen))
    return

  let m = oldToks.len
  let n = newToks.len
  # LCS length table (m+1) x (n+1).
  var dp = newSeq[int]((m + 1) * (n + 1))
  template at(i, j: int): int =
    dp[i * (n + 1) + j]

  template setAt(i, j, v: int) =
    dp[i * (n + 1) + j] = v

  for i in countdown(m - 1, 0):
    for j in countdown(n - 1, 0):
      if oldToks[i].text == newToks[j].text:
        setAt(i, j, at(i + 1, j + 1) + 1)
      else:
        setAt(i, j, max(at(i + 1, j), at(i, j + 1)))

  # Walk back to collect unchanged pairs; the rest is changed.
  var oldKept = newSeq[bool](m)
  var newKept = newSeq[bool](n)
  var i = 0
  var j = 0
  while i < m and j < n:
    if oldToks[i].text == newToks[j].text:
      oldKept[i] = true
      newKept[j] = true
      inc i
      inc j
    elif at(i + 1, j) >= at(i, j + 1):
      inc i
    else:
      inc j

  for k in 0 ..< m:
    if not oldKept[k]:
      result.oldRanges.add(
        ColumnRange(startCol: oldToks[k].startCol, endCol: oldToks[k].endCol)
      )
  for k in 0 ..< n:
    if not newKept[k]:
      result.newRanges.add(
        ColumnRange(startCol: newToks[k].startCol, endCol: newToks[k].endCol)
      )

  # Merge adjacent ranges separated only by whitespace into one so
  # `foo bar` -> `foo baz` highlights a single span per side.
  proc mergeAdjacent(ranges: seq[ColumnRange]): seq[ColumnRange] =
    if ranges.len <= 1:
      return ranges
    result.add(ranges[0])
    for k in 1 ..< ranges.len:
      if ranges[k].startCol <= result[^1].endCol + 1:
        result[^1].endCol = max(result[^1].endCol, ranges[k].endCol)
      else:
        result.add(ranges[k])

  result.oldRanges = mergeAdjacent(result.oldRanges)
  result.newRanges = mergeAdjacent(result.newRanges)

proc buildSideBySideRows*(
    items: seq[DiffLine], tabStop: int = DefaultDiffTabStop, wordHighlight: bool = true
): seq[SideBySideRow] =
  ## Align unified-diff `items` into paired side-by-side rows.
  ## Deleted/added blocks are paired positionally; leftovers become filler
  ## rows on one side. The per-pair word diff runs only when `wordHighlight`
  ## asks for it, for the first `MaxWordDiffRows` pairs.
  if items.len == 1 and items[0].text == "(No differences)":
    return @[
      SideBySideRow(
        kind: sbrEmpty,
        headerText: "(No differences)",
        oldLineNo: -1,
        newLineNo: -1,
        sourceIndex: 0,
      )
    ]
  if items.len == 1 and items[0].text.startsWith("Error:"):
    return @[
      SideBySideRow(
        kind: sbrMeta,
        headerText: items[0].text,
        oldLineNo: -1,
        newLineNo: -1,
        sourceIndex: 0,
      )
    ]

  var oldLineNo = 1
  var newLineNo = 1
  var inHunk = false
  var delBuf: seq[string] = @[]
  var addBuf: seq[string] = @[]
  var delIdx: seq[int] = @[]
  var addIdx: seq[int] = @[]
  var wordDiffBudget = if wordHighlight: MaxWordDiffRows else: 0

  proc flushBuffers(
      rows: var seq[SideBySideRow],
      delBuf: var seq[string],
      addBuf: var seq[string],
      delIdx: var seq[int],
      addIdx: var seq[int],
      oldLineNo: var int,
      newLineNo: var int,
  ) =
    let
      pairCount = min(delBuf.len, addBuf.len)
      blockStart = rows.len
    for k in 0 ..< pairCount:
      var oldRanges, newRanges: seq[ColumnRange] = @[]
      if wordDiffBudget > 0:
        dec wordDiffBudget
        (oldRanges, newRanges) = computeWordRanges(delBuf[k], addBuf[k])
      rows.add(
        SideBySideRow(
          kind: sbrChanged,
          leftText: delBuf[k],
          rightText: addBuf[k],
          sourceIndex: delIdx[k],
          leftWordRanges: oldRanges,
          rightWordRanges: newRanges,
        )
      )
    for k in pairCount ..< delBuf.len:
      rows.add(
        SideBySideRow(
          kind: sbrDeleted, leftText: delBuf[k], rightText: "", sourceIndex: delIdx[k]
        )
      )
    for k in pairCount ..< addBuf.len:
      rows.add(
        SideBySideRow(
          kind: sbrAdded, leftText: "", rightText: addBuf[k], sourceIndex: addIdx[k]
        )
      )
    # A block whose `+` lines precede its `-` lines emits a descending
    # `sourceIndex`. Restore the order the selection mapping needs.
    var ordered = true
    for i in blockStart + 1 ..< rows.len:
      if rows[i].sourceIndex < rows[i - 1].sourceIndex:
        ordered = false
        break
    if not ordered:
      var blockRows = rows[blockStart .. ^1]
      blockRows.sort(
        proc(a, b: SideBySideRow): int =
          cmp(a.sourceIndex, b.sourceIndex)
      )
      rows.setLen(blockStart)
      rows.add(blockRows)
    # Number the block only once it is in source order, otherwise the numbers
    # come out shuffled.
    for i in blockStart ..< rows.len:
      case rows[i].kind
      of sbrChanged:
        rows[i].oldLineNo = oldLineNo
        rows[i].newLineNo = newLineNo
        inc oldLineNo
        inc newLineNo
      of sbrDeleted:
        rows[i].oldLineNo = oldLineNo
        rows[i].newLineNo = -1
        inc oldLineNo
      of sbrAdded:
        rows[i].oldLineNo = -1
        rows[i].newLineNo = newLineNo
        inc newLineNo
      else:
        discard
    delBuf.setLen(0)
    addBuf.setLen(0)
    delIdx.setLen(0)
    addIdx.setLen(0)

  for itemIdx, item in items:
    let t = item.text
    case item.kind
    of dlkMeta:
      flushBuffers(result, delBuf, addBuf, delIdx, addIdx, oldLineNo, newLineNo)
      result.add(
        SideBySideRow(
          kind: sbrMeta,
          headerText: t,
          oldLineNo: -1,
          newLineNo: -1,
          sourceIndex: itemIdx,
        )
      )
    of dlkHeader:
      if t.startsWith("@@"):
        flushBuffers(result, delBuf, addBuf, delIdx, addIdx, oldLineNo, newLineNo)
        let h = parseHunkHeader(t)
        if h.ok:
          oldLineNo = h.oldStart
          newLineNo = h.newStart
          inHunk = true
        result.add(
          SideBySideRow(
            kind: sbrHeader,
            headerText: t,
            oldLineNo: -1,
            newLineNo: -1,
            sourceIndex: itemIdx,
          )
        )
      else:
        # ---/+++ file headers span both columns.
        flushBuffers(result, delBuf, addBuf, delIdx, addIdx, oldLineNo, newLineNo)
        result.add(
          SideBySideRow(
            kind: sbrMeta,
            headerText: t,
            oldLineNo: -1,
            newLineNo: -1,
            sourceIndex: itemIdx,
          )
        )
    of dlkDeleted:
      delBuf.add(expandTabsForDiff(stripDiffPrefix(t), tabStop))
      delIdx.add(itemIdx)
    of dlkAdded:
      addBuf.add(expandTabsForDiff(stripDiffPrefix(t), tabStop))
      addIdx.add(itemIdx)
    of dlkNormal:
      if t.startsWith("\\"):
        # "\ No newline at end of file" annotates the line before it, so
        # flushing here would break that block's pairing.
        discard
      else:
        flushBuffers(result, delBuf, addBuf, delIdx, addIdx, oldLineNo, newLineNo)
        let content = expandTabsForDiff(stripDiffPrefix(t), tabStop)
        if inHunk or (oldLineNo > 1 or newLineNo > 1):
          result.add(
            SideBySideRow(
              kind: sbrContext,
              leftText: content,
              rightText: content,
              oldLineNo: oldLineNo,
              newLineNo: newLineNo,
              sourceIndex: itemIdx,
            )
          )
          inc oldLineNo
          inc newLineNo
        else:
          # Outside any hunk, so it belongs to neither side ("Binary files
          # ... differ"). Span both columns instead of truncating it twice.
          result.add(
            SideBySideRow(
              kind: sbrMeta,
              headerText: t,
              oldLineNo: -1,
              newLineNo: -1,
              sourceIndex: itemIdx,
            )
          )
  flushBuffers(result, delBuf, addBuf, delIdx, addIdx, oldLineNo, newLineNo)

proc buildFileHighlight(
    path: string, language: SourceLanguage, tabStop: int
): Highlight =
  ## Tokenize the whole file so side-by-side rows get their real syntax
  ## colors. Returns nil when the file cannot be used.
  if language == langNone or path.len == 0:
    return nil
  try:
    if not fileExists(path) or getFileSize(path) > MaxSyntaxHighlightFileSize:
      return nil
    var lines: seq[string] = @[]
    for line in readFile(path).splitLines:
      lines.add(expandTabsForDiff(line, tabStop))
    if lines.len == 0 or lines.len > MaxSyntaxHighlightLines:
      return nil
    let (segments, _) = initHighlightIncremental(
      lines,
      0,
      lines.high,
      TokenizerState(),
      @[],
      language,
      DefaultMaxHighlightLineLength,
    )
    return Highlight(colorSegments: segments)
  except CatchableError:
    return nil

proc syntaxSpansForLine(highlight: Highlight, line, charLen: int): seq[SideSyntaxSpan] =
  ## Extract one line's syntax colors as sorted half-open char-column spans.
  if highlight.isNil or charLen <= 0:
    return @[]
  for col in 0 ..< charLen:
    let color = highlight.getColorPair(line, col)
    if result.len > 0 and result[^1].color == color and result[^1].endCol == col:
      result[^1].endCol = col + 1
    else:
      result.add(SideSyntaxSpan(startCol: col, endCol: col + 1, color: color))

proc ensureSideSyntax*(state: DiffViewerState) =
  ## Attach per-row syntax colors once. Called lazily so the unified view
  ## never pays for it.
  if state.syntaxComputed:
    return
  state.syntaxComputed = true
  if state.sideRows.len == 0:
    return
  var hasContent = false
  for row in state.sideRows:
    if row.oldLineNo > 0 or row.newLineNo > 0:
      hasContent = true
      break
  if not hasContent:
    return
  let language = block:
    let sourceLanguage = detectLanguage(state.sourceFilePath)
    if sourceLanguage != langNone:
      sourceLanguage
    else:
      detectLanguage(state.backupFilePath)
  if language == langNone:
    return
  let oldHighlight = buildFileHighlight(state.backupFilePath, language, state.tabStop)
  let newHighlight = buildFileHighlight(state.sourceFilePath, language, state.tabStop)
  if oldHighlight.isNil and newHighlight.isNil:
    return
  for row in state.sideRows.mitems:
    if not oldHighlight.isNil and row.oldLineNo > 0:
      row.leftSyntax =
        syntaxSpansForLine(oldHighlight, row.oldLineNo - 1, row.leftText.charLen)
    if not newHighlight.isNil and row.newLineNo > 0:
      row.rightSyntax =
        syntaxSpansForLine(newHighlight, row.newLineNo - 1, row.rightText.charLen)

proc rebuildSideRows*(state: DiffViewerState, tabStop: int = DefaultDiffTabStop) =
  ## Rebuild the aligned side-by-side rows from the unified items. Syntax
  ## colors are computed lazily by `ensureSideSyntax` on first display.
  state.sideRows = buildSideBySideRows(state.items, tabStop, state.wordHighlight)
  state.sideRowsWordHighlight = state.wordHighlight
  state.tabStop = tabStop
  state.syntaxComputed = false

proc ensureSideRows*(state: DiffViewerState) =
  ## Build the aligned rows on first use, so opening a diff in the default
  ## unified view does not pay for the pairing and the word diff.
  if state.sideRows.len == 0:
    state.rebuildSideRows(state.tabStop)

proc initDiffViewerState*(
    sourceFilePath: string,
    backupFilePath: string,
    viewMode: DiffViewMode = dvmUnified,
    wordHighlight: bool = true,
    tabStop: int = DefaultDiffTabStop,
): DiffViewerState =
  ## Initialize diff viewer state for comparing two files
  result = newDiffViewerState()
  result.sourceFilePath = sourceFilePath
  result.backupFilePath = backupFilePath
  result.viewMode = viewMode
  result.wordHighlight = wordHighlight

  let diffResult = initDiffViewerBuffer(sourceFilePath, backupFilePath)
  if diffResult.isOk:
    result.items = diffResult.get
  else:
    result.errorMessage = diffResult.error
    result.items = @[DiffLine(text: "Error: " & diffResult.error, kind: dlkNormal)]
  result.tabStop = tabStop

proc sideRowForItem*(state: DiffViewerState, itemIndex: int): int =
  ## Side-by-side row showing unified item `itemIndex`. Items with no row of
  ## their own (a "\ No newline" marker) map to the row before them.
  state.ensureSideRows()
  if state.sideRows.len == 0:
    return 0
  var
    lo = 0
    hi = state.sideRows.high
  while lo <= hi:
    let mid = (lo + hi) div 2
    if state.sideRows[mid].sourceIndex <= itemIndex:
      result = mid
      lo = mid + 1
    else:
      hi = mid - 1

proc itemForSideRow*(state: DiffViewerState, rowIndex: int): int =
  ## Unified item shown by side-by-side row `rowIndex`. A changed row pairs
  ## two items; the deleted one is where the unified view puts the cursor.
  state.ensureSideRows()
  if state.sideRows.len == 0 or state.items.len == 0:
    return 0
  let row = state.sideRows[clamp(rowIndex, 0, state.sideRows.high)]
  clamp(row.sourceIndex, 0, state.items.high)

proc toggleViewMode*(state: DiffViewerState) =
  ## Switch the requested presentation. The width fallback and the selection
  ## remap happen in `refreshDiffTextBuffer`, which the caller runs after.
  state.viewMode = if state.viewMode == dvmUnified: dvmSideBySide else: dvmUnified

proc toggleWordHighlight*(state: DiffViewerState) =
  state.wordHighlight = not state.wordHighlight
  if state.wordHighlight and not state.sideRowsWordHighlight:
    # Aligned without the word diff; drop them so the next use rebuilds
    # with the ranges the highlight needs.
    state.sideRows = @[]

proc isSideBySide*(state: DiffViewerState): bool =
  state.viewMode == dvmSideBySide

const SideTruncationMarker* = "…"
  ## Marks a cut-off panel. The view never wraps or scrolls horizontally, so
  ## without it the cut is invisible.

proc padOrTruncateSide*(s: string, width: int): string =
  ## Fit `s` to exactly `width` display columns: truncate with
  ## `SideTruncationMarker` when too wide, pad with spaces when too narrow.
  if width <= 0:
    return ""
  let truncated =
    if s.charDisplayWidth > width:
      s.truncateToWidthWithSuffix(width, SideTruncationMarker)
    else:
      s
  truncated.alignLeftDisplay(width)

proc formatSideBySideLine*(
    row: SideBySideRow, leftWidth: int, rightWidth: int = -1
): string =
  ## Format one aligned row as "left │ right". Panels are padded so the diff
  ## backgrounds cover the whole row; `rightWidth < 0` falls back to
  ## `leftWidth`. Header/meta/empty rows span as-is.
  let rightPanelWidth = if rightWidth >= 0: rightWidth else: leftWidth
  case row.kind
  of sbrHeader, sbrMeta, sbrEmpty:
    row.headerText
  else:
    row.leftText.padOrTruncateSide(leftWidth) & SideBySideSeparator &
      row.rightText.padOrTruncateSide(rightPanelWidth)

proc sidePanelWidth*(totalWidth: int): int {.inline.} =
  ## Left-panel display width for a given total width.
  max(10, (totalWidth - SideBySideSeparator.charDisplayWidth) div 2)

proc syntaxColorAt(
    spans: seq[SideSyntaxSpan], col: int, fallback: EditorColorPairIndex
): EditorColorPairIndex =
  ## Color of `col` from `spans` (sorted, non-overlapping char ranges).
  var
    lo = 0
    hi = spans.high
  while lo <= hi:
    let mid = (lo + hi) div 2
    if spans[mid].startCol <= col:
      if col < spans[mid].endCol:
        return spans[mid].color
      lo = mid + 1
    else:
      hi = mid - 1
  fallback

proc inColumnRanges(ranges: seq[ColumnRange], col: int): bool =
  for r in ranges:
    if col >= r.startCol and col < r.endCol:
      return true
  false

const DefaultBg = ColorValue(kind: Default)

proc diffBackgroundStyle(bg: ColorValue): Style =
  ## Style carrying only the diff background, so the segment's color pair
  ## keeps the syntax foreground.
  if bg == DefaultBg:
    Style()
  else:
    Style(bg: bg)

proc bgSegment(rowIdx, firstColumn, lastColumn: int, bg: ColorValue): ColorSegment =
  ## Single default-foreground segment carrying a diff background.
  ColorSegment(
    firstRow: rowIdx,
    firstColumn: firstColumn,
    lastRow: rowIdx,
    lastColumn: lastColumn,
    color: EditorColorPairIndex.default,
    style: diffBackgroundStyle(bg),
  )

proc appendPanelSegments(
    segments: var seq[ColorSegment],
    rowIdx, panelStart, panelLen, textLen: int,
    syntax: seq[SideSyntaxSpan],
    baseColor: EditorColorPairIndex,
    lineBg, wordBg: ColorValue,
    wordRanges: seq[ColumnRange],
) =
  ## Emit contiguous segments covering `panelLen` columns from `panelStart`.
  ## Columns past `textLen` are padding: `lineBg` but no syntax color.
  if panelLen <= 0:
    return
  let
    useLineBg = lineBg.kind != Default
    useWordBg = wordBg.kind != Default
  var
    runStart = 0
    runColor = EditorColorPairIndex.default
    runBg = DefaultBg
  for col in 0 .. panelLen:
    let color =
      if col >= textLen:
        EditorColorPairIndex.default
      else:
        syntaxColorAt(syntax, col, baseColor)
    let bg =
      if useWordBg and inColumnRanges(wordRanges, col):
        wordBg
      elif useLineBg:
        lineBg
      else:
        DefaultBg
    if col == 0:
      runColor = color
      runBg = bg
    elif col == panelLen or color != runColor or bg != runBg:
      segments.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: panelStart + runStart,
          lastRow: rowIdx,
          lastColumn: panelStart + col - 1,
          color: runColor,
          style: diffBackgroundStyle(runBg),
        )
      )
      runStart = col
      runColor = color
      runBg = bg

proc buildSideBySideSegments(
    rows: seq[SideBySideRow],
    lines: seq[string],
    leftWidth, rightWidth: int,
    wordHighlight: bool,
): seq[ColorSegment] =
  ## Build per-cell highlight segments for side-by-side lines. Text keeps its
  ## syntax color and the diff is carried by the background: a full-panel tint
  ## for added/deleted lines and a stronger one for changed words. Every row is
  ## covered so the renderer never falls through to a neighbouring segment.
  let sepCharLen = SideBySideSeparator.charLen
  let addedLineBg = getThemeStyle(EditorColorPairIndex.diffViewerAddedLineBg).bg
  let deletedLineBg = getThemeStyle(EditorColorPairIndex.diffViewerDeletedLineBg).bg
  let addedWordBg = getThemeStyle(EditorColorPairIndex.diffViewerAddedWord).bg
  let deletedWordBg = getThemeStyle(EditorColorPairIndex.diffViewerDeletedWord).bg

  for rowIdx, row in rows:
    let lineText = lines[rowIdx]
    let lineCharLen = lineText.charLen
    if lineCharLen == 0:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: 0,
          color: EditorColorPairIndex.default,
          style: Style(),
        )
      )
      continue
    case row.kind
    of sbrHeader:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: EditorColorPairIndex.diffViewerHeader,
          style: Style(),
        )
      )
    of sbrMeta:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: EditorColorPairIndex.diffViewerMeta,
          style: Style(),
        )
      )
    of sbrEmpty:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: EditorColorPairIndex.default,
          style: Style(),
        )
      )
    else:
      let leftPadded = row.leftText.padOrTruncateSide(leftWidth)
      let leftCharLen = leftPadded.charLen
      let rightStart = leftCharLen + sepCharLen
      let rightPadded = row.rightText.padOrTruncateSide(rightWidth)
      let rightCharLen = rightPadded.charLen

      let showWords = wordHighlight and row.kind == sbrChanged
      let leftLineBg =
        if row.kind == sbrDeleted or row.kind == sbrChanged:
          deletedLineBg
        else:
          DefaultBg
      let rightLineBg =
        if row.kind == sbrAdded or row.kind == sbrChanged: addedLineBg else: DefaultBg
      let leftWordBg = if showWords: deletedWordBg else: DefaultBg
      let rightWordBg = if showWords: addedWordBg else: DefaultBg
      var
        leftWords: seq[ColumnRange] = @[]
        rightWords: seq[ColumnRange] = @[]
      if showWords:
        leftWords = row.leftWordRanges
        rightWords = row.rightWordRanges

      # The separator's outer spaces belong to the panel next to them, so a
      # filler panel reaches the divider.
      let sepPad = if sepCharLen >= 3: 1 else: 0

      # Left panel. An added row has no old side: paint the filler color.
      if row.kind == sbrAdded:
        if leftCharLen > 0:
          result.add(
            ColorSegment(
              firstRow: rowIdx,
              firstColumn: 0,
              lastRow: rowIdx,
              lastColumn: leftCharLen - 1 + sepPad,
              color: EditorColorPairIndex.diffViewerFiller,
              style: Style(),
            )
          )
      else:
        appendPanelSegments(
          result, rowIdx, 0, leftCharLen, row.leftText.charLen, row.leftSyntax,
          EditorColorPairIndex.default, leftLineBg, leftWordBg, leftWords,
        )

      # Separator column. Each outer space follows its side's background, but
      # the divider stays unfilled so no tint crosses the center line.
      if sepCharLen >= 3:
        let divider = leftCharLen + 1
        if row.kind != sbrAdded:
          result.add(bgSegment(rowIdx, leftCharLen, divider - 1, leftLineBg))
        result.add(bgSegment(rowIdx, divider, divider, DefaultBg))
        if row.kind != sbrDeleted:
          result.add(bgSegment(rowIdx, divider + 1, rightStart - 1, rightLineBg))
      else:
        result.add(bgSegment(rowIdx, leftCharLen, rightStart - 1, DefaultBg))

      # Right panel. A deleted row has no new side: paint the filler color.
      if row.kind == sbrDeleted:
        if rightCharLen > 0:
          result.add(
            ColorSegment(
              firstRow: rowIdx,
              firstColumn: rightStart - sepPad,
              lastRow: rowIdx,
              lastColumn: rightStart + rightCharLen - 1,
              color: EditorColorPairIndex.diffViewerFiller,
              style: Style(),
            )
          )
      else:
        appendPanelSegments(
          result, rowIdx, rightStart, rightCharLen, row.rightText.charLen,
          row.rightSyntax, EditorColorPairIndex.default, rightLineBg, rightWordBg,
          rightWords,
        )

proc computeUnifiedWordRanges*(items: seq[DiffLine]): seq[seq[ColumnRange]] =
  ## Changed-word ranges per unified item (half-open char columns of the
  ## displayed line, prefix included). Only lines in a paired deleted/added
  ## block get ranges, and only for the first `MaxWordDiffRows` pairs.
  var ranges = newSeq[seq[ColumnRange]](items.len)
  var
    delIdxs: seq[int] = @[]
    addIdxs: seq[int] = @[]
    budget = MaxWordDiffRows

  proc flush() =
    let pairCount = min(delIdxs.len, addIdxs.len)
    for k in 0 ..< pairCount:
      if budget <= 0:
        break
      dec budget
      let
        delItem = items[delIdxs[k]]
        addItem = items[addIdxs[k]]
        oldText = stripDiffPrefix(delItem.text)
        newText = stripDiffPrefix(addItem.text)
        (oldRanges, newRanges) = computeWordRanges(oldText, newText)
        oldOffset = delItem.text.charLen - oldText.charLen
        newOffset = addItem.text.charLen - newText.charLen
      for r in oldRanges:
        ranges[delIdxs[k]].add(
          ColumnRange(startCol: r.startCol + oldOffset, endCol: r.endCol + oldOffset)
        )
      for r in newRanges:
        ranges[addIdxs[k]].add(
          ColumnRange(startCol: r.startCol + newOffset, endCol: r.endCol + newOffset)
        )
    delIdxs.setLen(0)
    addIdxs.setLen(0)

  for i, item in items:
    case item.kind
    of dlkDeleted:
      delIdxs.add(i)
    of dlkAdded:
      addIdxs.add(i)
    of dlkNormal:
      # "\ No newline at end of file" annotates the line before it, so it
      # must not split the pending block.
      if not item.text.startsWith("\\"):
        flush()
    of dlkHeader, dlkMeta:
      flush()
  flush()
  ranges

proc ensureUnifiedWordRanges*(state: DiffViewerState) =
  ## Compute the unified word ranges once. They depend only on `items`, so
  ## every later rebuild reuses them instead of re-running the LCS.
  if state.unifiedWordRanges.len != state.items.len:
    state.unifiedWordRanges = computeUnifiedWordRanges(state.items)

proc appendUnifiedLineSegments(
    segments: var seq[ColorSegment],
    rowIdx, lineCharLen: int,
    lineBg, wordBg: ColorValue,
    wordRanges: seq[ColumnRange],
) =
  ## Emit segments covering the whole line: changed-word ranges carry the
  ## stronger word tint, the rest the line tint.
  if lineCharLen <= 0:
    return
  var col = 0
  for r in wordRanges:
    let
      startCol = clamp(r.startCol, 0, lineCharLen)
      endCol = clamp(r.endCol, startCol, lineCharLen)
    if startCol > col:
      segments.add(bgSegment(rowIdx, col, startCol - 1, lineBg))
    if endCol > startCol:
      segments.add(bgSegment(rowIdx, startCol, endCol - 1, wordBg))
    col = max(col, endCol)
  if col < lineCharLen:
    segments.add(bgSegment(rowIdx, col, lineCharLen - 1, lineBg))

proc buildUnifiedSegments(
    items: seq[DiffLine], wordHighlight: bool, wordRanges: seq[seq[ColumnRange]]
): seq[ColorSegment] =
  ## Build per-line highlight segments for the unified diff. As in the
  ## side-by-side view the diff is carried by the background: a full-line tint
  ## for added/deleted lines and a stronger one for changed words.
  let
    addedLineBg = getThemeStyle(EditorColorPairIndex.diffViewerAddedLineBg).bg
    deletedLineBg = getThemeStyle(EditorColorPairIndex.diffViewerDeletedLineBg).bg
    addedWordBg = getThemeStyle(EditorColorPairIndex.diffViewerAddedWord).bg
    deletedWordBg = getThemeStyle(EditorColorPairIndex.diffViewerDeletedWord).bg
  let useWords = wordHighlight and wordRanges.len == items.len

  template rangesFor(rowIdx: int): seq[ColumnRange] =
    if useWords:
      wordRanges[rowIdx]
    else:
      @[]

  for rowIdx, item in items:
    let lineCharLen = item.text.charLen
    if lineCharLen == 0:
      result.add(bgSegment(rowIdx, 0, 0, DefaultBg))
      continue
    case item.kind
    of dlkHeader:
      # `@@` hunks get the header color; `---`/`+++` file headers are meta.
      let color =
        if item.text.startsWith("@"):
          EditorColorPairIndex.diffViewerHeader
        else:
          EditorColorPairIndex.diffViewerMeta
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: color,
          style: Style(),
        )
      )
    of dlkMeta:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: EditorColorPairIndex.diffViewerMeta,
          style: Style(),
        )
      )
    of dlkAdded:
      appendUnifiedLineSegments(
        result, rowIdx, lineCharLen, addedLineBg, addedWordBg, rangesFor(rowIdx)
      )
    of dlkDeleted:
      appendUnifiedLineSegments(
        result, rowIdx, lineCharLen, deletedLineBg, deletedWordBg, rangesFor(rowIdx)
      )
    of dlkNormal:
      result.add(
        ColorSegment(
          firstRow: rowIdx,
          firstColumn: 0,
          lastRow: rowIdx,
          lastColumn: lineCharLen - 1,
          color: EditorColorPairIndex.default,
          style: Style(),
        )
      )

proc createDiffTextBuffer*(state: DiffViewerState): TextBuffer =
  ## Create a TextBuffer from diff lines for rendering via the normal view
  ## path.
  var content = ""
  for i, line in state.items:
    if i > 0:
      content.add('\n')
    content.add(line.text)
  if state.wordHighlight:
    state.ensureUnifiedWordRanges()
  result = newTextBuffer(content)
  result.language = langDiff
  result.readOnly = true
  result.highlight = Highlight(
    colorSegments:
      buildUnifiedSegments(state.items, state.wordHighlight, state.unifiedWordRanges)
  )

proc createSideBySideTextBuffer*(
    state: DiffViewerState, totalWidth: int = 160
): TextBuffer =
  ## Create a TextBuffer with "old │ new" rows for side-by-side viewing.
  ## `totalWidth` is the available text width; the left panel takes half and
  ## the right panel the rest.
  state.ensureSideRows()
  state.ensureSideSyntax()
  let leftWidth = sidePanelWidth(totalWidth)
  let rightWidth = max(0, totalWidth - leftWidth - SideBySideSeparator.charDisplayWidth)
  var lines = newSeqOfCap[string](state.sideRows.len)
  for row in state.sideRows:
    lines.add(row.formatSideBySideLine(leftWidth, rightWidth))

  var content = lines.join("\n")
  if content.len == 0:
    content = "(No differences)"
    lines = @[content]

  result = newTextBuffer(content)
  result.language = langDiff
  result.readOnly = true
  result.highlight = Highlight(
    colorSegments: buildSideBySideSegments(
      state.sideRows, lines, leftWidth, rightWidth, state.wordHighlight
    )
  )

proc needsWidthRebuild*(state: DiffViewerState, textWidth: int): bool =
  ## Whether rebuilding for `textWidth` would change the buffer. Unified does
  ## not depend on the width, so a resize only matters while two columns are
  ## shown or when the width crosses `SideBySideMinWidth`.
  if textWidth == state.renderedWidth:
    return false
  let wantsSideBySide = state.isSideBySide and textWidth >= SideBySideMinWidth
  wantsSideBySide or state.renderedSideBySide

proc needsThemeRebuild*(state: DiffViewerState): bool =
  ## Whether the theme changed since the buffer was built. The segments bake
  ## concrete background colors, so a theme switch needs a rebuild.
  state.renderedThemeGeneration != themeGeneration()

proc needsRebuild*(state: DiffViewerState, textWidth: int): bool =
  ## Whether the buffer must be rebuilt before the next draw.
  state.needsThemeRebuild or state.needsWidthRebuild(textWidth)

proc refreshDiffTextBuffer*(state: DiffViewerState, textWidth: int = 160): TextBuffer =
  ## Rebuild the view buffer for the current `viewMode`. `textWidth` is the
  ## text area width (gutters excluded); falls back to unified when it is too
  ## narrow. Records the presentation actually generated so callers can report
  ## the effective mode instead of the requested one.
  let wasSideBySide = state.renderedSideBySide
  if state.isSideBySide and textWidth >= SideBySideMinWidth:
    state.renderedSideBySide = true
    result = state.createSideBySideTextBuffer(textWidth)
  else:
    state.renderedSideBySide = false
    result = state.createDiffTextBuffer()
  state.renderedWidth = textWidth
  state.renderedThemeGeneration = themeGeneration()
  if state.renderedSideBySide != wasSideBySide:
    # The two presentations index different row sequences; keep the selection
    # on the same diff line.
    state.selectedIndex =
      if state.renderedSideBySide:
        state.sideRowForItem(state.selectedIndex)
      else:
        state.itemForSideRow(state.selectedIndex)
  state.selectedIndex = clamp(state.selectedIndex, 0, max(0, result.len - 1))
