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

## A byte that does not decode is carried through the editor as a rune in
## U+DC80..U+DCFF. That rune is a lone surrogate: `$` on it emits the
## three-byte form `ED B2 xx`, which is not UTF-8. Every string an API hands
## back must therefore be sliced out of its source, never rebuilt from runes.
##
## These tests pin that down from the outside: the APIs that return text taken
## from buffer content must return the source bytes unchanged, and no output
## anywhere may contain a surrogate encoding.
##
## The word under the cursor (`*`) is not covered here: reaching it means
## running the search regex over the line, and `regex` asserts on input that is
## not valid UTF-8 before the extracted word can be checked.

import std/[options, sequtils, strutils, unicode, unittest]

import ../src/moepkg/[buffer, completion, encoding, highlight, unicode_utils, uri_utils]
import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/syntax/tokenizer

proc hasSurrogateEncoding(s: string): bool =
  ## Whether `s` holds a three-byte form decoding to U+D800..U+DFFF -- what
  ## `$` on a carrier rune produces, and what no UTF-8 string may contain.
  for i in 0 ..< s.len - 1:
    if s[i].uint8 == 0xED'u8 and s[i + 1].uint8 in 0xA0'u8 .. 0xBF'u8:
      return true
  false

proc isCleanUtf8(s: string): bool =
  ## Valid UTF-8 with no surrogate encoding. `sanitizeInvalidUtf8` rewrites
  ## anything ill-formed, so an unchanged string is a well-formed one.
  s.sanitizeInvalidUtf8 == s

const
  # An undecodable byte on its own, between characters, and in runs -- the
  # shapes `runeSizeAt` decides one byte at a time.
  DirtyLines = [
    "\xE3", "a\xE3b", "\xFF\xFE ok", "let x = \x81\x82;",
    "path /tmp/a\xE3b/c and https://example.com/\xE3 end", "\xF0\x9Fabc", "word\xE3word",
  ]

suite "Invalid bytes: the carrier rune never re-encodes":
  test "the helper catches what `$` on a carrier rune produces":
    # Guards the guard: if `$` stopped emitting WTF-8, these tests would pass
    # for the wrong reason.
    check hasSurrogateEncoding($invalidByteRune(0xE3'u8))
    check not isCleanUtf8($invalidByteRune(0xE3'u8))
    check not hasSurrogateEncoding("a\xE3b")
    check hasSurrogateEncoding("ok \xED\xB2\x83 no")

  test "slicing helpers return the source bytes unchanged":
    for line in DirtyLines:
      let n = line.charLen
      for start in 0 .. n:
        for count in 0 .. n - start:
          let sliced = line.charSubStr(start, count)
          check not sliced.hasSurrogateEncoding
          check sliced in line

  test "truncation helpers return the source bytes unchanged":
    for line in DirtyLines:
      for budget in 0 .. line.charLen + 1:
        for got in [
          line.truncateToCharsWithSuffix(budget, ""),
          line.truncateToWidthWithSuffix(budget, ""),
        ]:
          check not got.hasSurrogateEncoding
          check got in line

  test "deleteCharAt and toggleAsciiCase keep the byte they do not touch":
    for line in DirtyLines:
      check not line.toggleAsciiCase.hasSurrogateEncoding
      for pos in 0 ..< line.charLen:
        check not line.deleteCharAt(pos).hasSurrogateEncoding

  test "sanitizeForDisplay yields well-formed UTF-8":
    # The one place that deliberately rewrites the byte: a terminal cell may
    # not carry it, so it becomes U+FFFD rather than a lone surrogate.
    for line in DirtyLines:
      check line.sanitizeForDisplay.isCleanUtf8
      check not line.sanitizeForDisplay.hasSurrogateEncoding

  test "sanitizeCellRune never leaves a rune that re-encodes ill-formed":
    for line in DirtyLines:
      for (r, _) in line.chars:
        check ($r.sanitizeCellRune).isCleanUtf8

suite "Invalid bytes: word and path extraction":
  test "extracted words are source slices":
    for line in DirtyLines:
      for col in 0 .. line.charLen:
        for got in [
          line.extractWordAtPosition(col),
          line.extractPrefixBeforeCursor(col),
          line.extractPathPrefixBeforeCursor(col),
        ]:
          check not got.hasSurrogateEncoding
          check got in line

  test "extractWords never rebuilds a carrier rune":
    for line in DirtyLines:
      for word in line.extractWords:
        check word.isCleanUtf8
        check word in line

  test "an undecodable byte splits words rather than joining them":
    # A carrier rune is not a word character, so `word\xE3word` is two words
    # and neither can carry the byte out.
    check "word\xE3word".extractWords == @["word", "word"]
    check "word\xE3word".extractWordAtPosition(0) == "word"
    check "word\xE3word".extractPrefixBeforeCursor(9) == "word"

suite "Invalid bytes: URI and file path extraction":
  test "found URIs are source slices":
    for line in DirtyLines:
      for m in line.findAllUris:
        check not m.uri.hasSurrogateEncoding
        check m.uri in line
      for col in 0 .. line.charLen:
        let uri = line.extractUriAtPosition(col)
        if uri.isSome:
          check not uri.get.hasSurrogateEncoding
          check uri.get in line

  test "found file paths are source slices":
    for line in DirtyLines:
      for col in 0 .. line.charLen:
        let path = line.extractFilePathAtPosition(col)
        if path.isSome:
          check not path.get.hasSurrogateEncoding
          check path.get in line

  test "the capped scan agrees with the uncapped one":
    for line in DirtyLines:
      check line.findAllUris(line.charLen) == line.findAllUris()

suite "Invalid bytes: LSP offsets":
  test "UTF-16 offsets round-trip through an undecodable byte":
    # The carrier rune would re-encode to two or three bytes; the conversion
    # must bill the one byte that is really there or every later offset drifts.
    for line in DirtyLines:
      for col in 0 .. line.charLen:
        let byteOffset = line.charToBytePos(col)
        let utf16 = line.utf8OffsetToUtf16(byteOffset)
        check line.utf16OffsetToUtf8(utf16) == byteOffset

  test "an undecodable byte bills one UTF-16 unit":
    check "a\xE3b".utf8OffsetToUtf16(3) == 3
    check "\xE3".utf8OffsetToUtf16(1) == 1

suite "Invalid bytes: highlight columns":
  test "plain highlight spans the columns the buffer counts":
    let hl = initHighlight(@DirtyLines)
    for i, line in DirtyLines:
      check hl.colorSegments[i].lastColumn == line.charLen - 1

  test "tokenized highlight spans the columns the buffer counts":
    # The full parse used to concatenate `$` of each line's runes, turning one
    # undecodable byte into three columns and shifting every column after it.
    let lines = @["fn a() {} // \xE3 tail", "let s = \"\xFF\xFE\";", "\xE3"]
    let hl = initHighlight(lines, @[], SourceLanguage.langRust)
    for row, line in lines:
      var lastColumn = -1
      for seg in hl.colorSegments:
        if seg.lastRow == row:
          lastColumn = max(lastColumn, seg.lastColumn)
      check lastColumn == line.charLen - 1

  test "a buffer built from undecodable bytes highlights its own columns":
    let buf = newTextBuffer(DirtyLines.toSeq.join("\n"))
    for i, line in DirtyLines:
      check buf.highlight.colorSegments[i].lastColumn == line.charLen - 1
