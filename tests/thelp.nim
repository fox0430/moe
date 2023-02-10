import std/[unittest, strutils, importutils]
import moepkg/[unicodeext, gapbuffer, editorstatus, bufferstatus, ui]
import pkg/ncurses

import moepkg/helputils {.all.}
import moepkg/help {.all.}
import moepkg/commandline {.all.}

const CONTROL_J = 10
const CONTROL_K = 11

proc initHelpMode(): EditorStatus =
  result = initEditorStatus()

  const path = ""
  result.addNewBufferInCurrentWin(path, Mode.help)
  result.resize

suite "initHelpModeBuffer":
  test "initHelpModeBuffer":
    let
      buffer = initHelpModeBuffer().toGapBuffer
      help = helpsentences.splitLines

    for i in 0 ..< buffer.len:
      check $buffer[i] == help[i]

suite "isHelpCommand":
  test "valid commands":
    const commands = @[
      @[CONTROL_J.Rune],
      @[CONTROL_K.Rune],
      ":".toRunes,
      "k".toRunes, @[KEY_UP.Rune],
      "j".toRunes, @[KEY_DOWN.Rune],
      "h".toRunes, @[KEY_LEFT.Rune], @[KEY_BACKSPACE.Rune],
      "l".toRunes, @[KEY_RIGHT.Rune],
      "0".toRunes, @[KEY_HOME.Rune],
      "$".toRunes, @[KEY_END.Rune],
      "G".toRunes,
      "gg".toRunes
    ]

    for c in commands:
      check isHelpCommand(c) == InputState.Valid

  test "continue commands":
    const commands = @["g".toRunes]

    for c in commands:
      check isHelpCommand(c) == InputState.Continue

  test "invalid commands":
    const commands = @[@[999.Rune]]

    for c in commands:
      check isHelpCommand(c) == InputState.Invalid

suite "execHelpCommand":
  test "':' key":
    # Change mode to ex

    var status = initHelpMode()

    const key = ":".toRunes
    status.execHelpCommand(key)

    check currentBufStatus.isExmode
    check status.commandLine.buffer.len == 0

    privateAccess(status.commandLine.type)
    check status.commandLine.prompt == exModePrompt.toRunes

  test "'j' key":
    # Move to the below line

    var status = initHelpMode()

    const key = "j".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 1

  test "'k' key":
    # Move to the above line

    var status = initHelpMode()

    currentMainWindowNode.currentLine = 1

    const key = "k".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 0

  test "'l' key":
    # Move to the right

    var status = initHelpMode()

    const key = "l".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 1

  test "'h' key":
    # Move to the left

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    const key = "h".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 0

  test "'0' key":
    # Move to top of the line

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    const key = "0".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 0

  test "'$' key":
    # Move to last of the line

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    const key = "$".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].high

  test "'G' key":
    # Move to the last line of the buffer

    var status = initHelpMode()

    const key = "G".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == currentBufStatus.buffer.high

  test "gg key":
    # Move to the first line of the buffer

    var status = initHelpMode()

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high

    const key = "gg".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 0

