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

import highlite

proc yamlPlainStrLit(g: var GeneralTokenizer, pos: var int) =
  g.kind = gtStringLit
  while g.buf[pos] notin {'\0', '\x09'..'\x0D', ',', ']', '}'}:
    if g.buf[pos] == ':' and
        g.buf[pos + 1] in {'\0', '\x09'..'\x0D', ' '}:
      break
    inc(pos)

proc yamlPossibleNumber(g: var GeneralTokenizer, pos: var int) =
  g.kind = gtNone
  if g.buf[pos] == '-': inc(pos)
  if g.buf[pos] == '0': inc(pos)
  elif g.buf[pos] in '1'..'9':
    inc(pos)
    while g.buf[pos] in {'0'..'9'}: inc(pos)
  else: yamlPlainStrLit(g, pos)
  if g.kind == gtNone:
    if g.buf[pos] in {'\0', '\x09'..'\x0D', ' ', ',', ']', '}'}:
      g.kind = gtDecNumber
    elif g.buf[pos] == '.':
      inc(pos)
      if g.buf[pos] notin {'0'..'9'}: yamlPlainStrLit(g, pos)
      else:
        while g.buf[pos] in {'0'..'9'}: inc(pos)
        if g.buf[pos] in {'\0', '\x09'..'\x0D', ' ', ',', ']', '}'}:
          g.kind = gtFloatNumber
    if g.kind == gtNone:
      if g.buf[pos] in {'e', 'E'}:
        inc(pos)
        if g.buf[pos] in {'-', '+'}: inc(pos)
        if g.buf[pos] notin {'0'..'9'}: yamlPlainStrLit(g, pos)
        else:
          while g.buf[pos] in {'0'..'9'}: inc(pos)
          if g.buf[pos] in {'\0', '\x09'..'\x0D', ' ', ',', ']', '}'}:
            g.kind = gtFloatNumber
          else: yamlPlainStrLit(g, pos)
      else: yamlPlainStrLit(g, pos)
  while g.buf[pos] notin {'\0', ',', ']', '}', '\x0A', '\x0D'}:
    inc(pos)
    if g.buf[pos] notin {'\x09'..'\x0D', ' ', ',', ']', '}'}:
      yamlPlainStrLit(g, pos)
      break
  # theoretically, we would need to parse indentation (like with block scalars)
  # because of possible multiline flow scalars that start with number-like
  # content, but that is far too troublesome. I think it is fine that the
  # highlighter is sloppy here.

proc yamlNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        if pos != g.pos: break
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x':
          inc(pos)
          for i in 1..2:
            {.unroll.}
            if g.buf[pos] in hexChars: inc(pos)
          break
        of 'u':
          inc(pos)
          for i in 1..4:
            {.unroll.}
            if g.buf[pos] in hexChars: inc(pos)
          break
        of 'U':
          inc(pos)
          for i in 1..8:
            {.unroll.}
            if g.buf[pos] in hexChars: inc(pos)
          break
        else: inc(pos)
        break
      of '\0':
        g.state = gtOther
        break
      of '\"':
        inc(pos)
        g.state = gtOther
        break
      else: inc(pos)
  elif g.state == gtCharLit:
    # abusing gtCharLit as single-quoted string lit
    g.kind = gtStringLit
    inc(pos) # skip the starting '
    while true:
      case g.buf[pos]
      of '\'':
        inc(pos)
        if g.buf[pos] == '\'':
          inc(pos)
          g.kind = gtEscapeSequence
        else: g.state = gtOther
        break
      else: inc(pos)
  elif g.state == gtCommand:
    # gtCommand means 'block scalar header'
    case g.buf[pos]
    of ' ', '\t':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t'}: inc(pos)
    of '#':
      g.kind = gtComment
      while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
    of '\x0A', '\x0D': discard
    else:
      # illegal here. just don't parse a block scalar
      g.kind = gtNone
      g.state = gtOther
    if g.buf[pos] in {'\x0A', '\x0D'} and g.state == gtCommand:
      g.state = gtLongStringLit
  elif g.state == gtLongStringLit:
    # beware, this is the only token where we actually have to parse
    # indentation.

    g.kind = gtLongStringLit
    # first, we have to find the parent indentation of the block scalar, so that
    # we know when to stop
    assert g.buf[pos] in {'\x0A', '\x0D'}
    var lookbehind = pos - 1
    var headerStart = -1
    while lookbehind >= 0 and g.buf[lookbehind] notin {'\x0A', '\x0D'}:
      if headerStart == -1 and g.buf[lookbehind] in {'|', '>'}:
        headerStart = lookbehind
      dec(lookbehind)
    assert headerStart != -1
    var indentation = 1
    while g.buf[lookbehind + indentation] == ' ': inc(indentation)
    if g.buf[lookbehind + indentation] in {'|', '>'}:
      # when the header is alone in a line, this line does not show the parent's
      # indentation, so we must go further. search the first previous line with
      # non-whitespace content.
      while lookbehind >= 0 and g.buf[lookbehind] in {'\x0A', '\x0D'}:
        dec(lookbehind)
        while lookbehind >= 0 and
            g.buf[lookbehind] in {' ', '\t'}: dec(lookbehind)
      # now, find the beginning of the line...
      while lookbehind >= 0 and g.buf[lookbehind] notin {'\x0A', '\x0D'}:
        dec(lookbehind)
      # ... and its indentation
      indentation = 1
      while g.buf[lookbehind + indentation] == ' ': inc(indentation)
    if lookbehind == -1: indentation = 0 # top level
    elif g.buf[lookbehind + 1] == '-' and g.buf[lookbehind + 2] == '-' and
        g.buf[lookbehind + 3] == '-' and
        g.buf[lookbehind + 4] in {'\x09'..'\x0D', ' '}:
      # this is a document start, therefore, we are at top level
      indentation = 0
    # because lookbehind was at newline char when calculating indentation, we're
    # off by one. fix that. top level's parent will have indentation of -1.
    let parentIndentation = indentation - 1

    # find first content
    while g.buf[pos] in {' ', '\x0A', '\x0D'}:
      if g.buf[pos] == ' ': inc(indentation)
      else: indentation = 0
      inc(pos)
    var minIndentation = indentation

    # for stupid edge cases, we must check whether an explicit indentation depth
    # is given at the header.
    while g.buf[headerStart] in {'>', '|', '+', '-'}: inc(headerStart)
    if g.buf[headerStart] in {'0'..'9'}:
      minIndentation = min(minIndentation, ord(g.buf[headerStart]) - ord('0'))

    # process content lines
    while indentation > parentIndentation and g.buf[pos] != '\0':
      if (indentation < minIndentation and g.buf[pos] == '#') or
          (indentation == 0 and g.buf[pos] == '.' and g.buf[pos + 1] == '.' and
          g.buf[pos + 2] == '.' and
          g.buf[pos + 3] in {'\0', '\x09'..'\x0D', ' '}):
        # comment after end of block scalar, or end of document
        break
      minIndentation = min(indentation, minIndentation)
      while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
      while g.buf[pos] in {' ', '\x0A', '\x0D'}:
        if g.buf[pos] == ' ': inc(indentation)
        else: indentation = 0
        inc(pos)

    g.state = gtOther
  elif g.state == gtOther:
    # gtOther means 'inside YAML document'
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '#':
      g.kind = gtComment
      inc(pos)
      while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
    of '-':
      inc(pos)
      if g.buf[pos] in {'\0', ' ', '\x09'..'\x0D'}:
        g.kind = gtPunctuation
      elif g.buf[pos] == '-' and
          (pos == 1 or g.buf[pos - 2] in {'\x0A', '\x0D'}): # start of line
        inc(pos)
        if g.buf[pos] == '-' and g.buf[pos + 1] in {'\0', '\x09'..'\x0D', ' '}:
          inc(pos)
          g.kind = gtKeyword
        else: yamlPossibleNumber(g, pos)
      else: yamlPossibleNumber(g, pos)
    of '.':
      if pos == 0 or g.buf[pos - 1] in {'\x0A', '\x0D'}:
        inc(pos)
        for i in 1..2:
          {.unroll.}
          if g.buf[pos] != '.': break
          inc(pos)
        if pos == g.start + 3:
          g.kind = gtKeyword
          g.state = gtNone
        else: yamlPlainStrLit(g, pos)
      else: yamlPlainStrLit(g, pos)
    of '?':
      inc(pos)
      if g.buf[pos] in {'\0', ' ', '\x09'..'\x0D'}:
        g.kind = gtPunctuation
      else: yamlPlainStrLit(g, pos)
    of ':':
      inc(pos)
      if g.buf[pos] in {'\0', '\x09'..'\x0D', ' ', '\'', '\"'} or
          (pos > 0 and g.buf[pos - 2] in {'}', ']', '\"', '\''}):
        g.kind = gtPunctuation
      else: yamlPlainStrLit(g, pos)
    of '[', ']', '{', '}', ',':
      inc(pos)
      g.kind = gtPunctuation
    of '\"':
      inc(pos)
      g.state = gtStringLit
      g.kind = gtStringLit
    of '\'':
      g.state = gtCharLit
      g.kind = gtNone
    of '!':
      g.kind = gtTagStart
      inc(pos)
      if g.buf[pos] == '<':
        # literal tag (e.g. `!<tag:yaml.org,2002:str>`)
        while g.buf[pos] notin {'\0', '>', '\x09'..'\x0D', ' '}: inc(pos)
        if g.buf[pos] == '>': inc(pos)
      else:
        while g.buf[pos] in {'A'..'Z', 'a'..'z', '0'..'9', '-'}: inc(pos)
        case g.buf[pos]
        of '!':
          # prefixed tag (e.g. `!!str`)
          inc(pos)
          while g.buf[pos] notin
              {'\0', '\x09'..'\x0D', ' ', ',', '[', ']', '{', '}'}: inc(pos)
        of '\0', '\x09'..'\x0D', ' ': discard
        else:
          # local tag (e.g. `!nim:system:int`)
          while g.buf[pos] notin {'\0', '\x09'..'\x0D', ' '}: inc(pos)
    of '&':
      g.kind = gtLabel
      while g.buf[pos] notin {'\0', '\x09'..'\x0D', ' '}: inc(pos)
    of '*':
      g.kind = gtReference
      while g.buf[pos] notin {'\0', '\x09'..'\x0D', ' '}: inc(pos)
    of '|', '>':
      # this can lead to incorrect tokenization when | or > appear inside flow
      # content. checking whether we're inside flow content is not
      # chomsky type-3, so we won't do that here.
      g.kind = gtCommand
      g.state = gtCommand
      inc(pos)
      while g.buf[pos] in {'0'..'9', '+', '-'}: inc(pos)
    of '0'..'9': yamlPossibleNumber(g, pos)
    of '\0': g.kind = gtEof
    else: yamlPlainStrLit(g, pos)
  else:
    # outside document
    case g.buf[pos]
    of '%':
      if pos == 0 or g.buf[pos - 1] in {'\x0A', '\x0D'}:
        g.kind = gtDirective
        while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
      else:
        g.state = gtOther
        yamlPlainStrLit(g, pos)
    of ' ', '\x09'..'\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '#':
      g.kind = gtComment
      while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
    of '\0': g.kind = gtEof
    else:
      g.kind = gtNone
      g.state = gtOther
  g.length = pos - g.pos
  g.pos = pos


