import unittest
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, movement]

test "Move right":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  for i in 0 ..< 3: status.bufStatus[0].keyRight
  check(status.bufStatus[0].currentColumn == 2)

test "Move left":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.bufStatus[0].currentColumn = 2
  for i in 0 ..< 3: status.bufStatus[0].keyLeft
  check(status.bufStatus[0].currentColumn == 0)

test "Move down":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  for i in 0 ..< 3: status.bufStatus[0].keyDown
  check(status.bufStatus[0].currentLine == 2)

test "Move up":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.bufStatus[0].currentLine = 2
  for i in 0 ..< 3: status.bufStatus[0].keyUp
  check(status.bufStatus[0].currentLine == 0)

test "Move to first non blank of current line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].currentColumn = 4
  status.bufStatus[0].moveToFirstNonBlankOfLine
  check(status.bufStatus[0].currentColumn == 2)

test "Move to first of current line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].currentColumn = 4
  status.bufStatus[0].moveToFirstOfLine
  check(status.bufStatus[0].currentColumn == 0)

test "Move to last of current line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].moveToLastOfLine
  check(status.bufStatus[0].currentColumn == 4)

test "Move to first of previous Line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.bufStatus[0].currentLine = 1
  status.bufStatus[0].moveToFirstOfPreviousLine
  check(status.bufStatus[0].currentLine == 0)
  check(status.bufStatus[0].currentColumn == 0)

test "Move to first of next Line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.bufStatus[0].moveToFirstOfNextLine
  check(status.bufStatus[0].currentLine == 1)
  check(status.bufStatus[0].currentColumn == 0)

test "Jump line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.jumpLine(1)
  status.jumpLine(4)
  check(status.bufStatus[0].currentLine == 4)

test "Move to first line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.bufStatus[0].currentLine = 4
  status.moveToFirstLine
  check(status.bufStatus[0].currentLine == 0)

test "Move to last line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij", ru"klm", ru"nop", ru"qrs"])
  status.bufStatus[0].currentLine = 1
  status.moveToLastLine
  check(status.bufStatus[0].currentLine == 5)

test "Move to forward word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.bufStatus[0].moveToForwardWord
  check(status.bufStatus[0].currentColumn == 4)

test "Move to backward word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.bufStatus[0].currentColumn = 5
  for i in 0 ..< 2: status.bufStatus[0].moveToBackwardWord
  check(status.bufStatus[0].currentColumn == 0)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2: status.bufStatus[0].moveToForwardEndOfWord
  check(status.bufStatus[0].currentColumn == 6)

test "Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2: status.bufStatus[0].moveToForwardEndOfWord
  check(status.bufStatus[0].currentColumn == 6)
