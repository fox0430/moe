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

import tokenizer, syntax_javascript, syntax_html

# Astro file state tracking is now in GeneralTokenizer

proc astroNextToken*(g: var GeneralTokenizer) =
  ## Astro syntax tokenizer that handles frontmatter and JSX template sections

  # Don't reset astro state on `g.pos == 0`: incremental reparse builds a chunk
  # buffer that also starts at `pos == 0`, then restores the boundary state via
  # `restoreTokenizerState`. Resetting here would clobber it and make a mid-file
  # reparse mistake a closing `---` fence for an opening one.

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
    # Outside frontmatter - check for HTML content
    g.astroFirstLine = false

    # Check if we're starting an HTML tag
    if g.buf[g.pos] == '<' and g.pos + 1 < g.buf.len and
        g.buf[g.pos + 1] in {'A' .. 'Z', 'a' .. 'z', '/', '!'}:
      # Use HTML tokenizer for HTML content
      htmlNextToken(g)
      return
    elif g.buf[g.pos] == '{':
      # This might be a JSX expression, use JavaScript tokenizer
      javaScriptNextToken(g)
      return
    else:
      # Default to HTML tokenizer for template content
      htmlNextToken(g)
      return

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "astroNextToken: produced an empty token"
  g.pos = pos
