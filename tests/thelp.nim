import std/[unittest, strutils]
include moepkg/help

suite "Help":
  test "Check buffer":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    currentBufStatus.initHelpModeBuffer
    currentBufStatus.isUpdate = true
    status.update

    check(currentBufStatus.path == ru"help")

    let
      buffer = currentBufStatus.buffer
      help = helpsentences.splitLines

    for i in 0 ..< buffer.len:
      if i == 0: check buffer[0] == ru""
      else: check $buffer[i] == help[i - 1]

  test "Open help":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    status.verticalSplitWindow
    status.resize(100, 100)
    status.moveNextWindow

    status.addNewBuffer
    status.changeCurrentBuffer(status.bufStatus.high)
    status.changeMode(Mode.help)

    status.resize(100, 100)
    status.update

    currentBufStatus.initHelpModeBuffer

    status.resize(100, 100)
    status.update
