import std/[unittest, strutils]
import moepkg/[editorstatus, gapbuffer, unicodeext, movement, window,
               bufferstatus]

include moepkg/help

suite "Help":
  test "Check buffer":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    status.initHelpModeBuffer
    currentBufStatus.isUpdate = true
    status.update

    check(currentBufStatus.path == ru"help")

    let
      buffer = currentBufStatus.buffer
      help = helpsentences.splitLines

    for i in 0 ..< buffer.len:
      if i == 0: check buffer[0] == ru""
      else: check $buffer[i] == help[i - 1]
