import unittest, packages/docutils/highlite, strutils
import moepkg/[highlight, color]

test "initHighlight: start with newline":
  let
    code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    buffer = split(code, '\n')
    highlight = initHighlight(code, SourceLanguage.langNim)
  
  # unite segments
  var unitedStr: string
  for i in 0 ..< highlight.len:
    let segment = highlight[i]
    if i > 0 and segment.firstRow != highlight[i-1].lastRow: unitedStr &= "\n"
    let
      firstRow = segment.firstRow
      firstColumn = segment.firstColumn
      lastColum = nsegment.lastColumn
    unitedStr &= buffer[firstRow][firstColumn .. lastColumn]

  check(unitedStr == code)

test "indexOf: basic":
  let
    code = "proc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code, SourceLanguage.langNim)
  
  check(highlight.indexOf(0, 0) == 0)

test "indexOf: start with newline":
  let
    code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code, SourceLanguage.langNim)
  
  check(highlight.indexOf(0, 0) == 0)

test "over write":
  let
    code = "　"
    highlight = initHighlight(code, SourceLanguage.langNone)
    colorSegment = ColorSegment(firstRow: 0,
                                firstColumn: 0,
                                lastRow: 0,
                                lastColumn: 0,
                                color: EditorColorPair.highlightFullWidthSpace)
    h = highlight.overwrite(colorSegment)

  check(h.len == 1)
  check(h[0].firstRow == 0)
  check(h[0].firstColumn == 0)
  check(h[0].lastRow == 0)
  check(h[0].lastColumn == 0)
  check(h[0].color == EditorColorPair.highlightFullWidthSpace)
