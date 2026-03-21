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
from lexer/end_lexer import endLine

const haskellKeywords* = [
  "_", "case", "class", "data", "default", "deriving", "do", "else", "if", "import",
  "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "then",
  "type", "where",
]

proc haskellNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state in {gtLongComment, gtDocLongComment}:
    # Continuation of {- -} block comment
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = g.state
      let nested = hasNestedComments in flagsHaskell
      var depth = g.commentDepth
      while true:
        case g.buf[pos]
        of '\0':
          g.commentDepth = depth
          break
        of '-':
          inc(pos)
          if g.buf[pos] == '}':
            inc(pos)
            if depth == 0:
              g.state = gtNone
              g.commentDepth = 0
              break
            elif nested:
              dec(depth)
        of '{':
          inc(pos)
          if g.buf[pos] == '-':
            inc(pos)
            if nested:
              inc(depth)
        else:
          inc(pos)
  elif g.state == gtStringLit:
    g.kind = gtStringLit
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
        else:
          inc(pos)
        break
      of '\0', '\x0D', '\x0A':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\x09' .. '\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
        inc(pos)
    of '-':
      # Check for -- line comment
      if g.buf[pos + 1] == '-':
        g.kind = gtComment
        pos = g.endLine(pos)
      else:
        # Treat as operator (including ->, etc.)
        g.kind = gtOperator
        while g.buf[pos] in opChars:
          inc(pos)
    of '{':
      pos = g.lexCurlyOpen(pos, flagsHaskell)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(haskellKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in binChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of 'x', 'X':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in hexChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of 'o', 'O', '0' .. '7':
        g.kind = gtOctNumber
        if g.buf[pos] in {'o', 'O'}:
          inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      else:
        pos = generalNumber(g, pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
    of '1' .. '9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '\"', '\'':
      inc(pos)
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\"', '\'':
          inc(pos)
          break
        of '\\':
          g.state = g.kind
          break
        else:
          inc(pos)
    of '(', ')', '[', ']', '}', ':', ',', ';', '.':
      inc(pos)
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
    assert false, "haskellToken: produced an empty token"
  g.pos = pos
