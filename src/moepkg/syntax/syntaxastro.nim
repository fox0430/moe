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
import syntaxjavascript

# Astro file state tracking is now in GeneralTokenizer

proc astroNextToken*(g: var GeneralTokenizer) =
  ## Astro syntax tokenizer that handles frontmatter and JSX template sections

  # Reset state when starting fresh
  if g.pos == 0:
    g.astroInFrontmatter = false
    g.astroFirstLine = true

  var pos = g.pos
  g.start = g.pos

  # Handle frontmatter delimiters
  if g.astroFirstLine and g.buf[pos] == '-' and g.buf[pos + 1] == '-' and
      g.buf[pos + 2] == '-':
    # Start of frontmatter
    g.astroInFrontmatter = true
    g.astroFirstLine = false
    g.kind = gtDirective
    inc(pos, 3)
    # Skip any trailing characters on the line
    while g.buf[pos] notin {'\0', '\n', '\r'}:
      inc(pos)
  elif g.astroInFrontmatter and g.buf[pos] == '-' and g.buf[pos + 1] == '-' and
      g.buf[pos + 2] == '-':
    # End of frontmatter
    g.astroInFrontmatter = false
    g.kind = gtDirective
    inc(pos, 3)
    # Skip any trailing characters on the line
    while g.buf[pos] notin {'\0', '\n', '\r'}:
      inc(pos)
  elif g.astroInFrontmatter:
    # Inside frontmatter - use JavaScript tokenizer
    javaScriptNextToken(g)
    return
  else:
    # Outside frontmatter - use JavaScript tokenizer for JSX content
    g.astroFirstLine = false
    javaScriptNextToken(g)
    return

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "astroNextToken: produced an empty token"
  g.pos = pos
