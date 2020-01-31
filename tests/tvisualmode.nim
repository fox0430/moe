import unittest
import moepkg/editorstatus, moepkg/gapbuffer, moepkg/normalmode, moepkg/unicodeext, moepkg/highlight, moepkg/visualmode

proc updateVisualModeStat(status: var EditorStatus, colorSegment: var ColorSegment) =
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  colorSegment.updateColorSegment(status.bufStatus[0].selectArea)
  
  status.updatehighlight
  status.bufStatus[0].highlight = status.bufStatus[0].highlight.overwrite(colorSegment)

test "Visual mode: Delete buffer 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abcd"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)

  var colorSegment = initColorSegment(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[0].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight

    status.updateVisualModeStat(colorSegment)

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')

  check(status.bufStatus[0].buffer[0] == ru"d")

test "Visual mode: Delete buffer 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)

  var colorSegment = initColorSegment(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[0].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown

    status.updateVisualModeStat(colorSegment)

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 1 and status.bufStatus[0].buffer[0] == ru"")

test "Visual mode: Delete buffer 3":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ab", ru"cdef"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.changeMode(Mode.visual)

  var colorSegment = initColorSegment(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[0].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.updateVisualModeStat(colorSegment)

  status.bufStatus[0].keyRight
  status.updateVisualModeStat(colorSegment)

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 1 and status.bufStatus[0].buffer[0] == ru"ef")

test "Visual mode: Delete buffer 4":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"defg"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  status.bufStatus[0].keyRight

  status.changeMode(Mode.visual)

  var colorSegment = initColorSegment(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[0].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.updateVisualModeStat(colorSegment)

  status.bufStatus[0].keyRight
  status.updateVisualModeStat(colorSegment)

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 2 and status.bufStatus[0].buffer[0] == ru"a" and status.bufStatus[0].buffer[1] == ru"g")

test "Visual mode: Delete buffer 5":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)

  status.bufStatus[0].keyRight

  status.changeMode(Mode.visual)

  var colorSegment = initColorSegment(status.bufStatus[0].currentLine, status.bufStatus[0].currentColumn)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[0].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.updateVisualModeStat(colorSegment)

  status.visualCommand(status.bufStatus[0].selectArea, ru'x')
  check(status.bufStatus[0].buffer.len == 2 and status.bufStatus[0].buffer[0] == ru"a" and status.bufStatus[0].buffer[1] == ru"i")
