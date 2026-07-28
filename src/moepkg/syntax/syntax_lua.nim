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
  luaKeywords* = [
    "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
    "in", "local", "not", "or", "repeat", "return", "then", "until", "while",
  ]

  luaBooleans* = ["false", "nil", "true"]

  luaBuiltins* = [
    "assert", "collectgarbage", "coroutine", "debug", "dofile", "error", "getmetatable",
    "io", "ipairs", "load", "loadfile", "loadstring", "math", "next", "os", "package",
    "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset", "require",
    "select", "setmetatable", "string", "table", "tonumber", "tostring", "type",
    "unpack", "utf8", "xpcall",
  ]

  luaSpecialVars* = ["_ENV", "_G", "_VERSION"]

proc longBracketLevel(g: GeneralTokenizer, position: int): int =
  ## `=` run length of a long bracket opening at `position` (`[[` is 0, `[==[`
  ## is 2), or -1 when `position` does not start one.
  var pos = position
  if g.buf[pos] != '[':
    return -1
  inc(pos)
  var level = 0
  while g.buf[pos] == '=':
    inc(level)
    inc(pos)
  if g.buf[pos] == '[': level else: -1

proc scanLongBracket(g: var GeneralTokenizer, position: int, level: int): int =
  ## Consume a long string/comment body through its closing `]` `=`*level `]`.
  ## On EOF `g.state` is left as-is so the next line resumes inside it, and
  ## `g.lang.lua.longBracketLevel` stays live so the next line finds the same
  ## terminator. On close we clear both: without the clear, post-close
  ## `LangState` snapshots would carry a semantically dead level, and the
  ## incremental highlighter's convergence check would treat unrelated later
  ## lines as divergent whenever an earlier long bracket's `=` count changed.
  result = position
  while true:
    case g.buf[result]
    of '\0':
      return
    of ']':
      var
        pos = result + 1
        n = 0
      while g.buf[pos] == '=':
        inc(n)
        inc(pos)
      if n == level and g.buf[pos] == ']':
        g.state = gtNone
        g.lang.lua.longBracketLevel = 0
        return pos + 1
      inc(result)
    else:
      inc(result)

proc luaNumber(g: var GeneralTokenizer, position: int): int =
  ## Hex literals may carry a fraction and a binary exponent (`0x1p-4`), which
  ## `generalNumber` does not handle; everything else falls through to it.
  const
    decChars = {'0' .. '9'}
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  result = position
  if g.buf[result] == '0' and g.peek(result) in {'x', 'X'}:
    g.kind = gtHexNumber
    inc(result, 2)
    while g.buf[result] in hexChars:
      inc(result)
    if g.buf[result] == '.':
      g.kind = gtFloatNumber
      inc(result)
      while g.buf[result] in hexChars:
        inc(result)
    if g.buf[result] in {'p', 'P'}:
      g.kind = gtFloatNumber
      inc(result)
      if g.buf[result] in {'+', '-'}:
        inc(result)
      while g.buf[result] in decChars:
        inc(result)
    return
  result = generalNumber(g, result)

proc luaNextToken*(g: var GeneralTokenizer) =
  const
    decChars = {'0' .. '9'}
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    symCharsLocal = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
    # `.`/`:` only ever *start* a Lua operator, and have their own branches
    # below. Excluding them keeps `-.5` from lexing as `-.` + `5`.
    luaOpChars = opChars - {'.', ':'}
  var pos = g.pos
  g.start = g.pos

  if g.state in {gtLongComment, gtLongStringLit}:
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = g.state
      pos = g.scanLongBracket(pos, g.lang.lua.longBracketLevel)
  elif g.state == gtStringLit and g.buf[pos] notin {'\0', '\r', '\n'}:
    # Resume a string parked on a backslash by `scanStringBody`. Quoted
    # strings are line-bounded, so this only ever resumes mid-line.
    g.kind = gtStringLit
    let quote = g.lang.lua.stringQuote
    while true:
      case g.buf[pos]
      of '\\':
        if pos > g.start:
          # Emit the run of plain string content collected so far as its own
          # gtStringLit token. The next call resumes at the backslash and
          # takes the escape branch immediately (pos == g.start). Without this
          # split, kind would be overwritten to gtEscapeSequence and the
          # preceding chars would render as escape too.
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
        of '0' .. '9':
          var digits = 0
          while digits < 3 and g.buf[pos] in decChars:
            inc(pos)
            inc(digits)
        of 'u':
          inc(pos)
          if g.buf[pos] == '{':
            inc(pos)
            while g.buf[pos] in hexChars:
              inc(pos)
            if g.buf[pos] == '}':
              inc(pos)
        of '\0', '\r', '\n':
          # Trailing backslash at EOL: stay line-bounded.
          g.state = gtNone
        else:
          inc(pos)
        break
      of '\0', '\r', '\n':
        g.state = gtNone
        break
      of '\"', '\'':
        if g.buf[pos] == quote:
          inc(pos)
          g.state = gtNone
          break
        else:
          inc(pos)
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
    of '-':
      if g.peek(pos) == '-':
        inc(pos, 2)
        let level = g.longBracketLevel(pos)
        if level >= 0:
          g.kind = gtLongComment
          g.state = gtLongComment
          g.lang.lua.longBracketLevel = level
          inc(pos, level + 2)
          pos = g.scanLongBracket(pos, level)
        else:
          g.kind = gtComment
          pos = g.endLine(pos)
      else:
        g.kind = gtOperator
        while g.buf[pos] in luaOpChars:
          inc(pos)
    of '[':
      let level = g.longBracketLevel(pos)
      if level >= 0:
        g.kind = gtLongStringLit
        g.state = gtLongStringLit
        g.lang.lua.longBracketLevel = level
        inc(pos, level + 2)
        pos = g.scanLongBracket(pos, level)
      else:
        inc(pos)
        g.kind = gtPunctuation
    of '#':
      # `#!` is not valid Lua anywhere, so matching on the pair (not on line
      # position) keeps a mid-file reparse identical to a full parse. A bare
      # `#` is the length operator.
      if g.peek(pos) == '!':
        g.kind = gtComment
        pos = g.endLine(pos)
      else:
        inc(pos)
        g.kind = gtOperator
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symCharsLocal:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(luaKeywords, id) >= 0:
        g.kind = gtKeyword
      elif isKeyword(luaBooleans, id) >= 0:
        g.kind = gtBoolean
      elif isKeyword(luaSpecialVars, id) >= 0:
        g.kind = gtSpecialVar
      elif isKeyword(luaBuiltins, id) >= 0:
        g.kind = gtBuiltin
      else:
        g.kind = gtIdentifier
    of '0' .. '9':
      pos = g.luaNumber(pos)
    of '.':
      if g.peek(pos) in decChars:
        pos = g.luaNumber(pos)
      elif g.peek(pos) == '.':
        # `..` concat, `...` vararg
        g.kind = gtOperator
        inc(pos, 2)
        if g.buf[pos] == '.':
          inc(pos)
      else:
        inc(pos)
        g.kind = gtPunctuation
    of ':':
      if g.peek(pos) == ':':
        # `::label::` goto target
        g.kind = gtLabel
        inc(pos, 2)
        while g.buf[pos] in symCharsLocal:
          inc(pos)
        if g.buf[pos] == ':' and g.peek(pos) == ':':
          inc(pos, 2)
      else:
        inc(pos)
        g.kind = gtPunctuation
    of '\"', '\'':
      let quote = g.buf[pos]
      inc(pos)
      g.kind = gtStringLit
      # Line-bounded: a string spanning lines would become one token whose
      # interior boundary state breaks incremental resume.
      pos = g.scanStringBody(pos, quote)
      if g.state == gtStringLit:
        g.lang.lua.stringQuote = quote
    of '(', ')', '{', '}', ']', ';', ',':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in luaOpChars:
        g.kind = gtOperator
        while g.buf[pos] in luaOpChars:
          # `--` opens a comment and must never be absorbed into an operator
          # run: without this break, `x<--foo` lexes `<--` as one operator and
          # loses the comment.
          if g.buf[pos] == '-' and g.peek(pos) == '-':
            break
          inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "luaNextToken: produced an empty token"
  g.pos = pos
