#=====================================================
#Nim -- a Compiler for Nim. https://nim-lang.org/
#
#Copyright (C) 2006-2020 Andreas Rumpf. All rights reserved.
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
#[ MIT license: http://www.opensource.org/licenses/mit-license.php ]#
#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std/algorithm

import flags, tokenizer

const
  rustKeywords* = [
    "Self", "abstract", "as", "async", "await", "become", "box", "break", "const",
    "continue", "crate", "do", "dyn", "else", "enum", "extern", "final", "fn", "for",
    "if", "impl", "in", "let", "loop", "macro", "match", "mod", "move", "mut",
    "override", "priv", "pub", "ref", "return", "self", "static", "struct", "super",
    "trait", "try", "type", "typeof", "unsafe", "unsized", "use", "virtual", "where",
    "while", "yield",
  ]

  rustBooleans* = ["false", "true"]

  rustBuiltins* = [
    "AsMut", "AsRef", "Box", "Clone", "Copy", "Default", "DoubleEndedIterator", "Drop",
    "Eq", "Err", "Error", "ExactSizeIterator", "Extend", "Fn", "FnMut", "FnOnce",
    "From", "Into", "IntoIterator", "Iterator", "None", "Ok", "Option", "Ord",
    "PartialEq", "PartialOrd", "Result", "Send", "Sized", "SliceConcatExt", "Some",
    "String", "Sync", "ToOwned", "ToString", "Vec", "bool", "char", "f32", "f64",
    "i128", "i16", "i32", "i64", "i8", "isize", "str", "u128", "u16", "u32", "u64",
    "u8", "usize",
  ]

  rustAttributes* = [
    "allow", "automatically_derived", "bench", "cfg", "cfg_attr", "cold", "crate_name",
    "crate_type", "deny", "derive", "doc", "export_name", "feature", "forbid",
    "global_allocator", "inline", "link", "link_name", "macro_export", "macro_use",
    "must_use", "no_main", "no_mangle", "no_std", "non_exhaustive", "panic_handler",
    "path", "proc_macro", "proc_macro_attribute", "proc_macro_derive", "repr",
    "should_panic", "target_feature", "test", "track_caller", "used", "warn",
  ]

  rustHexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  rustOctChars = {'0' .. '7'}
  rustBinChars = {'0' .. '1'}
  rustSymChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  rustNumSuffixChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}

static:
  # rustGetKeyword relies on binarySearch, so the tables must stay sorted.
  doAssert rustKeywords.isSorted
  doAssert rustBooleans.isSorted
  doAssert rustBuiltins.isSorted
  doAssert rustAttributes.isSorted

proc rustGetKeyword(id: string, attrDepth: int): TokenClass =
  # `rustAttributes` only resolves to `gtPreprocessor` when we are inside
  # an open `#[...]` / `#![...]` bracket. Outside, names like `path`,
  # `test`, `derive`, `inline` are common identifiers and must not be
  # forcibly highlighted as preprocessor.
  if binarySearch(rustKeywords, id) > -1:
    return gtKeyword
  if binarySearch(rustBooleans, id) > -1:
    return gtBoolean
  if binarySearch(rustBuiltins, id) > -1:
    return gtBuiltin
  if attrDepth > 0 and binarySearch(rustAttributes, id) > -1:
    return gtPreprocessor
  return gtIdentifier

proc rustNormalString(g: var GeneralTokenizer, pos: var int) =
  # Consume a regular `"..."` string. Multi-line content is supported via
  # state parking: the closing `"` terminates the token, `\` yields control
  # via `g.state = gtStringLit` so the next call can produce an escape
  # token, and a newline or buffer-end parks `g.state = gtLongStringLit` so
  # the next line continues as the same string. Splitting at `\n` is also
  # what makes per-line state captures record the mid-string context (see
  # the rationale on `rustRawString`).
  g.lang.rust.inRawString = false
  g.lang.rust.rawStringHashCount = 0
  inc(pos)
  g.kind = gtStringLit
  while true:
    case g.buf[pos]
    of '\0':
      g.state = gtLongStringLit
      break
    of '\n':
      inc(pos)
      g.state = gtLongStringLit
      break
    of '\"':
      inc(pos)
      g.lang.rust.inByteString = false
      break
    of '\\':
      g.state = gtStringLit
      break
    else:
      inc(pos)

proc rustRawString(g: var GeneralTokenizer, pos: var int) =
  # `pos` points at the first `#` (or `"`) right after the `r` / `br` prefix.
  # Counts the leading `#`s, then scans until a closing `"` followed by the
  # same number of `#`s. Raw strings have no escape processing. Yields one
  # sub-token per source line so that per-line tokenizer-state captures (used
  # by incremental re-highlighting) record the mid-string context with the
  # correct hash count and `rustInRawString = true`; without this split,
  # captures inside a multi-line raw string read the post-close state and
  # restart parsing as if the buffer were not inside any string.
  var hashCount = 0
  while g.buf[pos] == '#':
    inc(hashCount)
    inc(pos)
  inc(pos) # past opening "
  g.kind = gtStringLit
  g.lang.rust.inRawString = true
  g.lang.rust.rawStringHashCount = hashCount
  while g.buf[pos] != '\0':
    if g.buf[pos] == '\n':
      inc(pos)
      g.state = gtLongStringLit
      return
    if g.buf[pos] == '"':
      var look = pos + 1
      var matched = 0
      while matched < hashCount and g.buf[look] == '#':
        inc(matched)
        inc(look)
      if matched == hashCount:
        pos = look
        g.lang.rust.inRawString = false
        g.lang.rust.rawStringHashCount = 0
        return
    inc(pos)
  g.state = gtLongStringLit

proc isRustRawStringStart(buf: cstring, pos: int): bool =
  # Looks at `r` (or the `r` of `br`) at `pos` and returns true iff the
  # following bytes form a raw-string opener: zero or more `#` then `"`.
  var p = pos + 1
  while buf[p] == '#':
    inc(p)
  result = buf[p] == '\"'

proc rustCharOrLifetime(g: var GeneralTokenizer, pos: var int) =
  # Disambiguates char literal vs lifetime. Char literals: `'x'`, `'\\n'`,
  # `'\\xFF'`, `'\\u{1F600}'`. Anything else after `'` is a lifetime such as
  # `'a` or `'static`, consumed as a single identifier token.
  inc(pos)
  if g.buf[pos] == '\\':
    inc(pos)
    case g.buf[pos]
    of 'x':
      inc(pos)
      if g.buf[pos] in rustHexChars:
        inc(pos)
      if g.buf[pos] in rustHexChars:
        inc(pos)
    of 'u':
      inc(pos)
      if g.buf[pos] == '{':
        inc(pos)
        while g.buf[pos] in rustHexChars:
          inc(pos)
        if g.buf[pos] == '}':
          inc(pos)
    of '\0':
      discard
    of '\n':
      # Never cross the line: `'\` at end of line is malformed code, and a
      # token containing content beyond the newline would invalidate the
      # per-line state captures the incremental re-highlight relies on.
      discard
    else:
      inc(pos)
    # `\` after `'` rules out a lifetime, so any trailing identifier-like
    # bytes belong to a (malformed) char literal — consume them and the
    # closing `'` if present so the token boundary is sensible.
    if g.buf[pos] != '\'':
      while g.buf[pos] in rustSymChars:
        inc(pos)
    if g.buf[pos] == '\'':
      inc(pos)
    g.kind = gtCharLit
  elif g.buf[pos] != '\0' and g.buf[pos] != '\'' and g.buf[pos] != '\n':
    # UTF-8 lead byte → infer width, then check for closing `'`. Treats
    # malformed continuation/invalid leads as 1 byte so a stray high byte
    # falls back to the lifetime path instead of overshooting the buffer.
    # A newline is excluded above: `'` + newline + `'` must not form a
    # cross-line char literal (gtCharLit is not a boundary-captured kind,
    # so a token crossing the newline would make incremental re-highlight
    # resume the next line from the wrong state). The bare `'` falls back
    # to the lifetime path and tokenizes alone, like any unclosed quote.
    let lead = g.buf[pos].uint8
    let width =
      if lead < 0x80'u8:
        1
      elif lead < 0xC0'u8:
        1
      elif lead < 0xE0'u8:
        2
      elif lead < 0xF0'u8:
        3
      elif lead < 0xF8'u8:
        4
      else:
        1
    var look = pos + 1
    var consumed = 1
    var valid = true
    while consumed < width:
      let cont = g.buf[look].uint8
      # Valid UTF-8 continuation bytes are 0x80..0xBF. A null byte (EOF)
      # or any byte outside that range means we mis-judged the lead and
      # must fall back to the lifetime path.
      if cont == 0'u8 or cont < 0x80'u8 or cont >= 0xC0'u8:
        valid = false
        break
      inc(look)
      inc(consumed)
    if valid and consumed == width and g.buf[look] == '\'':
      pos = look + 1
      g.kind = gtCharLit
    else:
      while g.buf[pos] in rustSymChars:
        inc(pos)
      g.kind = gtIdentifier
  else:
    while g.buf[pos] in rustSymChars:
      inc(pos)
    g.kind = gtIdentifier

proc rustReadEscape(g: var GeneralTokenizer, pos: var int) =
  # Consumes one `\X` escape and emits a `gtEscapeSequence` token. Caller
  # must ensure `g.buf[pos] == '\\'` on entry. Sets `g.state = gtLongStringLit`
  # when the buffer ends mid-escape so the next line resumes the string.
  g.kind = gtEscapeSequence
  inc(pos)
  case g.buf[pos]
  of 'x':
    inc(pos)
    if g.buf[pos] in rustHexChars:
      inc(pos)
    if g.buf[pos] in rustHexChars:
      inc(pos)
  of 'u':
    if g.lang.rust.inByteString:
      # `\u{...}` is invalid in byte strings. Emit only the `\` itself
      # (length 1) as a broken-escape signal so the highlighter does not
      # lie about validity; `u{...}` flows on as ordinary string text.
      discard
    else:
      inc(pos)
      if g.buf[pos] == '{':
        inc(pos)
        while g.buf[pos] in rustHexChars:
          inc(pos)
        if g.buf[pos] == '}':
          inc(pos)
  of '\0':
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
  of '\n':
    # `\` followed by a newline is Rust's line-continuation escape. End the
    # sub-token at the newline and park `gtLongStringLit`, exactly like the
    # other in-string sub-token paths. Leaving the state as the caller's
    # `gtStringLit` here used to produce an empty non-EOF token when the
    # buffer ended right after the newline, and the recovery in
    # `rustNextToken` then walked past the NUL terminator (out-of-bounds
    # read on the cstring buffer).
    inc(pos)
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
  else:
    inc(pos)

proc rustConsumeDecSuffix(g: var GeneralTokenizer, pos: var int) =
  # Consumes the type suffix on a decimal-shaped literal. Promotes the
  # token kind to `gtFloatNumber` when the suffix is exactly `f32` or
  # `f64`, so `1f64` and `1.5f32` are colored as floats.
  let suffixStart = pos
  while g.buf[pos] in rustNumSuffixChars:
    inc(pos)
  if pos - suffixStart == 3 and g.buf[suffixStart] == 'f':
    let c1 = g.buf[suffixStart + 1]
    let c2 = g.buf[suffixStart + 2]
    if (c1 == '3' and c2 == '2') or (c1 == '6' and c2 == '4'):
      g.kind = gtFloatNumber

proc rustGeneralNumber(g: var GeneralTokenizer, position: int): int =
  # Rust-specific decimal/float parser. Unlike `generalNumber`, the `.` is
  # only consumed when followed by another decimal digit, so range
  # expressions like `1..2` and method calls like `1.method()` tokenize
  # correctly instead of being mis-read as a float `1.`.
  # `_` is allowed inside digit runs (e.g. `1_000`, `1.000_5`, `1e1_0`)
  # but never as the lookahead after `.` so `1._method()` still splits.
  const
    decChars = {'0' .. '9', '_'}
    digitLookahead = {'0' .. '9'}
  var pos = position
  g.kind = gtDecNumber
  while g.buf[pos] in decChars:
    inc(pos)
  if g.buf[pos] == '.' and g.buf[pos + 1] in digitLookahead:
    g.kind = gtFloatNumber
    inc(pos)
    while g.buf[pos] in decChars:
      inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}:
      inc(pos)
    while g.buf[pos] in decChars:
      inc(pos)
  result = pos

proc rustNextToken*(g: var GeneralTokenizer, flags: TokenizerFlags = {}) =
  discard flags # reserved; kept for getNextToken dispatch signature
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    if g.buf[pos] == '\0':
      # Entering at buffer end (e.g. the buffer ends right after a consumed
      # escape like `\x`) must yield EOF, mirroring the gtLongStringLit
      # branch below. Falling into the loop would emit an empty non-EOF
      # token and trip the recovery at the bottom of `rustNextToken`.
      g.kind = gtEof
    elif g.buf[pos] == '\\':
      # Entering at the pending escape — the usual case: the previous
      # sub-token broke at the `\` without consuming it.
      rustReadEscape(g, pos)
    else:
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\\':
          # End the string sub-token before the escape; state stays
          # gtStringLit so the next call emits the escape on its own
          # (mirrors rustNormalString). Calling rustReadEscape here would
          # overwrite `kind` and fold the preceding string chars into the
          # escape token's color.
          break
        of '\0':
          # Reached only after at least one char was consumed; the token is
          # non-empty and the next call lands in the EOF guard above.
          g.state = gtLongStringLit
          g.lang.rust.rawStringHashCount = 0
          break
        of '\n':
          # End the sub-token at the newline and park state so the next line
          # resumes inside the same string. Routing through gtLongStringLit
          # (not gtStringLit) signals "no escape pending" to the resume path.
          inc(pos)
          g.state = gtLongStringLit
          g.lang.rust.rawStringHashCount = 0
          break
        of '\"':
          inc(pos)
          g.state = gtNone
          g.lang.rust.inByteString = false
          break
        else:
          inc(pos)
  elif g.state == gtLongStringLit:
    if g.buf[pos] == '\0':
      g.kind = gtEof
    elif g.lang.rust.inRawString:
      let hashCount = g.lang.rust.rawStringHashCount
      g.kind = gtLongStringLit
      while g.buf[pos] != '\0':
        if g.buf[pos] == '\n':
          # End the sub-token at the newline; state stays gtLongStringLit
          # and `rustInRawString` / hash count persist so the next line
          # resumes inside the same raw string.
          inc(pos)
          break
        if g.buf[pos] == '"':
          var look = pos + 1
          var matched = 0
          while matched < hashCount and g.buf[look] == '#':
            inc(matched)
            inc(look)
          if matched == hashCount:
            pos = look
            g.state = gtNone
            g.lang.rust.rawStringHashCount = 0
            g.lang.rust.inRawString = false
            break
        inc(pos)
    elif g.buf[pos] == '\\':
      # Bug fix: a non-raw multi-line string can resume with a backslash
      # as the very first character. Without this branch the loop below
      # would `break` immediately without advancing `pos`, producing an
      # empty token and tripping the safety check in `rustNextToken`.
      rustReadEscape(g, pos)
    else:
      g.kind = gtLongStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\n':
          inc(pos)
          # Stay in gtLongStringLit; the next line resumes the same string.
          break
        of '\"':
          inc(pos)
          g.state = gtNone
          g.lang.rust.inByteString = false
          break
        of '\\':
          g.state = gtStringLit
          break
        else:
          inc(pos)
  elif g.state == gtLongComment or g.state == gtDocLongComment:
    let resumeKind = g.state
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = resumeKind
    var nested = g.lang.rust.commentDepth
    while g.kind != gtEof:
      case g.buf[pos]
      of '*':
        inc(pos)
        if g.buf[pos] == '/':
          inc(pos)
          if nested == 0:
            g.state = gtNone
            g.lang.rust.commentDepth = 0
            break
          else:
            dec(nested)
      of '/':
        inc(pos)
        if g.buf[pos] == '*':
          inc(pos)
          inc(nested)
      of '\0':
        g.lang.rust.commentDepth = nested
        break
      else:
        inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '/':
      inc(pos)
      if g.buf[pos] == '/':
        # /// (outer doc) or //! (inner doc), but //// is not doc
        if (g.buf[pos + 1] == '/' and g.buf[pos + 2] != '/') or g.buf[pos + 1] == '!':
          g.kind = gtDocComment
        else:
          g.kind = gtComment
        while not (g.buf[pos] in {'\0', '\n', '\r'}):
          inc(pos)
      elif g.buf[pos] == '*':
        # /** outer doc, but /**/ (empty) and /*** (3+ stars) are not doc.
        # /*! is inner doc.
        let isDocBlock =
          (g.buf[pos + 1] == '*' and g.buf[pos + 2] != '*' and g.buf[pos + 2] != '/') or
          g.buf[pos + 1] == '!'
        let blockState = if isDocBlock: gtDocLongComment else: gtLongComment
        g.kind = blockState
        var nested = 0
        inc(pos)
        while true:
          case g.buf[pos]
          of '*':
            inc(pos)
            if g.buf[pos] == '/':
              inc(pos)
              if nested == 0:
                break
              else:
                dec(nested)
          of '/':
            inc(pos)
            if g.buf[pos] == '*':
              inc(pos)
              inc(nested)
          of '\0':
            g.state = blockState
            g.lang.rust.commentDepth = nested
            break
          else:
            inc(pos)
      else:
        g.kind = gtOperator
        while g.buf[pos] in opChars:
          inc(pos)
    of '#':
      if g.buf[pos + 1] == '[':
        # `#[...]` outer attribute. Highlight just the opener; the body
        # tokenizes normally with `rustAttrBracketDepth` letting the
        # identifier path resolve attribute names to gtPreprocessor.
        inc(pos, 2)
        inc(g.lang.rust.attrBracketDepth)
        g.kind = gtPreprocessor
      elif g.buf[pos + 1] == '!' and g.buf[pos + 2] == '[':
        # `#![...]` inner attribute.
        inc(pos, 3)
        inc(g.lang.rust.attrBracketDepth)
        g.kind = gtPreprocessor
      else:
        inc(pos)
        g.kind = gtOperator
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      if g.buf[pos] == 'r' and isRustRawStringStart(g.buf, pos):
        inc(pos) # past 'r'
        rustRawString(g, pos)
      elif g.buf[pos] == 'r' and g.buf[pos + 1] == '#' and
          g.buf[pos + 2] in {'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF'}:
        # `r#ident` raw identifier — escape for using a reserved word as a
        # name (e.g. `r#fn`). Consumed as a single identifier token.
        inc(pos, 2) # past 'r#'
        while g.buf[pos] in rustSymChars:
          inc(pos)
        g.kind = gtIdentifier
      elif g.buf[pos] == 'b' and g.buf[pos + 1] == 'r' and
          isRustRawStringStart(g.buf, pos + 1):
        inc(pos, 2) # past 'br'
        rustRawString(g, pos)
      elif g.buf[pos] == 'b' and g.buf[pos + 1] == '\"':
        inc(pos) # past 'b'
        g.lang.rust.inByteString = true
        rustNormalString(g, pos)
      elif g.buf[pos] == 'b' and g.buf[pos + 1] == '\'':
        inc(pos) # past 'b'
        rustCharOrLifetime(g, pos)
      else:
        var id = ""
        while g.buf[pos] in rustSymChars:
          add(id, g.buf[pos])
          inc(pos)
        g.kind = rustGetKeyword(id, g.lang.rust.attrBracketDepth)
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b':
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in rustBinChars + {'_'}:
          inc(pos)
        while g.buf[pos] in rustNumSuffixChars:
          inc(pos)
      of 'x':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in rustHexChars + {'_'}:
          inc(pos)
        while g.buf[pos] in rustNumSuffixChars:
          inc(pos)
      of 'o':
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in rustOctChars + {'_'}:
          inc(pos)
        while g.buf[pos] in rustNumSuffixChars:
          inc(pos)
      else:
        # Rust has no implicit-octal; a leading `0` is just decimal.
        pos = rustGeneralNumber(g, pos)
        rustConsumeDecSuffix(g, pos)
    of '1' .. '9':
      pos = rustGeneralNumber(g, pos)
      rustConsumeDecSuffix(g, pos)
    of '\'':
      rustCharOrLifetime(g, pos)
    of '\"':
      rustNormalString(g, pos)
    of '[':
      inc(pos)
      if g.lang.rust.attrBracketDepth > 0:
        # Nested `[` inside an open attribute (e.g. array literal in attr
        # value) needs to track depth so the matching `]` doesn't close
        # the outer attribute prematurely.
        inc(g.lang.rust.attrBracketDepth)
      g.kind = gtPunctuation
    of ']':
      inc(pos)
      if g.lang.rust.attrBracketDepth > 0:
        dec(g.lang.rust.attrBracketDepth)
        # When this `]` closes the outermost attribute (depth back to 0),
        # color it the same as the opening `#[` so the bracket pair stays
        # visually balanced. Inner `]` (e.g. closing an array literal
        # inside the attribute body) keeps punctuation color.
        if g.lang.rust.attrBracketDepth == 0:
          g.kind = gtPreprocessor
        else:
          g.kind = gtPunctuation
      else:
        g.kind = gtPunctuation
    of '(', ')', '{', '}', ',', ';':
      inc(pos)
      g.kind = gtPunctuation
    of ':':
      inc(pos)
      if g.buf[pos] == ':':
        inc(pos)
        g.kind = gtOperator
      else:
        g.kind = gtPunctuation
    of '.':
      inc(pos)
      if g.buf[pos] == '.' and g.buf[pos + 1] == '.':
        # ... (rest pattern)
        inc(pos, 2)
        g.kind = gtOperator
      elif g.buf[pos] == '.':
        # .. (range) or ..= (inclusive range)
        inc(pos)
        if g.buf[pos] == '=':
          inc(pos)
        g.kind = gtOperator
      else:
        g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in opChars:
        g.kind = gtOperator
        while g.buf[pos] in opChars:
          inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    # Defensive recovery: never let the highlighter return an empty
    # non-EOF token. That would either loop forever in the caller or
    # crash it. Surfacing the bug in debug builds keeps the regression
    # visible without taking the editor down in release builds.
    when defined(debug):
      doAssert false, "rustNextToken: produced an empty token"
    if g.buf[pos] == '\0':
      # Never step past the NUL terminator: `buf` is a cstring, so reading
      # beyond it is an out-of-bounds heap read and `g.start` would point
      # past the buffer, crashing the highlighter's slicing. Convert the
      # empty token to EOF instead.
      g.kind = gtEof
    else:
      inc(pos)
      g.length = pos - g.pos
  g.pos = pos
