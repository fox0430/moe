import std/[unittest, strutils]
import moepkg/[highlight, color]
import moepkg/syntax/highlite

const reservedWords = @[
  ReservedWord(word: "WIP", color: EditorColorPair.reservedWord)
]

test "initHighlight: start with newline":
  let
    code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    buffer = split(code, '\n')
    highlight = initHighlight(code,
                              reservedWords,
                              SourceLanguage.langNim)

  # unite segments
  var unitedStr: string
  for i in 0 ..< highlight.len:
    let segment = highlight[i]
    if i > 0 and segment.firstRow != highlight[i-1].lastRow: unitedStr &= "\n"
    let
      firstRow = segment.firstRow
      firstColumn = segment.firstColumn
      lastColumn = segment.lastColumn
    unitedStr &= buffer[firstRow][firstColumn .. lastColumn]

  check(unitedStr == code)

test "indexOf: basic":
  let
    code = "proc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code,
                              reservedWords,
                              SourceLanguage.langNim)

  check(highlight.indexOf(0, 0) == 0)

test "indexOf: start with newline":
  let
    code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code,
                              reservedWords,
                              SourceLanguage.langNim)

  check(highlight.indexOf(0, 0) == 0)

test "over write":
  let
    code = "　"
    highlight = initHighlight(code,
                              reservedWords,
                              SourceLanguage.langNone)
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

# Fix #733
test """Highlight "echo \"""":
  const code = """echo "\""""
  discard initHighlight(code,
                        reservedWords,
                        SourceLanguage.langNim)

test "initHighlight shell script (Fix #1166)":
  const code = "echo hello"
  let r = initHighlight(code,
                        reservedWords,
                        SourceLanguage.langShell)

  check r.len > 0
