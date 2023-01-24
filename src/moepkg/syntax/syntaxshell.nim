import flags
import highlite
import lexer

const
  shellKeywords* = [ "["
                   , "]"
                   , "alias"
                   , "bg"
                   , "bind"
                   , "break"
                   , "builtin"
                   , "case"
                   , "cd"
                   , "chdir"
                   , "command"
                   , "compgen"
                   , "complete"
                   , "continue"
                   , "declare"
                   , "dirs"
                   , "disown"
                   , "do"
                   , "done"
                   , "echo"
                   , "elif"
                   , "else"
                   , "enable"
                   , "esac"
                   , "eval"
                   , "exec"
                   , "exit"
                   , "export"
                   , "fc"
                   , "fg"
                   , "fi"
                   , "for"
                   , "function"
                   , "getopts"
                   , "hash"
                   , "help"
                   , "history"
                   , "if"
                   , "in"
                   , "jobs"
                   , "kill"
                   , "let"
                   , "local"
                   , "login"
                   , "logout"
                   , "newgrp"
                   , "popd"
                   , "print"
                   , "printf"
                   , "pushd"
                   , "pwd"
                   , "read"
                   , "readonly"
                   , "return"
                   , "select"
                   , "set"
                   , "shift"
                   , "shopt"
                   , "source"
                   , "stop"
                   , "suspend"
                   , "test"
                   , "then"
                   , "time"
                   , "times"
                   , "trap"
                   , "type"
                   , "typeset"
                   , "ulimit"
                   , "umask"
                   , "unalias"
                   , "unset"
                   , "until"
                   , "wait"
                   , "whence"
                   , "while"
                   , "{"
                   , "}"
                   ]

proc shellNextToken*(g: var GeneralTokenizer) =
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
    of '#': pos = g.lexHash(pos, flagsShell)
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(shellKeywords, id) >= 0: g.kind = gtKeyword
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
    of '\'':
      inc pos
      g.kind = gtStringLit

      while true:
        case g.buf[pos]
        of '\0':
          break

        of '\'':
          inc pos
          break

        of '\\':
          g.state = g.kind
          break

        else:
          inc pos
    of '(', ')', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in opChars:
        g.kind = gtOperator
        while g.buf[pos] in opChars: inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "shellNextToken: produced an empty token"
  g.pos = pos