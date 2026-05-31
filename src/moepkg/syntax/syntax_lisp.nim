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

import tokenizer
from lexer/end_lexer import endLine

const lispKeywords* = [
  "and", "block", "case", "catch", "cond", "decf", "declaim", "declare", "defclass",
  "defconstant", "defgeneric", "define-condition", "define-method-combination",
  "defmacro", "defmethod", "defpackage", "defparameter", "defsetf", "defstruct",
  "deftype", "defun", "defvar", "do", "do*", "dolist", "dotimes", "ecase", "error",
  "etypecase", "eval-when", "flet", "format", "funcall", "function", "go",
  "handler-bind", "handler-case", "if", "in-package", "labels", "lambda", "let", "let*",
  "loop", "macrolet", "make-instance", "multiple-value-bind", "nil", "or", "proclaim",
  "prog1", "progn", "provide", "require", "restart-case", "return", "return-from",
  "setf", "setq", "t", "tagbody", "the", "throw", "typecase", "unless",
  "unwind-protect", "values", "when", "with-open-file", "with-slots",
]

proc lispNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    lispSymChars = {
      'A' .. 'Z',
      'a' .. 'z',
      '0' .. '9',
      '_',
      '-',
      '*',
      '+',
      '?',
      '!',
      '<',
      '>',
      '=',
      '/',
      '&',
      '%',
      '\x80' .. '\xFF',
    }
  var pos = g.pos
  g.start = g.pos
  if g.state == gtLongComment:
    # Continuation of #| |# block comment
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongComment
      var depth = g.commentDepth
      while true:
        case g.buf[pos]
        of '\0':
          g.commentDepth = depth
          break
        of '|':
          inc(pos)
          if g.buf[pos] == '#':
            inc(pos)
            if depth == 0:
              g.state = gtNone
              g.commentDepth = 0
              break
            else:
              dec(depth)
        of '#':
          inc(pos)
          if g.buf[pos] == '|':
            inc(pos)
            inc(depth)
        else:
          inc(pos)
  elif g.state == gtStringLit:
    if g.buf[pos] == '\0':
      # Empty line inside a multi-line string. Emit nothing (gtEof) but keep the
      # string state so the literal resumes on the next line.
      g.kind = gtEof
    else:
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
            # Trailing backslash at the line end: the literal still continues on
            # the next line, so keep the string state.
            g.state = gtStringLit
          else:
            inc(pos)
          break
        of '\0':
          # Still unterminated at the line end: keep spanning onto the next line.
          g.state = gtStringLit
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
    of ';':
      g.kind = gtComment
      pos = g.endLine(pos)
    of '#':
      inc(pos)
      case g.buf[pos]
      of '|':
        # Block comment #| ... |#
        inc(pos)
        g.kind = gtLongComment
        g.state = gtLongComment
        g.commentDepth = 0
        var depth = 0
        while true:
          case g.buf[pos]
          of '\0':
            g.commentDepth = depth
            break
          of '|':
            inc(pos)
            if g.buf[pos] == '#':
              inc(pos)
              if depth == 0:
                g.state = gtNone
                g.commentDepth = 0
                break
              else:
                dec(depth)
          of '#':
            inc(pos)
            if g.buf[pos] == '|':
              inc(pos)
              inc(depth)
          else:
            inc(pos)
      of '\'':
        # Function quote #'
        inc(pos)
        g.kind = gtOperator
      of '\\':
        # Character literal #\x
        inc(pos)
        g.kind = gtCharLit
        if g.buf[pos] notin {'\0', '\x0D', '\x0A'}:
          # Read the character name (e.g., #\space, #\newline)
          if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
            while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
              inc(pos)
          else:
            inc(pos)
      of '(':
        # Vector literal #(
        inc(pos)
        g.kind = gtPunctuation
      of 'x', 'X':
        # Hex number #x
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in hexChars:
          inc(pos)
      of 'o', 'O':
        # Octal number #o
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
      of 'b', 'B':
        # Binary number #b
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in binChars:
          inc(pos)
      else:
        g.kind = gtOperator
    of '\'':
      # Quote
      inc(pos)
      g.kind = gtOperator
    of '`':
      # Backquote
      inc(pos)
      g.kind = gtOperator
    of ',':
      # Unquote
      inc(pos)
      if g.buf[pos] == '@':
        # Splice ,@
        inc(pos)
      g.kind = gtOperator
    of '(', ')':
      inc(pos)
      g.kind = gtPunctuation
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          # Unterminated at the line end. Lisp strings span lines, so keep the
          # string state so the next line continues as a string literal. This
          # matches the full reparse, which sees the buffer as one '\n'-joined
          # string and runs the literal past the newline.
          g.state = gtStringLit
          break
        of '\"':
          inc(pos)
          break
        of '\\':
          g.state = g.kind
          break
        else:
          inc(pos)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in lispSymChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(lispKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '-':
      # Could be negative number or symbol
      if g.buf[pos + 1] in {'0' .. '9'}:
        inc(pos)
        pos = generalNumber(g, pos)
      else:
        var id = ""
        while g.buf[pos] in lispSymChars:
          add(id, g.buf[pos])
          inc(pos)
        if id.len > 0:
          if isKeyword(lispKeywords, id) >= 0:
            g.kind = gtKeyword
          else:
            g.kind = gtIdentifier
        else:
          inc(pos)
          g.kind = gtOperator
    of '*', '+', '?', '!', '<', '>', '=', '/', '&', '%':
      # Could be a symbol starting with these chars
      var id = ""
      while g.buf[pos] in lispSymChars:
        add(id, g.buf[pos])
        inc(pos)
      if id.len > 0:
        if isKeyword(lispKeywords, id) >= 0:
          g.kind = gtKeyword
        else:
          g.kind = gtIdentifier
      else:
        inc(pos)
        g.kind = gtOperator
    of '0':
      pos = generalNumber(g, pos)
    of '1' .. '9':
      pos = generalNumber(g, pos)
    of '\0':
      g.kind = gtEof
    else:
      inc(pos)
      g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "lispNextToken: produced an empty token"
  g.pos = pos
