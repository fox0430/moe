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

import std/strutils
from std/algorithm import binarySearch

import highlite

const
  # The following list comes from doc/keywords.txt, make sure it is
  # synchronized with this array by running the module itself as a test case.
  nimKeywords = ["addr", "and", "as", "asm", "bind", "block",
    "break", "case", "cast", "concept", "const", "continue", "converter",
    "defer", "discard", "distinct", "div", "do",
    "elif", "else", "end", "enum", "except", "export",
    "finally", "for", "from", "func",
    "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro", "method",
    "mixin", "mod", "nil", "not", "notin", "object", "of", "or", "out", "proc",
    "ptr", "raise", "ref", "return", "shl", "shr", "static",
    "template", "try", "tuple", "type", "using", "var", "when", "while",
    "xor", "yield"]
  nimBooleans = ["true", "false"]
  nimSpecialVars = ["result"]
  # Builtin types, objects, and exceptions
  nimBuiltins = ["AccessViolationError", "AlignType", "ArithmeticError",
    "AssertionError", "BiggestFloat", "BiggestInt", "Byte", "ByteAddress",
    "CloseFile", "CompileDate", "CompileTime", "Conversion", "DeadThreadError",
    "DivByZeroError", "EndOfFile", "Endianness", "Exception", "ExecIOEffect",
    "FieldError", "File", "FileHandle", "FileMode", "FileModeFileHandle",
    "FloatDivByZeroError", "FloatInexactError", "FloatInvalidOpError",
    "FloatOverflowError", "FloatUnderflowError", "FloatingPointError",
    "FlushFile", "GC_Strategy", "GC_disable", "GC_disableMarkAnd", "GC_enable",
    "GC_enableMarkAndSweep", "GC_fullCollect", "GC_getStatistics", "GC_ref",
    "GC_setStrategy","GC_unref", "IOEffect", "IOError", "IndexError",
    "KeyError", "LibHandle", "LibraryError", "Msg", "Natural", "NimNode",
    "OSError", "ObjectAssignmentError", "ObjectConversionError", "OpenFile",
    "Ordinal", "OutOfMemError", "OverflowError", "PFloat32", "PFloat64",
    "PFrame", "PInt32", "PInt64", "Positive", "ProcAddr", "QuitFailure",
    "QuitSuccess", "RangeError", "ReadBytes", "ReadChars", "ReadIOEffect",
    "RefCount", "ReraiseError", "ResourceExhaustedError", "RootEffect",
    "RootObj", "RootObjRootRef", "Slice", "SomeInteger", "SomeNumber",
    "SomeOrdinal", "SomeReal", "SomeSignedInt", "SomeUnsignedInt",
    "StackOverflowError", "Sweep", "SystemError", "TFrame", "THINSTANCE",
    "TResult", "TaintedString", "TimeEffect", "Utf16Char", "ValueError",
    "WideCString", "WriteIOEffect", "abs", "add", "addQuitProc", "alloc",
    "alloc0", "array", "assert", "autoany", "bool", "byte", "card","cchar",
    "cdouble", "cfloat", "char", "chr", "cint", "clong", "clongdouble",
    "clonglong", "copy", "copyMem", "countdown", "countup", "cpuEndian",
    "cschar", "cshort", "csize", "cstring", "cstringArray", "cuchar", "cuint",
    "culong", "culonglong", "cushort", "dbgLineHook", "dealloc", "dec",
    "defined", "echo", "equalMem", "equalmem", "excl", "expr", "fileHandle",
    "find", "float", "float32", "float64", "getCurrentException", "getFilePos",
    "getFileSize", "getFreeMem", "getOccupiedMem", "getRefcount","getTotalMem",
    "guarded","high", "hostCPU", "hostOS", "inc", "incl", "inf", "int", "int16",
    "int32", "int64", "int8", "isNil", "items", "len", "lines", "low", "max",
    "min", "moveMem", "movemem", "nan", "neginf", "new", "newSeq", "newString",
    "newseq", "newstring", "nimMajor", "nimMinor", "nimPatch", "nimVersion",
    "nimmajor", "nimminor", "nimpatch", "nimversion", "openArray", "openarray",
    "ord", "pointer", "pop", "pred", "ptr", "quit", "range", "readBuffer",
    "readChar", "readFile", "readLine", "readbuffer", "readfile", "readline",
    "realloc", "ref", "repr", "seq", "seqToPtr", "seqtoptr", "set",
    "setFilePos", "setLen", "setfilepos", "setlen", "shared", "sizeof",
    "stderr", "stdin", "stdout", "stmt", "string", "succ", "swap",
    "toBiggestFloat", "toBiggestInt", "toFloat", "toInt", "toU16", "toU32",
    "toU8", "tobiggestfloat", "tobiggestint", "tofloat", "toint", "tou16",
    "tou32", "tou8", "typed", "typedesc", "uint", "uint16", "uint32",
    "uint32uint64", "uint64", "uint8", "untyped", "varArgs", "void", "write",
    "writeBuffer", "writeBytes", "writeChars", "writeLine", "writeLn", "ze",
    "ze64", "zeroMem"]

proc nimGetKeyword(id: string): TokenClass =
  for k in nimKeywords:
    if cmpIgnoreStyle(id, k) == 0: return gtKeyword
  if binarySearch(nimBooleans, id) > -1: return gtBoolean
  if binarySearch(nimSpecialVars, id) > -1: return gtSpecialVar
  if id[0] in 'A'..'Z': return gtTypeName
  if binarySearch(nimBuiltins, id) > -1: return gtBuiltin
  result = gtIdentifier

  when false:
    var i = getIdent(id)
    if (i.id >= ord(tokKeywordLow) - ord(tkSymbol)) and
        (i.id <= ord(tokKeywordHigh) - ord(tkSymbol)):
      result = gtKeyword
    else:
      result = gtIdentifier

proc nimNumberPostfix(g: var GeneralTokenizer, position: int): int =
  var pos = position
  if g.buf[pos] == '\'':
    inc(pos)
    case g.buf[pos]
    of 'f', 'F':
      g.kind = gtFloatNumber
      inc(pos)
      if g.buf[pos] in {'0'..'9'}: inc(pos)
      if g.buf[pos] in {'0'..'9'}: inc(pos)
    of 'i', 'I':
      inc(pos)
      if g.buf[pos] in {'0'..'9'}: inc(pos)
      if g.buf[pos] in {'0'..'9'}: inc(pos)
    else:
      discard
  result = pos

proc nimNumber(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0'..'9', '_'}
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
  result = nimNumberPostfix(g, pos)

proc nimNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0'..'9', 'A'..'F', 'a'..'f', '_'}
    octChars = {'0'..'7', '_'}
    binChars = {'0'..'1', '_'}
    SymChars = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF'}
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
    of '#':
      g.kind = gtComment
      inc(pos)
      var isDoc = false
      if g.buf[pos] == '#':
        inc(pos)
        isDoc = true
      if g.buf[pos] == '[':
        g.kind = gtLongComment
        var nesting = 0
        while true:
          case g.buf[pos]
          of '\0': break
          of '#':
            if isDoc:
              if g.buf[pos+1] == '#' and g.buf[pos+2] == '[':
                inc nesting
            elif g.buf[pos+1] == '[':
              inc nesting
            inc pos
          of ']':
            if isDoc:
              if g.buf[pos+1] == '#' and g.buf[pos+2] == '#':
                if nesting == 0:
                  inc(pos, 3)
                  break
                dec nesting
            elif g.buf[pos+1] == '#':
              if nesting == 0:
                inc(pos, 2)
                break
              dec nesting
            inc pos
          else:
            inc pos
      else:
        while g.buf[pos] notin {'\0', '\x0A', '\x0D'}: inc(pos)
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in SymChars + {'_'}:
        add(id, g.buf[pos])
        inc(pos)
      if (g.buf[pos] == '\"'):
        if (g.buf[pos + 1] == '\"') and (g.buf[pos + 2] == '\"'):
          inc(pos, 3)
          g.kind = gtLongStringLit
          while true:
            case g.buf[pos]
            of '\0':
              break
            of '\"':
              inc(pos)
              if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
                  g.buf[pos+2] != '\"':
                inc(pos, 2)
                break
            else: inc(pos)
        else:
          g.kind = gtRawData
          inc(pos)
          while not (g.buf[pos] in {'\0', '\x0A', '\x0D'}):
            if g.buf[pos] == '"' and g.buf[pos+1] != '"': break
            inc(pos)
          if g.buf[pos] == '\"': inc(pos)
      else:
        if (g.buf[pos] == '(' or g.buf[pos] == '*') and nimGetKeyword(id) == gtIdentifier:
          g.kind = gtFunctionName
        else:
          g.kind = nimGetKeyword(id)
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in binChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      of 'x', 'X':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in hexChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      of 'o', 'O':
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in octChars: inc(pos)
        pos = nimNumberPostfix(g, pos)
      else: pos = nimNumber(g, pos)
    of '1'..'9':
      pos = nimNumber(g, pos)
    of '\'':
      inc(pos)
      g.kind = gtCharLit
      while true:
        case g.buf[pos]
        of '\0', '\x0D', '\x0A':
          break
        of '\'':
          inc(pos)
          break
        of '\\':
          inc(pos, 2)
        else: inc(pos)
    of '\"':
      inc(pos)
      if (g.buf[pos] == '\"') and (g.buf[pos + 1] == '\"'):
        inc(pos, 2)
        g.kind = gtLongStringLit
        while true:
          case g.buf[pos]
          of '\0':
            break
          of '\"':
            inc(pos)
            if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
                g.buf[pos+2] != '\"':
              inc(pos, 2)
              break
          else: inc(pos)
      else:
        g.kind = gtStringLit
        while true:
          case g.buf[pos]
          of '\0', '\x0D', '\x0A':
            break
          of '\"':
            inc(pos)
            break
          of '\\':
            g.state = g.kind
            break
          else: inc(pos)
    of '(', ')', '[', ']', '{', '}', '`', ':', ',', ';':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in OpChars:
        let sp = pos
        g.kind = gtOperator
        while g.buf[pos] in OpChars: inc(pos)
        let ep = pos
        if sp + 1 == ep  and g.buf[sp] == '*' and g.buf[ep] == '(' :
          g.kind = gtSpecialVar
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.state != gtNone and g.length <= 0:
    assert false, "nimNextToken: produced an empty token"
  g.pos = pos
