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
import syntaxhtml

const javaScriptkeywords* = [
  "Array", "ArrayBuffer", "Attr", "BigInt64Array", "BigUint64Array", "Boolean",
  "Buffer", "CDATASection", "CharacterData", "Collator", "Comment", "DOMException",
  "DOMImplementation", "DOMSTRING_SIZE_ERR", "DataViewDate", "DateTimeFormat",
  "Document", "DocumentFragment", "DocumentType", "Element", "Entity",
  "EntityReference", "Error", "Float32Array", "Float64Array", "Function",
  "HIERARCHY_REQUEST_ERR", "INDEX_SIZE_ERR", "INUSE_ATTRIBUTE_ERR",
  "INVALID_ACCESS_ERR", "INVALID_CHARACTER_ERR", "INVALID_MODIFICATION_ERR",
  "INVALID_STATE_ERR", "Int16Array", "Int32Array", "Int8Array", "Intl", "Iterator",
  "JSON", "Map", "MathNumber", "NAMESPACE_ERR", "NOT_FOUND_ERR", "NOT_SUPPORTED_ERR",
  "NO_DATA_ALLOWED_ERR", "NO_MODIFICATION_ALLOWED_ERR", "NamedNodeMap", "Node",
  "NodeList", "Notation", "NumberFormat", "Object", "Object", "ParallelArray",
  "ProcessingInstruction", "Promise", "PromiseProxy", "Reflect", "RegExp", "SYNTAX_ERR",
  "Set", "String", "String", "Symbol", "Text", "Uint16Array", "Uint32Array",
  "Uint8Array", "Uint8ClampedArray", "Uint8ClampedArray", "WRONG_DOCUMENT_ERR",
  "WeakMap", "WeakSet", "WebAssembly", "abstract", "apply", "arguments", "as", "assert",
  "async", "await", "boolean", "break", "byte", "catch", "catchexport", "char",
  "charAt", "class", "console", "console", "const", "constructor", "continue",
  "decodeURI", "decodeURIComponent", "delete", "do", "document", "double", "else",
  "encodeURI", "encodeURIComponenteval", "enum", "except", "false", "fetch", "filter",
  "final", "finally", "float", "for", "from", "function", "global", "globalThis",
  "goto", "if", "implementsprotected", "import", "in", "indexOf", "instanceof", "int",
  "interface", "is", "isFinite", "isNaN", "join", "keys", "let", "log", "long",
  "native", "new", "null", "map", "onblur", "onclick", "oncontextmenu", "ondblclick",
  "onfocus", "onkeydown", "onkeypress", "onkeyup", "onmousedown", "onmousemove",
  "onmouseout", "onmouseover", "onmouseup", "onresize", "or", "package", "parseFloat",
  "parseIntuneval", "pass", "private", "public", "push", "reduce", "reject", "require",
  "resolve", "return", "short", "static", "switch", "synchronized", "then", "throw",
  "throws", "transient", "true", "try", "typeof", "value", "var", "void", "volatile",
  "while", "window", "yield",
]

# Template literal depth and brace depth are now tracked in GeneralTokenizer

proc javaScriptNextToken*(g: var GeneralTokenizer) =
  ## javaScriptNextToken is Incomplete

  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos

  # Reset state when starting fresh (pos = 0 and not in template literal state)
  if g.pos == 0 and g.state != gtLongStringLit:
    g.templateLiteralDepth = 0
    g.braceDepthStack = @[]
    g.inJsxMode = false
    g.jsxTagDepth = 0

  # If we're in JSX mode, delegate to HTML tokenizer
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

  # Handle template literal state
  if g.state == gtLongStringLit:
    # We're inside a template literal
    let startPos = pos
    while true:
      case g.buf[pos]
      of '\0':
        g.kind = gtLongStringLit
        # Keep state as gtLongStringLit for continuation on next line
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
      assert false, "javaScriptNextToken: produced an empty token"
    g.pos = pos
    return

  case g.buf[pos]
  of ' ', '\x09' .. '\x0D':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
      inc(pos)
  of '<':
    # Check for JSX tags outside of template literals
    if pos + 1 < g.buf.len and g.buf[pos + 1] in {'A' .. 'Z', 'a' .. 'z', '/', '!'}:
      # This looks like JSX/HTML, switch to JSX mode
      g.inJsxMode = true
      htmlNextToken(g)
      return
    else:
      # Regular less-than operator
      g.kind = gtOperator
      while g.buf[pos] in opChars:
        inc(pos)
  of '/':
    inc(pos)
    if g.buf[pos] == '/':
      g.kind = gtComment
      while not (g.buf[pos] in {'\0', '\x0A', '\x0D'}):
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
        of '\0':
          break
        else:
          inc(pos)
  of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
    var id = ""
    while g.buf[pos] in symChars:
      add(id, g.buf[pos])
      inc(pos)
    
    # Check if this identifier is a key (followed by colon)
    var isKey = false
    var tempPos = pos
    # Skip whitespace after identifier
    while tempPos < g.buf.len and g.buf[tempPos] in {' ', '\t', '\n', '\r'}:
      inc(tempPos)
    # Check if next non-whitespace character is colon
    if tempPos < g.buf.len and g.buf[tempPos] == ':':
      isKey = true
    
    if isKeyword(javaScriptkeywords, id) >= 0:
      g.kind = gtKeyword
    elif isKey:
      g.kind = gtKey
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
    of 'o', 'O':
      g.kind = gtOctNumber
      inc(pos)
      while g.buf[pos] in octChars:
        inc(pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '0' .. '7':
      g.kind = gtOctNumber
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
    let quote = g.buf[pos]
    inc(pos)

    # Check if this string is a key (for object literals with quotes)
    var isKey = false
    var tempPos = pos
    # Skip to end of string to check if it's followed by colon
    while tempPos < g.buf.len and g.buf[tempPos] != '\0':
      case g.buf[tempPos]
      of '\"', '\'':
        if g.buf[tempPos] == quote:
          inc(tempPos)
          # Skip whitespace after closing quote
          while tempPos < g.buf.len and g.buf[tempPos] in {' ', '\t', '\n', '\r'}:
            inc(tempPos)
          # Check if next non-whitespace character is colon
          if tempPos < g.buf.len and g.buf[tempPos] == ':':
            isKey = true
          break
        else:
          inc(tempPos)
      of '\\':
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
        if quote == '\"':
          break
        else:
          inc(pos)
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
  of '`':
    inc(pos)
    g.kind = gtLongStringLit
    g.state = gtLongStringLit
    inc(g.templateLiteralDepth)
    # Only consume until first ${
    while true:
      case g.buf[pos]
      of '\0':
        # Keep state for continuation
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
  of '(', ')', '[', ']', ':', ',', ';', '.':
    inc(pos)
    g.kind = gtPunctuation
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
      if pos < g.buf.len and g.buf[pos] == '<':
        g.inJsxMode = true
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
    assert false, "clikeNextToken: produced an empty token"
  g.pos = pos
