import packages/docutils/highlite
import strutils, sequtils, ospaths, strformat
import unicodeext, ui

type ColorSegment = object
  firstRow*, firstColumn*, lastRow*, lastColumn*: int
  color*: ColorPair

type Highlight* = object
  colorSegments: seq[ColorSegment]

proc initHighlight*(buffer, language: string): Highlight =
  let
    lang = getSourceLanguage(language)
    # TODO: use settings file
    defaultColor = brightWhiteDefault
  var currentRow, currentColumn: int

  if lang == SourceLanguage.langNone:
    var
      cs = ColorSegment(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: 0, color: defaultColor)
      empty = true
    for r in runes(buffer):
      if r == '\n':
        if not empty: result.colorSegments.add(cs)
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
    return result

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(buffer)

  while true:
    token.getNextToken(lang)

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
    var
      cs = ColorSegment(firstRow: currentRow, firstColumn: currentColumn, lastRow: currentRow, lastColumn: currentColumn, color: color)
      empty = true

    for r in runes(buffer[first..last]):
      if r == '\n':
        if not empty: result.colorSegments.add(cs)
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

proc `[]`*(highlight: Highlight, i: int): ColorSegment = highlight.colorSegments[i]

proc `[]`*(highlight: Highlight, i: BackwardsIndex): ColorSegment = highlight.colorSegments[highlight.colorSegments.len - int(i)]

proc len*(highlight: Highlight): int = highlight.colorSegments.len

proc high*(highlight: Highlight): int = highlight.colorSegments.high

proc index*(highlight: Highlight, row, column: int): int =
  # calculate index of color segment (row, column) belonging

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
 
proc detectLanguage*(filename: string): string =
  # TODO: use settings file
  let extention = filename.splitFile.ext
  case extention:
  of ".nim", ".nimble":
    result = "Nim"
  of ".c", ".h":
    result = "C"
  of ".cpp", "hpp", "cc":
    result = "C++"
  of ".cs":
    result = "C#"
  of ".java":
    result = "Java"
  of ".yaml":
    result = "Yaml"
  else:
    result = "Plain"
