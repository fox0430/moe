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

import tokenizer
from lexer/end_lexer import endLine

# `isKeyword` binary-searches these, so they must stay byte-sorted.
const
  goKeywords* = [
    "break", "case", "chan", "const", "continue", "default", "defer", "else",
    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
    "package", "range", "return", "select", "struct", "switch", "type", "var",
  ]

  goBooleans* = ["false", "nil", "true"]

  goSpecialVars* = ["iota"]

  goBuiltins* = [
    "any", "append", "bool", "byte", "cap", "clear", "close", "comparable", "complex",
    "complex128", "complex64", "copy", "delete", "error", "float32", "float64", "imag",
    "int", "int16", "int32", "int64", "int8", "len", "make", "max", "min", "new",
    "panic", "print", "println", "real", "recover", "rune", "string", "uint", "uint16",
    "uint32", "uint64", "uint8", "uintptr",
  ]

proc scanRawString(g: var GeneralTokenizer, position: int): int =
  ## Consume a Go raw string body through its closing backtick. Raw strings have
  ## no escape processing — every byte is literal. On EOF `g.state` is left as
  ## `gtLongStringLit` so the next line resumes inside the string; on close it
  ## reverts to `gtNone`. Stops past a newline that leads into a markdown ```
  ## fence so the outer `markdownNextToken` can close the code block.
  result = position
  while true:
    case g.buf[result]
    of '\0':
      return
    of '`':
      g.state = gtNone
      return result + 1
    of '\n':
      inc(result)
      var scan = result
      var spaces = 0
      while g.buf[scan] == ' ' and spaces < 3:
        inc(scan)
        inc(spaces)
      if g.buf[scan] == '`' and g.buf[scan + 1] == '`' and g.buf[scan + 2] == '`':
        return
    else:
      inc(result)

proc goNumber(g: var GeneralTokenizer, position: int): int =
  ## Handle Go numeric literals: prefixed `0x`/`0b`/`0o` integers, hex floats
  ## with binary exponent, digit separators (`_`), and the imaginary suffix
  ## (`i`). A leading `.` also lands here via the main dispatch, so a plain
  ## `.5` is recognised as a float.
  const
    decChars = {'0' .. '9'}
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    binChars = {'0', '1'}
    octChars = {'0' .. '7'}
  result = position
  if g.buf[result] == '0' and g.peek(result) in {'x', 'X'}:
    g.kind = gtHexNumber
    inc(result, 2)
    while g.buf[result] in hexChars or g.buf[result] == '_':
      inc(result)
    if g.buf[result] == '.':
      g.kind = gtFloatNumber
      inc(result)
      while g.buf[result] in hexChars or g.buf[result] == '_':
        inc(result)
    if g.buf[result] in {'p', 'P'}:
      g.kind = gtFloatNumber
      inc(result)
      if g.buf[result] in {'+', '-'}:
        inc(result)
      while g.buf[result] in decChars or g.buf[result] == '_':
        inc(result)
    if g.buf[result] == 'i':
      inc(result)
    return
  if g.buf[result] == '0' and g.peek(result) in {'b', 'B'}:
    g.kind = gtBinNumber
    inc(result, 2)
    while g.buf[result] in binChars or g.buf[result] == '_':
      inc(result)
    if g.buf[result] == 'i':
      inc(result)
    return
  if g.buf[result] == '0' and g.peek(result) in {'o', 'O'}:
    g.kind = gtOctNumber
    inc(result, 2)
    while g.buf[result] in octChars or g.buf[result] == '_':
      inc(result)
    if g.buf[result] == 'i':
      inc(result)
    return
  # Decimal (may promote to float on `.` or `e`), possibly imaginary. Go also
  # accepts a leading `0` before an all-octal digit run (`0755`), but keeping
  # it as `gtDecNumber` gives the same colour and avoids conflating with the
  # explicit `0o` form.
  g.kind = gtDecNumber
  while g.buf[result] in decChars or g.buf[result] == '_':
    inc(result)
  if g.buf[result] == '.':
    g.kind = gtFloatNumber
    inc(result)
    while g.buf[result] in decChars or g.buf[result] == '_':
      inc(result)
  if g.buf[result] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(result)
    if g.buf[result] in {'+', '-'}:
      inc(result)
    while g.buf[result] in decChars or g.buf[result] == '_':
      inc(result)
  if g.buf[result] == 'i':
    inc(result)

proc goNextToken*(g: var GeneralTokenizer) =
  const
    decChars = {'0' .. '9'}
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    symCharsLocal = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
    # `.` and `:` only ever *start* their own operators/punctuation and have
    # explicit branches below. Excluding them keeps `+.5` from lexing as `+.`
    # + `5` and lets an isolated `:` render as punctuation.
    goOpChars = opChars - {'.', ':'}
  var pos = g.pos
  g.start = g.pos

  if g.state == gtLongStringLit:
    # Multi-line raw string resume.
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongStringLit
      pos = g.scanRawString(pos)
  elif g.state == gtLongComment:
    # Multi-line `/* ... */` block comment. Not nested in Go.
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongComment
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '*':
          inc(pos)
          if g.buf[pos] == '/':
            inc(pos)
            g.state = gtNone
            break
        else:
          inc(pos)
  elif g.state == gtStringLit and g.buf[pos] notin {'\0', '\r', '\n'}:
    # Interpreted string parked on a backslash by `scanStringBody`. Go's
    # interpreted strings are line-bounded, so this only ever resumes mid-line.
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        if pos > g.start:
          # Emit the plain run collected so far as its own gtStringLit token.
          # The next call resumes at the backslash and takes the escape branch
          # immediately (pos == g.start). Without this split, `kind` would be
          # overwritten to gtEscapeSequence and the preceding chars would
          # render as escape too.
          break
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x', 'X':
          inc(pos)
          if g.buf[pos] in hexChars:
            inc(pos)
          if g.buf[pos] in hexChars:
            inc(pos)
        of 'u':
          inc(pos)
          var n = 0
          while n < 4 and g.buf[pos] in hexChars:
            inc(pos)
            inc(n)
        of 'U':
          inc(pos)
          var n = 0
          while n < 8 and g.buf[pos] in hexChars:
            inc(pos)
            inc(n)
        of '0' .. '7':
          var digits = 0
          while digits < 3 and g.buf[pos] in {'0' .. '7'}:
            inc(pos)
            inc(digits)
        of '\0', '\r', '\n':
          g.state = gtNone
        else:
          inc(pos)
        break
      of '\0', '\r', '\n':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  else:
    # A string resume landing on EOL/EOF has no content left; end it rather
    # than emit an empty token.
    g.state = gtNone
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '/':
      if g.peek(pos) == '/':
        g.kind = gtComment
        pos = g.endLine(pos)
      elif g.peek(pos) == '*':
        g.kind = gtLongComment
        g.state = gtLongComment
        inc(pos, 2)
        while true:
          case g.buf[pos]
          of '\0':
            break
          of '*':
            inc(pos)
            if g.buf[pos] == '/':
              inc(pos)
              g.state = gtNone
              break
          else:
            inc(pos)
      else:
        g.kind = gtOperator
        while g.buf[pos] in goOpChars:
          # `//` opens a comment and `/*` opens a block comment — neither must
          # be absorbed into a `/=` or similar operator run.
          if g.buf[pos] == '/' and g.peek(pos) in {'/', '*'}:
            break
          inc(pos)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symCharsLocal:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(goKeywords, id) >= 0:
        g.kind = gtKeyword
      elif isKeyword(goBooleans, id) >= 0:
        g.kind = gtBoolean
      elif isKeyword(goSpecialVars, id) >= 0:
        g.kind = gtSpecialVar
      elif isKeyword(goBuiltins, id) >= 0:
        g.kind = gtBuiltin
      else:
        g.kind = gtIdentifier
    of '0' .. '9':
      pos = g.goNumber(pos)
    of '.':
      if g.peek(pos) in decChars:
        pos = g.goNumber(pos)
      elif g.peek(pos) == '.' and g.peek(pos, 2) == '.':
        # `...` variadic / slice-expansion.
        g.kind = gtOperator
        inc(pos, 3)
      else:
        inc(pos)
        g.kind = gtPunctuation
    of ':':
      if g.peek(pos) == '=':
        # Short variable declaration operator.
        g.kind = gtOperator
        inc(pos, 2)
      else:
        inc(pos)
        g.kind = gtPunctuation
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      pos = g.scanStringBody(pos, '\"')
    of '\'':
      # Rune literal — line-bounded like a C char literal.
      inc(pos)
      g.kind = gtCharLit
      while true:
        case g.buf[pos]
        of '\0', '\r', '\n':
          break
        of '\'':
          inc(pos)
          break
        of '\\':
          inc(pos)
          g.skipEscapedChar(pos)
        else:
          inc(pos)
    of '`':
      inc(pos)
      g.kind = gtLongStringLit
      g.state = gtLongStringLit
      pos = g.scanRawString(pos)
    of '(', ')', '[', ']', '{', '}', ',', ';':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in goOpChars:
        g.kind = gtOperator
        while g.buf[pos] in goOpChars:
          if g.buf[pos] == '/' and g.peek(pos) in {'/', '*'}:
            break
          inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "goNextToken: produced an empty token"
  g.pos = pos
