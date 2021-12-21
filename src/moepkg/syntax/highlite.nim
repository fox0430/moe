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

## Source highlighter for programming or markup languages.
## Currently only few languages are supported, other languages may be added.
## The interface supports one language nested in another.
##
## **Note:** Import ``packages/docutils/highlite`` to use this module
##
## You can use this to build your own syntax highlighting, check this example:
##
## .. code::nim
##   let code = """for x in $int.high: echo x.ord mod 2 == 0"""
##   var toknizr: GeneralTokenizer
##   initGeneralTokenizer(toknizr, code)
##   while true:
##     getNextToken(toknizr, langNim)
##     case toknizr.kind
##     of gtEof: break  # End Of File (or string)
##     of gtWhitespace:
##       echo gtWhitespace # Maybe you want "visible" whitespaces?.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##     of gtOperator:
##       echo gtOperator # Maybe you want Operators to use a specific color?.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##     # of gtSomeSymbol: syntaxHighlight("Comic Sans", "bold", "99px", "pink")
##     else:
##       echo toknizr.kind # All the kinds of tokens can be processed here.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##
## The proc ``getSourceLanguage`` can get the language ``enum`` from a string:
##
## .. code::nim
##   for l in ["C", "c++", "jAvA", "Nim", "c#"]: echo getSourceLanguage(l)
##

import
  std/strutils
from std/algorithm import binarySearch

type
  TokenClass* = enum
    gtEof, gtNone, gtWhitespace, gtDecNumber, gtBinNumber, gtHexNumber,
    gtOctNumber, gtFloatNumber, gtIdentifier, gtKeyword, gtStringLit,
    gtLongStringLit, gtCharLit, gtEscapeSequence, # escape sequence like \xff
    gtOperator, gtPunctuation, gtComment, gtLongComment, gtRegularExpression,
    gtTagStart, gtTagEnd, gtKey, gtValue, gtRawData, gtAssembler,
    gtPreprocessor, gtDirective, gtCommand, gtRule, gtHyperlink, gtLabel,
    gtReference, gtOther, gtBoolean, gtSpecialVar, gtBuiltin, gtFunctionName, gtTypeName

  GeneralTokenizer* = object of RootObj
    kind*: TokenClass
    start*, length*: int
    buf*: cstring
    pos*: int
    state*: TokenClass

  SourceLanguage* = enum
    langNone, langNim, langCpp, langCsharp, langC, langJava,
    langYaml, langPython, langJavaScript, langShell, langMarkDown

const
  sourceLanguageToStr*: array[SourceLanguage, string] = ["none",
    "Nim", "C++", "C#", "C", "Java", "Yaml", "Python", "JavaScript", "Shell",
    "MarkDown"]

  OpChars* = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.',
              '|', '=', '%', '&', '$', '@', '~', ':'}


proc getSourceLanguage*(name: string): SourceLanguage =
  for i in countup(succ(low(SourceLanguage)), high(SourceLanguage)):
    if cmpIgnoreStyle(name, sourceLanguageToStr[i]) == 0:
      return i
  result = langNone

proc initGeneralTokenizer*(g: var GeneralTokenizer, buf: cstring) =
  g.buf = buf
  g.kind = low(TokenClass)
  g.start = 0
  g.length = 0
  g.state = low(TokenClass)
  var pos = 0                     # skip initial whitespace:
  while g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
  g.pos = pos

proc initGeneralTokenizer*(g: var GeneralTokenizer, buf: string) =
  initGeneralTokenizer(g, cstring(buf))

proc generalNumber*(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0'..'9'}
  var pos = position
  g.kind = gtDecNumber
  while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] == '.':
    g.kind = gtFloatNumber
    inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}: inc(pos)
    while g.buf[pos] in decChars: inc(pos)
  result = pos

proc generalStrLit*(g: var GeneralTokenizer, position: int): int =
  const
    decChars = {'0'..'9'}
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
  var pos = position
  g.kind = gtStringLit
  var c = g.buf[pos]
  inc(pos)                    # skip " or '
  while true:
    case g.buf[pos]
    of '\0':
      break
    of '\\':
      inc(pos)
      case g.buf[pos]
      of '\0':
        break
      of '0'..'9':
        while g.buf[pos] in decChars: inc(pos)
      of 'x', 'X':
        inc(pos)
        if g.buf[pos] in hexChars: inc(pos)
        if g.buf[pos] in hexChars: inc(pos)
      else: inc(pos, 2)
    else:
      if g.buf[pos] == c:
        inc(pos)
        break
      else:
        inc(pos)
  result = pos

proc isKeyword*(x: openArray[string], y: string): int =
  binarySearch(x, y)

type
  TokenizerFlag* = enum
    hasPreprocessor, hasNestedComments
  TokenizerFlags* = set[TokenizerFlag]

import syntaxnim, syntaxyaml, syntaxjavascript, syntaxc, syntaxcpp,
       syntaxcsharp, syntaxjava, syntaxpython
proc getNextToken*(g: var GeneralTokenizer, lang: SourceLanguage) =
  case lang
  of langNone: assert false
  of langNim: nimNextToken(g)
  of langCpp: cppNextToken(g)
  of langCsharp: csharpNextToken(g)
  of langC: cNextToken(g)
  of langJava: javaNextToken(g)
  of langYaml: yamlNextToken(g)
  of langPython: pythonNextToken(g)
  of langJavaScript: javaScriptNextToken(g)
  else: discard
