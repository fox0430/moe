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

import tokenizer, syntax_html

const
  typescriptBooleans* = ["false", "null", "true", "undefined"]

  typescriptBuiltins* = [
    "Array", "ArrayBuffer", "Attr", "BigInt64Array", "BigUint64Array", "Boolean",
    "Buffer", "CDATASection", "CharacterData", "Collator", "Comment", "DOMException",
    "DOMImplementation", "DOMSTRING_SIZE_ERR", "DataView", "Date", "DateTimeFormat",
    "Document", "DocumentFragment", "DocumentType", "Element", "Entity",
    "EntityReference", "Error", "Float32Array", "Float64Array", "Function",
    "HIERARCHY_REQUEST_ERR", "INDEX_SIZE_ERR", "INUSE_ATTRIBUTE_ERR",
    "INVALID_ACCESS_ERR", "INVALID_CHARACTER_ERR", "INVALID_MODIFICATION_ERR",
    "INVALID_STATE_ERR", "Int16Array", "Int32Array", "Int8Array", "Intl", "Iterator",
    "JSON", "Map", "Math", "NAMESPACE_ERR", "NOT_FOUND_ERR", "NOT_SUPPORTED_ERR",
    "NO_DATA_ALLOWED_ERR", "NO_MODIFICATION_ALLOWED_ERR", "NamedNodeMap", "Node",
    "NodeList", "Notation", "Number", "NumberFormat", "Object", "ParallelArray",
    "ProcessingInstruction", "Promise", "PromiseProxy", "Reflect", "RegExp",
    "SYNTAX_ERR", "Set", "String", "Symbol", "Text", "Uint16Array", "Uint32Array",
    "Uint8Array", "Uint8ClampedArray", "WRONG_DOCUMENT_ERR", "WeakMap", "WeakSet",
    "WebAssembly",
  ]

  typescriptKeywords* = [
    "abstract", "accessor", "any", "apply", "arguments", "as", "assert", "asserts",
    "async", "await", "bigint", "boolean", "break", "byte", "case", "catch", "char",
    "charAt", "class", "console", "const", "constructor", "continue", "declare",
    "decodeURI", "decodeURIComponent", "delete", "do", "document", "double", "else",
    "encodeURI", "encodeURIComponent", "enum", "eval", "except", "export", "extends",
    "fetch", "filter", "final", "finally", "float", "for", "from", "function", "global",
    "globalThis", "goto", "if", "implements", "import", "in", "indexOf", "infer",
    "instanceof", "int", "interface", "is", "isFinite", "isNaN", "join", "keyof",
    "keys", "let", "log", "long", "map", "module", "namespace", "native", "never",
    "new", "number", "onblur", "onclick", "oncontextmenu", "ondblclick", "onfocus",
    "onkeydown", "onkeypress", "onkeyup", "onmousedown", "onmousemove", "onmouseout",
    "onmouseover", "onmouseup", "onresize", "or", "out", "override", "package",
    "parseFloat", "parseInt", "pass", "private", "protected", "public", "push",
    "readonly", "reduce", "reject", "require", "resolve", "return", "satisfies",
    "short", "static", "string", "switch", "symbol", "synchronized", "then", "throw",
    "throws", "transient", "try", "type", "typeof", "uneval", "unique", "unknown",
    "using", "value", "var", "void", "volatile", "while", "window", "yield",
  ]

proc tsGetKeyword*(id: string): TokenClass =
  if binarySearch(typescriptBooleans, id) > -1:
    return gtBoolean
  if binarySearch(typescriptBuiltins, id) > -1:
    return gtBuiltin
  if binarySearch(typescriptKeywords, id) > -1:
    return gtKeyword
  return gtIdentifier

# Template literal depth and brace depth are now tracked in GeneralTokenizer

proc typescriptNextToken*(g: var GeneralTokenizer) =
  ## typescriptNextToken is based on javaScriptNextToken with TypeScript extensions

  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos

  # On a truly fresh tokenization (pos == 0 with no carried context) all
  # state fields are already at their zero defaults via GeneralTokenizer's
  # default object initialization. On a resumed tokenization (incremental
  # re-highlight) the caller has restored these fields via
  # `restoreTokenizerState`; resetting them here would silently lose the
  # JSX / template-literal / brace-depth context and cause downstream
  # tokens to diverge from a fresh full reparse.

  # If we're in JSX/TSX mode, delegate to HTML tokenizer
  if g.inJsxMode and g.state != gtLongStringLit:
    htmlNextToken(g)
    # Check if we should exit JSX mode
    if g.buf[g.pos] == '{' and g.buf[g.pos - 1] != '\\':
      # Entering JSX expression
      g.inJsxMode = false
      return
    elif g.kind == gtOperator and g.buf[g.pos - 1] == '>':
      # Check if this is the end of a closing tag
      if g.jsxTagDepth == 0:
        g.inJsxMode = false
    return

  # Handle block comment continuation
  if g.state in {gtLongComment, gtDocLongComment}:
    if g.buf[pos] == '\0':
      g.kind = gtEof
      g.length = 0
      return
    g.kind = g.state
    while true:
      case g.buf[pos]
      of '*':
        inc(pos)
        if g.buf[pos] == '/':
          inc(pos)
          g.state = gtNone
          g.commentDepth = 0
          break
      of '@':
        if g.commentDepth == 1 and g.buf[pos + 1] in {'A' .. 'Z', 'a' .. 'z'} and
            (pos == 0 or g.buf[pos - 1] in {' ', '\t', '\n', '\r', '*'}):
          if pos > g.start:
            break # Return text before tag
          else:
            g.kind = gtPreprocessor
            inc(pos)
            while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
              inc(pos)
            break
        else:
          inc(pos)
      of '{':
        if g.commentDepth == 1 and pos > g.start:
          break
        elif g.commentDepth == 1:
          g.kind = gtPreprocessor
          var braceNest = 0
          while g.buf[pos] != '\0' and not (g.buf[pos] == '*' and g.buf[pos + 1] == '/'):
            if g.buf[pos] == '{':
              inc(braceNest)
            elif g.buf[pos] == '}':
              dec(braceNest)
              if braceNest == 0:
                inc(pos)
                break
            inc(pos)
          break
        else:
          inc(pos)
      of '\0':
        break
      else:
        inc(pos)
    g.length = pos - g.pos
    g.pos = pos
    return

  # Handle template literal state
  if g.state == gtLongStringLit:
    # We're inside a template literal. Mirror the block-comment EOF guard
    # above: when the buffer ends mid-string the loop below would set
    # `kind = gtLongStringLit` without advancing `pos`, producing a
    # zero-length token and tripping the safety assert. Return `gtEof`
    # directly so `state` stays parked for the next chunk.
    if g.buf[pos] == '\0':
      g.kind = gtEof
      g.length = 0
      return
    let startPos = pos
    while true:
      case g.buf[pos]
      of '\0':
        g.kind = gtLongStringLit
        # Keep state as gtLongStringLit for continuation on next line
        break
      of '\n':
        inc(pos)
        g.kind = gtLongStringLit
        # State stays gtLongStringLit; next line resumes the template literal.
        break
      of '`':
        # End of template literal
        inc(pos)
        g.kind = gtLongStringLit
        g.state = gtNone
        if g.templateLiteralDepth > 0:
          dec(g.templateLiteralDepth)
        break
      of '\\':
        inc(pos)
        if g.buf[pos] == '\0':
          g.kind = gtLongStringLit
          # Keep state as gtLongStringLit for continuation
          break
        inc(pos)
      of '$':
        if g.buf[pos + 1] == '{':
          # Found interpolation start
          if pos > g.start:
            # Return the string part before interpolation
            g.kind = gtLongStringLit
          else:
            # Return the ${ as operator
            inc(pos, 2)
            g.kind = gtOperator
            g.state = gtNone # Exit template literal state temporarily
            # Push 0 to track brace depth for this interpolation
            g.braceDepthStack.add(0)
          break
        else:
          inc(pos)
      of '<':
        # Check if this looks like HTML in template literal
        if pos > startPos:
          # Return the string part before HTML
          g.kind = gtLongStringLit
          break
        else:
          # Try to parse as HTML tag
          let htmlStart = pos
          inc(pos)
          if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '/', '!'}:
            # This looks like an HTML tag, use HTML tokenizer
            var htmlTokenizer = g
            htmlTokenizer.pos = htmlStart
            htmlTokenizer.start = htmlStart
            htmlNextToken(htmlTokenizer)
            # Copy the result
            g.kind = htmlTokenizer.kind
            g.pos = htmlTokenizer.pos
            g.length = htmlTokenizer.length
            return
          else:
            # Not HTML, treat as regular string content
            discard
      else:
        inc(pos)
    g.length = pos - g.pos
    if g.kind != gtEof and g.length <= 0:
      assert false, "typescriptNextToken: produced an empty token"
    g.pos = pos
    return

  case g.buf[pos]
  of ' ', '\x09' .. '\x0D':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
      inc(pos)
  of '<':
    # Check for generic types or JSX tags
    # If preceded by an identifier character, treat as generic type (not JSX)
    let prevIsIdentChar = pos > 0 and g.buf[pos - 1] in symChars
    if g.buf[pos + 1] in {'A' .. 'Z', 'a' .. 'z', '/', '!'} and not prevIsIdentChar:
      # This looks like JSX/TSX, switch to JSX mode
      g.inJsxMode = true
      htmlNextToken(g)
      return
    else:
      # Generic type <T> or less-than operator
      g.kind = gtOperator
      inc(pos)
      while g.buf[pos] in opChars and g.buf[pos] != '>':
        inc(pos)
  of '/':
    inc(pos)
    if g.buf[pos] == '/':
      g.kind = gtComment
      while not (g.buf[pos] in {'\0', '\x0A', '\x0D'}):
        inc(pos)
    elif g.buf[pos] == '*':
      g.kind = gtLongComment
      inc(pos)
      # Detect TSDoc: /** but not /**/ (empty)
      if g.buf[pos] == '*' and g.buf[pos + 1] != '/':
        g.commentDepth = 1 # Mark as TSDoc
        g.kind = gtDocLongComment
      else:
        g.commentDepth = 0
      while true:
        case g.buf[pos]
        of '*':
          inc(pos)
          if g.buf[pos] == '/':
            inc(pos)
            g.commentDepth = 0
            break
        of '@':
          if g.commentDepth == 1 and g.buf[pos + 1] in {'A' .. 'Z', 'a' .. 'z'}:
            if pos > g.start:
              g.state = gtDocLongComment
              break
            else:
              g.kind = gtPreprocessor
              g.state = gtDocLongComment
              inc(pos)
              while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
                inc(pos)
              break
          else:
            inc(pos)
        of '{':
          if g.commentDepth == 1 and pos > g.start:
            g.state = gtDocLongComment
            break
          elif g.commentDepth == 1:
            g.kind = gtPreprocessor
            g.state = gtDocLongComment
            var braceNest = 0
            while g.buf[pos] != '\0' and
                not (g.buf[pos] == '*' and g.buf[pos + 1] == '/'):
              if g.buf[pos] == '{':
                inc(braceNest)
              elif g.buf[pos] == '}':
                dec(braceNest)
                if braceNest == 0:
                  inc(pos)
                  break
              inc(pos)
            break
          else:
            inc(pos)
        of '\0':
          g.state = if g.commentDepth == 1: gtDocLongComment else: gtLongComment
          break
        else:
          inc(pos)
    else:
      # Division operator or regex
      g.kind = gtOperator
  of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
    var id = ""
    while g.buf[pos] in symChars:
      add(id, g.buf[pos])
      inc(pos)

    # Check if this identifier is a key (followed by colon or ?:). The
    # lookahead must stay on the current line: scanning past `\n` would
    # make this line's color depend on later lines, which an incremental
    # re-highlight (resuming from per-line states) can never observe.
    var isKey = false
    var tempPos = pos
    # Skip spaces/tabs after identifier (same line only)
    while g.buf[tempPos] in {' ', '\t'}:
      inc(tempPos)
    # Check if next non-whitespace character is colon or optional colon (?:)
    if g.buf[tempPos] == ':':
      isKey = true
    elif g.buf[tempPos] == '?' and g.buf[tempPos + 1] == ':':
      isKey = true

    let kwKind = tsGetKeyword(id)
    if kwKind != gtIdentifier:
      g.kind = kwKind
    elif isKey:
      g.kind = gtKey
    elif g.buf[pos] == '(':
      g.kind = gtFunctionName
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
      if g.buf[pos] == 'n':
        # BigInt literal
        inc(pos)
      elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of 'x', 'X':
      g.kind = gtHexNumber
      inc(pos)
      while g.buf[pos] in hexChars:
        inc(pos)
      if g.buf[pos] == 'n':
        # BigInt literal
        inc(pos)
      elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of 'o', 'O':
      g.kind = gtOctNumber
      inc(pos)
      while g.buf[pos] in octChars:
        inc(pos)
      if g.buf[pos] == 'n':
        # BigInt literal
        inc(pos)
      elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '0' .. '7':
      g.kind = gtOctNumber
      inc(pos)
      while g.buf[pos] in octChars:
        inc(pos)
      if g.buf[pos] == 'n':
        # BigInt literal
        inc(pos)
      elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    else:
      pos = generalNumber(g, pos)
      if g.buf[pos] == 'n':
        # BigInt literal
        inc(pos)
      elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
  of '1' .. '9':
    pos = generalNumber(g, pos)
    if g.buf[pos] == 'n':
      # BigInt literal
      inc(pos)
    elif g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
      inc(pos)
  of '\"', '\'':
    let quote = g.buf[pos]
    inc(pos)

    # Check if this string is a key (for object literals with quotes).
    # The string token itself is line-bounded (see the scan loop below), so
    # the lookahead must also stop at the end of the line: scanning past
    # `\n` would make this line's color depend on later lines, which an
    # incremental re-highlight (resuming from per-line states) can never
    # observe.
    var isKey = false
    var tempPos = pos
    # Scan to the closing quote (same line only) to check for a colon
    while g.buf[tempPos] != '\0':
      case g.buf[tempPos]
      of '\r', '\n':
        break
      of '\"', '\'':
        if g.buf[tempPos] == quote:
          inc(tempPos)
          # Skip spaces/tabs after closing quote (same line only)
          while g.buf[tempPos] in {' ', '\t'}:
            inc(tempPos)
          # Check if next non-whitespace character is colon or optional colon (?:)
          if g.buf[tempPos] == ':':
            isKey = true
          elif g.buf[tempPos] == '?' and g.buf[tempPos + 1] == ':':
            isKey = true
          break
        else:
          inc(tempPos)
      of '\\':
        # `g.buf[tempPos]` is `\` here, so `tempPos + 1` is at most the NUL
        # terminator; stop at an escaped EOL or the NUL rather than stepping past it.
        if g.buf[tempPos + 1] in {'\r', '\n', '\0'}:
          break
        inc(tempPos, 2) # Skip escape sequence
      else:
        inc(tempPos)

    # Set kind based on whether this is a key or value
    if isKey:
      g.kind = gtKey
    else:
      g.kind = gtStringLit

    while true:
      case g.buf[pos]
      of '\0':
        break
      of '\r', '\n':
        # Treat both `"..."` and `'...'` as line-bounded so per-line state
        # captures don't see a multi-line token; an unterminated string just
        # ends at the newline and the next line tokenizes fresh.
        break
      of '\"', '\'':
        if g.buf[pos] == quote:
          inc(pos)
          break
        else:
          inc(pos)
      of '\\':
        if g.buf[pos + 1] in {'\r', '\n'}:
          # An escaped newline would continue the string onto the next line;
          # end the token at EOL instead (consuming the backslash) to keep
          # the line-bounded design above. The isKey lookahead makes the
          # matching choice and stops before an escaped newline.
          inc(pos)
          break
        inc(pos)
        if g.buf[pos] == '\0':
          break
        inc(pos)
      else:
        inc(pos)
  of '`':
    inc(pos)
    g.kind = gtLongStringLit
    g.state = gtLongStringLit
    inc(g.templateLiteralDepth)
    # Only consume until first ${ or the next newline. Splitting at `\n`
    # keeps per-line state captures accurate so an incremental re-parse
    # from any line in the middle of the template literal sees the same
    # `state=gtLongStringLit` as a fresh full reparse would.
    while true:
      case g.buf[pos]
      of '\0':
        # Keep state for continuation
        break
      of '\n':
        inc(pos)
        # State stays gtLongStringLit; next line resumes the template literal.
        break
      of '`':
        inc(pos)
        g.state = gtNone
        if g.templateLiteralDepth > 0:
          dec(g.templateLiteralDepth)
        break
      of '\\':
        inc(pos)
        if g.buf[pos] == '\0':
          # Keep state for continuation
          break
        inc(pos)
      of '$':
        if g.buf[pos + 1] == '{':
          # Stop here, next token will be ${
          break
        else:
          inc(pos)
      else:
        inc(pos)
  of '(', ')', '[', ']', ',', ';':
    inc(pos)
    g.kind = gtPunctuation
  of ':':
    inc(pos)
    g.kind = gtPunctuation
  of '.':
    inc(pos)
    if g.buf[pos] == '.' and g.buf[pos + 1] == '.':
      # Spread operator
      inc(pos, 2)
      g.kind = gtOperator
    else:
      g.kind = gtPunctuation
  of '?':
    inc(pos)
    if g.buf[pos] == '.':
      # Optional chaining
      inc(pos)
      g.kind = gtOperator
    elif g.buf[pos] == '?':
      # Nullish coalescing
      inc(pos)
      g.kind = gtOperator
    else:
      # Ternary or optional property
      g.kind = gtOperator
  of '!':
    inc(pos)
    if g.buf[pos] == '=':
      inc(pos)
      if g.buf[pos] == '=':
        inc(pos)
      g.kind = gtOperator
    else:
      # Non-null assertion or negation
      g.kind = gtOperator
  of '{':
    inc(pos)
    if g.braceDepthStack.len > 0:
      inc(g.braceDepthStack[^1])
    g.kind = gtPunctuation
  of '}':
    inc(pos)
    if g.braceDepthStack.len > 0:
      if g.braceDepthStack[^1] == 0:
        # This closes a template interpolation
        discard g.braceDepthStack.pop()
        g.kind = gtOperator
        g.state = gtLongStringLit # Go back to template literal
      else:
        # This is a regular brace inside interpolation
        dec(g.braceDepthStack[^1])
        g.kind = gtPunctuation
    else:
      g.kind = gtPunctuation
      # Check if we should return to JSX mode after closing expression
      if g.buf[pos] == '<':
        g.inJsxMode = true
  of '@':
    # Decorator syntax
    inc(pos)
    if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '_', '\x80' .. '\xFF'}:
      g.kind = gtPreprocessor
      while g.buf[pos] in symChars:
        inc(pos)
    else:
      g.kind = gtOperator
  of '\0':
    g.kind = gtEof
  else:
    if g.buf[pos] in opChars:
      g.kind = gtOperator
      while g.buf[pos] in opChars:
        inc(pos)
    elif g.buf[pos] == '>' and g.inJsxMode:
      # Handle JSX closing tags
      htmlNextToken(g)
      return
    else:
      inc(pos)
      g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "typescriptNextToken: produced an empty token"
  g.pos = pos
