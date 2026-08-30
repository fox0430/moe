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

import std/[unittest, random, strutils, sequtils, os]

import pkg/results

import ../src/moepkg/[buffer, unicode_utils, word_dictionary]

proc hasSurrogate(s: string): bool =
  # UTF-8 encoding of UTF-16 surrogates (U+D800..DFFF) is ED A0..BF 80..BF.
  # Conservative 2-byte detection: treated as invalid even if the third byte
  # is not a continuation byte.
  if s.len < 2:
    return false
  for i in 0 ..< s.len - 1:
    if s[i].uint8 == 0xED'u8 and s[i + 1].uint8 in 0xA0'u8 .. 0xBF'u8:
      return true
  false

proc snapshot(b: TextBuffer): seq[string] =
  result = newSeq[string](b.len)
  for i in 0 ..< b.len:
    result[i] = b.getLine(i)

proc randomLine(rng: var Rand, maxLen: int): string =
  let n = rng.rand(maxLen)
  result = newString(n)
  for i in 0 ..< n:
    var v: uint8
    while true:
      v = rng.rand(255).uint8
      if v != 10 and v != 13:
        break
    result[i] = char(v)

proc randomInsertText(rng: var Rand): string =
  # CR included intentionally; insertTextEnd normalizes it to LF.
  let n = 1 + rng.rand(5)
  result = newString(n)
  for i in 0 ..< n:
    if rng.rand(9) == 0:
      result[i] = '\n'
    else:
      result[i] = char(rng.rand(255))

proc randomPos(b: TextBuffer, rng: var Rand, allowEnd: bool): BufferPosition =
  if b.len == 0:
    return BufferPosition(line: 0, column: 0)
  let line = rng.rand(b.len - 1)
  let maxCol =
    if allowEnd:
      b.getLine(line).charLen
    else:
      max(0, b.getLine(line).charLen - 1)
  let col =
    if maxCol == 0:
      0
    else:
      rng.rand(maxCol)

  BufferPosition(line: line, column: col)

proc randomRange(b: TextBuffer, rng: var Rand): (BufferPosition, BufferPosition) =
  let s = randomPos(b, rng, true)
  let eLine = s.line + rng.rand(b.len - 1 - s.line)
  let eMax = b.getLine(eLine).charLen
  var eCol: int
  if eLine == s.line:
    let remain = eMax - s.column
    if remain <= 0:
      eCol = s.column
    else:
      eCol = s.column + rng.rand(remain)
  else:
    eCol =
      if eMax == 0:
        0
      else:
        rng.rand(eMax)

  (s, BufferPosition(line: eLine, column: eCol))

proc runProperty(iters, baseSeed: int, backend: BufferBackend): bool =
  for it in 0 ..< iters:
    let seed = baseSeed + it
    # +1 preserves compatibility with the existing MOE_FUZZ_EDIT_SEED
    # reproduction harness. initRand(0) is valid, but keep the offset so
    # previously reported FAIL seeds remain accurate.
    var rng = initRand(seed.int64 + 1)
    var lines: seq[string]
    let nLines = 1 + rng.rand(4)
    for _ in 0 ..< nLines:
      lines.add(randomLine(rng, 20))

    var b = newTextBuffer(lines.join("\n"), backend = backend)
    let nEdits = 5 + rng.rand(8)
    var history: seq[string]
    for _ in 0 ..< nEdits:
      let kind = rng.rand(2)
      let before = snapshot(b)
      var applied = false
      var after: seq[string]

      case kind
      of 0:
        let pos = randomPos(b, rng, true)
        let text = randomInsertText(rng)
        let r = b.insertText(pos, text)
        if r.isOk:
          applied = true
          after = snapshot(b)
          history.add("insert " & $pos & " " & text.escape)
      of 1:
        var ok = false
        for _ in 0 ..< 5:
          if b.len == 0:
            break
          let pos = randomPos(b, rng, false)
          if b.getLine(pos.line).charLen > pos.column:
            let r = b.deleteChar(pos)
            if r.isOk:
              ok = true
              after = snapshot(b)
              history.add("deleteChar " & $pos)
              break
        applied = ok
      of 2:
        if b.len == 0:
          continue
        let (s, e) = randomRange(b, rng)
        let r = b.deleteRange(s, e)
        if r.isOk:
          applied = true
          after = snapshot(b)
          history.add("deleteRange " & $s & " " & $e)
      else:
        doAssert false, "unreachable"

      if not applied:
        continue

      let ur = b.undo()
      if ur.isErr or snapshot(b) != before:
        echo "FAIL seed=" & $seed & " iter=" & $it
        for h in history:
          echo "  " & h
        echo "before: " & $before
        echo "after: " & $after
        echo "undo got: " & $snapshot(b)
        return false
      let rr = b.redo()
      if rr.isErr or snapshot(b) != after:
        echo "FAIL redo seed=" & $seed & " iter=" & $it
        for h in history:
          echo "  " & h
        echo "before: " & $before
        echo "after: " & $after
        echo "redo got: " & $snapshot(b)
        return false
  true

suite "WordDictionary chars":
  test "enumerateWords splits on invalid bytes":
    check "word\xE3word".enumerateWords.toSeq == @["word", "word"]
    check "a\xE3b".enumerateWords.toSeq.len == 0
  test "enumerateWords never emits surrogate":
    for s in ["\xE3", "a\xE3b", "\xFF\xFE ok", "word\xE3word", "\xF0\x9Fabc"]:
      for w in s.enumerateWords:
        check not w.hasSurrogate
        check w in s

suite "Buffer edit property":
  proc parseEnvInt(key, defaultVal: string): int =
    try:
      parseInt(getEnv(key, defaultVal))
    except ValueError:
      parseInt(defaultVal)

  let iters = parseEnvInt("MOE_FUZZ_EDIT_ITERS", "200")
  let baseSeed = parseEnvInt("MOE_FUZZ_EDIT_SEED", "0")
  test "random bytes edit -> undo is identity (all backends)":
    for backend in [GapBuffer, SqrtDecomp, Rope, PieceTable]:
      check runProperty(iters, baseSeed, backend)
  test "seam regression (all backends)":
    for backend in [GapBuffer, SqrtDecomp, Rope, PieceTable]:
      let b = newTextBuffer("\xE3X\x81\x82", backend = backend)
      check b.getLine(0).charLen == 4
      discard b.deleteChar(BufferPosition(line: 0, column: 1))
      # E3 (lone) + 58 + 81 (lone) + 82 (lone) -> deleting 58 merges E3 81 82 into one character
      check b.getLine(0).charLen == 1
      check b.getLine(0) == "\xE3\x81\x82"
      check b.undo().isOk
      check b.getLine(0) == "\xE3X\x81\x82"
      check b.getLine(0).charLen == 4
      check b.redo().isOk
      check b.getLine(0) == "\xE3\x81\x82"
      check b.getLine(0).charLen == 1
