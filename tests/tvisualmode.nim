import unittest
import moepkg/editorstatus, moepkg/gapbuffer, moepkg/normalmode, moepkg/unicodeext, moepkg/highlight, moepkg/visualmode

test "Visual mode: Delete buffer 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abcd"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)
  status.resize(100, 100)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')

  check(status.bufStatus[0].buffer[0] == ru"d")

test "Visual mode: Delete buffer 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)
  status.resize(100, 100)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 1 and status.bufStatus[0].buffer[0] == ru"")

test "Visual mode: Delete buffer 3":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ab", ru"cdef"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)
  status.resize(100, 100)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  status.bufStatus[0].keyRight
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 1 and status.bufStatus[0].buffer[0] == ru"ef")

test "Visual mode: Delete buffer 4":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"defg"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.bufStatus[0].keyRight
  status.update

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  status.bufStatus[0].keyRight
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 2 and status.bufStatus[0].buffer[0] == ru"a" and status.bufStatus[0].buffer[1] == ru"g")

test "Visual mode: Delete buffer 5":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.bufStatus[0].keyRight
  status.update

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 2 and status.bufStatus[0].buffer[0] == ru"a" and status.bufStatus[0].buffer[1] == ru"i")
