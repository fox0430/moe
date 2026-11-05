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

## Crash fuzz for every tokenizer.
##
## Over every `SourceLanguage` (except `langNone`), all short strings over a
## metacharacter-heavy alphabet and random strings go through two checks:
##
## * `checkTokenStream` drives `getNextToken` over the whole input, and from the
##   state cached at each line boundary. It fails on any `Defect`, on a token
##   outside the buffer, and on a stream that does not reach EOF.
## * `checkEditedRow` runs `updateHighlightIncremental` on each row and fails if
##   the result differs from a full parse.
##
## Every language is covered automatically; adding a `SourceLanguage` member
## without a lexer arm is already a compile error in `dispatch`.
##
## A failing case is printed with its language, input and seed. A hang or a
## fatal signal cannot print: the language is the test after the last reported
## one, and `MOE_FUZZ_TOKENIZER_TRACE=1` prints each case before running it.
##
## Tuning via env vars:
##   MOE_FUZZ_TOKENIZER_DEPTH          default 3
##   MOE_FUZZ_TOKENIZER_ITERS          default 5000  (random cases per language)
##   MOE_FUZZ_TOKENIZER_RESUME_DEPTH   default 2
##   MOE_FUZZ_TOKENIZER_RESUME_ITERS   default 500   (random cases per language)
##   MOE_FUZZ_TOKENIZER_SEED           default 42
##   MOE_FUZZ_TOKENIZER_TRACE          unset

import std/[os, random, strutils, unicode, unittest]

import ../src/moepkg/celina_backend except defaultStyle
import ../src/moepkg/highlight
import ../src/moepkg/syntax/[tokenizer, dispatch]

const
  ## One-character pieces plus the delimiters that make state machines (quotes,
  ## escapes, comment starts, long-bracket prefixes) meet the end of a line or
  ## the end of the buffer.
  Alpha = [
    "\"", "'", "\\", "\n", "`", "$", "{", "}", "#", "/", "*", "[", "]", "<", ">", "!",
    "-", "a", "0", " ", "=", "(", ")", "\r", ":", "%", "\"\"\"", "'''", "x", "r",
  ]

  ## Pieces for the random cases only, which open states no short string
  ## reaches: fenced code needs a language the lexer knows.
  RareAlpha = [
    "\t", "|", "+", "@", "\xE3\x81\x82", "\xFF", "#|", "@\"", "@@", "<![CDATA[",
    "<script>", "</script>", "<style>", "```", "```nim\n",
  ]

  # Line boundaries are what the re-parse resumes from, so random cases have
  # one in every this many pieces.
  NewlineEvery = 4

  MaxRandomLength = 30

  # A token consumes at least one byte, apart from a few zero-consume state
  # transitions (YAML). Tight enough to fail a loop that only flips state.
  MaxTokensPerByte = 4
  MaxTokensSlack = 16

  # Exercises both the comment branch and the per-line cap.
  ReservedWords = [ReservedWord(word: "x", color: EditorColorPairIndex.keyword)]
  MaxLineLen = 8

  DefaultDepth = 3
  DefaultResumeDepth = 2
  DefaultRandomCases = 5_000
  DefaultResumeCases = 500
  DefaultSeed = 42

type
  CaseCheck = proc(language: SourceLanguage, src: string): string {.nimcall.}

  FuzzFailure = object
    input: string
    message: string

proc describe(e: ref Exception): string =
  ## Never empty, so a failure cannot read as success.
  $e.name & ": " & e.msg.splitLines()[0]

proc walkTokens(
    language: SourceLanguage,
    src: string,
    initial = TokenizerState(lang: defaultLangState()),
): string =
  ## Tokenize `src` from `initial`. Returns "" on success, otherwise a one-line
  ## failure description.
  var tokenizer: GeneralTokenizer
  tokenizer.initGeneralTokenizer(src)
  tokenizer.restoreTokenizerState(initial)

  let maxTokens = MaxTokensPerByte * src.len + MaxTokensSlack
  var tokens = 0
  while true:
    tokenizer.getNextToken(language)
    if tokenizer.kind == gtEof:
      if tokenizer.pos != src.len:
        # The monotonic-advance guard in `getNextToken` turns a stalled lexer
        # into EOF. The input holds no NUL, so EOF before the end of the buffer
        # is a stall, whether or not assertions caught its empty token.
        result = "EOF at byte " & $tokenizer.pos & " of " & $src.len
      break
    if tokenizer.start < 0 or tokenizer.length < 0 or
        tokenizer.start + tokenizer.length > src.len:
      result =
        "token at " & $tokenizer.start & " of length " & $tokenizer.length &
        " leaves a buffer of " & $src.len
      break
    inc tokens
    if tokens > maxTokens:
      result = "token stream did not reach EOF within " & $maxTokens & " tokens"
      break

proc checkTokenStream(language: SourceLanguage, src: string): string =
  try:
    result = walkTokens(language, src)
    let lines = src.split('\n')
    if result.len == 0:
      let (_, states) =
        initHighlightIncremental(lines, 0, lines.high, TokenizerState(), @[], language)
      for row in 1 .. lines.high:
        result = walkTokens(language, lines[row .. ^1].join("\n"), states[row - 1])
        if result.len > 0:
          result = "from row " & $row & ": " & result
          break
  except CatchableError, Defect:
    result = describe(getCurrentException())

proc firstRowDiffering(lines: seq[string], incr, full: Highlight): int =
  ## The first row whose colors or styles differ, -1 if none. The color of a
  ## space or tab is skipped: which adjacent token absorbs it has no visible
  ## effect. Its style still counts, since a background shows.
  for row, line in lines:
    for column, rune in line.toRunes:
      let blank = rune == Rune(' ') or rune == Rune('\t')
      if not blank and incr.getColorPair(row, column) != full.getColorPair(row, column):
        return row
      if incr.literalStyleAt(row, column) != full.literalStyleAt(row, column):
        return row
  -1

proc checkEditedRow(language: SourceLanguage, src: string): string =
  ## Re-parse after a change on each row, as a real edit does, with and without
  ## the line cap. Nothing changes, so the result must be the full parse and
  ## the cached line states must stay as they were.
  let lines = src.split('\n')
  let getLine = proc(i: int): string =
    lines[i]
  try:
    for maxLineLen in [0, MaxLineLen]:
      let (segments, states) = initHighlightIncremental(
        lines, 0, lines.high, TokenizerState(), @ReservedWords, language, maxLineLen
      )
      let full = Highlight(colorSegments: segments)
      for row in 0 .. lines.high:
        var incr = IncrementalHighlight(
          segments: segments, lineStates: LineStateCache(states: states)
        )
        updateHighlightIncremental(
          lines.len, getLine, incr, row, @ReservedWords, language, maxLineLen
        )
        let differing =
          firstRowDiffering(lines, Highlight(colorSegments: incr.segments), full)
        if differing >= 0:
          return
            "edit on row " & $row & " changes the colors or styles of row " & $differing &
            " (maxLineLen " & $maxLineLen & ")"
        if incr.lineStates.states != states:
          return
            "edit on row " & $row & " changes the cached line states (maxLineLen " &
            $maxLineLen & ")"
  except CatchableError, Defect:
    result = describe(getCurrentException())

proc dumpFailure(
    language: SourceLanguage, failure: FuzzFailure, mode, reproduce: string
) =
  echo "=== TOKENIZER FUZZ FAILURE (" & mode & ") ==="
  echo "Language:  " & sourceLanguageToStr[language]
  echo "Input:     " & failure.input.escape
  echo "Failure:   " & failure.message
  echo "Reproduce: " & reproduce

proc languageSeed(baseSeed: int, language: SourceLanguage): int64 =
  ## A distinct stream per language, keyed by name so adding a language does
  ## not shift the cases the others run.
  var h = 14695981039346656037'u64
  for c in sourceLanguageToStr[language]:
    h = (h xor uint64(uint8(c))) * 1099511628211'u64
  let seed = int64(baseSeed) xor cast[int64](h)
  # `initRand` rejects 0.
  if seed == 0: 1 else: seed

proc randomInput(rng: var Rand): string =
  for _ in 0 ..< rng.rand(1 .. MaxRandomLength):
    if rng.rand(NewlineEvery - 1) == 0:
      result.add '\n'
    elif rng.rand(3) == 0:
      result.add sample(rng, RareAlpha)
    else:
      result.add sample(rng, Alpha)

proc fuzz(
    language: SourceLanguage, checkCase: CaseCheck, depth, randomCases, baseSeed: int
): FuzzFailure =
  ## All strings of up to `depth` pieces, then `randomCases` random ones. Stops
  ## at the first failure.
  let trace = existsEnv("MOE_FUZZ_TOKENIZER_TRACE")

  proc run(src: string, failure: var FuzzFailure): bool =
    if trace:
      stderr.writeLine sourceLanguageToStr[language], " ", src.escape
    let message = checkCase(language, src)
    if message.len == 0:
      return true
    failure.input = src
    failure.message = message
    false

  proc walk(prefix: string, depth: int, failure: var FuzzFailure): bool =
    if not run(prefix, failure):
      return false
    if depth == 0:
      return true
    for piece in Alpha:
      if not walk(prefix & piece, depth - 1, failure):
        return false
    true

  if not walk("", depth, result):
    return
  var rng = initRand(languageSeed(baseSeed, language))
  for _ in 0 ..< randomCases:
    if not run(randomInput(rng), result):
      return

proc envInt(name: string, default: int, minValue = low(int)): int =
  ## Reads an int tuning env var. A malformed or out-of-range value raises a
  ## ValueError naming the variable.
  let raw = getEnv(name, $default)
  try:
    result = parseInt(raw)
  except ValueError:
    raise newException(ValueError, name & " must be an integer, got \"" & raw & "\"")
  if result < minValue:
    raise
      newException(ValueError, name & " must be >= " & $minValue & ", got " & $result)

let seed = envInt("MOE_FUZZ_TOKENIZER_SEED", DefaultSeed)

suite "Tokenizer fuzz: every language":
  let
    depth = envInt("MOE_FUZZ_TOKENIZER_DEPTH", DefaultDepth, 0)
    randomCases = envInt("MOE_FUZZ_TOKENIZER_ITERS", DefaultRandomCases, 0)
    reproduce =
      "MOE_FUZZ_TOKENIZER_DEPTH=" & $depth & " MOE_FUZZ_TOKENIZER_ITERS=" & $randomCases &
      " MOE_FUZZ_TOKENIZER_SEED=" & $seed

  for language in SourceLanguage:
    if language == langNone:
      continue
    test sourceLanguageToStr[language] & ": token stream stays sound":
      let failure = fuzz(language, checkTokenStream, depth, randomCases, seed)
      if failure.message.len > 0:
        dumpFailure(language, failure, "tokens", reproduce)
      check failure.message.len == 0

suite "Tokenizer fuzz: incremental re-parse":
  let
    depth = envInt("MOE_FUZZ_TOKENIZER_RESUME_DEPTH", DefaultResumeDepth, 0)
    randomCases = envInt("MOE_FUZZ_TOKENIZER_RESUME_ITERS", DefaultResumeCases, 0)
    reproduce =
      "MOE_FUZZ_TOKENIZER_RESUME_DEPTH=" & $depth & " MOE_FUZZ_TOKENIZER_RESUME_ITERS=" &
      $randomCases & " MOE_FUZZ_TOKENIZER_SEED=" & $seed

  for language in SourceLanguage:
    if language == langNone:
      continue
    test sourceLanguageToStr[language] & ": matches a full parse":
      let failure = fuzz(language, checkEditedRow, depth, randomCases, seed)
      if failure.message.len > 0:
        dumpFailure(language, failure, "re-parse", reproduce)
      check failure.message.len == 0
