import packages/docutils/highlite, strutils, sequtils, ospaths, strformat, parseutils
import unicodeext, ui

type ColorSegment* = object
  firstRow*, firstColumn*, lastRow*, lastColumn*: int
  color*: ColorPair

type Highlight* = object
  colorSegments: seq[ColorSegment]

proc len*(highlight: Highlight): int = highlight.colorSegments.len

proc high*(highlight: Highlight): int = highlight.colorSegments.high

proc `[]`*(highlight: Highlight, i: int): ColorSegment = highlight.colorSegments[i]

proc `[]`*(highlight: Highlight, i: BackwardsIndex): ColorSegment = highlight.colorSegments[highlight.colorSegments.len - int(i)]

proc isIntersect(s, t: ColorSegment): bool = not ((t.lastRow, t.lastColumn) < (s.firstRow, s.firstColumn) or (s.lastRow, s.lastColumn) < (t.firstRow, t.firstColumn))

proc contains(s, t: ColorSegment): bool = ((s.firstRow, s.firstColumn) <= (t.firstRow, t.firstColumn) and (t.lastRow, t.lastColumn) <= (s.lastRow, s.lastColumn))

proc overwrite(s, t: ColorSegment): seq[ColorSegment] =
  ## Overwrite `s` with t
  type Position = tuple[row, column: int]

  proc prev(pos: Position): Position =
    if pos.column > 0: (pos.row, pos.column-1) else: (pos.row-1, high(int))
  
  proc next(pos: Position): Position =
    (pos.row, pos.column+1)

  if not s.isIntersect(t): return @[s]

  if t.contains(s): return @[ColorSegment(firstRow: s.firstRow, firstColumn: s.firstColumn, lastRow: s.lastRow, lastColumn: s.lastColumn, color: t.color)]
  
  if s.contains(t):
    if (s.firstRow, s.firstColumn) < (t.firstRow, t.firstColumn):
      let last = prev((t.firstRow, t.firstColumn))
      result.add(ColorSegment(firstRow: s.firstRow, firstColumn: s.firstColumn, lastRow: last.row, lastColumn: last.column, color: s.color))
    
    result.add(t)

    if (t.lastRow, t.lastColumn) < (s.lastRow, s.lastColumn):
      let first = next((t.lastRow, t.lastColumn))
      result.add(ColorSegment(firstRow: first.row, firstColumn: first.column, lastRow: s.lastRow, lastColumn: s.lastColumn, color: s.color))
    
    return result
  
  if (t.firstRow, t.firstColumn) < (s.firstRow, s.firstColumn):
    let first = next((t.lastRow, t.lastColumn))
    result.add(ColorSegment(firstRow: s.firstRow, firstColumn: s.firstColumn, lastRow: t.lastRow, lastColumn: t.lastColumn, color: t.color))
    result.add(ColorSegment(firstRow: first.row, firstColumn: first.column, lastRow: s.lastRow, lastColumn: s.lastColumn, color: s.color))
  else:
    let last = prev((t.firstRow, t.firstColumn))
    result.add(ColorSegment(firstRow: s.firstRow, firstColumn: s.firstColumn, lastRow: last.row, lastColumn: last.column, color: s.color))
    result.add(ColorSegment(firstRow: t.firstRow, firstColumn: t.firstColumn, lastRow: s.lastRow, lastColumn: s.lastColumn, color: t.color))

proc overwrite*(highlight: Highlight, colorSegment: ColorSegment): Highlight =
  ## Overwrite `highlight` with colorSegment

  for i in 0 ..< highlight.colorSegments.len:
    let cs = highlight.colorSegments[i]
    result.colorSegments.add(cs.overwrite(colorSegment))

proc initHighlight*(buffer: string, language: SourceLanguage, defaultColor: Colorpair): Highlight =
  # TODO: use settings file
  var currentRow, currentColumn: int

  template splitByNewline(str, c: typed) =
    const newline = Rune('\n')
    var
      cs = ColorSegment(firstRow: currentRow, firstColumn: currentColumn, lastRow: currentRow, lastColumn: currentColumn, color: c)
      empty = true
    for r in runes(str):
      if r == newline:
        if empty: result.colorSegments.add(ColorSegment(firstRow: currentRow, firstColumn: 0, lastRow: currentRow, lastColumn: -1, color: defaultColor))
        else: result.colorSegments.add(cs)
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
    if not empty: result.colorSegments.add(cs)

  if language == SourceLanguage.langNone:
    splitByNewline(buffer, defaultColor)
    return result

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(buffer)

  # `highlite.initGeneralTokenizer' skips initial whitespace (including newline('0x0A')), so we parse it by ourselves.
  var pad: string
  if buffer.parseWhile(pad, {' ', '\x09'..'\x0D'}) > 0:
    splitByNewline(pad, defaultColor)

  while true:
    token.getNextToken(language)

    if token.kind == gtEof: break

    let
      first = token.start
      last = first+token.length-1
    if all(buffer[first .. last], proc (x: char): bool = x == '\n'):
      currentRow += last - first + 1
      currentColumn = 0
      continue
    
    let color = case token.kind:
        of gtKeyword: brightGreenDefault
        of gtStringLit: magentaDefault
        of gtDecNumber: lightBlueDefault
        of gtComment, gtLongComment: whiteDefault
        of gtWhitespace: defaultColor
        else: defaultColor
    splitByNewline(buffer[first..last], color)

proc index*(highlight: Highlight, row, column: int): int =
  ## calculate index of color segment (row, column) belonging

  doAssert((row, column) >= (highlight[0].firstRow, highlight[0].firstColumn), fmt"row = {row}, column = {column}, highlight[0].firstRow = {highlight[0].firstRow}, hightlihgt[0].firstColumn = {highlight[0].firstColumn}")
  doAssert((row, column) <= (highlight[^1].firstRow, highlight[^1].firstColumn), fmt"row = {row}, column = {column}, highlight[^1].firstRow = {highlight[^1].firstRow}, hightlihgt[^1].firstColumn = {highlight[^1].firstColumn}")

  var
    lb = 0
    ub = highlight.len
  while ub-lb > 1:
    let mid = (lb+ub) div 2
    if (row, column) >= (highlight[mid].firstRow, highlight[mid].firstColumn): lb = mid
    else: ub = mid

  return lb
 
proc detectLanguage*(filename: string): SourceLanguage =
  # TODO: use settings file
  let extention = filename.splitFile.ext
  case extention:
  of ".nim", ".nimble":
    return SourceLanguage.langNim
  of ".c", ".h":
    return SourceLanguage.langC
  of ".cpp", "hpp", "cc":
    return SourceLanguage.langCpp
  of ".cs":
    return SourceLanguage.langCsharp
  of ".java":
    return SourceLanguage.langJava
  of ".yaml":
    return SourceLanguage.langYaml
  else:
    return SourceLanguage.langNone
