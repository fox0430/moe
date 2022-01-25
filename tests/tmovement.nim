import std/unittest
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, movement,
               bufferstatus]

test "Move right":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyRight(currentMainWindowNode)

  check(currentMainWindowNode.currentColumn == 2)

test "Move left":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  currentMainWindowNode.currentColumn = 2
  for i in 0 ..< 3:
    currentMainWindowNode.keyLeft

  check(currentMainWindowNode.currentColumn == 0)

test "Move down":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyDown(currentMainWindowNode)

  check(currentMainWindowNode.currentLine == 2)

test "Move up":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  currentMainWindowNode.currentLine = 2
  for i in 0 ..< 3:
    status.bufStatus[0].keyUp(currentMainWindowNode)

  check(currentMainWindowNode.currentLine == 0)

test "Move to first non blank of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  currentMainWindowNode.currentColumn = 4
  status.bufStatus[0].moveToFirstNonBlankOfLine(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 2)

test "Move to first of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  currentMainWindowNode.currentColumn = 4
  currentMainWindowNode.moveToFirstOfLine
  check(currentMainWindowNode.currentColumn == 0)

test "Move to last of current line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].moveToLastOfLine(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 4)

test "Move to first of previous Line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  currentMainWindowNode.currentLine = 1
  status.bufStatus[0].moveToFirstOfPreviousLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 0)
  check(currentMainWindowNode.currentColumn == 0)

test "Move to first of next Line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.bufStatus[0].moveToFirstOfNextLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 1)
  check(currentMainWindowNode.currentColumn == 0)

test "Jump line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  currentBufStatus.jumpLine(currentMainWindowNode, 1)
  currentBufStatus.jumpLine(currentMainWindowNode, 4)
  check(currentMainWindowNode.currentLine == 4)

test "Move to first line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  currentMainWindowNode.currentLine = 4
  currentBufStatus.moveToFirstLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 0)

test "Move to last line":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  currentMainWindowNode.currentLine = 1
  currentBufStatus.moveToLastLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 5)

test "Move to forward word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.bufStatus[0].moveToForwardWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 4)

test "Move to backward word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  currentMainWindowNode.currentColumn = 5
  for i in 0 ..< 2:
    status.bufStatus[0].moveToBackwardWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 0)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 6)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 6)

test "Move to previous blank line":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru"ghi"])
  currentMainWindowNode.currentLine = currentBufStatus.buffer.high

  currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 1
  check currentMainWindowNode.currentColumn == 0

test "Move to next blank line":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"", ru"ghi"])

  currentBufStatus.moveToNextBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 2
  check currentMainWindowNode.currentColumn == 0
