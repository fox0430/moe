import unittest
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, movement,
               bufferstatus]

test "Move right":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

  check(status.workSpace[0].currentMainWindowNode.currentColumn == 2)

test "Move left":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.reservedWords,
    status.bufStatus[0].language)

  status.workSpace[0].currentMainWindowNode.currentColumn = 2
  for i in 0 ..< 3:
    status.workSpace[0].currentMainWindowNode.keyLeft

  check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

test "Move down":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  check(status.workSpace[0].currentMainWindowNode.currentLine == 2)

test "Move up":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.reservedWords,
    status.bufStatus[0].language)

  status.workSpace[0].currentMainWindowNode.currentLine = 2
  for i in 0 ..< 3:
    status.bufStatus[0].keyUp(status.workSpace[0].currentMainWindowNode)

  check(status.workSpace[0].currentMainWindowNode.currentLine == 0)

test "Move to first non blank of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.workSpace[0].currentMainWindowNode.currentColumn = 4
  status.bufStatus[0].moveToFirstNonBlankOfLine(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 2)

test "Move to first of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.workSpace[0].currentMainWindowNode.currentColumn = 4
  status.workSpace[0].currentMainWindowNode.moveToFirstOfLine
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

test "Move to last of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].moveToLastOfLine(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 4)

test "Move to first of previous Line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.workSpace[0].currentMainWindowNode.currentLine = 1
  status.bufStatus[0].moveToFirstOfPreviousLine(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentLine == 0)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

test "Move to first of next Line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.bufStatus[0].moveToFirstOfNextLine(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentLine == 1)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

test "Jump line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.jumpLine(1)
  status.jumpLine(4)
  check(status.workSpace[0].currentMainWindowNode.currentLine == 4)

test "Move to first line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.workSpace[0].currentMainWindowNode.currentLine = 4
  status.moveToFirstLine
  check(status.workSpace[0].currentMainWindowNode.currentLine == 0)

test "Move to last line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.workSpace[0].currentMainWindowNode.currentLine = 1
  status.moveToLastLine
  check(status.workSpace[0].currentMainWindowNode.currentLine == 5)

test "Move to forward word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.bufStatus[0].moveToForwardWord(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 4)

test "Move to backward word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.workSpace[0].currentMainWindowNode.currentColumn = 5
  for i in 0 ..< 2:
    status.bufStatus[0].moveToBackwardWord(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 6)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(status.workSpace[0].currentMainWindowNode)
  check(status.workSpace[0].currentMainWindowNode.currentColumn == 6)
