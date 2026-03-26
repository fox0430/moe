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

import std/[sequtils, os, strutils, strformat, unicode, algorithm, options, tables]

import pkg/celina

import color, primitives
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

  Highlight* = ref object
    colorSegments*: seq[ColorSegment]

  ReservedWord* = object
    word*: string
    color*: EditorColorPairIndex

  # Visual selection area (for compatibility with old code)
  SelectedArea* = object
    startLine*, endLine*: int
    startColumn*, endColumn*: int

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
    mdInIndentedCode*: bool
    mdInMathMode*: bool
    mdInDisplayMath*: bool
    latexInMathMode*: bool
    latexInDisplayMath*: bool

  LineStateCache* = object ## Cache of tokenizer states for each line
    states*: seq[TokenizerState]
    version*: int # Synchronized with buffer changeSeq for invalidation

  IncrementalHighlight* = ref object ## Incremental highlighting information
    segments*: seq[ColorSegment]
    lineStates*: LineStateCache

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
    mdInIndentedCode: g.mdInIndentedCode,
    mdInMathMode: g.mdInMathMode,
    mdInDisplayMath: g.mdInDisplayMath,
    latexInMathMode: g.latexInMathMode,
    latexInDisplayMath: g.latexInDisplayMath,
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
  g.mdInIndentedCode = state.mdInIndentedCode
  g.mdInMathMode = state.mdInMathMode
  g.mdInDisplayMath = state.mdInDisplayMath
  g.latexInMathMode = state.latexInMathMode
  g.latexInDisplayMath = state.latexInDisplayMath

# Default style for highlighting
let defaultStyle* =
  Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

proc `$`*(highlight: Highlight): string =
  result = "Highlight: ["
  for i, s in highlight.colorSegments:
    result &=
      fmt"ColorSegment(firstRow: {$s.firstRow}, firstColumn: {$s.firstColumn}, lastRow: {$s.lastRow}, lastColumn: {$s.lastColumn}, color: {s.color})"
    if i < highlight.colorSegments.high:
      result.add ", "
  result.add "]"

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

  # Because the following assertion is sluggish, it is disabled in release builds.
  when not defined(release):
    doAssert(
      (row, column) >= (highlight[0].firstRow, highlight[0].firstColumn),
      fmt"row = {row}, column = {column}, highlight[0].firstRow = {highlight[0].firstRow}, hightlihgt[0].firstColumn = {highlight[0].firstColumn}",
    )
    doAssert(
      (row, column) <= (highlight[^1].lastRow, highlight[^1].lastColumn),
      fmt"row = {row}, column = {column}, highlight[^1].lastRow = {highlight[^1].lastRow}, hightlihgt[^1].lastColumn = {highlight[^1].lastColumn}, highlight = {highlight}",
    )

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

proc getColorPair*(highlight: Highlight, line, col: int): EditorColorPairIndex =
  ## Get the color at the specified position using binary search.
  ## Returns default color if the position is out of bounds.

  # Handle empty highlight
  if highlight.colorSegments.len == 0:
    return EditorColorPairIndex.default

  # Check if position is within valid range
  if (line, col) < (highlight[0].firstRow, highlight[0].firstColumn) or
      (line, col) > (highlight[^1].lastRow, highlight[^1].lastColumn):
    return EditorColorPairIndex.default

  # Use binary search to find the segment
  let idx = highlight.indexOf(line, col)
  return highlight[idx].color

proc getSegmentModifiers*(highlight: Highlight, line, col: int): set[StyleModifier] =
  ## Get the style modifiers at the specified position using binary search.
  ## Returns empty set if the position is out of bounds.

  if highlight.colorSegments.len == 0:
    return {}

  if (line, col) < (highlight[0].firstRow, highlight[0].firstColumn) or
      (line, col) > (highlight[^1].lastRow, highlight[^1].lastColumn):
    return {}

  let idx = highlight.indexOf(line, col)
  return highlight[idx].style.modifiers

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

  type Position = tuple[row, column: int]

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
  ## Overwrite `highlight` with colorSegment

  let old = highlight
  highlight = Highlight()
  for i in 0 ..< old.colorSegments.len:
    let cs = old.colorSegments[i]
    highlight.colorSegments.add(cs.overwrite(colorSegment))

proc addModifier*(
    highlight: var Highlight,
    firstRow, firstCol, lastRow, lastCol: int,
    modifier: StyleModifier,
) =
  ## Add a style modifier to segments overlapping the given range,
  ## splitting segments at boundaries so only the overlapping portion
  ## receives the modifier.

  type Position = tuple[row, column: int]

  let rangeFirst: Position = (firstRow, firstCol)
  let rangeLast: Position = (lastRow, lastCol)

  var newSegments: seq[ColorSegment]
  for cs in highlight.colorSegments:
    let csFirst: Position = (cs.firstRow, cs.firstColumn)
    let csLast: Position = (cs.lastRow, cs.lastColumn)

    if csLast < rangeFirst or csFirst > rangeLast:
      # No overlap
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

  highlight.colorSegments = newSegments

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
  of gtOperator: EditorColorPairIndex.operator
  of gtBuiltin: EditorColorPairIndex.builtin
  of gtKeyword: EditorColorPairIndex.keyword
  of gtBoolean: EditorColorPairIndex.boolean
  of gtSpecialVar: EditorColorPairIndex.specialVar
  of gtCharLit: EditorColorPairIndex.charLit
  of gtStringLit: EditorColorPairIndex.stringLit
  of gtLongStringLit: EditorColorPairIndex.stringLit
  of gtBinNumber: EditorColorPairIndex.binNumber
  of gtDecNumber: EditorColorPairIndex.decNumber
  of gtFloatNumber: EditorColorPairIndex.floatNumber
  of gtHexNumber: EditorColorPairIndex.hexNumber
  of gtOctNumber: EditorColorPairIndex.octNumber
  of gtComment: EditorColorPairIndex.comment
  of gtLongComment: EditorColorPairIndex.longComment
  of gtDocComment: EditorColorPairIndex.docComment
  of gtDocLongComment: EditorColorPairIndex.docLongComment
  of gtPreprocessor: EditorColorPairIndex.preprocessor
  of gtFunctionName: EditorColorPairIndex.functionName
  of gtTypeName: EditorColorPairIndex.typeName
  of gtWhitespace: EditorColorPairIndex.whitespace
  of gtPragma: EditorColorPairIndex.pragma
  of gtIdentifier: EditorColorPairIndex.identifier
  of gtTable: EditorColorPairIndex.table
  of gtDate: EditorColorPairIndex.date
  of gtKey: EditorColorPairIndex.property
  else: EditorColorPairIndex.default

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

  var bufferStr: string
  for i in 0 .. buffer.high:
    bufferStr &= $buffer[i]
    if i < buffer.high:
      bufferStr &= '\n'

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

proc initHighlightIncremental*(
    buffer: seq[Runes],
    startLine: int,
    endLine: int,
    initialState: TokenizerState,
    reservedWords: seq[ReservedWord],
    language: SourceLanguage,
): tuple[segments: seq[ColorSegment], lineStates: seq[TokenizerState]] =
  ## Parse a partial buffer range with initial tokenizer state
  ## Returns color segments and tokenizer state at the end of each line
  ## Used for incremental re-highlighting of changed regions

  if language == SourceLanguage.langNone or buffer.len == 0:
    # Return empty results for plain text
    return (segments: @[], lineStates: @[])

  # Build buffer string for the requested range
  var bufferStr: string
  for i in startLine .. min(endLine, buffer.high):
    bufferStr &= $buffer[i]
    if i < min(endLine, buffer.high):
      bufferStr &= '\n'

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

        # Capture tokenizer state at line boundary.
        # For multi-line tokens (long strings, block comments), temporarily
        # set the state to the token kind so incremental re-parsing can
        # correctly resume from inside the multi-line construct.
        let savedState = token.state
        if token.kind in {gtLongStringLit, gtLongComment}:
          token.state = token.kind
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

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(bufferStr)

  # Restore initial tokenizer state
  token.restoreTokenizerState(initialState)

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

    let color = getEditorColorPair(token.kind, language)

    if token.kind == gtComment:
      for r in bufferStr[first .. last].parseReservedWord(reservedWords, color):
        if r[0] == "":
          continue
        splitByNewlineWithState(r[0], r[1])
      continue

    splitByNewlineWithState(bufferStr[first .. last], color)

  # Capture final state for the last line
  if currentRow <= endLine:
    lineStates.add(captureTokenizerState(token))

  return (segments: colorSegments, lineStates: lineStates)

proc updateHighlightIncremental*(
    buffer: seq[Runes],
    incrHighlight: var IncrementalHighlight,
    changedStartLine: int,
    bufferChangeSeq: int,
    reservedWords: seq[ReservedWord],
    language: SourceLanguage,
) =
  ## Update highlighting incrementally for a changed region.
  ## Re-parses from the changed line in chunks, stopping early when the
  ## tokenizer state converges with the cached state (meaning all subsequent
  ## lines would produce the same result as before). Falls back to parsing
  ## the entire rest of the file when convergence cannot be detected (e.g.
  ## when the line count has changed).

  const ChunkSize = 100

  # Start re-parsing from the changed line.
  # A small backward margin accounts for tokens that may span the boundary.
  let reparseStart = max(0, changedStartLine - 2)

  # Get initial state for the re-parse range
  var initialState: TokenizerState
  if reparseStart > 0 and reparseStart - 1 < incrHighlight.lineStates.states.len:
    initialState = incrHighlight.lineStates.states[reparseStart - 1]
  else:
    initialState = TokenizerState()

  # State convergence detection is only valid when the line count has not
  # changed; otherwise cached states at the same index refer to different lines.
  let canConverge = buffer.len == incrHighlight.lineStates.states.len

  # Parse in chunks, checking for state convergence after each chunk
  var
    currentStart = reparseStart
    currentState = initialState
    allNewSegments: seq[ColorSegment]
    allNewLineStates: seq[TokenizerState]
    reparseEnd = reparseStart - 1

  while currentStart <= buffer.high:
    let chunkEnd = min(currentStart + ChunkSize - 1, buffer.high)

    let (newSegments, newLineStates) = initHighlightIncremental(
      buffer, currentStart, chunkEnd, currentState, reservedWords, language
    )

    allNewSegments.add(newSegments)
    allNewLineStates.add(newLineStates)
    reparseEnd = chunkEnd

    if newLineStates.len > 0:
      currentState = newLineStates[^1]

    # Check for convergence: if the tokenizer state at the end of this chunk
    # matches the old cached state, all subsequent lines will produce the same
    # segments as before — no need to continue parsing.
    if canConverge and chunkEnd < buffer.high and newLineStates.len > 0 and
        newLineStates[^1] == incrHighlight.lineStates.states[chunkEnd]:
      break

    currentStart = chunkEnd + 1

  # Keep segments outside the re-parsed range
  var filteredSegments: seq[ColorSegment]
  for seg in incrHighlight.segments:
    if seg.firstRow < buffer.len and seg.lastRow < buffer.len and
        (seg.lastRow < reparseStart or seg.firstRow > reparseEnd):
      filteredSegments.add(seg)

  incrHighlight.segments = filteredSegments & allNewSegments

  # Sort segments by position
  incrHighlight.segments.sort do(a, b: ColorSegment) -> int:
    if a.firstRow != b.firstRow:
      return cmp(a.firstRow, b.firstRow)
    else:
      return cmp(a.firstColumn, b.firstColumn)

  # Update line state cache - resize to match buffer
  incrHighlight.lineStates.states.setLen(buffer.len)

  # Replace states for re-parsed lines only
  if allNewLineStates.len > 0:
    var stateIdx = 0
    for lineIdx in reparseStart .. reparseEnd:
      if stateIdx < allNewLineStates.len and lineIdx < buffer.len:
        incrHighlight.lineStates.states[lineIdx] = allNewLineStates[stateIdx]
        inc stateIdx

  incrHighlight.lineStates.version = bufferChangeSeq

proc detectLanguage*(filename: string): SourceLanguage =
  # Check basename for special files (no extension)
  case filename.extractFilename
  of "COMMIT_EDITMSG":
    return SourceLanguage.langCommitEditMsg
  of "git-rebase-todo":
    return SourceLanguage.langGitRebaseTodo
  of "nimble.lock":
    return SourceLanguage.langJson
  else:
    discard

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
  of ".tcl", ".tk", ".itcl", ".itk":
    return SourceLanguage.langTcl
  of ".toml":
    return SourceLanguage.langToml
  of ".cff", ".yaml", ".yml":
    return SourceLanguage.langYaml
  of ".json":
    return SourceLanguage.langJson
  of ".tex", ".sty", ".cls", ".ltx", ".dtx":
    return SourceLanguage.langLatex
  of ".lisp", ".lsp", ".cl", ".el", ".scm", ".ss", ".rkt", ".asd", ".fasl":
    return SourceLanguage.langLisp
  else:
    return SourceLanguage.langNone

proc initSelectedAreaColorSegment*(
    position: BufferPosition, color: EditorColorPairIndex
): ColorSegment {.inline.} =
  result.firstRow = position.line
  result.firstColumn = position.column
  result.lastRow = position.line
  result.lastColumn = position.column
  result.color = color
  result.style = defaultStyle

proc overwriteColorSegmentBlock*[T](
    highlight: var Highlight, area: SelectedArea, buffer: T
) =
  var
    startLine = area.startLine
    endLine = area.endLine
    startColumn = area.startColumn
    endColumn = area.endColumn
  if startLine > endLine:
    swap(startLine, endLine)
  if startColumn > endColumn:
    swap(startColumn, endColumn)

  for i in startLine .. endLine:
    let colorSegment = ColorSegment(
      firstRow: i,
      firstColumn: startColumn,
      lastRow: i,
      lastColumn: min(endColumn, buffer[i].high),
      color: EditorColorPairIndex.selectArea,
      style: defaultStyle,
    )
    highlight.overwrite(colorSegment)

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

proc semanticTokenToColorSegment*(
    token: SemanticToken, legend: SemanticTokensLegend
): ColorSegment =
  ## Convert a single SemanticToken to a ColorSegment.
  let
    typeName = getSemanticTokenType(token, legend)
    modifiers = getSemanticTokenModifiers(token, legend)
    color = semanticTokenTypeToColor(typeName, modifiers)

  result = ColorSegment(
    firstRow: token.line,
    firstColumn: token.startChar,
    lastRow: token.line, # Semantic tokens are typically single-line
    lastColumn: token.endChar - 1, # endChar is exclusive, lastColumn is inclusive
    color: color,
    style: defaultStyle,
  )

proc applySemanticTokens*(
    highlight: var Highlight, tokens: SemanticTokens, legend: SemanticTokensLegend
) =
  ## Apply semantic tokens to an existing Highlight, overwriting the relevant segments.
  ## Semantic tokens from LSP take precedence over local syntax highlighting.
  ##
  ## Performance: O(n + m) where n = existing segments, m = semantic tokens
  ## Uses batch processing instead of individual overwrite calls.
  let decodedTokens = decodeSemanticTokens(tokens)
  if decodedTokens.len == 0:
    return

  # Convert all tokens to ColorSegments and index by line for O(1) lookup
  var tokensByLine = initTable[int, seq[ColorSegment]]()
  for token in decodedTokens:
    let segment = semanticTokenToColorSegment(token, legend)
    if segment.lastColumn >= segment.firstColumn:
      if token.line notin tokensByLine:
        tokensByLine[token.line] = @[]
      tokensByLine[token.line].add(segment)

  if tokensByLine.len == 0:
    return

  # Sort tokens within each line by column
  for line in tokensByLine.keys:
    tokensByLine[line].sort do(a, b: ColorSegment) -> int:
      cmp(a.firstColumn, b.firstColumn)

  # Build new segment list by merging existing segments with tokens
  var newSegments: seq[ColorSegment] = @[]

  for seg in highlight.colorSegments:
    # Check if this segment's line has any tokens
    if seg.firstRow notin tokensByLine and seg.lastRow notin tokensByLine:
      # No tokens on this line, keep segment as-is
      newSegments.add(seg)
      continue

    # For simplicity, handle single-line segments (most common case)
    if seg.firstRow == seg.lastRow:
      let line = seg.firstRow
      if line notin tokensByLine:
        newSegments.add(seg)
        continue

      # Split segment around tokens on this line
      let lineTokens = tokensByLine[line]
      var currentCol = seg.firstColumn

      for token in lineTokens:
        # Skip tokens completely before current position
        if token.lastColumn < currentCol:
          continue

        # Skip tokens completely outside segment bounds
        if token.lastColumn < seg.firstColumn or token.firstColumn > seg.lastColumn:
          continue

        # Effective token start (clipped to current position and segment bounds)
        let effectiveStart = max(token.firstColumn, max(currentCol, seg.firstColumn))
        let effectiveEnd = min(token.lastColumn, seg.lastColumn)

        # Skip if no valid range after clipping
        if effectiveStart > effectiveEnd:
          continue

        # Add portion before token (if any)
        if currentCol < effectiveStart:
          newSegments.add(
            ColorSegment(
              firstRow: line,
              firstColumn: currentCol,
              lastRow: line,
              lastColumn: effectiveStart - 1,
              color: seg.color,
              style: seg.style,
            )
          )

        # Add the token itself
        newSegments.add(
          ColorSegment(
            firstRow: line,
            firstColumn: effectiveStart,
            lastRow: line,
            lastColumn: effectiveEnd,
            color: token.color,
            style: token.style,
          )
        )
        currentCol = effectiveEnd + 1

        # Stop if we've covered the entire segment
        if currentCol > seg.lastColumn:
          break

      # Add remaining portion after last token (if any)
      if currentCol <= seg.lastColumn:
        newSegments.add(
          ColorSegment(
            firstRow: line,
            firstColumn: currentCol,
            lastRow: line,
            lastColumn: seg.lastColumn,
            color: seg.color,
            style: seg.style,
          )
        )
    else:
      # Multi-line segment: for now, use the slower individual overwrite
      # This is rare in practice
      var tempHighlight = Highlight(colorSegments: @[seg])
      for line in seg.firstRow .. seg.lastRow:
        if line in tokensByLine:
          for token in tokensByLine[line]:
            tempHighlight.overwrite(token)
      newSegments.add(tempHighlight.colorSegments)

  highlight.colorSegments = newSegments

proc semanticTokensToHighlight*(
    tokens: SemanticTokens, legend: SemanticTokensLegend, bufferLen: int
): Highlight =
  ## Create a new Highlight from semantic tokens only.
  ## This creates a sparse highlight - positions not covered by tokens will have default color.
  result = Highlight(colorSegments: @[])
  let decodedTokens = decodeSemanticTokens(tokens)

  for token in decodedTokens:
    if token.line < bufferLen:
      let segment = semanticTokenToColorSegment(token, legend)
      if segment.lastColumn >= segment.firstColumn:
        result.colorSegments.add(segment)

  # Sort segments by position
  result.colorSegments.sort do(a, b: ColorSegment) -> int:
    if a.firstRow != b.firstRow:
      return cmp(a.firstRow, b.firstRow)
    else:
      return cmp(a.firstColumn, b.firstColumn)
