import std/[sequtils, strformat, os, parseutils, strutils]
import syntax/highlite
import unicodeext, color, independentutils

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

proc overwrite*(highlight: var Highlight, colorSegment: ColorSegment) =
  ## Overwrite `highlight` with colorSegment

  let old = highlight
  highlight = Highlight()
  for i in 0 ..< old.colorSegments.len:
    let cs = old.colorSegments[i]
    highlight.colorSegments.add(cs.overwrite(colorSegment))

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

proc getEditorColorPairInNim(kind: TokenClass ): EditorColorPair =

  case kind:
    of gtKeyword: EditorColorPair.keyword
    of gtBoolean: EditorColorPair.boolean
    of gtSpecialVar: EditorColorPair.specialVar
    of gtOperator: EditorColorPair.functionName
    of gtBuiltin: EditorColorPair.builtin
    of gtStringLit: EditorColorPair.stringLit
    of gtBinNumber: EditorColorPair.binNumber
    of gtDecNumber: EditorColorPair.decNumber
    of gtFloatNumber: EditorColorPair.floatNumber
    of gtHexNumber: EditorColorPair.hexNumber
    of gtOctNumber: EditorColorPair.octNumber
    of gtComment: EditorColorPair.comment
    of gtLongComment: EditorColorPair.longComment
    of gtPreprocessor: EditorColorPair.preprocessor
    of gtFunctionName: EditorColorPair.functionName
    of gtTypeName: EditorColorPair.typeName
    of gtWhitespace, gtPunctuation: EditorColorPair.defaultChar
    of gtPragma: EditorColorPair.pragma
    else:
      EditorColorPair.defaultChar

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
    of gtBinNumber: EditorColorPair.binNumber
    of gtDecNumber: EditorColorPair.decNumber
    of gtFloatNumber: EditorColorPair.floatNumber
    of gtHexNumber: EditorColorPair.hexNumber
    of gtOctNumber: EditorColorPair.octNumber
    of gtComment: EditorColorPair.comment
    of gtLongComment: EditorColorPair.longComment
    of gtPreprocessor: EditorColorPair.preprocessor
    of gtWhitespace: EditorColorPair.defaultChar
    of gtPragma: EditorColorPair.pragma
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

  if language == SourceLanguage.langNone:
    splitByNewline(buffer, EditorColorPair.defaultChar)
    return result

  var token = GeneralTokenizer()
  token.initGeneralTokenizer(buffer)
  var pad: string
  if buffer.parseWhile(pad, {' ', '\x09'..'\x0D'}) > 0:
    splitByNewline(pad, EditorColorPair.defaultChar)

  while true:
    try:
      token.getNextToken(language)
    except AssertionDefect:
      discard

    if token.kind == gtEof: break

    let
      first = token.start

      # Make it complete even if it's incomplete.
      last =
        if first + token.length - 1 > buffer.high:
          buffer.high
        else:
          first + token.length - 1

    block:
      # Increment `currentRow` if newlines only.
      let str = buffer[first..last]
      if str != "" and all(str, proc (x: char): bool = x == '\n'):
        currentRow += last - first + 1
        currentColumn = 0
        continue

    let color = if language == SourceLanguage.langNim:
                  getEditorColorPairInNim(token.kind)
                else:
                  getEditorColorPair(token.kind, language)

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
  case filename.splitFile.ext:
  of ".c", ".dox", ".h", ".i":
    return SourceLanguage.langC
  of ".C", ".CPP", ".H", ".HPP", ".c++", ".cc", ".cp", ".cpp", ".cxx", ".h++",
     ".hh", ".hp", ".hpp", ".hxx", ".ii", ".tcc":
    return SourceLanguage.langCpp
  of ".cs":
    return SourceLanguage.langCsharp
  of ".cabal", ".hs":
    return SourceLanguage.langHaskell
  of ".java":
    return SourceLanguage.langJava
  of ".js", ".ts":
    return SourceLanguage.langJavaScript
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
  of ".cff", ".yaml", ".yml":
    return SourceLanguage.langYaml
  else:
    return SourceLanguage.langNone

proc initSelectedAreaColorSegment*(
  position: BufferPosition,
  color: EditorColorPair): ColorSegment {.inline.} =
    result.firstRow = position.line
    result.firstColumn = position.column
    result.lastRow = position.line
    result.lastColumn = position.column
    result.color = color

proc overwriteColorSegmentBlock*[T](
  highlight: var Highlight,
  area: SelectedArea,
  buffer: T) =

    var
      startLine = area.startLine
      endLine = area.endLine
      startColumn = area.startColumn
      endColumn = area.endColumn
    if startLine > endLine: swap(startLine, endLine)
    if startColumn > endColumn: swap(startColumn, endColumn)

    for i in startLine .. endLine:
      let colorSegment = ColorSegment(
        firstRow: i,
        firstColumn: startColumn,
        lastRow: i,
        lastColumn: min(endColumn, buffer[i].high),
        color: EditorColorPair.visualMode)
      highlight.overwrite(colorSegment)
