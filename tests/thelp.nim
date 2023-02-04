import std/[unittest, strutils, importutils]
import moepkg/[unicodeext, gapbuffer, editorstatus, bufferstatus]

import moepkg/helputils {.all.}
import moepkg/help {.all.}
import moepkg/commandline {.all.}

suite "initHelpModeBuffer":
  test "initHelpModeBuffer":
    let
      buffer = initHelpModeBuffer().toGapBuffer
      help = helpsentences.splitLines

    for i in 0 ..< buffer.len:
      check $buffer[i] == help[i]

suite "execHelpCommand":
  test "':' key":
    var status = initEditorStatus()

    const path = ""
    status.addNewBufferInCurrentWin(path, Mode.help)
    status.resize

    const key = ":".toRunes
    status.execHelpCommand(key)

    check currentBufStatus.isExmode
    check status.commandLine.buffer.len == 0

    privateAccess(status.commandLine.type)
    check status.commandLine.prompt == exModePrompt.toRunes
