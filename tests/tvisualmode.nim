import unittest, osproc
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

test "Visual mode: Yank buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[status.currentBuffer].yankBuffer(status.registers, area, status.platform, clipboard)

  check(status.registers.yankedStr == ru"abc")

test "Visual mode: Yank buffer (Disable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[status.currentBuffer].yankBuffer(status.registers, area, status.platform, clipboard)

  check(status.registers.yankedLines == @[ru"abc", ru"def"])

test "Visual block mode: Yank buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[status.currentBuffer].yankBufferBlock(status.registers, area, status.platform, clipboard)

  check(status.registers.yankedLines == @[ru"a", ru"d"])

test "Visual block mode: Yank buffer (Disable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[status.currentBuffer].yankBufferBlock(status.registers, area, status.platform, clipboard)

  check(status.registers.yankedLines == @[ru"a", ru"d"])

test "Visual block mode: Delete buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[status.currentBuffer].deleteBufferBlock(status.registers, area, status.platform, clipboard)

  check(status.bufStatus[0].buffer[0] == ru"bc")
  check(status.bufStatus[0].buffer[1] == ru"ef")

test "Visual mode: Yank buffer (Enable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[status.currentBuffer].yankBuffer(status.registers, area, status.platform, clipboard)

  let (output, exitCode) = execCmdEx("xclip -o")
  check(exitCode == 0 and output[0 .. output.high - 1] == "abc")

test "Visual mode: Yank buffer (Enable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[status.currentBuffer].yankBuffer(status.registers, area, status.platform, clipboard)

  let (output, exitCode) = execCmdEx("xclip -o")
  check(exitCode == 0 and output[0 .. output.high - 1] == "abc\ndef")

test "Visual block mode: Yank buffer (Enable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[status.currentBuffer].yankBufferBlock(status.registers, area, status.platform, clipboard)

  let (output, exitCode) = execCmdEx("xclip -o")
  check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

test "Visual block mode: Yank buffer (Enable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[status.currentBuffer].yankBufferBlock(status.registers, area, status.platform, clipboard)

  let (output, exitCode) = execCmdEx("xclip -o")
  check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

test "Visual block mode: Delete buffer (Enable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[0].keyDown
  status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[status.currentBuffer].deleteBufferBlock(status.registers, area, status.platform, clipboard)

  let (output, exitCode) = execCmdEx("xclip -o")
  check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

test "Visual mode: Join lines":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  let area = status.bufStatus[0].selectArea

  status.update
  status.bufStatus[status.currentBuffer].joinLines(status.currentMainWindowNode, area)

  check(status.bufStatus[status.currentBuffer].buffer.len == 1 and status.bufStatus[status.currentBuffer].buffer[0] == ru"abcdefghi")

test "Visual block mode: Join lines":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  let area = status.bufStatus[0].selectArea

  status.update
  status.bufStatus[status.currentBuffer].joinLines(status.currentMainWindowNode, area)

  check(status.bufStatus[status.currentBuffer].buffer.len == 1 and status.bufStatus[status.currentBuffer].buffer[0] == ru"abcdefghi")

test "Visual mode: Add indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'>')

  check(status.bufStatus[status.currentBuffer].buffer[0] == ru"  abc")
  check(status.bufStatus[status.currentBuffer].buffer[1] == ru"  def")
  check(status.bufStatus[status.currentBuffer].buffer[2] == ru"  ghi")

test "Visual block mode: Add indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualblock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'>')

  check(status.bufStatus[status.currentBuffer].buffer[0] == ru"  abc")
  check(status.bufStatus[status.currentBuffer].buffer[1] == ru"  def")
  check(status.bufStatus[status.currentBuffer].buffer[2] == ru"  ghi")

test "Visual mode: Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'<')

  check(status.bufStatus[status.currentBuffer].buffer[0] == ru"abc")
  check(status.bufStatus[status.currentBuffer].buffer[1] == ru"def")
  check(status.bufStatus[status.currentBuffer].buffer[2] == ru"ghi")

test "Visual block mode: Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(100, 100)

  status.changeMode(Mode.visualblock)
  status.bufStatus[0].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown
    status.bufStatus[0].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'<')

  check(status.bufStatus[status.currentBuffer].buffer[0] == ru"abc")
  check(status.bufStatus[status.currentBuffer].buffer[1] == ru"def")
  check(status.bufStatus[status.currentBuffer].buffer[2] == ru"ghi")
