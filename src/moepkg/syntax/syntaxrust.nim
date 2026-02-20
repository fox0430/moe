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

  rustBooleans = ["false", "true"]

  rustBuiltins* = [
    "AsMut", "AsRef", "Box", "Clone", "Copy", "Default", "DoubleEndedIterator", "Drop",
    "Eq", "ErrSliceConcatExt", "Error", "ExactSizeIterator", "Extend", "Fn", "FnMut",
    "FnOnce", "From", "Into", "IntoIterator", "Iterator", "None", "Ok", "Option", "Ord",
    "PartialEq", "PartialOrd", "Result", "Self", "Send", "Sized", "Some", "String",
    "Sync", "ToOwned", "ToString", "Variant", "Vec", "bool", "char", "f32", "f64",
    "i128", "i16", "i32", "i64", "i8", "isize", "str", "u128", "u16", "u32", "u64",
    "u8", "usize",
  ]

proc rustGetKeyword(id: string): TokenClass =
  if binarySearch(rustKeywords, id) > -1:
    return gtKeyword
  if binarySearch(rustBooleans, id) > -1:
    return gtBoolean
  if binarySearch(rustBuiltins, id) > -1:
    return gtBuiltin
  else:
    gtIdentifier

template isCharLit*(g: var GeneralTokenizer, position: int): bool =
  (g.buf.high > pos + 1) and (g.buf[position + 2] == '\'')

proc rustNextToken*(g: var GeneralTokenizer, flags: TokenizerFlags = {}) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
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
      of '\0', '\r', '\n':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  elif g.state == gtLongComment:
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongComment
    var nested = g.commentDepth
    while g.kind != gtEof:
      case g.buf[pos]
      of '*':
        inc(pos)
        if g.buf[pos] == '/':
          inc(pos)
          if nested == 0:
            g.state = gtNone
            g.commentDepth = 0
            break
          else:
            dec(nested)
      of '/':
        inc(pos)
        if g.buf[pos] == '*':
          inc(pos)
          inc(nested)
      of '\0':
        g.commentDepth = nested
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
        g.kind = gtComment
        while not (g.buf[pos] in {'\0', '\n', '\r'}):
          inc(pos)
      elif g.buf[pos] == '*':
        g.kind = gtLongComment
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
          of '/':
            inc(pos)
            if g.buf[pos] == '*':
              inc(pos)
              if hasNestedComments in flags:
                inc(nested)
          of '\0':
            g.state = gtLongComment
            g.commentDepth = nested
            break
          else:
            inc(pos)
      else:
        g.kind = gtOperator
        while g.buf[pos] in opChars:
          inc(pos)
    of '#':
      inc(pos)
      if hasPreprocessor in flags:
        g.kind = gtPreprocessor
        while g.buf[pos] in {' ', '\t'}:
          inc(pos)
        while g.buf[pos] in symChars:
          inc(pos)
      else:
        g.kind = gtOperator
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      g.kind = rustGetKeyword(id)
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in binChars:
          inc(pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
          inc(pos)
      of 'x', 'X':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in hexChars:
          inc(pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
          inc(pos)
      of 'o', 'O':
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
          inc(pos)
      of '0' .. '7':
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
          inc(pos)
      else:
        pos = generalNumber(g, pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
          inc(pos)
    of '1' .. '9':
      pos = generalNumber(g, pos)
      while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
        inc(pos)
    of '\'':
      # TODO: Maybe need to fix Rust lifetime.
      if isCharLit(g, pos):
        # Common char
        pos = pos + 3
        g.kind = gtCharLit
      else:
        # Rust Lifetime
        inc(pos)
        g.kind = gtIdentifier
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\"':
          inc(pos)
          break
        of '\\':
          g.state = g.kind
          break
        else:
          inc(pos)
    of '(', ')', '[', ']', '{', '}', ',', ';':
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
    assert false, "rustNextToken: produced an empty token"
  g.pos = pos
