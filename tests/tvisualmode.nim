import std/[unittest, osproc]
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, movement, bufferstatus,
               register]
include moepkg/[visualmode, platform, independentutils]

proc isXselAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0 and execCmdExNoOutput("xsel --version") == 0

suite "Visual mode: Delete buffer":
  test "Delete buffer 1":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abcd"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check(currentBufStatus.buffer[0] == ru"d")

  test "Delete buffer 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"")

  test "Delete buffer 3":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ab", ru"cdef"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"ef")

  test "Delete buffer 4":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"defg"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"g")

  test "Delete buffer 5":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"i")

  test "Fix #890":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"a"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyDown(currentMainWindowNode)

    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"a"
    check currentBufStatus.buffer[1] == ru"a"

  test "Visual mode: Check cursor position after delete buffer":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"a b c"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentMainWindowNode.currentColumn = 2

    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check currentBufStatus.buffer[0] == ru"a  c"
    check currentMainWindowNode.currentColumn == 2

suite "Visual mode: Yank buffer (Disable clipboard)":
  test "Yank lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(status.registers,
                                currentMainWindowNode,
                                area,
                                status.settings)

    check status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer == @[ru"abc", ru"def"]

  test "Yank string (Fix #1124)":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(status.registers,
                                currentMainWindowNode,
                                area,
                                status.settings)

    check not status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer[^1] == ru"abc"

  test "Yank lines when the last line is empty (Fix #1183)":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru""])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(status.registers,
                                currentMainWindowNode,
                                area,
                                status.settings)

    check status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer == @[ru"abc", ru""]

  test "Yank the empty line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(status.registers,
                                currentMainWindowNode,
                                area,
                                status.settings)

    check status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer == @[ru""]

suite "Visual block mode: Yank buffer (Disable clipboard)":
  test "Yank lines 1":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBufferBlock(status.registers,
                                     currentMainWindowNode,
                                     area,
                                     status.settings)

    check status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer == @[ru"a", ru"d"]

  test "Yank lines 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBufferBlock(status.registers,
                                     currentMainWindowNode,
                                     area,
                                     status.settings)

    check status.registers.noNameRegister.isLine
    check status.registers.noNameRegister.buffer == @[ru"a", ru"d"]

suite "Visual block mode: Delete buffer (Disable clipboard)":
  test "Delete buffer":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    let area = currentBufStatus.selectArea
    status.settings.clipboard.enable = false
    currentBufStatus.deleteBufferBlock(status.registers,
                                       currentMainWindowNode,
                                       area,
                                       status.settings,
                                       status.commandLine)

    check(currentBufStatus.buffer[0] == ru"bc")
    check(currentBufStatus.buffer[1] == ru"ef")

if isXselAvailable():
  suite "Visual mode: Yank buffer (Enable clipboard)":
    test "Yank string":
      var status = initEditorStatus()

      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visual)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBuffer(status.registers,
                                  currentMainWindowNode,
                                  area,
                                  status.settings)

      if (CURRENT_PLATFORM == Platforms.linux or
          CURRENT_PLATFORM == Platforms.wsl):
        let
          cmd = if CURRENT_PLATFORM == Platforms.linux:
                  execCmdEx("xsel -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if CURRENT_PLATFORM == Platforms.linux:
          check output[0 .. output.high - 1] == "abc"
        else:
          # On the WSL
          check output[0 .. output.high - 2] == "abc"

    test "Yank lines":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visual)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBuffer(status.registers,
                                  currentMainWindowNode,
                                  area,
                                  status.settings)

      if (CURRENT_PLATFORM == Platforms.linux or
          CURRENT_PLATFORM == Platforms.wsl):
        let
          cmd = if CURRENT_PLATFORM == Platforms.linux:
                  execCmdEx("xsel -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if CURRENT_PLATFORM == Platforms.linux:
          check output[0 .. output.high - 1] == "abc\ndef"
        else:
          # On the WSL
          check output[0 .. output.high - 2] == "abc\ndef"

if isXselAvailable():
  suite "Visual block mode: Yank buffer (Enable clipboard) 1":
    test "Yank lines 1":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBufferBlock(status.registers,
                                       currentMainWindowNode,
                                       area,
                                       status.settings)

      if CURRENT_PLATFORM == Platforms.linux:
        let
          cmd = execCmdEx("xsel -o")
          (output, exitCode) = cmd

        check exitCode == 0
        check output[0 .. output.high - 1] == "a\nd"

    test "Yank lines 2":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBufferBlock(status.registers,
                                       currentMainWindowNode,
                                       area,
                                       status.settings)

      if CURRENT_PLATFORM == Platforms.linux:
        let
          cmd = execCmdEx("xsel -o")
          (output, exitCode) = cmd

        check exitCode == 0
        check output[0 .. output.high - 1] == "a\nd"

if isXselAvailable():
  suite "Visual block mode: Delete buffer":
    test "Delete buffer (Enable clipboard) 1":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(status.registers,
                                         currentMainWindowNode,
                                         area,
                                         status.settings,
                                         status.commandLine)

      if CURRENT_PLATFORM == Platforms.linux:
        let (output, exitCode) = execCmdEx("xsel -o")
        check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

    test "Delete buffer (Enable clipboard) 2":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"edf"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)

        currentBufStatus.selectArea.updateSelectArea(
          currentMainWindowNode.currentLine,
          currentMainWindowNode.currentColumn)

        status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(status.registers,
                                         currentMainWindowNode,
                                         area,
                                         status.settings,
                                         status.commandLine)

    test "Fix #885":
      var status = initEditorStatus()
      status.addNewBuffer
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"de", ru"fgh"])

      currentMainWindowNode.highlight = initHighlight(
        $currentBufStatus.buffer,
        status.settings.highlightSettings.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectArea = initSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyRight(currentMainWindowNode)
      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

      let area = currentBufStatus.selectArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)

      check currentBufStatus.buffer[0] == ru"c"
      check currentBufStatus.buffer[1] == ru""
      check currentBufStatus.buffer[2] == ru"h"

suite "Visual mode: Join lines":
  test "Join 3 lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    let area = currentBufStatus.selectArea

    status.update
    currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"abcdefghi")

suite "Visual block mode: Join lines":
  test "Join 3 lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    let area = currentBufStatus.selectArea

    status.update
    currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"abcdefghi")

test "Visual mode: Add indent":
  test "Add 1 indent":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'>')

    check(currentBufStatus.buffer[0] == ru"  abc")
    check(currentBufStatus.buffer[1] == ru"  def")
    check(currentBufStatus.buffer[2] == ru"  ghi")

suite "Visual block mode: Add indent":
  test "Add 1 indent":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectArea, ru'>')

    check(currentBufStatus.buffer[0] == ru"  abc")
    check(currentBufStatus.buffer[1] == ru"  def")
    check(currentBufStatus.buffer[2] == ru"  ghi")

suite "Visual mode: Delete indent":
  test "Delete 1 indent":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'<')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"def")
    check(currentBufStatus.buffer[2] == ru"ghi")

suite "Visual block mode: Delete indent":
  test "Delete 1 indent":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectArea, ru'<')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"def")
    check(currentBufStatus.buffer[2] == ru"ghi")

suite "Visual mode: Converts string into lower-case string":
  test "Converts string into lower-case string 1":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"AあbC"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"aあbc")

  test "Converts string into lower-case string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"dEF")

  test "Converts string into lower-case string 4 (Fix #687)":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"", ru"DEF", ru""])
    currentMainWindowNode.highlight = initHighlight($currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"def")

test "Visual block mode: Converts string into lower-case string":
  test "Converts string into lower-case string":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualBlockCommand(currentBufStatus.selectArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abC")
    check(currentBufStatus.buffer[1] == ru"deF")

suite "Visual mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"aあBc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.update
    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"AあBC")

  test "Converts string into upper-case string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"Def")

  test "Visual mode: Converts string into upper-case string 4 (Fix #687)":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru""])
    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update
      currentBufStatus.selectArea.updateSelectArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"DEF")


suite "Visual block mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyRight(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.visualBlockCommand(currentBufStatus.selectArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABc")
    check(currentBufStatus.buffer[1] == ru"DEf")

suite "Visual block mode: Insert buffer":
  test "insert tab (Fix #1186)":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    # Insert buffer
    block:
      status.changeMode(Mode.insert)

      let area = currentBufStatus.selectArea
      currentMainWindowNode.currentLine = area.startLine
      currentMainWindowNode.currentColumn = area.startColumn

      const insertBuffer = ru "\t"

      # Insert buffer to the area.startLine
      for c in insertBuffer:
        insertTab(currentBufStatus,
                  currentMainWindowNode,
                  status.settings.tabStop,
                  status.settings.autoCloseParen)

      currentBufStatus.insertCharBlock(
        currentMainWindowNode,
        insertBuffer,
        area,
        status.settings.tabStop,
        status.settings.autoCloseParen,
        status.commandLine)

    check currentBufStatus.buffer[0] == ru"  abc"
    check currentBufStatus.buffer[1] == ru"  def"

suite "Visual mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'>')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'<')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.selectArea.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'J')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.replaceCharacter(currentBufStatus.selectArea, ru 'z', status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'I')

    check currentBufStatus.mode == Mode.visual

suite "Visual block mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'x')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'I')

    check currentBufStatus.mode == Mode.visualblock

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'>')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'<')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.selectArea.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'J')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'u')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectArea, ru'U')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectArea = initSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.replaceCharacter(currentBufStatus.selectArea, ru 'z', status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"
