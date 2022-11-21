import std/algorithm

import flags
import highlite

const
  rustKeywords* = [ "abstract"
                  , "as"
                  , "become"
                  , "box"
                  , "break"
                  , "const"
                  , "continue"
                  , "crate"
                  , "do"
                  , "dyn"
                  , "else"
                  , "enum"
                  , "extern"
                  , "false"
                  , "final"
                  , "fn"
                  , "for"
                  , "if"
                  , "impl"
                  , "in"
                  , "let"
                  , "loop"
                  , "macro"
                  , "match"
                  , "mod"
                  , "move"
                  , "mut"
                  , "override"
                  , "priv"
                  , "pub"
                  , "ref"
                  , "return"
                  , "Self"
                  , "self"
                  , "static"
                  , "struct"
                  , "super"
                  , "trait"
                  , "true"
                  , "try"
                  , "type"
                  , "typeof"
                  , "unsafe"
                  , "unsized"
                  , "use"
                  , "virtual"
                  , "where"
                  , "while"
                  , "yield"
                  ]

  # Types and traits
  rustBuiltins* = [ "AsMut"
                  , "AsRef"
                  , "Box"
                  , "Clone"
                  , "Copy"
                  , "Default"
                  , "DoubleEndedIterator"
                  , "Drop"
                  , "Eq"
                  , "ErrSliceConcatExt"
                  , "ExactSizeIterator"
                  , "Extend"
                  , "Fn"
                  , "FnMut"
                  , "FnOnce"
                  , "From"
                  , "Into"
                  , "IntoIterator"
                  , "Iterator"
                  , "None"
                  , "Ok"
                  , "Option"
                  , "Ord"
                  , "PartialEq"
                  , "PartialOrd"
                  , "Result"
                  , "Self"
                  , "Send"
                  , "Sized"
                  , "Some"
                  , "String"
                  , "Sync"
                  , "ToOwned"
                  , "ToString"
                  , "Variant"
                  , "Variant"
                  , "Vec"
                  , "bool"
                  , "char"
                  , "f32"
                  , "f64"
                  , "i128"
                  , "i16"
                  , "i32"
                  , "i64"
                  , "i8"
                  , "isize"
                  , "str"
                  , "u128"
                  , "u16"
                  , "u32"
                  , "u64"
                  , "u8"
                  , "usize"
                  ]

# TODO: mergeKeywords() will be deleted in the future.
# TODO: Allow set different colors for each kind without merging
# like Nim syntax highlighting.
proc mergeKeywords(): seq[string] {.compiletime.} =
  for k in rustKeywords: result.add k
  for k in rustBuiltins: result.add k
  result.sort

template isCharLit*(g: var GeneralTokenizer, position: int): bool =
  (g.buf.high > pos + 1) and (g.buf[position + 2] == '\'')

proc rustNextToken(g: var GeneralTokenizer, keywords: openArray[string],
                   flags: TokenizerFlags) =
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
      of '\0', '\r', '\n':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else: inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\t'..'\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t'..'\r'}: inc(pos)
    of '/':
      inc(pos)
      if g.buf[pos] == '/':
        g.kind = gtComment
        while not (g.buf[pos] in {'\0', '\n', '\r'}): inc(pos)
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
            if g.buf[pos] == '*':
              inc(pos)
              if hasNestedComments in flags: inc(nested)
          of '\0':
            break
          else: inc(pos)
    of '#':
      inc(pos)
      if hasPreprocessor in flags:
        g.kind = gtPreprocessor
        while g.buf[pos] in {' ', '\t'}: inc(pos)
        while g.buf[pos] in symChars: inc(pos)
      else:
        g.kind = gtOperator
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
    of '\'':
      # TODO: Maybe need to fix Rust lifetime.
      if isCharLit(g, pos):
        # Common char
        pos = pos + 3
        g.kind = gtCharLit
      else:
        # Rust Lifetime
        inc(pos)
        g.kind = gtIdentifier
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\"':
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

proc rustNextToken*(g: var GeneralTokenizer) =
  const keywords = mergeKeywords()
  rustNextToken(g, keywords, {})
