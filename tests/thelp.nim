import std/[unittest, strutils]
import moepkg/[unicodeext, gapbuffer]

import moepkg/helputils {.all.}

suite "Help":
  test "initHlepModeBuffer":
    let
      buffer = initHelpModeBuffer().toGapBuffer
      help = helpsentences.splitLines

    for i in 0 ..< buffer.len:
      check $buffer[i] == help[i]
