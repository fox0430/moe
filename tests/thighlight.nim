import unittest, packages/docutils/highlite, strutils
import moepkg/highlight, moepkg/ui

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
    unitedStr &= buffer[segment.firstRow][segment.firstColumn .. segment.lastColumn]

  check(unitedStr == code)

test "index: basic":
  let
    code = "proc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code, SourceLanguage.langNim)
  
  check(highlight.index(0, 0) == 0)

test "index: start with newline":
  let
    code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    highlight = initHighlight(code, SourceLanguage.langNim)
  
  check(highlight.index(0, 0) == 0)
