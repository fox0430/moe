#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[sequtils, os, parseutils, strutils, strformat]
import syntax/highlite
import unicodeext, color, independentutils, ui

type
  ColorSegment* = object
    firstRow*, firstColumn*, lastRow*, lastColumn*: int
    color*: EditorColorPairIndex
    attribute*: Attribute

  Highlight* = ref object
    colorSegments*: seq[ColorSegment]

  ReservedWord* = object
    word*: string
    color*: EditorColorPairIndex

proc `$`*(highlight: Highlight): string =
  result = "Highlight: ["
  for i, s in highlight.colorSegments:
    result &=
      fmt"ColorSegment(firstRow: {$s.firstRow}, " &
      fmt"firstColumn: {$s.firstColumn}, " &
      fmt"lastRow: {$s.lastRow}, " &
      fmt"lastColumn: {$s.lastColumn}, " &
      fmt"color: {s.color}, " &
      fmt"attribute: {s.attribute})"
    if i < highlight.colorSegments.high:
      result.add ", "
  result.add "]"

proc len*(highlight: Highlight): int {.inline.} = highlight.colorSegments.len

proc high*(highlight: Highlight): int {.inline.} = highlight.colorSegments.high

proc `[]`*(highlight: Highlight, i: int): ColorSegment {.inline.} =
  highlight.colorSegments[i]

proc `[]`*(highlight: Highlight, i: BackwardsIndex): ColorSegment {.inline.} =
  highlight.colorSegments[highlight.colorSegments.len - int(i)]

proc getColorPair*(highlight: Highlight, line, col: int): EditorColorPairIndex =
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
    return @[ColorSegment(
      firstRow: s.firstRow,
      firstColumn: s.firstColumn,
      lastRow: s.lastRow,
      lastColumn: s.lastColumn,
      color: t.color,
      attribute: t.attribute)]

  if s.contains(t):
    if (s.firstRow, s.firstColumn) < (t.firstRow, t.firstColumn):
      let last = prev((t.firstRow, t.firstColumn))
      result.add(ColorSegment(
        firstRow: s.firstRow,
        firstColumn: s.firstColumn,
        lastRow: last.row,
        lastColumn: last.column,
        color: s.color,
        attribute: t.attribute))

    result.add(t)

    if (t.lastRow, t.lastColumn) < (s.lastRow, s.lastColumn):
      let first = next((t.lastRow, t.lastColumn))
      result.add(ColorSegment(
        firstRow: first.row,
        firstColumn: first.column,
        lastRow: s.lastRow,
        lastColumn: s.lastColumn,
        color: s.color,
        attribute: t.attribute))

    return result

  if (t.firstRow, t.firstColumn) < (s.firstRow, s.firstColumn):
    let first = next((t.lastRow, t.lastColumn))
    result.add(ColorSegment(
      firstRow: s.firstRow,
      firstColumn: s.firstColumn,
      lastRow: t.lastRow,
      lastColumn: t.lastColumn,
      color: t.color,
      attribute: t.attribute))

    result.add(ColorSegment(
      firstRow: first.row,
      firstColumn: first.column,
      lastRow: s.lastRow,
      lastColumn: s.lastColumn,
      color: s.color,
      attribute: t.attribute))
  else:
    let last = prev((t.firstRow, t.firstColumn))
    result.add(ColorSegment(
      firstRow: s.firstRow,
      firstColumn: s.firstColumn,
      lastRow: last.row,
      lastColumn: last.column,
      color: s.color,
      attribute: t.attribute))

    result.add(ColorSegment(
      firstRow: t.firstRow,
      firstColumn: t.firstColumn,
      lastRow: s.lastRow,
      lastColumn: s.lastColumn,
      color: t.color,
      attribute: t.attribute))

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
  color: EditorColorPairIndex): (string, EditorColorPairIndex) =

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

    const First = 0
    let
      last = pos + reservedWord.word.len
    yield (buffer[First ..< pos], color)
    yield (buffer[pos ..< last], reservedWord.color)
    buffer = buffer[last ..^ 1]

proc getEditorColorPairInNim(kind: TokenClass): EditorColorPairIndex =
  case kind:
    of gtKeyword: EditorColorPairIndex.keyword
    of gtBoolean: EditorColorPairIndex.boolean
    of gtSpecialVar: EditorColorPairIndex.specialVar
    of gtOperator: EditorColorPairIndex.functionName
    of gtBuiltin: EditorColorPairIndex.builtin
    of gtStringLit: EditorColorPairIndex.stringLit
    of gtBinNumber: EditorColorPairIndex.binNumber
    of gtDecNumber: EditorColorPairIndex.decNumber
    of gtFloatNumber: EditorColorPairIndex.floatNumber
    of gtHexNumber: EditorColorPairIndex.hexNumber
    of gtOctNumber: EditorColorPairIndex.octNumber
    of gtComment: EditorColorPairIndex.comment
    of gtLongComment: EditorColorPairIndex.longComment
    of gtPreprocessor: EditorColorPairIndex.preprocessor
    of gtFunctionName: EditorColorPairIndex.functionName
    of gtTypeName: EditorColorPairIndex.typeName
    of gtWhitespace, gtPunctuation: EditorColorPairIndex.default
    of gtPragma: EditorColorPairIndex.pragma
    else: EditorColorPairIndex.default

proc getEditorColorPair(
  kind: TokenClass,
  language: SourceLanguage): EditorColorPairIndex =

    case kind:
      of gtKeyword: EditorColorPairIndex.keyword
      of gtBoolean: EditorColorPairIndex.boolean
      of gtSpecialVar: EditorColorPairIndex.specialVar
      of gtBuiltin: EditorColorPairIndex.builtin
      of gtStringLit:
        if language == SourceLanguage.langYaml: EditorColorPairIndex.default
        else: EditorColorPairIndex.stringLit
      of gtBinNumber: EditorColorPairIndex.binNumber
      of gtDecNumber: EditorColorPairIndex.decNumber
      of gtFloatNumber: EditorColorPairIndex.floatNumber
      of gtHexNumber: EditorColorPairIndex.hexNumber
      of gtOctNumber: EditorColorPairIndex.octNumber
      of gtComment: EditorColorPairIndex.comment
      of gtLongComment: EditorColorPairIndex.longComment
      of gtPreprocessor: EditorColorPairIndex.preprocessor
      of gtWhitespace: EditorColorPairIndex.default
      of gtPragma: EditorColorPairIndex.pragma
      of gtIdentifier:
        # TODO: Add EditorColorPairIndex.identifier?
        if language == SourceLanguage.langToml: EditorColorPairIndex.keyword
        else: EditorColorPairIndex.default
      of gtTable:
        # TODO: Add EditorColorPairIndex.table?
        if language == SourceLanguage.langToml: EditorColorPairIndex.keyword
        else: EditorColorPairIndex.default
      of gtDate:
        # TODO: Add EditorColorPairIndex.date?
        if language == SourceLanguage.langToml: EditorColorPairIndex.decNumber
        else: EditorColorPairIndex.default
      else: EditorColorPairIndex.default

proc initHighlightPlain*(buffer: seq[Runes]): Highlight {.inline.} =
  ## Return highlighting for the plain text.

  var colorSegments: seq[ColorSegment]
  for i in 0 .. buffer.high:
    let lastColumn =
      if buffer[i].len > 0: buffer[i].high
      else: -1
    colorSegments.add ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: lastColumn,
      color: EditorColorPairIndex.default)

  return Highlight(colorSegments: colorSegments)

proc initHighlight*(
  buffer: seq[Runes],
  reservedWords: seq[ReservedWord],
  language: SourceLanguage): Highlight =

    if language == SourceLanguage.langNone:
      return initHighlightPlain(buffer)

    var bufferStr: string
    for i in 0 .. buffer.high:
      bufferStr &= $buffer[i]
      if i < buffer.high: bufferStr &= '\n'

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
          color: c)
        empty = true
      for r in runes(str):
        if r == Newline:
          # push an empty segment
          if empty:
            let color = EditorColorPairIndex.default
            colorSegments.add(ColorSegment(
              firstRow: currentRow,
              firstColumn: currentColumn,
              lastRow: currentRow,
              lastColumn: currentColumn - 1,
              color: color))
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
      if not empty: colorSegments.add(cs)

    var token = GeneralTokenizer()
    token.initGeneralTokenizer(bufferStr)
    var pad: string
    if bufferStr.parseWhile(pad, {' ', '\x09'..'\x0D'}) > 0:
      splitByNewline(pad, EditorColorPairIndex.default)

    while true:
      token.getNextToken(language)

      if token.kind == gtEof: break

      let
        first = token.start

        # Make it complete even if it's incomplete.
        last =
          if first + token.length - 1 > bufferStr.high: bufferStr.high
          else: first + token.length - 1

      block:
        # Increment `currentRow` if newlines only.
        let str = bufferStr[first..last]
        if str != "" and all(str, proc (x: char): bool = x == '\n'):
          currentRow += last - first + 1
          currentColumn = 0
          continue

      let color =
        if language == SourceLanguage.langNim:
          getEditorColorPairInNim(token.kind)
        else:
          getEditorColorPair(token.kind, language)

      if token.kind == gtComment:
        for r in bufferStr[first..last].parseReservedWord(reservedWords, color):
          if r[0] == "": continue
          splitByNewline(r[0], r[1])
        continue

      splitByNewline(bufferStr[first..last], color)

    return Highlight(colorSegments: colorSegments)

proc indexOf*(highlight: Highlight, row, column: int): int =
  ## calculate the index of the color segment which the pair (row, column) belongs to

  # Because the following assertion is sluggish, it is disabled in release builds.
  when not defined(release):
    doAssert(
      (row, column) >= (highlight[0].firstRow, highlight[0].firstColumn),
      fmt"row = {row}, column = {column}, highlight[0].firstRow = {highlight[0].firstRow}, hightlihgt[0].firstColumn = {highlight[0].firstColumn}")
    doAssert(
      (row, column) <= (highlight[^1].lastRow, highlight[^1].lastColumn),
      fmt"row = {row}, column = {column}, highlight[^1].lastRow = {highlight[^1].lastRow}, hightlihgt[^1].lastColumn = {highlight[^1].lastColumn}, highlight = {highlight}")

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
  of ".toml":
    return SourceLanguage.langToml
  of ".cff", ".yaml", ".yml":
    return SourceLanguage.langYaml
  else:
    return SourceLanguage.langNone

proc initSelectedAreaColorSegment*(
  position: BufferPosition,
  color: EditorColorPairIndex): ColorSegment {.inline.} =

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
        color: EditorColorPairIndex.visualMode)
      highlight.overwrite(colorSegment)
