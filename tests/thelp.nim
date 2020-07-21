import unittest, strutils
import moepkg/[editorstatus, gapbuffer, unicodeext, movement, window, bufferstatus]

include moepkg/help

suite "Help":
  test "Check buffer":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.resize(100, 100)
    status.update

    status.initHelpModeBuffer
    status.update

    check(status.bufStatus[0].path == ru"help")

    let buffer = status.bufStatus[0].buffer
    var
      line = 1
      f = open(currentSourcePath.parentDir() / "../documents/howtouse.md",
               FileMode.fmRead)

    while not f.endOfFile:
      let
        markDownLine = f.readLine()
        bufferLine = $buffer[line][0 .. buffer[line].high]
      check bufferLine == markDownLine.multiReplace(@[("```", ""), ("  ", "")])
      inc line
