import sequtils, os, strformat, parseutils
import syntax/highlite
import unicodetext, color
from strutils import find

type ColorSegment* = object
  firstRow*, firstColumn*, lastRow*, lastColumn*: int
  color*: EditorColorPair

type Highlight* = object
  colorSegments*: seq[ColorSegment]

type
  ReservedWord* = object
    word*: string
    color*: EditorColorPair

proc len*(highlight: Highlight): int {.inline.} = highlight.colorSegments.len

proc high*(highlight: Highlight): int {.inline.} = highlight.colorSegments.high

proc `[]`*(highlight: Highlight, i: int): ColorSegment {.inline.} =
  highlight.colorSegments[i]

proc `[]`*(highlight: Highlight, i: BackwardsIndex): ColorSegment {.inline.} =
  highlight.colorSegments[highlight.colorSegments.len - int(i)]

proc getColorPair*(highlight: Highlight, line, col: int): EditorColorPair =
  for colorSegment in highlight.colorSegments:
    if line >= colorSegment.firstRow and
       colorSegment.lastRow >= line and
       col >= colorSegment.firstColumn and
       colorSegment.lastColumn >= col: return colorSegment.color

proc isIntersect(s, t: ColorSegment): bool =
  not ((t.lastRow, t.lastColumn) < (s.firstRow, s.firstColumn) or
  (s.lastRow, s.lastColumn) < (t.firstRow, t.firstColumn))

proc contains(s, t: ColorSegment): bool =
  ((s.firstRow, s.firstColumn) <= (t.firstRow, t.firstColumn) and
  (t.lastRow, t.lastColumn) <= (s.lastRow, s.lastColumn))

proc overwrite(s, t: ColorSegment): seq[ColorSegment] =
  ## Overwrite `s` with t
  type Position = tuple[row, column: int]

  proc prev(pos: Position): Position =
    if pos.column > 0: (pos.row, pos.column-1) else: (pos.row-1, high(int))

  proc next(pos: Position): Position =
    (pos.row, pos.column+1)

  if not s.isIntersect(t): return @[s]

  if t.contains(s):
    return @[ColorSegment(firstRow: s.firstRow,
                          firstColumn: s.firstColumn,
                          lastRow: s.lastRow,
                          lastColumn: s.lastColumn,
                          color: t.color)]

  if s.contains(t):
    if (s.firstRow, s.firstColumn) < (t.firstRow, t.firstColumn):
      let last = prev((t.firstRow, t.firstColumn))
      result.add(ColorSegment(firstRow: s.firstRow,
                              firstColumn: s.firstColumn,
                              lastRow: last.row,
                              lastColumn: last.column,
                              color: s.color))

    result.add(t)

    if (t.lastRow, t.lastColumn) < (s.lastRow, s.lastColumn):
      let first = next((t.lastRow, t.lastColumn))
      result.add(ColorSegment(firstRow: first.row,
                              firstColumn: first.column,
                              lastRow: s.lastRow,
                              lastColumn: s.lastColumn,
                              color: s.color))

    return result

  if (t.firstRow, t.firstColumn) < (s.firstRow, s.firstColumn):
    let first = next((t.lastRow, t.lastColumn))
    result.add(ColorSegment(firstRow: s.firstRow,
                            firstColumn: s.firstColumn,
                            lastRow: t.lastRow,
                            lastColumn: t.lastColumn,
                            color: t.color))
    result.add(ColorSegment(firstRow: first.row,
                            firstColumn: first.column,
                            lastRow: s.lastRow,
                            lastColumn: s.lastColumn,
                            color: s.color))
  else:
    let last = prev((t.firstRow, t.firstColumn))
    result.add(ColorSegment(firstRow: s.firstRow,
                            firstColumn: s.firstColumn,
                            lastRow: last.row,
                            lastColumn: last.column,
                            color: s.color))
    result.add(ColorSegment(firstRow: t.firstRow,
                            firstColumn: t.firstColumn,
                            lastRow: s.lastRow,
                            lastColumn: s.lastColumn,
                            color: t.color))

proc overwrite*(highlight: Highlight, colorSegment: ColorSegment): Highlight =
  ## Overwrite `highlight` with colorSegment

  for i in 0 ..< highlight.colorSegments.len:
    let cs = highlight.colorSegments[i]
    result.colorSegments.add(cs.overwrite(colorSegment))

iterator parseReservedWord(
  buffer: string,
  reservedWords: seq[ReservedWord],
  color: EditorColorPair): (string, EditorColorPair) =

  var
    buffer = buffer
  while true:
    var
      found: bool
      pos = int.high
      reservedWord: ReservedWord

    # search minimum pos
    for r in reservedWords:
      let p = buffer.find(r.word)
      if p < 0: continue
      if p <= pos:
        pos = p
        reservedWord = r
      found = true
    if not found:
      yield (buffer[0 ..^ 1], color)
      break

    const
      first = 0
    let
      last = pos + reservedWord.word.len
    yield (buffer[first ..< pos], color)
    yield (buffer[pos ..< last], reservedWord.color)
    buffer = buffer[last ..^ 1]

proc getEditorColorPairInNim(kind: TokenClass,
                             isProcName: bool): EditorColorPair =

  case kind:
    of gtKeyword: EditorColorPair.keyword
    of gtBoolean: EditorColorPair.boolean
    of gtSpecialVar: EditorColorPair.specialVar
    of gtBuiltin: EditorColorPair.builtin
    of gtStringLit: EditorColorPair.stringLit
    of gtDecNumber: EditorColorPair.decNumber
    of gtComment: EditorColorPair.comment
    of gtLongComment: EditorColorPair.longComment
    of gtPreprocessor: EditorColorPair.preprocessor
    of gtWhitespace, gtPunctuation: EditorColorPair.defaultChar
    else:
      if isProcName: EditorColorPair.functionName
      else: EditorColorPair.defaultChar

proc getEditorColorPair(kind: TokenClass,
                        language: SourceLanguage): EditorColorPair =

  case kind:
    of gtKeyword: EditorColorPair.keyword
    of gtBoolean: EditorColorPair.boolean
    of gtSpecialVar: EditorColorPair.specialVar
    of gtBuiltin: EditorColorPair.builtin
    of gtStringLit:
      if language == SourceLanguage.langYaml: EditorColorPair.defaultChar
      else: EditorColorPair.stringLit
    of gtDecNumber: EditorColorPair.decNumber
    of gtComment: EditorColorPair.comment
    of gtLongComment: EditorColorPair.longComment
    of gtPreprocessor: EditorColorPair.preprocessor
    of gtWhitespace: EditorColorPair.defaultChar
    else: EditorColorPair.defaultChar

proc initHighlight*(buffer: string,
                    reservedWords: seq[ReservedWord],
                    language: SourceLanguage): Highlight =

  var currentRow, currentColumn: int

  template splitByNewline(str, c: typed) =
    const newline = Rune('\n')
    var
      cs = ColorSegment(firstRow: currentRow,
                        firstColumn: currentColumn,
                        lastRow: currentRow,
                        lastColumn: currentColumn,
                        color: c)
      empty = true
    for r in runes(str):
      if r == newline:
        # push an empty segment
        if empty:
          let color = EditorColorPair.defaultChar
          result.colorSegments.add(ColorSegment(firstRow: currentRow,
                                                firstColumn: currentColumn,
                                                lastRow: currentRow,
                                                lastColumn: currentColumn - 1,
                                                color: color))
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

  if language == SourceLanguage.langNone or
     language == SourceLanguage.langShell or
     language == SourceLanguage.langMarkDown:
    splitByNewline(buffer, EditorColorPair.defaultChar)
    return result

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(buffer)
  var pad: string
  if buffer.parseWhile(pad, {' ', '\x09'..'\x0D'}) > 0:
    splitByNewline(pad, EditorColorPair.defaultChar)

  # Only use in nim
  var isProcName = false

  while true:
    try:
      token.getNextToken(language)
    except AssertionError:
      discard

    if token.kind == gtEof: break

    let
      first = token.start
      last = first+token.length-1
    if all(buffer[first .. last], proc (x: char): bool = x == '\n'):
      currentRow += last - first + 1
      currentColumn = 0
      continue

    let color = if language == SourceLanguage.langNim:
                  getEditorColorPairInNim(token.kind, isProcName)
                else:
                  getEditorColorPair(token.kind, language)

    isProcName = if (language == SourceLanguage.langNim) and
                   (buffer[first.. last] == "proc" or
                   buffer[first.. last] == "macro" or
                   buffer[first.. last] == "template" or
                   buffer[first.. last] == "func"): true
                  elif language == SourceLanguage.langNim and
                       isProcName and
                       token.kind == gtWhitespace: true
                 else: false

    if token.kind == gtComment:
      for r in buffer[first..last].parseReservedWord(reservedWords, color):
        if r[0] == "": continue
        splitByNewline(r[0], r[1])
      continue

    splitByNewline(buffer[first..last], color)

proc indexOf*(highlight: Highlight, row, column: int): int =
  ## calculate the index of the color segment which the pair (row, column) belongs to

  # Because the following assertion is sluggish, it is disabled in release builds.
  when not defined(release):
    block:
      let mess = fmt"row = {row}, column = {column}, highlight[0].firstRow = {highlight[0].firstRow}, hightlihgt[0].firstColumn = {highlight[0].firstColumn}"
      doAssert((row, column) >= (highlight[0].firstRow, highlight[0].firstColumn),
               mess)
    block:
      let mess = fmt"row = {row}, column = {column}, highlight[^1].lastRow = {highlight[^1].lastRow}, hightlihgt[^1].lastColumn = {highlight[^1].lastColumn}, highlight = {highlight}"
      doAssert((row, column) <= (highlight[^1].lastRow, highlight[^1].lastColumn),
               mess)
  var
    lb = 0
    ub = highlight.len
  while ub-lb > 1:
    let mid = (lb+ub) div 2
    if (row, column) >= (highlight[mid].firstRow, highlight[mid].firstColumn):
      lb = mid
    else: ub = mid

  return lb

proc detectLanguage*(filename: string): SourceLanguage =
  # TODO: use settings file
  let extention = filename.splitFile.ext
  case extention:
  of ".nim", ".nimble", ".nims":
    return SourceLanguage.langNim
  of ".c", ".h":
    return SourceLanguage.langC
  of ".cpp", "hpp", "cc":
    return SourceLanguage.langCpp
  of ".cs":
    return SourceLanguage.langCsharp
  of ".java":
    return SourceLanguage.langJava
  of ".yaml", ".yml":
    return SourceLanguage.langYaml
  of ".py":
    return SourceLanguage.langPython
  of ".js":
    return SourceLanguage.langJavaScript
  of ".sh", ".bash":
    return SourceLanguage.langShell
  of ".md":
    return SourceLanguage.langMarkDown
  else:
    return SourceLanguage.langNone
