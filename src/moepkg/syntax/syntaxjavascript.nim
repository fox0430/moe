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

const
  keywords = ["Array", "ArrayBuffer", "Attr", "BigInt64Array",
    "BigUint64Array", "Boolean", "Buffer", "CDATASection", "CharacterData",
    "Collator", "Comment", "DOMException", "DOMImplementation",
    "DOMSTRING_SIZE_ERR", "DataViewDate", "DateTimeFormat", "Document",
    "DocumentFragment", "DocumentType", "Element", "Entity",
    "EntityReference", "Float32Array", "Float64Array", "Function",
    "HIERARCHY_REQUEST_ERR", "INDEX_SIZE_ERR", "INUSE_ATTRIBUTE_ERR",
    "INVALID_ACCESS_ERR", "INVALID_CHARACTER_ERR", "INVALID_MODIFICATION_ERR",
    "INVALID_STATE_ERR", "Int16Array", "Int32Array", "Int8Array", "Intl",
    "Iterator", "JSON", "Map", "MathNumber", "NAMESPACE_ERR",
    "NOT_FOUND_ERR", "NOT_SUPPORTED_ERR", "NO_DATA_ALLOWED_ERR",
    "NO_MODIFICATION_ALLOWED_ERR", "NamedNodeMap", "Node", "NodeList",
    "Notation", "NumberFormat", "Object", "Object", "ParallelArray",
    "ProcessingInstruction", "PromiseProxy", "Reflect", "RegExp",
    "SYNTAX_ERR", "Set", "String", "String", "Symbol", "Text", "Uint16Array",
    "Uint32Array", "Uint8Array", "Uint8ClampedArray", "Uint8ClampedArray",
    "WRONG_DOCUMENT_ERR", "WeakMap", "WeakSet", "WebAssembly", "abstract",
    "apply", "arguments", "as", "assert", "async", "await", "boolean",
    "break", "byte", "catchexport", "char", "charAt", "class", "console",
    "console", "const", "continue", "decodeURI", "decodeURIComponent",
    "delete", "do", "document", "double", "else", "encodeURI",
    "encodeURIComponenteval", "enum", "except", "false", "fetch", "final",
    "finally", "float", "for", "from", "function", "global", "goto", "if",
    "implementsprotected", "import", "in", "indexOf", "instanceof", "int",
    "interface", "is", "isFinite", "isNaN", "join", "keys", "let", "log",
    "long", "native", "new", "null", "onblur", "onclick", "oncontextmenu",
    "ondblclick", "onfocus", "onkeydown", "onkeypress", "onkeyup",
    "onmousedown", "onmousemove", "onmouseout", "onmouseover", "onmouseup",
    "onresize", "or", "package", "parseFloat", "parseIntuneval", "pass",
    "private", "public", "push", "require", "return", "short", "switch",
    "synchronized", "throw", "throws", "transient", "true", "try", "value",
    "var", "void", "volatile", "while", "window", "yield"
  ]

# javaScriptNextToken is Incomplete
proc javaScriptNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
    octChars = {'0'..'7'}
    binChars = {'0'..'1'}
    symChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\x80'..'\xFF'}
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
          if g.buf[pos] in hexChars: inc(pos)
          if g.buf[pos] in hexChars: inc(pos)
        of '0'..'9':
          while g.buf[pos] in {'0'..'9'}: inc(pos)
        of '\0':
          g.state = gtNone
        else: inc(pos)
        break
      of '\0', '\x0D', '\x0A':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else: inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\x09'..'\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
    of '/':
      inc(pos)
      if g.buf[pos] == '/':
        g.kind = gtComment
        while not (g.buf[pos] in {'\0', '\x0A', '\x0D'}): inc(pos)
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
              if nested == 0: break
          of '/':
            inc(pos)
            if g.buf[pos] == '*': inc(pos)
          of '\0':
            break
          else: inc(pos)
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(keywords, id) >= 0: g.kind = gtKeyword
      else: g.kind = gtIdentifier
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        inc(pos)
        while g.buf[pos] in binChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      of 'x', 'X':
        inc(pos)
        while g.buf[pos] in hexChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      of '0'..'7':
        inc(pos)
        while g.buf[pos] in octChars: inc(pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
      else:
        pos = generalNumber(g, pos)
        if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
    of '1'..'9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
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
        else: inc(pos)
    of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in OpChars:
        g.kind = gtOperator
        while g.buf[pos] in OpChars: inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "clikeNextToken: produced an empty token"
  g.pos = pos
