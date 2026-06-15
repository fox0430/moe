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

import std/strutils

import tokenizer

const
  ## DTD / DOCTYPE declaration keywords. Uppercase by spec, matched
  ## case-sensitively anywhere a bare name appears (same trade-off as
  ## `htmlKeywords`: a text-content word that happens to match is also
  ## highlighted). Must stay sorted for `isKeyword`'s binary search.
  xmlDtdKeywords* = [
    "ATTLIST", "CDATA", "DOCTYPE", "ELEMENT", "ENTITY", "FIXED", "IMPLIED", "NOTATION",
    "PCDATA", "PUBLIC", "REQUIRED", "SYSTEM",
  ]

  ## Special pseudo-attributes: the XML declaration's `version` / `encoding` /
  ## `standalone` and namespace declarations (`xmlns`, `xmlns:prefix`).
  ## Highlighted as builtins to stand out from ordinary attribute names.
  ## Must stay sorted for `isKeyword`'s binary search.
  xmlSpecialAttrs* = ["encoding", "standalone", "version", "xmlns"]

# Cross-line state: `g.state == gtLongComment` inside a multi-line
# `<!-- ... -->` comment, `g.state == gtCData` inside a multi-line
# `<![CDATA[ ... ]]>` section, `gtNone` otherwise.

proc xmlNextToken*(g: var GeneralTokenizer) =
  ## XML syntax highlighting tokenizer.
  ##
  ## Unlike HTML there is no fixed tag vocabulary, so element names are
  ## recognized positionally: a name directly following `<`, `</`, `<?` or
  ## `<!` is highlighted as a keyword, any other name as an identifier.
  ## DTD keywords (SYSTEM, PUBLIC, ...) are highlighted as keywords and the
  ## special pseudo-attributes (version, encoding, standalone, xmlns) as
  ## builtins.

  # `'\x80' .. '\xFF'` keeps multibyte (UTF-8) sequences inside a single
  # token. Tokenizing them byte-by-byte would break the rune-based column
  # bookkeeping in highlight.nim, shifting every color segment after the
  # multibyte run. It also matches the XML spec, which allows non-ASCII
  # name characters.
  const symChars =
    {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_', ':', '.', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos

  # Resume a multi-line construct from the state carried across the line
  # boundary: `<!-- comment -->` (gtLongComment) or `<![CDATA[ ]]>`
  # (gtCData).
  if g.state in {gtLongComment, gtCData}:
    let terminated =
      if g.state == gtLongComment:
        scanToTerminator(g.buf, pos, '-', '-', '>')
      else:
        scanToTerminator(g.buf, pos, ']', ']', '>')
    if pos == g.pos:
      # Nothing left to consume on this line; terminate without emitting an
      # empty token. The state is kept so the next line continues the
      # construct.
      g.kind = gtEof
    else:
      g.kind = g.state
      if terminated:
        g.state = gtNone
    g.length = pos - g.pos
    g.pos = pos
    return

  case g.buf[pos]
  of ' ', '\t' .. '\r':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t' .. '\r'}:
      inc(pos)
  of '<':
    inc(pos)
    # NUL-safe lookahead without `g.buf.len` (strlen): each byte below is
    # only read after the previous one matched a non-NUL char.
    if g.buf[pos] == '!' and g.buf[pos + 1] == '-' and g.buf[pos + 2] == '-':
      # XML comment <!--
      g.kind = gtLongComment
      inc(pos, 3) # Skip !-- (the < is already consumed)
      if scanToTerminator(g.buf, pos, '-', '-', '>'):
        g.state = gtNone
      else:
        # Unterminated on this line; the state continues it on the next line.
        g.state = gtLongComment
    elif g.buf[pos] == '!' and g.buf[pos + 1] == '[' and g.buf[pos + 2] == 'C' and
        g.buf[pos + 3] == 'D' and g.buf[pos + 4] == 'A' and g.buf[pos + 5] == 'T' and
        g.buf[pos + 6] == 'A' and g.buf[pos + 7] == '[':
      # CDATA section <![CDATA[
      g.kind = gtCData
      inc(pos, 8) # Skip ![CDATA[ (the < is already consumed)
      if scanToTerminator(g.buf, pos, ']', ']', '>'):
        g.state = gtNone
      else:
        # Unterminated on this line; the state continues it on the next line.
        g.state = gtCData
    elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '_', '/', '!', '?', '\x80' .. '\xFF'}:
      # Tag start: <tag, </tag, <?xml, or <!DOCTYPE
      g.kind = gtTagStart
    else:
      # Less-than operator
      g.kind = gtOperator
  of 'A' .. 'Z', 'a' .. 'z', '_', '\x80' .. '\xFF':
    # Element name, attribute name or text content.
    # An element, processing-instruction or declaration name directly follows
    # `<`, `</`, `<?` or `<!` on the same line, so a single-character
    # look-back is enough to recognize it. XML has no fixed tag vocabulary,
    # so any name in that position is highlighted as a keyword. The
    # positional rule wins over the keyword lists below (e.g. an element
    # named <version> is a tag, not a pseudo-attribute) and is checked first
    # so tag names skip the `name` accumulation entirely.
    var positional = false
    if g.start > 0:
      let prev = g.buf[g.start - 1]
      if prev == '<':
        positional = true
      elif prev in {'/', '?', '!'} and g.start > 1 and g.buf[g.start - 2] == '<':
        positional = true
    if positional:
      g.kind = gtKeyword
      while g.buf[pos] in symChars:
        inc(pos)
    else:
      g.kind = gtIdentifier
      var name = ""
      while g.buf[pos] in symChars:
        add(name, g.buf[pos])
        inc(pos)
      if isKeyword(xmlDtdKeywords, name) >= 0:
        # DTD keywords: SYSTEM, PUBLIC, ELEMENT, #REQUIRED, ...
        g.kind = gtKeyword
      elif isKeyword(xmlSpecialAttrs, name) >= 0 or name.startsWith("xmlns:"):
        # XML declaration pseudo-attributes and namespace declarations
        g.kind = gtBuiltin
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
  of '?':
    if g.buf[pos + 1] == '>':
      # XML declaration/processing instruction end ?>
      inc(pos, 2)
      g.kind = gtTagEnd
    else:
      inc(pos)
      g.kind = gtOperator
  of '&':
    # XML entity or character reference: `&name;`, `&#169;`, `&#x41;`
    g.kind = gtOperator
    inc(pos)
    if g.buf[pos] == '#':
      inc(pos)
      if g.buf[pos] == 'x':
        # Hex character reference &#x41;
        inc(pos)
        while g.buf[pos] in {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
          inc(pos)
      else:
        # Decimal character reference &#169;
        while g.buf[pos] in {'0' .. '9'}:
          inc(pos)
    else:
      # Entity names share the XML Name charset (e.g. `&my.entity;`)
      while g.buf[pos] in symChars:
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
    assert false, "xmlNextToken: produced an empty token"
  g.pos = pos
