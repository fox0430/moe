import unittest, osproc
import moepkg/[editorstatus, gapbuffer, unicodetext, highlight, movement, bufferstatus]
include moepkg/[visualmode]

suite "Visual mode: Delete buffer":
  test "Delete buffer 1":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abcd"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

      status.bufStatus[0].selectArea.updateSelectArea(
        status.workSpace[0].currentMainWindowNode.currentLine,
        status.workSpace[0].currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check(status.bufStatus[0].buffer[0] == ru"d")

  test "Delete buffer 2":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

      status.bufStatus[0].selectArea.updateSelectArea(
        status.workSpace[0].currentMainWindowNode.currentLine,
        status.workSpace[0].currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check(status.bufStatus[0].buffer.len == 1)
    check(status.bufStatus[0].buffer[0] == ru"")

  test "Delete buffer 3":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"ab", ru"cdef"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check(status.bufStatus[0].buffer.len == 1)
    check(status.bufStatus[0].buffer[0] == ru"ef")

  test "Delete buffer 4":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"defg"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check(status.bufStatus[0].buffer.len == 2)
    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"g")

  test "Delete buffer 5":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

      status.bufStatus[0].selectArea.updateSelectArea(
        status.workSpace[0].currentMainWindowNode.currentLine,
        status.workSpace[0].currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check(status.bufStatus[0].buffer.len == 2)
    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"i")

  test "Fix #890":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"", ru"a"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.update

    status.changeMode(Mode.visual)
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(status.bufStatus[0].selectArea, ru'x')

    check status.bufStatus[0].buffer.len == 2
    check status.bufStatus[0].buffer[0] == ru"a"
    check status.bufStatus[0].buffer[1] == ru"a"


test "Visual mode: Yank buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[currentBufferIndex].yankBuffer(status.registers,
                                                  status.workSpace[0].currentMainWindowNode,
                                                  area,
                                                  status.platform,
                                                  clipboard)

  check(status.registers.yankedStr == ru"abc")

test "Visual mode: Yank buffer (Disable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[currentBufferIndex].yankBuffer(status.registers,
                                                  status.workSpace[0].currentMainWindowNode,
                                                  area,
                                                  status.platform,
                                                  clipboard)

  check(status.registers.yankedLines == @[ru"abc", ru"def"])

test "Visual block mode: Yank buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[currentBufferIndex].yankBufferBlock(status.registers,
                                                       status.workSpace[0].currentMainWindowNode,
                                                       area,
                                                       status.platform,
                                                       clipboard)

  check(status.registers.yankedLines == @[ru"a", ru"d"])

test "Visual block mode: Yank buffer (Disable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[currentBufferIndex].yankBufferBlock(status.registers,
                                                       status.workSpace[0].currentMainWindowNode,
                                                       area,
                                                       status.platform,
                                                       clipboard)

  check(status.registers.yankedLines == @[ru"a", ru"d"])

test "Visual block mode: Delete buffer (Disable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = false
  status.bufStatus[currentBufferIndex].deleteBufferBlock(status.registers,
                                                         status.workSpace[0].currentMainWindowNode,
                                                         area,
                                                         status.platform,
                                                         clipboard)

  check(status.bufStatus[0].buffer[0] == ru"bc")
  check(status.bufStatus[0].buffer[1] == ru"ef")

test "Visual mode: Yank buffer (Enable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[currentBufferIndex].yankBuffer(
    status.registers,
    status.workSpace[0].currentMainWindowNode,
    area,
    status.platform,
    clipboard)

  if (status.platform == editorstatus.Platform.linux or
      status.platform == editorstatus.Platform.wsl):
    let
      cmd = if status.platform == editorstatus.Platform.linux:
              execCmdEx("xclip -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
      (output, exitCode) = cmd

    check exitCode == 0
    if status.platform == editorstatus.Platform.linux:
      check output[0 .. output.high - 1] == "abc"
    else:
      # On the WSL
      check output[0 .. output.high - 2] == "abc"

test "Visual mode: Yank buffer (Enable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[currentBufferIndex].yankBuffer(
    status.registers,
    status.workSpace[0].currentMainWindowNode,
    area,
    status.platform,
    clipboard)

  if (status.platform == editorstatus.Platform.linux or
      status.platform == editorstatus.Platform.wsl):
    let
      cmd = if status.platform == editorstatus.Platform.linux:
              execCmdEx("xclip -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
      (output, exitCode) = cmd

    check exitCode == 0
    if status.platform == editorstatus.Platform.linux:
      check output[0 .. output.high - 1] == "abc\ndef"
    else:
      # On the WSL
      check output[0 .. output.high - 2] == "abc\ndef"

test "Visual block mode: Yank buffer (Enable clipboard) 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[currentBufferIndex].yankBufferBlock(
    status.registers,
    status.workSpace[0].currentMainWindowNode,
    area,
    status.platform,
    clipboard)

  if status.platform == editorstatus.Platform.linux:
    let
      cmd = execCmdEx("xclip -o")
      (output, exitCode) = cmd

    check exitCode == 0
    check output[0 .. output.high - 1] == "a\nd"

test "Visual block mode: Yank buffer (Enable clipboard) 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn)

    status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn)

  status.update

  let
    area = status.bufStatus[0].selectArea
    clipboard = true
  status.bufStatus[currentBufferIndex].yankBufferBlock(
    status.registers,
    status.workSpace[0].currentMainWindowNode,
    area,
    status.platform,
    clipboard)

  if status.platform == editorstatus.Platform.linux:
    let
      cmd = execCmdEx("xclip -o")
      (output, exitCode) = cmd

    check exitCode == 0
    check output[0 .. output.high - 1] == "a\nd"

suite "Visual block mode: Delete buffer":
  test "Delete buffer (Enable clipboard) 1":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    let
      area = status.bufStatus[0].selectArea
      clipboard = true
    status.bufStatus[currentBufferIndex].deleteBufferBlock(status.registers,
                                                           status.workSpace[0].currentMainWindowNode,
                                                           area,
                                                           status.platform,
                                                           clipboard)

    if status.platform == editorstatus.Platform.linux:
      let (output, exitCode) = execCmdEx("xclip -o")
      check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

  test "Delete buffer (Enable clipboard) 2":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"", ru"edf"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

      status.bufStatus[0].selectArea.updateSelectArea(
        status.workSpace[0].currentMainWindowNode.currentLine,
        status.workSpace[0].currentMainWindowNode.currentColumn)

      status.update

    let
      area = status.bufStatus[0].selectArea
      clipboard = true
    status.bufStatus[currentBufferIndex].deleteBufferBlock(status.registers,
                                                           status.workSpace[0].currentMainWindowNode,
                                                           area,
                                                           status.platform,
                                                           clipboard)

  test "Fix #885":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"de", ru"fgh"])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.highlightSettings.reservedWords,
      status.bufStatus[0].language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[0].selectArea = initSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
    for i in 0 ..< 2:
      status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

    let
      area = status.bufStatus[0].selectArea
      clipboard = false
    status.bufStatus[0].deleteBufferBlock(status.registers,
      status.workSpace[0].currentMainWindowNode,
      area,
      status.platform,
      clipboard)

    check status.bufStatus[0].buffer[0] == ru"c"
    check status.bufStatus[0].buffer[1] == ru""
    check status.bufStatus[0].buffer[2] == ru"h"

test "Visual mode: Join lines":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  let area = status.bufStatus[0].selectArea

  status.update
  status.bufStatus[currentBufferIndex].joinLines(status.workSpace[0].currentMainWindowNode,
                                                 area)

  check(status.bufStatus[currentBufferIndex].buffer.len == 1)
  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"abcdefghi")

test "Visual block mode: Join lines":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  let area = status.bufStatus[0].selectArea

  status.update
  status.bufStatus[currentBufferIndex].joinLines(status.workSpace[0].currentMainWindowNode,
                                                 area)

  check(status.bufStatus[currentBufferIndex].buffer.len == 1)
  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"abcdefghi")

test "Visual mode: Add indent":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'>')

  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"  abc")
  check(status.bufStatus[currentBufferIndex].buffer[1] == ru"  def")
  check(status.bufStatus[currentBufferIndex].buffer[2] == ru"  ghi")

test "Visual block mode: Add indent":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualblock)

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)
    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'>')

  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"  abc")
  check(status.bufStatus[currentBufferIndex].buffer[1] == ru"  def")
  check(status.bufStatus[currentBufferIndex].buffer[2] == ru"  ghi")

test "Visual mode: Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'<')

  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"abc")
  check(status.bufStatus[currentBufferIndex].buffer[1] == ru"def")
  check(status.bufStatus[currentBufferIndex].buffer[2] == ru"ghi")

test "Visual block mode: Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualblock)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'<')

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  check(status.bufStatus[currentBufferIndex].buffer[0] == ru"abc")
  check(status.bufStatus[currentBufferIndex].buffer[1] == ru"def")
  check(status.bufStatus[currentBufferIndex].buffer[2] == ru"ghi")

test "Visual mode: Converts string into lower-case string":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ABC"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)
    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"abc")

test "Visual mode: Converts string into lower-case string 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"AあbC"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 3:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)
    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"aあbc")

test "Visual mode: Converts string into lower-case string 3":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"abc")
  check(status.bufStatus[0].buffer[1] == ru"dEF")

# Fix #687
test "Visual mode: Converts string into lower-case string 4":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ABC", ru"", ru"DEF", ru""])
  status.workSpace[0].currentMainWindowNode.highlight = initHighlight($status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.workSpace[0].currentMainWindowNode.currentLine,
                                                  status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 3:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
    status.update
    status.bufStatus[0].selectArea.updateSelectArea(status.workSpace[0].currentMainWindowNode.currentLine,
                                                    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.visualCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"abc")
  check(status.bufStatus[0].buffer[1] == ru"")
  check(status.bufStatus[0].buffer[2] == ru"def")

test "Visual block mode: Converts string into lower-case string":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ABC"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"abc")

test "Visual block mode: Converts string into lower-case string 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'u')

  check(status.bufStatus[0].buffer[0] == ru"abC")
  check(status.bufStatus[0].buffer[1] == ru"deF")

test "Visual mode: Converts string into upper-case string":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"ABC")

test "Visual mode: Converts string into upper-case string 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"aあBc"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 3:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"AあBC")

test "Visual mode: Converts string into upper-case string 3":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)

  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.update

  status.visualCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"ABC")
  check(status.bufStatus[0].buffer[1] == ru"Def")

# Fix #687
test "Visual mode: Converts string into upper-case string 4":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru""])
  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visual)
  status.bufStatus[0].selectArea = initSelectArea(status.workSpace[0].currentMainWindowNode.currentLine,
                                                  status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 3:
    status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
    status.update
    status.bufStatus[0].selectArea.updateSelectArea(status.workSpace[0].currentMainWindowNode.currentLine,
                                                    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.visualCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"ABC")
  check(status.bufStatus[0].buffer[1] == ru"")
  check(status.bufStatus[0].buffer[2] == ru"DEF")


test "Visual block mode: Converts string into upper-case string":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)

  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  for i in 0 ..< 2:
    status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)

    status.bufStatus[0].selectArea.updateSelectArea(
      status.workSpace[0].currentMainWindowNode.currentLine,
      status.workSpace[0].currentMainWindowNode.currentColumn)

    status.update

  status.update
  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"ABC")

test "Visual block mode: Converts string into upper-case string 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
    $status.bufStatus[0].buffer,
    status.settings.highlightSettings.reservedWords,
    status.bufStatus[0].language)

  status.resize(100, 100)

  status.changeMode(Mode.visualBlock)
  status.bufStatus[0].selectArea = initSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)

  status.bufStatus[0].keyRight(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)
  status.update

  status.bufStatus[0].keyDown(status.workSpace[0].currentMainWindowNode)
  status.bufStatus[0].selectArea.updateSelectArea(
    status.workSpace[0].currentMainWindowNode.currentLine,
    status.workSpace[0].currentMainWindowNode.currentColumn)
  status.update

  status.visualBlockCommand(status.bufStatus[0].selectArea, ru'U')

  check(status.bufStatus[0].buffer[0] == ru"ABc")
  check(status.bufStatus[0].buffer[1] == ru"DEf")
