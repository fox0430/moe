#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, options, os, importutils, sequtils, oids, tables]
import pkg/results
import moepkg/lsp/protocol/enums
import moepkg/[editor, gapbuffer, bufferstatus, editorview, unicodeext, ui,
               highlight, windownode, movement, build, backgroundprocess,
               syntaxcheck, independentutils, tabline, settings, visualmode]

import moepkg/editorstatus {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

proc initSelectedArea(status: EditorStatus) =
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)
    .some

suite "addNewBufferInCurrentWin":
  test "Empty buffer":
    # Create a file for the test.
    let path = $genOid()
    writeFile(path, "hello")

    var status = initEditorStatus()
    let r = status.addNewBufferInCurrentWin

    if fileExists(path): removeFile(path)

    check r.isOk
    check status.bufStatus.len == 1
    check currentBufStatus.path == ru""
    check currentBufStatus.buffer.toSeqRunes == @[ru""]

    check mainWindowNode.getAllWindowNode.len == 1

  test "Open a new":
    # Create a file for the test.
    let path = $genOid()
    writeFile(path, "hello")

    var status = initEditorStatus()
    let r = status.addNewBufferInCurrentWin(path)

    if fileExists(path): removeFile(path)

    check r.isOk
    check status.bufStatus.len == 1
    check currentBufStatus.path == path.toRunes
    check currentBufStatus.buffer.toSeqRunes == @[ru"hello"]

    check mainWindowNode.getAllWindowNode.len == 1

  test "Open a dir":
    const Path = "./"
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Path).get

    check status.bufStatus.len == 1
    check currentBufStatus.path == ru"./"
    check currentBufStatus.buffer.len > 0

    check mainWindowNode.getAllWindowNode.len == 1

  test "Open an unreadable file":
    # Create an unreadable file for the test.
    let path = $genOid()
    writeFile(path, "hello")
    const Permissions = {fpUserWrite}
    setFilePermissions(path, Permissions)

    var status = initEditorStatus()
    let r = status.addNewBufferInCurrentWin(path)

    if fileExists(path): removeFile(path)

    check r.isErr

  test "Open an unreadable dir":
    # Create an unreadable dir for the test.
    let path = $genOid()
    createDir(path)
    const Permissions = {fpUserWrite}
    setFilePermissions(path, Permissions)

    var status = initEditorStatus()
    let r = status.addNewBufferInCurrentWin(path, Mode.filer)

    if dirExists(path): removeDir(path)

    check r.isErr

suite "Open new buffers in the current window":
  test "Open 2 buffers":
    var status = initEditorStatus()
    status.settings.view.sidebar = false

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    block:
      check status.bufStatus.len == 1

      check mainWindowNode.getAllWindowNode.len == 1
      check currentMainWindowNode.view.sidebar.isNone

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    block:
      check status.bufStatus.len == 2

      check mainWindowNode.getAllWindowNode.len == 1
      check currentMainWindowNode.view.sidebar.isNone

  test "Add 2 buffers with Sidebar":
    var status = initEditorStatus()
    status.settings.view.sidebar = true

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    block:
      check status.bufStatus.len == 1

      check mainWindowNode.getAllWindowNode.len == 1
      check currentMainWindowNode.view.sidebar.isSome

    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    status.update

    block:
      check status.bufStatus.len == 2

      check mainWindowNode.getAllWindowNode.len == 1
      check currentMainWindowNode.view.sidebar.isSome

  test "Add new buffer (Dir)":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin("./").get

    status.resize(100, 100)
    status.update

test "Add new buffer and update editor view when disabling current line highlighting (Fix #1189)":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.settings.view.highlightCurrentLine = false

  status.resize(100, 100)
  status.update

test "Vertical split window":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.resize(100, 100)
  status.verticalSplitWindow

test "Horizontal split window":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.resize(100, 100)
  status.horizontalSplitWindow

test "resize 1":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.resize(100, 100)
  currentBufStatus.buffer = initGapBuffer(@[ru"a"])

  currentMainWindowNode.highlight =
    initHighlight(currentBufStatus.buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    currentBufStatus.language)

  currentMainWindowNode.view =
    initEditorView(currentBufStatus.buffer, 1, 1)

  status.resize(0, 0)

test "resize 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.resize(100, 100)
  currentBufStatus.buffer = initGapBuffer(@[ru"a"])

  currentMainWindowNode.highlight =
    initHighlight(currentBufStatus.buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    currentBufStatus.language)

  currentMainWindowNode.view =
    initEditorView(currentBufStatus.buffer, 20, 4)

  status.resize(20, 4)

  currentMainWindowNode.currentColumn = 1
  status.changeMode(Mode.insert)

  for i in 0 ..< 10:
    currentBufStatus.keyEnter(
      currentMainWindowNode,
      status.settings.standard.autoCloseParen,
      status.settings.standard.tabStop)
    status.update

test "Auto delete paren 1":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")

test "Auto delete paren 2":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

    for i in 0 ..< 2:
     currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
    for i in 0 ..< 3:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

test "Auto delete paren 3":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get

    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])

    for i in 0 ..< 3:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

test "Auto delete paren 4":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")
    check(currentBufStatus.buffer[1] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])
    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.standard.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")
    check(currentBufStatus.buffer[1] == ru"")

test "Auto delete paren 5":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    currentBufStatus.keyRight(currentMainWindowNode)
    currentBufStatus.keyBackspace(
      currentMainWindowNode,
      status.settings.standard.autoDeleteParen,
      status.settings.standard.tabStop)

    check(currentBufStatus.buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
    currentBufStatus.keyBackspace(
      currentMainWindowNode,
      status.settings.standard.autoDeleteParen,
      status.settings.standard.tabStop)

    check(currentBufStatus.buffer[0] == ru"")

test "Auto delete paren 6":
  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

    status.changeMode(Mode.insert)

    for i in 0 ..< 5:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.keyBackspace(
      currentMainWindowNode,
      status.settings.standard.autoDeleteParen,
      status.settings.standard.tabStop)

    check(currentBufStatus.buffer[0] == ru"(aa)")

  block:
    var status = initEditorStatus()
    status.settings.standard.autoDeleteParen = true

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

    status.changeMode(Mode.insert)

    for i in 0 ..< 6:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.keyBackspace(
      currentMainWindowNode,
      status.settings.standard.autoDeleteParen,
      status.settings.standard.tabStop)

    check(currentBufStatus.buffer[0] == ru"a(a)")

test "Write tab line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin("test.txt").get

  status.resize(100, 100)

  privateAccess(TabLine)
  check status.tabLine.size.w == 100

test "Close window":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.resize(100, 100)
  status.verticalSplitWindow
  status.closeWindow(currentMainWindowNode)

test "Close window 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get

  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 1)

  check(currentMainWindowNode.h == 98)
  check(currentMainWindowNode.w == 100)

test "Close window 3":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get

  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 2)

  for n in windowNodeList:
    check(n.w == 50)
    check(n.h == 98)

test "Close window 4":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get

  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 2)

  check(windowNodeList[0].w == 100)
  check(windowNodeList[0].h == 49)

  check(windowNodeList[1].w == 100)
  check(windowNodeList[1].h == 49)

test "Close window 5":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin("test.nim").get

  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.moveCurrentMainWindow(1)
  discard status.addNewBufferInCurrentWin("test2.nim").get
  status.changeCurrentBuffer(1)
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode)
  status.resize(100, 100)
  status.update

  check(currentMainWindowNode.bufferIndex == 0)

# Fix #611
test "Change current buffer":
  var status = initEditorStatus()

  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.path = ru"test"
  currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

  status.resize(100, 100)
  status.update

  let
    currentLine = currentBufStatus.buffer.high
    currentColumn = currentBufStatus.buffer[currentLine].high
  currentMainWindowNode.currentLine = currentLine
  currentMainWindowNode.currentColumn = currentColumn

  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.path = ru"test2"
  currentBufStatus.buffer =  initGapBuffer(@[ru""])

  status.changeCurrentBuffer(1)

  status.resize(100, 100)
  status.update

suite "editorstatus: Updates/Restore the last cursor postion":
  test "Update the last cursor position (3 lines)":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.updateLastCursorPostion

    privateAccess(status.lastPosition[0].type)

    check status.lastPosition[0].path == absolutePath("test.nim").ru
    check status.lastPosition[0].line == 1
    check status.lastPosition[0].column == 1

  test "Update and restore the last cursor position (3 lines and edit the buffer after save)":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    status.updateLastCursorPostion

    # Edit buffer after update the last cursor position
    currentBufStatus.buffer[1] = ru ""

    currentMainWindowNode.restoreCursorPostion(currentBufStatus,
                                               status.lastPosition)
    status.update

    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

  test "Update and restore the last cursor position (3 lines and last line is empty)":
    var status = initEditorStatus()

    discard status.addNewBufferInCurrentWin("test.nim").get

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru ""])

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    status.update

    status.updateLastCursorPostion

    currentMainWindowNode.restoreCursorPostion(
      currentBufStatus,
      status.lastPosition)

    status.update

    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 0

suite "Fix #1361":
  test "Insert a character after split window":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru ""])

    status.resize(100, 100)
    status.update

    status.verticalSplitWindow

    const Key = ru 'a'
    currentBufStatus.insertCharacter(
      currentMainWindowNode,
      status.settings.standard.autoCloseParen,
      Key)

    status.update

    let nodes = mainWindowNode.getAllWindowNode
    check nodes[0].highlight == nodes[1].highlight

suite "BackgroundTasks":
  const
    TestDir = "./backgroundTasksTest"
    TestFilePath = TestDir / "test.nim"
    Buffer = "echo 1"

  setup:
    createDir(TestDir)
    writeFile(TestFilePath, Buffer)

  teardown:
    removeDir(TestDir)

  test "checkBackgroundBuild 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[Buffer.toRunes])

    status.backgroundTasks.build.add startBackgroundBuild(
      TestFilePath.toRunes,
      currentBufStatus.language).get

    for i in 0 .. 10:
      sleep 1000

      status.checkBackgroundBuild
      if status.backgroundTasks.build.len == 0:
        break

    if status.backgroundTasks.build.len > 0:
      status.backgroundTasks.build[0].process.kill
      check false

  test "checkBackgroundBuild 2":
    ## Exec background builds twice.

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[Buffer.toRunes])

    for i in 0 .. 1:
      status.backgroundTasks.build.add startBackgroundBuild(
        TestFilePath.toRunes,
        currentBufStatus.language).get

    for i in 0 .. 10:
      sleep 1000

      status.checkBackgroundBuild
      if status.backgroundTasks.build.len == 0:
        break

    if status.backgroundTasks.build.len > 0:
      for i in 0 ..< status.backgroundTasks.build.len:
        status.backgroundTasks.build[i].process.kill

      check false

suite "updateCommandLine":
  test "Write syntax checker messages":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["import std/os", "echo 1"]
      .toSeqRunes
      .toGapBuffer

    let syntaxError = SyntaxError(
      position: BufferPosition(line: 0, column: 11),
      messageType: SyntaxCheckMessageType.warning,
      message: ru"imported and not used: 'os' [UnusedImport]")

    currentBufStatus.syntaxCheckResults = @[syntaxError]

    status.resize(100, 100)
    status.update

    check status.commandLine.buffer ==
      ru"SyntaxError: (0, 11) imported and not used: 'os' [UnusedImport]"

  test "Write syntax checker messages and move line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["import std/os", "echo 1"]
      .toSeqRunes
      .toGapBuffer

    let syntaxError = SyntaxError(
      position: BufferPosition(line: 0, column: 11),
      messageType: SyntaxCheckMessageType.warning,
      message: ru"imported and not used: 'os' [UnusedImport]")

    currentBufStatus.syntaxCheckResults = @[syntaxError]

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentLine = 1
    status.update

    # Should be empty for other lines.
    check status.commandLine.buffer.len == 0

suite "updateSelectedArea: Visual mode":
  test "Move to right":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 0, endColumn: 1)

  test "Move to below":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 1, endColumn: 0)

suite "updateSelectedArea: Visual block mode":
  test "Move to right":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 0, endColumn: 1)

  test "Move to below":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visualblock)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 1, endColumn: 0)

suite "updateSelectedArea: Visual line mode":
  test "Move to right":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visualLine)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 0, endColumn: 2)

  test "Move to below":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    status.changeMode(Mode.visualLine)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    check currentBufStatus.selectedArea.get ==
      SelectedArea(startLine: 0, startColumn: 0, endLine: 1, endColumn: 2)

suite "editorstatus: smoothScrollDelays":
  test "totalLines: 20, minDelay 5, maxDelay 20":
    const
      TotalLines = 20
      MinDelay = 5
      MaxDelay = 20

    check smoothScrollDelays(TotalLines, MinDelay, MaxDelay) == @[
      13, 10, 8, 7, 6, 6, 6, 7, 8, 10, 13, 16, 20, 25, 30, 36, 42, 49, 56, 64]

  test "totalLines: 0, minDelay 5, maxDelay 20":
    const
      TotalLines = 0
      MinDelay = 5
      MaxDelay = 20

    check smoothScrollDelays(TotalLines, MinDelay, MaxDelay).len == 0

suite "editorstatus: scrollUpNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..30).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 30

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollUpNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 10

  test "numberOfLines: 20 and buffer.len: 10":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..10).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 10

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollUpNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 0

suite "editorstatus: scrollDownNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..30).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollDownNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 20

  test "numberOfLines: 20 and buffer.len: 10":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..10).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollDownNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 10

suite "editorstatus: smoothScrollUpNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..30).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 30

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollUpNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 10

  test "numberOfLines: 20; buffer.len: 10":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..10).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 10

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollUpNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 0

suite "editorstatus: smoothScrollDownNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..30).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollDownNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 20

  test "numberOfLines: 20; buffer.len: 10":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0..10).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollDownNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 10

suite "editorstatus: initLsp":
  test "Init wtih nimlsp":
    let path = $genOid() & ".nim"
    var status = initEditorStatus()

    status.settings.lsp.enable = true
    status.settings.lsp.languages["nim"] = LspLanguageSettings(
      extensions: @[ru"nim"],
      command: ru"nimlsp",
      trace: TraceValue.verbose)

    status.bufStatus.add initBufferStatus(path, Mode.normal).get

    let workspaceRoot = getCurrentDir()
    const LanguageId = "nim"
    check status.lspInitialize(workspaceRoot, LanguageId).isOk
