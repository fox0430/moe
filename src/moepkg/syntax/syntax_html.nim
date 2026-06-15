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

const htmlKeywords* = [
  "a", "abbr", "address", "area", "article", "aside", "audio", "base", "bdi", "bdo",
  "blockquote", "body", "br", "button", "canvas", "cite", "code", "datalist", "del",
  "details", "dfn", "dialog", "div", "em", "embed", "fieldset", "figcaption", "figure",
  "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html",
  "iframe", "img", "input", "ins", "kbd", "label", "legend", "li", "link", "main",
  "map", "mark", "meta", "meter", "nav", "noscript", "object", "ol", "option", "output",
  "p", "param", "picture", "pre", "progress", "q", "rp", "rt", "ruby", "samp", "script",
  "section", "select", "slot", "small", "source", "span", "strong", "style", "sub",
  "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot", "th",
  "thead", "time", "title", "tr", "track", "ul", "var", "video", "wbr",
]

# Comment state and script/style context are now tracked in GeneralTokenizer

proc htmlNextToken*(g: var GeneralTokenizer) =
  ## HTML syntax highlighting tokenizer

  const symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_', ':'}
  var pos = g.pos
  g.start = g.pos

  # Reset state when starting fresh
  if g.pos == 0 and g.state != gtLongComment:
    g.inComment = false
    g.commentDepth = 0
    g.inScript = false
    g.inStyle = false

  # Handle comment state
  if g.state == gtLongComment or g.inComment:
    let terminated = scanToTerminator(g.buf, pos, '-', '-', '>')
    if pos == g.pos:
      # Nothing left to consume on this line; terminate without emitting an
      # empty token. State stays gtLongComment so the next line continues
      # the comment.
      g.kind = gtEof
    else:
      g.kind = gtLongComment
      if terminated:
        g.state = gtNone
        g.inComment = false
    g.length = pos - g.pos
    g.pos = pos
    return

  case g.buf[pos]
  of ' ', '\t' .. '\r':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t' .. '\r'}:
      if g.buf[pos] == '\n':
        g.state = gtWhitespace
      inc(pos)
  of '<':
    inc(pos)
    # NUL-safe lookahead without `g.buf.len` (strlen): each byte below is
    # only read after the previous one matched a non-NUL char.
    if g.buf[pos] == '!' and g.buf[pos + 1] == '-' and g.buf[pos + 2] == '-':
      # HTML comment <!--
      g.kind = gtLongComment
      inc(pos, 3) # Skip !-- (the < is already consumed)
      if scanToTerminator(g.buf, pos, '-', '-', '>'):
        g.state = gtNone
        g.inComment = false
      else:
        # Unterminated on this line; the state continues it on the next line.
        g.state = gtLongComment
        g.inComment = true
    elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '/', '!'}:
      # Tag start: <tag, </tag, or <!DOCTYPE
      g.kind = gtTagStart
    else:
      # Less-than operator
      g.kind = gtOperator
  of 'A' .. 'Z', 'a' .. 'z', '_':
    # Tag name or attribute
    g.kind = gtIdentifier
    var name = ""
    while g.buf[pos] in symChars:
      add(name, g.buf[pos])
      inc(pos)
    # Check if it's a known HTML tag
    if isKeyword(htmlKeywords, name) >= 0:
      g.kind = gtKeyword
  of '>':
    inc(pos)
    g.kind = gtTagEnd
  of '\"', '\'':
    let quote = g.buf[pos]
    inc(pos)
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\0':
        break
      of '\r', '\n':
        break
      of '\"', '\'':
        if g.buf[pos] == quote:
          inc(pos)
          break
        else:
          inc(pos)
      of '\\':
        inc(pos)
        if g.buf[pos] == '\0':
          break
        inc(pos)
      else:
        inc(pos)
  of '=':
    inc(pos)
    g.kind = gtOperator
  of '/':
    # `g.buf[pos]` is '/', so reading `pos + 1` is at most the NUL
    # terminator — no length check needed.
    if g.buf[pos + 1] == '>':
      # Self-closing tag />
      inc(pos, 2)
      g.kind = gtTagEnd
    else:
      inc(pos)
      g.kind = gtOperator
  of '&':
    # HTML entities
    g.kind = gtOperator
    inc(pos)
    while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '#'}:
      inc(pos)
    if g.buf[pos] == ';':
      inc(pos)
  of '\0':
    g.kind = gtEof
  else:
    inc(pos)
    g.kind = gtNone

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "htmlNextToken: produced an empty token"
  g.pos = pos
