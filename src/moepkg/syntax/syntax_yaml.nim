# Nim -- a Compiler for Nim. https://nim-lang.org/
#
# Copyright (C) 2006-2022 Andreas Rumpf. All rights reserved.
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
#
# [ MIT license: http://www.opensource.org/licenses/mit-license.php ]

import flags, tokenizer, lexer

const
  YamlBooleans = [
    "true", "True", "TRUE", "false", "False", "FALSE", "yes", "Yes", "YES", "no", "No",
    "NO", "on", "On", "ON", "off", "Off", "OFF",
  ]
  YamlNulls = ["null", "Null", "NULL"]
  YamlSpecialFloats = [
    ".inf", ".Inf", ".INF", "-.inf", "-.Inf", "-.INF", "+.inf", "+.Inf", "+.INF",
    ".nan", ".NaN", ".NAN",
  ]

proc yamlPlainStrLit(g: var GeneralTokenizer, pos: var int) =
  g.kind = gtStringLit
  while g.buf[pos] notin {'\0', '\t' .. '\r', ',', ']', '}'}:
    if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
      break
    if g.buf[pos] == ' ' and g.buf[pos + 1] == '#':
      break
    inc(pos)

proc yamlClassifyToken(g: var GeneralTokenizer, pos: int) =
  ## Reclassify a gtStringLit token as key/boolean/null/identifier
  if g.kind != gtStringLit:
    return

  # Key detection: next char is ':' + whitespace/EOF
  if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
    g.kind = gtKey
    return

  # Special value checks
  let tokenLen = pos - g.start
  if tokenLen >= 1 and tokenLen <= 6:
    var token = newString(tokenLen)
    for i in 0 ..< tokenLen:
      token[i] = g.buf[g.start + i]
    if token in YamlBooleans:
      g.kind = gtBoolean
    elif token in YamlNulls or token == "~":
      g.kind = gtSpecialVar
    elif token in YamlSpecialFloats:
      g.kind = gtFloatNumber
    else:
      g.kind = gtIdentifier
  else:
    g.kind = gtIdentifier

proc yamlPossibleNumber(g: var GeneralTokenizer, pos: var int) =
  g.kind = gtNone
  var digitStart = pos
  if g.buf[pos] == '-':
    inc(pos)
    digitStart = pos
  if g.buf[pos] == '0':
    inc(pos)
    # Hex: 0x... (only without preceding sign, i.e. token starts with '0')
    if pos == g.start + 1 and g.buf[pos] in {'x', 'X'}:
      inc(pos)
      if g.buf[pos] in {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}:
        g.kind = gtHexNumber
        while g.buf[pos] in {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}:
          inc(pos)
      else:
        yamlPlainStrLit(g, pos)
      return
    # Octal: 0o... (only without preceding sign)
    elif pos == g.start + 1 and g.buf[pos] in {'o', 'O'}:
      inc(pos)
      if g.buf[pos] in {'0' .. '7'}:
        g.kind = gtOctNumber
        while g.buf[pos] in {'0' .. '7'}:
          inc(pos)
      else:
        yamlPlainStrLit(g, pos)
      return
  elif g.buf[pos] in '1' .. '9':
    inc(pos)
    while g.buf[pos] in {'0' .. '9'}:
      inc(pos)
  else:
    yamlPlainStrLit(g, pos)
  if g.kind == gtNone:
    let digitCount = pos - digitStart
    # Date: YYYY-MM-DD[Thh:mm:ss[.frac][Z|±hh:mm]]
    if digitCount == 4 and g.buf[pos] == '-' and g.buf[pos + 1] in {'0' .. '9'}:
      g.kind = gtDate
      while g.buf[pos] in {'0' .. '9', 'T', 't', 'Z', 'z', '-', ':', '.', '+'}:
        if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
          break # YAML key indicator ': '
        inc(pos)
      return
  if g.kind == gtNone:
    if g.buf[pos] in {'\0', '\t' .. '\r', ' ', ',', ']', '}'}:
      g.kind = gtDecNumber
    elif g.buf[pos] == '.':
      inc(pos)
      if g.buf[pos] notin {'0' .. '9'}:
        yamlPlainStrLit(g, pos)
      else:
        while g.buf[pos] in {'0' .. '9'}:
          inc(pos)
        if g.buf[pos] in {'\0', '\t' .. '\r', ' ', ',', ']', '}'}:
          g.kind = gtFloatNumber
    if g.kind == gtNone:
      if g.buf[pos] in {'e', 'E'}:
        inc(pos)
        if g.buf[pos] in {'-', '+'}:
          inc(pos)
        if g.buf[pos] notin {'0' .. '9'}:
          yamlPlainStrLit(g, pos)
        else:
          while g.buf[pos] in {'0' .. '9'}:
            inc(pos)
          if g.buf[pos] in {'\0', '\t' .. '\r', ' ', ',', ']', '}'}:
            g.kind = gtFloatNumber
          else:
            yamlPlainStrLit(g, pos)
      else:
        yamlPlainStrLit(g, pos)
  if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
    discard # Let ':' be processed as a separate token
  else:
    while g.buf[pos] notin {'\0', ',', ']', '}', '\n', '\r'}:
      inc(pos)
      if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
        break
      if g.buf[pos] notin {'\t' .. '\r', ' ', ',', ']', '}'}:
        yamlPlainStrLit(g, pos)
        break
  # theoretically, we would need to parse indentation (like with block scalars)
  # because of possible multiline flow scalars that start with number-like
  # content, but that is far too troublesome. I think it is fine that the
  # highlighter is sloppy here.

proc yamlNextToken*(g: var GeneralTokenizer) =
  const hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  var pos = g.pos
  g.start = g.pos
  # Default kind so no zero-consume arm can leak the previous token's kind —
  # or, on a fresh tokenizer resuming from a captured state, the init value
  # gtEof, which would stop the consumer's token loop before it read anything
  # (phantom EOF, the whole chunk lost). Every arm that produces a real token
  # overwrites this; no branch reads the previous call's kind.
  g.kind = gtNone
  if g.state in {gtStringLit, gtKey}:
    g.kind = g.state
    while true:
      case g.buf[pos]
      of '\\':
        if pos != g.pos:
          break
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x':
          inc(pos)
          for i in 1 .. 2:
            if g.buf[pos] in hexChars:
              inc(pos)
          break
        of 'u':
          inc(pos)
          for i in 1 .. 4:
            if g.buf[pos] in hexChars:
              inc(pos)
          break
        of 'U':
          inc(pos)
          for i in 1 .. 8:
            if g.buf[pos] in hexChars:
              inc(pos)
          break
        else:
          # Never consume the terminator or a newline (see skipEscapedChar):
          # the per-line fold below must still capture the boundary state.
          g.skipEscapedChar(pos)
        break
      of '\0':
        # End of buffer is NOT end of string: keep the in-string state so the
        # final boundary capture stays truthful. A chunked parse
        # (`updateHighlightIncremental`/`continueInitialHighlight`) hands this
        # state to the next chunk; parking `gtOther` here made every
        # double-quoted string crossing a chunk boundary resume as plain YAML.
        # When nothing was consumed this IS the end of the token stream —
        # report gtEof directly (state preserved) instead of a zero-length
        # string token.
        if pos == g.pos:
          g.kind = gtEof
        break
      of '\n', '\r':
        # Fold across the line keeping `gtStringLit`/`gtKey`: one token per line
        # so the incremental boundary state marks each as inside the string,
        # rather than parking `gtOther` at end of buffer and back-filling it.
        inc(pos)
        break
      of '\"':
        inc(pos)
        g.state = gtOther
        break
      else:
        inc(pos)
  elif g.state == gtCharLit:
    # abusing gtCharLit as single-quoted string lit
    g.kind = if g.yamlIsKey: gtKey else: gtStringLit
    # Check if we're at an escape sequence ''
    if g.buf[pos] == '\'' and g.buf[pos + 1] == '\'':
      inc(pos, 2)
      g.kind = gtEscapeSequence
    elif g.buf[pos] == '\'':
      inc(pos) # skip the starting '
      while true:
        case g.buf[pos]
        of '\0':
          # Unterminated at end of buffer; stop so we don't read past it.
          # Keep gtCharLit: end of buffer is not end of string, and a chunked
          # parse resumes the next chunk from this state (see the gtStringLit
          # continuation above).
          break
        of '\n', '\r':
          # Fold across the line keeping `gtCharLit`: one token per line so the
          # closing-quote token (which resets to `gtOther`) stays on its own
          # line and the lines between are marked as inside the string.
          inc(pos)
          break
        of '\'':
          if g.buf[pos + 1] == '\'':
            # Escape sequence, return content first if any
            if pos > g.pos + 1:
              break
            inc(pos, 2)
            g.kind = gtEscapeSequence
          else:
            inc(pos)
            g.state = gtOther
          break
        else:
          inc(pos)
    else:
      # Continue reading after previous token
      while true:
        case g.buf[pos]
        of '\0':
          # Keep gtCharLit at end of buffer (chunk resume; see the gtStringLit
          # continuation above) and report gtEof when nothing was consumed.
          if pos == g.pos:
            g.kind = gtEof
          break
        of '\n', '\r':
          inc(pos)
          break
        of '\'':
          if g.buf[pos + 1] == '\'':
            # Escape sequence, return content first if any
            if pos > g.pos:
              break
            inc(pos, 2)
            g.kind = gtEscapeSequence
          else:
            inc(pos)
            g.state = gtOther
          break
        else:
          inc(pos)
  elif g.state == gtCommand:
    # gtCommand means 'block scalar header'
    case g.buf[pos]
    of ' ', '\t':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsYaml)
    of '\n', '\r':
      # Consume nothing; the state flip below moves parsing into the scalar.
      # The proc-entry default already rules out a phantom gtEof here; report
      # the zero-length header→scalar transition as whitespace explicitly.
      g.kind = gtWhitespace
    of '\0':
      # End of buffer right after the header line: keep gtCommand so the chunk
      # boundary capture is truthful. A chunked driver must rewind this
      # handoff — a fresh buffer cannot resume the scalar without the header
      # line. At a true end of file nothing follows, so keeping it is
      # harmless.
      g.kind = gtEof
    else:
      # illegal here. just don't parse a block scalar
      g.kind = gtNone
      g.state = gtOther
    if g.buf[pos] in {'\n', '\r'} and g.state == gtCommand:
      g.state = gtLongStringLit
  elif g.state == gtLongStringLit:
    # beware, this is the only token where we actually have to parse
    # indentation.

    g.kind = gtLongStringLit
    # first, we have to find the parent indentation of the block scalar, so that
    # we know when to stop
    if g.buf[pos] == '\0':
      # End of buffer while still inside the scalar (the cut-by-EOF exit below
      # keeps gtLongStringLit): report gtEof with the state preserved so the
      # final boundary capture stays truthful, instead of letting the stale
      # fallback below flip it to gtOther.
      g.kind = gtEof
      g.length = 0
      return
    if g.buf[pos] notin {'\n', '\r'}:
      # Buffer was modified and state is stale; fall back to normal parsing.
      # Consume nothing: flipping to `gtOther` already guarantees progress
      # (matching the gtCommand else arm), the next call re-parses this char
      # through the regular branches instead of silently swallowing it, and a
      # NUL here must not be stepped over (`inc` would push `pos` to `len + 1`
      # and the next call would read past the terminator). `g.length` must be
      # set explicitly — returning early skips the shared epilogue and would
      # leave the previous token's length on this zero-progress token.
      g.kind = gtNone
      g.state = gtOther
      g.length = 0
      return
    var lookbehind = pos - 1
    var headerStart = -1
    while lookbehind >= 0 and g.buf[lookbehind] notin {'\n', '\r'}:
      if headerStart == -1 and g.buf[lookbehind] in {'|', '>'}:
        headerStart = lookbehind
      dec(lookbehind)
    if headerStart == -1:
      # Block scalar header not found; buffer was modified. Fall back without
      # consuming the newline at `pos` (the gtOther whitespace branch tokenizes
      # it on the next call, keeping the consumer's row accounting intact) and
      # with `g.length` set, for the same reasons as the fallback above.
      g.kind = gtNone
      g.state = gtOther
      g.length = 0
      return
    var indentation = 1
    while g.buf[lookbehind + indentation] == ' ':
      inc(indentation)
    let headerAlone = g.buf[lookbehind + indentation] in {'|', '>'}
    var foundParent = false
    if headerAlone:
      # when the header is alone in a line, this line does not show the parent's
      # indentation, so we must go further. search the first previous line with
      # non-whitespace content.
      while lookbehind >= 0 and g.buf[lookbehind] in {'\n', '\r'}:
        dec(lookbehind)
        while lookbehind >= 0 and g.buf[lookbehind] in {' ', '\t'}:
          dec(lookbehind)
      # `>= 0`: landed on a real parent line whose indentation we honour.
      # `-1`: ran off the top, so there is no parent and the block is top level.
      foundParent = lookbehind >= 0
      # now, find the beginning of the line...
      while lookbehind >= 0 and g.buf[lookbehind] notin {'\n', '\r'}:
        dec(lookbehind)
      # ... and its indentation
      indentation = 1
      while g.buf[lookbehind + indentation] == ' ':
        inc(indentation)
    if headerAlone and not foundParent:
      # Alone header with nothing above it: top level. Keyed on `foundParent`,
      # not `lookbehind == -1`, because a reparse chunk can start on the parent
      # line itself (parent found, yet `lookbehind` still hits the buffer start);
      # forcing top level there would let the block swallow following keys. An
      # inline header (`key: |`) keeps its own indentation here — though the
      # document-marker check below still forces top level when the header's
      # own line is a `---` marker (`--- |`).
      indentation = 0
    elif g.buf[lookbehind + 1] == '-' and g.buf[lookbehind + 2] == '-' and
        g.buf[lookbehind + 3] == '-' and g.buf[lookbehind + 4] in {'\t' .. '\r', ' '}:
      # The line at `lookbehind + 1` — the parent line for an alone header,
      # otherwise the header's own line (`--- |`) — is a document start
      # marker, therefore we are at top level. No `lookbehind >= 0` guard:
      # `lookbehind` is the newline BEFORE that line, so it is -1 when the
      # line starts the buffer — which an incremental reparse chunk regularly
      # does. `lookbehind + 1` is the line's first char either way (>= 0,
      # never out of bounds).
      indentation = 0
    # because lookbehind was at newline char when calculating indentation, we're
    # off by one. fix that. top level's parent will have indentation of -1.
    let parentIndentation = indentation - 1

    # find first content
    while g.buf[pos] in {' ', '\n', '\r'}:
      if g.buf[pos] == ' ':
        inc(indentation)
      else:
        indentation = 0
      inc(pos)
    var minIndentation = indentation

    # for stupid edge cases, we must check whether an explicit indentation depth
    # is given at the header.
    while g.buf[headerStart] in {'>', '|', '+', '-'}:
      inc(headerStart)
    if g.buf[headerStart] in {'0' .. '9'}:
      minIndentation = min(minIndentation, ord(g.buf[headerStart]) - ord('0'))

    # process content lines
    while indentation > parentIndentation and g.buf[pos] != '\0':
      if (indentation < minIndentation and g.buf[pos] == '#') or (
        indentation == 0 and g.buf[pos] == '.' and g.buf[pos + 1] == '.' and
        g.buf[pos + 2] == '.' and g.buf[pos + 3] in {'\0', '\t' .. '\r', ' '}
      ):
        # comment after end of block scalar, or end of document
        break
      minIndentation = min(indentation, minIndentation)
      while g.buf[pos] notin {'\0', '\n', '\r'}:
        inc(pos)
      while g.buf[pos] in {' ', '\n', '\r'}:
        if g.buf[pos] == ' ':
          inc(indentation)
        else:
          indentation = 0
        inc(pos)

    if g.buf[pos] != '\0':
      # The scalar genuinely ended inside this buffer (dedent line, comment,
      # or `...` document end found at `pos`).
      g.state = gtOther
    # else: the buffer ended while scanning the scalar's extent — whether it
    # continues depends on lines this buffer does not contain (a chunked parse
    # cuts here). Keep gtLongStringLit so the boundary capture is truthful;
    # the chunked drivers rewind the handoff because a fresh buffer cannot
    # resume a block scalar (its extent needs the header and parent lines
    # above). At a true end of file nothing follows, so keeping it is
    # harmless.
  elif g.state == gtOther:
    # gtOther means 'inside YAML document'
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsYaml)
    of '-':
      inc(pos)
      if g.buf[pos] in {'\0', ' ', '\t' .. '\r'}:
        g.kind = gtPunctuation
      elif g.buf[pos] == '-' and (pos == 1 or g.buf[pos - 2] in {'\n', '\r'}):
        # start of line
        inc(pos)
        if g.buf[pos] == '-' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
          inc(pos)
          g.kind = gtKeyword
        else:
          yamlPossibleNumber(g, pos)
          if g.kind in {gtDecNumber, gtFloatNumber, gtHexNumber, gtOctNumber, gtDate}:
            if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
              g.kind = gtKey
          else:
            yamlClassifyToken(g, pos)
      else:
        yamlPossibleNumber(g, pos)
        if g.kind in {gtDecNumber, gtFloatNumber, gtHexNumber, gtOctNumber, gtDate}:
          if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
            g.kind = gtKey
        else:
          yamlClassifyToken(g, pos)
    of '.':
      if pos == 0 or g.buf[pos - 1] in {'\n', '\r'}:
        inc(pos)
        for i in 1 .. 2:
          if g.buf[pos] != '.':
            break
          inc(pos)
        if pos == g.start + 3:
          g.kind = gtKeyword
          g.state = gtNone
        else:
          yamlPlainStrLit(g, pos)
          yamlClassifyToken(g, pos)
      else:
        yamlPlainStrLit(g, pos)
        yamlClassifyToken(g, pos)
    of '?':
      inc(pos)
      if g.buf[pos] in {'\0', ' ', '\t' .. '\r'}:
        g.kind = gtPunctuation
      else:
        yamlPlainStrLit(g, pos)
        yamlClassifyToken(g, pos)
    of ':':
      inc(pos)
      # `pos > 1`, not `pos > 0`: `pos` is already past the ':', so the char
      # before it is `pos - 2`, which only exists from `pos == 2` on. With the
      # ':' at buffer start (`pos == 1`) the old guard read `g.buf[-1]` —
      # out-of-bounds garbage that differs between a full parse and an
      # incremental chunk starting at that line.
      if g.buf[pos] in {'\0', '\t' .. '\r', ' ', '\'', '\"'} or
          (pos > 1 and g.buf[pos - 2] in {'}', ']', '\"', '\''}):
        g.kind = gtPunctuation
      else:
        yamlPlainStrLit(g, pos)
        yamlClassifyToken(g, pos)
    of '[', ']', '{', '}', ',':
      inc(pos)
      g.kind = gtPunctuation
    of '\"':
      inc(pos)
      g.yamlIsKey = false
      var tempPos = pos
      while g.buf[tempPos] != '\0':
        case g.buf[tempPos]
        of '\"':
          inc(tempPos)
          while g.buf[tempPos] in {' ', '\t'}:
            inc(tempPos)
          if g.buf[tempPos] == ':' and g.buf[tempPos + 1] in {'\0', '\t' .. '\r', ' '}:
            g.yamlIsKey = true
          break
        of '\\':
          # Keep the lookahead line-bounded: skipping `\<newline>` would make
          # this line's key-ness depend on later lines (a backward dependency
          # incremental re-highlighting cannot see), and `\` at end of buffer
          # would jump past the NUL terminator (same rule as `skipEscapedChar`).
          if g.buf[tempPos + 1] in eolChars:
            break
          inc(tempPos, 2)
        of '\n', '\r':
          break
        else:
          inc(tempPos)
      g.state = if g.yamlIsKey: gtKey else: gtStringLit
      g.kind = if g.yamlIsKey: gtKey else: gtStringLit
      # Continue reading string content until escape or end quote. This
      # deliberately does NOT stop at newlines, so the opener token can span
      # lines (unlike the per-line fold in the continuation branch above).
      # Still chunk-consistent: `g.state` is already gtStringLit/gtKey here,
      # so each interior line-boundary capture stores the correct resumable
      # state.
      while g.buf[pos] notin {'\0', '\\', '\"'}:
        inc(pos)
    of '\'':
      g.yamlIsKey = false
      var tempPos = pos + 1
      while g.buf[tempPos] != '\0':
        if g.buf[tempPos] == '\'':
          if g.buf[tempPos + 1] == '\'':
            inc(tempPos, 2) # '' escape
          else:
            inc(tempPos)
            while g.buf[tempPos] in {' ', '\t'}:
              inc(tempPos)
            if g.buf[tempPos] == ':' and g.buf[tempPos + 1] in {'\0', '\t' .. '\r', ' '}:
              g.yamlIsKey = true
            break
        elif g.buf[tempPos] in {'\n', '\r'}:
          break
        else:
          inc(tempPos)
      g.state = gtCharLit
      g.kind = gtNone
    of '!':
      g.kind = gtTagStart
      inc(pos)
      if g.buf[pos] == '<':
        # literal tag (e.g. `!<tag:yaml.org,2002:str>`)
        while g.buf[pos] notin {'\0', '>', '\t' .. '\r', ' '}:
          inc(pos)
        if g.buf[pos] == '>':
          inc(pos)
      else:
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-'}:
          inc(pos)
        case g.buf[pos]
        of '!':
          # prefixed tag (e.g. `!!str`)
          inc(pos)
          while g.buf[pos] notin {'\0', '\t' .. '\r', ' ', ',', '[', ']', '{', '}'}:
            inc(pos)
        of '\0', '\t' .. '\r', ' ':
          discard
        else:
          # local tag (e.g. `!nim:system:int`)
          while g.buf[pos] notin {'\0', '\t' .. '\r', ' '}:
            inc(pos)
    of '&':
      g.kind = gtLabel
      while g.buf[pos] notin {'\0', '\t' .. '\r', ' '}:
        inc(pos)
    of '*':
      g.kind = gtReference
      while g.buf[pos] notin {'\0', '\t' .. '\r', ' '}:
        inc(pos)
    of '|', '>':
      # this can lead to incorrect tokenization when | or > appear inside flow
      # content. checking whether we're inside flow content is not
      # chomsky type-3, so we won't do that here.
      g.kind = gtCommand
      g.state = gtCommand
      inc(pos)
      while g.buf[pos] in {'0' .. '9', '+', '-'}:
        inc(pos)
    of '0' .. '9':
      yamlPossibleNumber(g, pos)
      if g.kind in {gtDecNumber, gtFloatNumber, gtHexNumber, gtOctNumber, gtDate}:
        if g.buf[pos] == ':' and g.buf[pos + 1] in {'\0', '\t' .. '\r', ' '}:
          g.kind = gtKey
      else:
        yamlClassifyToken(g, pos)
    of '\0':
      g.kind = gtEof
    else:
      yamlPlainStrLit(g, pos)
      yamlClassifyToken(g, pos)
  else:
    # outside document
    case g.buf[pos]
    of '%':
      if pos == 0 or g.buf[pos - 1] in {'\n', '\r'}:
        g.kind = gtDirective
        while g.buf[pos] notin {'\0', '\n', '\r'}:
          inc(pos)
      else:
        g.state = gtOther
        yamlPlainStrLit(g, pos)
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsYaml)
    of '\0':
      g.kind = gtEof
    else:
      g.kind = gtNone
      g.state = gtOther
  g.length = pos - g.pos
  g.pos = pos
