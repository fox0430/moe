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

# Portions of this file are adapted from fzy (https://github.com/jhawthorn/fzy)
# through Vim's src/fuzzy.c.
# Original code:
#   Copyright (c) 2014 John Hawthorn
#   Licensed under the MIT License.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

## Fuzzy matching as Vim's matchfuzzypos() does (`:h fuzzy-matching`): the fzy
## algorithm of Vim's src/fuzzy.c, so candidates rank, score and highlight as
## in Vim.
##
## A query is split into words at blanks and every word must match, in any
## order. Case only decides whether a word matches: a lower case letter of
## the query matches either case, an upper case one only itself. Scores are
## computed ignoring case. Positions count characters, a character being a
## code point with the composing characters after it.

import std/[algorithm, math, options, strutils, unicode]

import ../[unicode_utils, char_class, char_case]

const
  FuzzyMaxChars* = 1024
    ## Vim's FUZZY_MATCH_MAX_LEN: only the characters of a candidate up to
    ## this many are matched.
  FuzzyScoreMax* = int(int32.high)
    ## The score of a candidate equal to a word ignoring case (Vim's INT_MAX).

  FuzzyScoreMin = int(int32.low) + 1

  ScoreGapLeading = -0.005
  ScoreGapTrailing = -0.005
  ScoreGapInner = -0.01
  ScoreMatchConsecutive = 1.0
  ScoreMatchSlash = 0.9
  ScoreMatchWord = 0.8
  ScoreMatchCapital = 0.7
  ScoreMatchDot = 0.6
  ScoreScale = 1000.0

type
  FuzzyWord = object
    chars: seq[int32] ## The first code point of each character
    upper: seq[int32] ## `chars` in upper case, which a character also matches
    lower: seq[int32] ## `chars` in lower case, which the scoring compares

  FuzzyPattern* = object ## A query ready to match candidates.
    text: string
    words: seq[FuzzyWord]

  FuzzyMatcher* = object ## Scratch space reused across candidates.
    hay: seq[int32] ## The candidate's characters in lower case
    bonus: seq[float]
    lastD, lastM, currD, currM: seq[float] ## Rows, for a score alone
    d, m: seq[float] ## Whole matrices, for positions

  PositionsWanted = enum
    pwNone
    pwFirstWord
    pwAll

  FuzzyRank* = object ## A matched candidate as matchfuzzy() sorts it.
    index*: int ## The candidate's place in the source
    score*: int
    exact*: bool ## The query follows the first match literally

proc vimChar(r: Rune): int32 =
  ## The character Vim reads: an undecodable byte is its value.
  if r.isInvalidByteRune: r.invalidByteValue.int32 else: r.int32

proc charAt(text: string, i: int): tuple[c: int32, next: int] =
  ## The first code point of the character at byte `i` and the byte after its
  ## composing characters. A lam and an alef stay two characters, as in the
  ## editor's columns, unlike Vim with 'arabicshape'.
  if text[i].uint8 < 0x80'u8 and (i + 1 >= text.len or text[i + 1].uint8 < 0x80'u8):
    return (text[i].int32, i + 1)
  var (prev, size) = text.charAtByte(i)
  result = (vimChar(prev), i + size)
  while result.next < text.len:
    let (r, rsize) = text.charAtByte(result.next)
    if not continuesChar(prev, r):
      break
    prev = r
    result.next += rsize

proc toLowerVim(c: int32): int32 =
  utfToLower(Rune(c)).int32

proc toUpperVim(c: int32): int32 =
  utfToUpper(Rune(c)).int32

proc initFuzzyPattern*(query: string): FuzzyPattern =
  ## Splits `query` into words at spaces and tabs, as Vim's skipwhite().
  result.text = query
  var i = 0
  while i < query.len:
    if query[i] in {' ', '\t'}:
      inc i
      continue
    var word: FuzzyWord
    while i < query.len:
      let (c, next) = query.charAt(i)
      if c == ' '.int32 or c == '\t'.int32:
        break
      word.chars.add c
      word.upper.add c.toUpperVim
      word.lower.add c.toLowerVim
      i = next
    result.words.add word

proc isEmpty*(p: FuzzyPattern): bool =
  ## Whether the query has no word: empty or blanks only.
  p.words.len == 0

proc hasMatch(w: FuzzyWord, key: string): bool =
  ## Vim's has_match(): the word's characters appear in order in the whole
  ## candidate.
  var h = 0
  for k in 0 ..< w.chars.len:
    var found = false
    while h < key.len:
      let (c, next) = key.charAt(h)
      h = next
      if c == w.chars[k] or c == w.upper[k]:
        found = true
        break
    if not found:
      return false
  true

proc isWordChar(c: int32): bool =
  ## Vim's vim_iswordc() with the default 'iskeyword'.
  c > 0 and utfClass(Rune(c)) >= 2

proc bonusOf(last, c: int32): float =
  ## Vim's compute_bonus_codepoint().
  if not c.isWordChar:
    0.0
  elif last == '/'.int32:
    ScoreMatchSlash
  elif last == '-'.int32 or last == '_'.int32 or last == ' '.int32:
    ScoreMatchWord
  elif last == '.'.int32:
    ScoreMatchDot
  elif utfIsUpper(Rune(c)) and utfIsLower(Rune(last)):
    ScoreMatchCapital
  else:
    0.0

proc setupHaystack(mt: var FuzzyMatcher, key: string) =
  ## Vim's setup_match_struct().
  mt.hay.setLen 0
  mt.bonus.setLen 0
  var
    i = 0
    prev = '/'.int32
  while i < key.len and mt.hay.len < FuzzyMaxChars:
    let (c, next) = key.charAt(i)
    mt.hay.add c.toLowerVim
    mt.bonus.add bonusOf(prev, c)
    prev = c
    i = next

proc matchRow(
    hay: openArray[int32],
    bonus: openArray[float],
    needle: int32,
    row, n: int,
    currD, currM: var openArray[float],
    lastD, lastM: openArray[float],
) =
  ## Vim's match_row(). `lastD` and `lastM` are read only past the first row.
  let gapScore = if row == n - 1: ScoreGapTrailing else: ScoreGapInner
  var
    prevScore = NegInf
    prevM = NegInf
    prevD = NegInf
  for j in 0 ..< hay.len:
    if needle == hay[j]:
      var score = NegInf
      if row == 0:
        score = (j.float * ScoreGapLeading) + bonus[j]
      elif j > 0:
        # A consecutive match doesn't stack with the bonus
        score = max(prevM + bonus[j], prevD + ScoreMatchConsecutive)
      if row > 0:
        prevD = lastD[j]
        prevM = lastM[j]
      currD[j] = score
      prevScore = max(score, prevScore + gapScore)
      currM[j] = prevScore
    else:
      if row > 0:
        prevD = lastD[j]
        prevM = lastM[j]
      currD[j] = NegInf
      prevScore = prevScore + gapScore
      currM[j] = prevScore

proc equalsWord(mt: FuzzyMatcher, w: FuzzyWord, n: int): bool =
  for i in 0 ..< n:
    if w.lower[i] != mt.hay[i]:
      return false
  true

proc wordBounds(
    mt: FuzzyMatcher, w: FuzzyWord
): tuple[n, m: int, early: Option[float]] =
  ## The word and haystack lengths, and the score when no search is needed:
  ## a word longer than the haystack, or one equal to it.
  result.n = min(w.chars.len, FuzzyMaxChars)
  result.m = mt.hay.len
  if result.n > result.m:
    result.early = some(NegInf)
  elif result.n == result.m and mt.equalsWord(w, result.n):
    result.early = some(Inf)

proc wordScore(mt: var FuzzyMatcher, w: FuzzyWord): float =
  ## Vim's match_positions() without the positions, in two rows.
  let (n, m, early) = mt.wordBounds(w)
  if early.isSome:
    return early.get
  for s in [addr mt.lastD, addr mt.lastM, addr mt.currD, addr mt.currM]:
    s[].setLen m
  for i in 0 ..< n:
    swap mt.lastD, mt.currD
    swap mt.lastM, mt.currM
    matchRow(mt.hay, mt.bonus, w.lower[i], i, n, mt.currD, mt.currM, mt.lastD, mt.lastM)
  mt.currM[m - 1]

proc wordPositions(
    mt: var FuzzyMatcher, w: FuzzyWord, positions: var seq[int], offset: int
): float =
  ## Vim's match_positions(): the score, and the match positions written to
  ## `positions` from `offset`, the latest of the best paths.
  let (n, m, early) = mt.wordBounds(w)
  if early == some(Inf):
    for i in 0 ..< n:
      positions[offset + i] = i
  if early.isSome:
    return early.get
  mt.d.setLen n * m
  mt.m.setLen n * m
  for i in 0 ..< n:
    let
      cur = i * m
      last =
        if i == 0:
          cur
        else:
          cur - m
    matchRow(
      mt.hay,
      mt.bonus,
      w.lower[i],
      i,
      n,
      mt.d.toOpenArray(cur, cur + m - 1),
      mt.m.toOpenArray(cur, cur + m - 1),
      mt.d.toOpenArray(last, last + m - 1),
      mt.m.toOpenArray(last, last + m - 1),
    )

  var
    matchRequired = false
    j = m - 1
  for i in countdown(n - 1, 0):
    while j >= 0:
      let
        dij = mt.d[i * m + j]
        mij = mt.m[i * m + j]
      if dij != NegInf and (matchRequired or dij == mij):
        # Scored as consecutive: the character before must match too
        matchRequired =
          i > 0 and j > 0 and mij == mt.d[(i - 1) * m + j - 1] + ScoreMatchConsecutive
        positions[offset + i] = j
        dec j
        break
      dec j
  mt.m[(n - 1) * m + m - 1]

proc toScore(s: float): Option[int] =
  ## A word's score as Vim rounds it.
  if s == Inf:
    some(FuzzyScoreMax)
  elif s == NegInf:
    none(int)
  elif s < 0:
    some(int(ceil(s * ScoreScale - 0.5)))
  else:
    some(int(floor(s * ScoreScale + 0.5)))

proc addScore(total: var int, score: int) =
  ## Vim's saturated sum of word scores.
  if score > 0 and total > FuzzyScoreMax - score:
    total = FuzzyScoreMax
  elif score < 0 and total < FuzzyScoreMin - score:
    total = FuzzyScoreMin
  else:
    total += score

proc byteOfChar(text: string, charIndex: int): int =
  ## The byte where the `charIndex`th character starts, or -1 past the end.
  var count = 0
  while result < text.len:
    if count == charIndex:
      return
    result = text.charAt(result).next
    inc count
  result = -1

proc matchWords(
    mt: var FuzzyMatcher,
    p: FuzzyPattern,
    key: string,
    positions: var seq[int],
    wanted: PositionsWanted,
): Option[int] =
  ## Vim's fuzzy_match(): the summed score when every word matches, with the
  ## positions of the words `wanted`.
  if p.words.len == 0:
    return none(int)
  var
    total = 0
    count = 0
    haySet = false
  for wi, w in p.words:
    let chars = min(w.chars.len, FuzzyMaxChars)
    if count > FuzzyMaxChars - chars:
      return none(int)
    if not w.hasMatch(key):
      return none(int)
    if not haySet:
      mt.setupHaystack(key)
      haySet = true
    let s =
      if wanted == pwAll or wanted == pwFirstWord and wi == 0:
        if positions.len < count + chars:
          positions.setLen count + chars
        mt.wordPositions(w, positions, count)
      else:
        mt.wordScore(w)
    let score = s.toScore
    if score.isNone:
      return none(int)
    total.addScore score.get
    count += chars
    if count >= FuzzyMaxChars:
      break
  if wanted == pwAll:
    positions.setLen count
  some(total)

proc fuzzyRank*(
    mt: var FuzzyMatcher, p: FuzzyPattern, key: string, index: int
): Option[FuzzyRank] =
  ## The rank of `key`, the `index`th candidate, or none when a word doesn't
  ## match or the query is empty.
  var first: seq[int]
  # Positions are needed only for `exact`, which requires the query in `key`.
  let literal = key.find(p.text) >= 0
  let score = mt.matchWords(p, key, first, if literal: pwFirstWord else: pwNone)
  if score.isNone:
    return none(FuzzyRank)
  var rank = FuzzyRank(index: index, score: score.get)
  if literal:
    let start = key.byteOfChar(first[0])
    rank.exact = start >= 0 and key.continuesWith(p.text, start)
  some(rank)

proc fuzzyMatchPos*(
    mt: var FuzzyMatcher, p: FuzzyPattern, key: string, positions: var seq[int]
): Option[int] =
  ## The score of `key` against the query, with the match positions of each
  ## word in turn, one per character (words may share a position).
  ## None when a word doesn't match or the query is empty.
  mt.matchWords(p, key, positions, pwAll)

proc cmpFuzzyRank*(a, b: FuzzyRank): int =
  ## matchfuzzy()'s order: higher score first, then a candidate the query
  ## follows literally from its first match, then the source order.
  if a.score != b.score:
    cmp(b.score, a.score)
  elif a.exact != b.exact:
    (if a.exact: -1 else: 1)
  else:
    cmp(a.index, b.index)

proc fuzzyFilter*(p: FuzzyPattern, keys: openArray[string]): seq[FuzzyRank] =
  ## Vim's matchfuzzy(): the matching candidates, best first.
  var mt: FuzzyMatcher
  for i, key in keys:
    let rank = mt.fuzzyRank(p, key, i)
    if rank.isSome:
      result.add rank.get
  result.sort(cmpFuzzyRank)

proc fuzzyRuneColumns*(key: string, positions: openArray[int]): seq[int] =
  ## The rune column (as `toCharRunes` indexes) of each character position.
  var maxPos = -1
  for p in positions:
    maxPos = max(maxPos, p)
  var starts = newSeqOfCap[int](maxPos + 1)
  var
    i = 0
    column = 0
  while i < key.len and starts.len <= maxPos:
    starts.add column
    let next = key.charAt(i).next
    var j = i
    while j < next:
      j += key.runeSizeAt(j)
      inc column
    i = next
  for p in positions:
    result.add(
      if p < starts.len:
        starts[p]
      else:
        -1
    )
