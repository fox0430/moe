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

import flags, tokenizer, lexer

const pythonKeywords* = [
  "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
  "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
  "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
  "raise", "return", "try", "while", "with", "yield",
]

proc pythonNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos

  # If a state continuation begins at end-of-buffer, emit gtEof rather than
  # producing an empty token.
  if g.buf[pos] == '\0' and g.state in {gtDocLongComment, gtStringLit}:
    g.kind = gtEof
    g.state = gtNone
    g.lang.python.commentDepth = 0
    g.length = 0
    g.pos = pos
    return

  # A single-line string continuation cannot cross a newline; drop the state
  # so the main path can tokenize the newline as whitespace.
  if g.state == gtStringLit and g.buf[pos] in {'\r', '\n'}:
    g.state = gtNone
    g.lang.python.commentDepth = 0

  if g.state == gtDocLongComment:
    # Continuation of triple-quoted docstring across lines.
    # commentDepth: 1 = """, 2 = '''
    g.kind = gtDocLongComment
    let quoteChar = if g.lang.python.commentDepth == 1: '\"' else: '\''
    while true:
      case g.buf[pos]
      of '\0':
        break
      of '\\':
        inc(pos)
        if g.buf[pos] != '\0':
          inc(pos)
      of '\"', '\'':
        if g.buf[pos] == quoteChar and g.peek(pos) == quoteChar and
            g.peek(pos, 2) == quoteChar:
          inc(pos, 3)
          g.state = gtNone
          g.lang.python.commentDepth = 0
          break
        else:
          inc(pos)
      else:
        inc(pos)
  elif g.state == gtStringLit:
    # Continuation of a single-line string after a \ escape split.
    # commentDepth: 1 = ", 2 = '
    g.kind = gtStringLit
    let quoteChar = if g.lang.python.commentDepth == 2: '\'' else: '\"'
    while true:
      case g.buf[pos]
      of '\\':
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
          while g.buf[pos] in {'0' .. '9'}:
            inc(pos)
        of '\0':
          g.state = gtNone
          g.lang.python.commentDepth = 0
        else:
          inc(pos)
        break
      of '\0', '\r', '\n':
        g.state = gtNone
        g.lang.python.commentDepth = 0
        break
      of '\"', '\'':
        if g.buf[pos] == quoteChar:
          inc(pos)
          g.state = gtNone
          g.lang.python.commentDepth = 0
          break
        else:
          inc(pos)
      else:
        inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsPython)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(pythonKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '0' .. '9':
      pos = g.scanRadixNumber(pos)
      # Python allows a single trailing type letter (e.g. the `j` of an
      # imaginary literal, or a stray suffix); the shared scanner leaves it.
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '\"', '\'':
      let quoteChar = g.buf[pos]
      inc(pos)
      if g.buf[pos] == quoteChar and g.peek(pos) == quoteChar:
        # Triple-quoted string (docstring)
        inc(pos, 2)
        g.kind = gtDocLongComment
        while true:
          case g.buf[pos]
          of '\0':
            g.state = gtDocLongComment
            g.lang.python.commentDepth = if quoteChar == '\"': 1 else: 2
            break
          of '\\':
            inc(pos)
            if g.buf[pos] != '\0':
              inc(pos)
          of '\"', '\'':
            if g.buf[pos] == quoteChar and g.peek(pos) == quoteChar and
                g.peek(pos, 2) == quoteChar:
              inc(pos, 3)
              break
            else:
              inc(pos)
          else:
            inc(pos)
      else:
        g.kind = gtStringLit
        pos = g.scanStringBody(pos, quoteChar)
        if g.state == gtStringLit:
          # scanStringBody parked on a backslash; record which quote opened the
          # literal so the resume path picks the right terminator.
          # commentDepth: 1 = ", 2 = '
          g.lang.python.commentDepth = if quoteChar == '\"': 1 else: 2
    of '(':
      inc(pos)
      g.kind = gtPunctuation
    of ')', '[', ']', '{', '}', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of ':':
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
    assert false, "pythonNextToken: produced an empty token"
  g.pos = pos
