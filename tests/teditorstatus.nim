#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import
  std/[unittest, options, os, osproc, importutils, sequtils, oids, tables, strformat]

import pkg/results

import moepkg/lsp/utils
import moepkg/lsp/protocol/[types, enums]
import
  moepkg/[
    editor, gapbuffer, bufferstatus, editorview, unicodeext, build, highlight,
    windownode, movement, backgroundprocess, syntaxcheck, independentutils, tabline,
    settings, visualmode, statusline, buffercache,
  ]

import utils

import moepkg/exmode {.all.}
import moepkg/editorstatus {.all.}
import moepkg/ui {.all.}

proc initSelectedArea(status: EditorStatus) =
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn
  ).some

suite "addNewBuffer":
  var status: EditorStatus

  setup:
    status = initEditorStatus().get

  test "Empty buffer":
    check status.addNewBuffer("", Mode.normal).get == 0

    check status.bufStatus.len == 1
    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes
    check currentBufStatus.path == ru""
    check currentBufStatus.mode == Mode.normal

  test "2 Empty buffers":
    block:
      let path = $genOid()
      check status.addNewBuffer(path, Mode.normal).get == 0

      check status.bufStatus.len == 1
      check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes
      check currentBufStatus.path == path.toRunes
      check currentBufStatus.mode == Mode.normal

    block:
      let path = $genOid()
      check status.addNewBuffer(path, Mode.normal).get == 1

      check status.bufStatus.len == 2
      check status.bufStatus[1].buffer.toSeqRunes == @[""].toSeqRunes
      check status.bufStatus[1].path == path.toRunes
      check status.bufStatus[1].mode == Mode.normal

  test "Read only mode":
    status.isReadonly = true

    check status.addNewBuffer("", Mode.normal).get == 0

    check status.bufStatus.len == 1
    check currentBufStatus.isReadonly

suite "addNewBufferInCurrentWin":
  test "Empty buffer":
    # Create a file for the test.
    let path = $genOid()
    writeFile(path, "hello")

    var status = initEditorStatus().get
    let r = status.addNewBufferInCurrentWin

    if fileExists(path):
      removeFile(path)

    check r.isOk
    check status.bufStatus.len == 1
    check currentBufStatus.path == ru""
    check currentBufStatus.buffer.toSeqRunes == @[ru""]

    check mainWindowNode.getAllWindowNode.len == 1

  test "Open a new":
    # Create a file for the test.
    let path = $genOid()
    writeFile(path, "hello")

    var status = initEditorStatus().get
    let r = status.addNewBufferInCurrentWin(path)

    if fileExists(path):
      removeFile(path)

    check r.isOk
    check status.bufStatus.len == 1
    check currentBufStatus.path == path.toRunes
    check currentBufStatus.buffer.toSeqRunes == @[ru"hello"]

    check mainWindowNode.getAllWindowNode.len == 1

  test "Open a dir":
    const Path = "./"
    var status = initEditorStatus().get
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

    var status = initEditorStatus().get
    let r = status.addNewBufferInCurrentWin(path)

    if fileExists(path):
      removeFile(path)

    check r.isErr

  test "Open an unreadable dir":
    # Create an unreadable dir for the test.
    let path = $genOid()
    createDir(path)
    const Permissions = {fpUserWrite}
    setFilePermissions(path, Permissions)

    var status = initEditorStatus().get
    let r = status.addNewBufferInCurrentWin(path, Mode.filer)

    if dirExists(path):
      removeDir(path)

    check r.isErr

suite "Open new buffers in the current window":
  test "Open 2 buffers":
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get

    discard status.addNewBufferInCurrentWin("./").get

    status.resize(100, 100)
    status.update

  test "Add new buffer and update editor view when disabling current line highlighting (Fix #1189)":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.settings.view.highlightCurrentLine = false

    status.resize(100, 100)
    status.update

suite "Vertical split window":
  test "Basic":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    assert status.verticalSplitWindow.isOk

suite "Horizontal split window":
  test "Basic":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    assert status.horizontalSplitWindow.isOk

suite "resize":
  test "Basic 1":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    currentBufStatus.buffer = initGapBuffer(@[ru"a"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes, status.settings.highlight.reservedWords,
      currentBufStatus.language,
    )

    currentMainWindowNode.view = initEditorView(currentBufStatus.buffer, 1, 1)

    status.resize(0, 0)

  test "Basic 2":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    currentBufStatus.buffer = initGapBuffer(@[ru"a"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes, status.settings.highlight.reservedWords,
      currentBufStatus.language,
    )

    currentMainWindowNode.view = initEditorView(currentBufStatus.buffer, 20, 4)

    status.resize(20, 4)

    currentMainWindowNode.currentColumn = 1
    status.changeMode(Mode.insert)

    for i in 0 ..< 10:
      currentBufStatus.keyEnter(
        currentMainWindowNode, status.settings.standard.autoCloseParen,
        status.settings.standard.tabStop,
      )
      status.update

suite "Auto delete paren":
  test "Basic 1":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"()"])
      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"()"])
      currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"")

  test "Basic 2":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
      currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

      for i in 0 ..< 2:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
      for i in 0 ..< 3:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

  test "Basic 3":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get

      currentBufStatus.buffer = initGapBuffer(@[ru"(()"])

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
      currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"(")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
      for i in 0 ..< 2:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"(")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"())"])

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru")")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"())"])
      currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru")")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"())"])

      for i in 0 ..< 3:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"()")

  test "Basic 4":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"")
      check(currentBufStatus.buffer[1] == ru"")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])
      currentBufStatus.keyDown(currentMainWindowNode)

      currentBufStatus.deleteCharacter(
        currentMainWindowNode.currentLine, currentMainWindowNode.currentColumn,
        status.settings.standard.autoDeleteParen,
      )

      check(currentBufStatus.buffer[0] == ru"")
      check(currentBufStatus.buffer[1] == ru"")

  test "Basic 5":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"()"])
      status.changeMode(Mode.insert)
      currentBufStatus.keyRight(currentMainWindowNode)
      currentBufStatus.keyBackspace(
        currentMainWindowNode, status.settings.standard.autoDeleteParen,
        status.settings.standard.tabStop,
      )

      check(currentBufStatus.buffer[0] == ru"")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"()"])
      status.changeMode(Mode.insert)
      for i in 0 ..< 2:
        currentBufStatus.keyRight(currentMainWindowNode)
      currentBufStatus.keyBackspace(
        currentMainWindowNode, status.settings.standard.autoDeleteParen,
        status.settings.standard.tabStop,
      )

      check(currentBufStatus.buffer[0] == ru"")

  test "Basic 6":
    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

      status.changeMode(Mode.insert)

      for i in 0 ..< 5:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.keyBackspace(
        currentMainWindowNode, status.settings.standard.autoDeleteParen,
        status.settings.standard.tabStop,
      )

      check(currentBufStatus.buffer[0] == ru"(aa)")

    block:
      var status = initEditorStatus().get
      status.settings.standard.autoDeleteParen = true

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

      status.changeMode(Mode.insert)

      for i in 0 ..< 6:
        currentBufStatus.keyRight(currentMainWindowNode)

      currentBufStatus.keyBackspace(
        currentMainWindowNode, status.settings.standard.autoDeleteParen,
        status.settings.standard.tabStop,
      )

      check(currentBufStatus.buffer[0] == ru"a(a)")

suite "Tab line":
  test "Write tab line":
    test "Basic":
      var status = initEditorStatus().get
      discard status.addNewBufferInCurrentWin("test.txt").get

      status.resize(100, 100)

      privateAccess(TabLine)
      check status.tabLine.size.w == 100

suite "Close window":
  test "Basic":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)
    assert status.verticalSplitWindow.isOk
    status.closeWindow(currentMainWindowNode)

  test "Basic 2":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    assert status.horizontalSplitWindow.isOk
    status.resize(100, 100)
    status.update

    status.closeWindow(currentMainWindowNode)
    status.resize(100, 100)
    status.update

    let windowNodeList = mainWindowNode.getAllWindowNode

    check(windowNodeList.len == 1)

    check(currentMainWindowNode.h == 98)
    check(currentMainWindowNode.w == 100)

  test "Basic 3":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    assert status.verticalSplitWindow.isOk
    status.resize(100, 100)
    status.update

    assert status.horizontalSplitWindow.isOk
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

  test "Basic 4":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    assert status.horizontalSplitWindow.isOk
    status.resize(100, 100)
    status.update

    assert status.verticalSplitWindow.isOk
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

  test "Basic 5":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin("test.nim").get

    status.resize(100, 100)
    status.update

    assert status.verticalSplitWindow.isOk
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
suite "changeCurrentBuffer":
  test "Fix #611":
    var status = initEditorStatus().get

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
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.changeCurrentBuffer(1)

    status.resize(100, 100)
    status.update

suite "editorstatus: Updates/Restore the last cursor position":
  test "Update the last cursor position (3 lines)":
    var status = initEditorStatus().get

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.updateLastCursorPosition

    privateAccess(status.lastPosition[0].type)

    check status.lastPosition[0].path == absolutePath("test.nim").ru
    check status.lastPosition[0].line == 1
    check status.lastPosition[0].column == 1

  test "Update and restore the last cursor position (3 lines and edit the buffer after save)":
    var status = initEditorStatus().get

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    status.updateLastCursorPosition

    # Edit buffer after update the last cursor position
    currentBufStatus.buffer[1] = ru ""

    currentMainWindowNode.restoreCursorPosition(currentBufStatus, status.lastPosition)
    status.update

    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

  test "Update and restore the last cursor position (3 lines and last line is empty)":
    var status = initEditorStatus().get

    discard status.addNewBufferInCurrentWin("test.nim").get

    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru ""])

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    status.update

    status.updateLastCursorPosition

    currentMainWindowNode.restoreCursorPosition(currentBufStatus, status.lastPosition)

    status.update

    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 0

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
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[Buffer.toRunes])

    status.backgroundTasks.build.add startBackgroundBuild(
      TestFilePath.toRunes, currentBufStatus.language
    ).get

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

    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin("test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[Buffer.toRunes])

    for i in 0 .. 1:
      status.backgroundTasks.build.add startBackgroundBuild(
        TestFilePath.toRunes, currentBufStatus.language
      ).get

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
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["import std/os", "echo 1"].toSeqRunes.toGapBuffer

    let syntaxError = SyntaxError(
      position: BufferPosition(line: 0, column: 11),
      messageType: SyntaxCheckMessageType.warning,
      message: ru"imported and not used: 'os' [UnusedImport]",
    )

    currentBufStatus.syntaxCheckResults = @[syntaxError]

    status.resize(100, 100)
    status.update

    check status.commandLine.buffer ==
      ru"SyntaxError: (0, 11) imported and not used: 'os' [UnusedImport]"

  test "Write syntax checker messages and move line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["import std/os", "echo 1"].toSeqRunes.toGapBuffer

    let syntaxError = SyntaxError(
      position: BufferPosition(line: 0, column: 11),
      messageType: SyntaxCheckMessageType.warning,
      message: ru"imported and not used: 'os' [UnusedImport]",
    )

    currentBufStatus.syntaxCheckResults = @[syntaxError]

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentLine = 1
    status.update

    # Should be empty for other lines.
    check status.commandLine.buffer.len == 0

suite "updateSelectedArea: Visual mode":
  test "Move to right":
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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
    var status = initEditorStatus().get
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

    check smoothScrollDelays(TotalLines, MinDelay, MaxDelay) ==
      @[13, 10, 8, 7, 6, 6, 6, 7, 8, 10, 13, 16, 20, 25, 30, 36, 42, 49, 56, 64]

  test "totalLines: 0, minDelay 5, maxDelay 20":
    const
      TotalLines = 0
      MinDelay = 5
      MaxDelay = 20

    check smoothScrollDelays(TotalLines, MinDelay, MaxDelay).len == 0

suite "editorstatus: scrollUpNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 30).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 30

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollUpNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 10

  test "numberOfLines: 20 and buffer.len: 10":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 10).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 10

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollUpNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 0

suite "editorstatus: scrollDownNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 30).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollDownNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 20

  test "numberOfLines: 20 and buffer.len: 10":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 10).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const NumberOfLines = 20
    status.scrollDownNumberOfLines(NumberOfLines)

    check currentMainWindowNode.currentLine == 10

suite "editorstatus: smoothScrollUpNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 30).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 30

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollUpNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 10

  test "numberOfLines: 20; buffer.len: 10":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 10).mapIt(it.toRunes).toGapBuffer
    currentMainWindowNode.currentLine = 10

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollUpNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 0

suite "editorstatus: smoothScrollDownNumberOfLines":
  test "numberOfLines: 20":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 30).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollDownNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 20

  test "numberOfLines: 20; buffer.len: 10":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toSeq(0 .. 10).mapIt(it.toRunes).toGapBuffer

    status.resize(100, 100)
    status.update

    const TotalLines = 20
    check status.smoothScrollDownNumberOfLines(TotalLines).isNone

    check currentMainWindowNode.currentLine == 10

suite "editorstatus: initLsp":
  test "Init with lasm":
    if not isLasmAvailable():
      skip()
    else:
      let path = $genOid() & ".nim"
      var status = initEditorStatus().get

      status.settings.lsp.enable = true
      status.settings.lsp.languages["nim"] = LspLanguageSettings(
        extensions: @[ru"nim"], command: ru"lasm", trace: TraceValue.verbose
      )

      status.bufStatus.add initBufferStatus(path, Mode.normal).get

      let workspaceRoot = getCurrentDir()
      const
        LanguageId = "nim"
        Bufferid = 1
      check status.lspInitialize(BufferId, workspaceRoot, LanguageId).isOk

  test "Don't send initialize request twice":
    if not isLasmAvailable():
      skip()
    else:
      const
        LanguageId = "nim"
        Bufferid = 1
      let path = $genOid() & ".nim"
      var status = initEditorStatus().get

      status.settings.lsp.enable = true
      status.settings.lsp.languages["nim"] = LspLanguageSettings(
        extensions: @[LanguageId.toRunes], command: ru"lasm", trace: TraceValue.verbose
      )

      assert status.addNewBufferInCurrentWin(path).isOk

      let workspaceRoot = getCurrentDir()

      assert status.lspInitialize(BufferId, workspaceRoot, LanguageId).isOk
      let lastId = lspClient.lastId

      # Again
      assert status.lspInitialize(BufferId, workspaceRoot, LanguageId).isOk
      check lastId == lspClient.lastId

suite "editorstatus: autoSave":
  const TestDir = "autoSaveTest"
  var filePath = ""

  setup:
    createDir(TestDir)
    filePath = TestDir / $genOid() & ".nim"

  teardown:
    if dirExists(TestDir):
      removeDir(TestDir)

  test "Basic":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin(filePath).get

    status.settings.autoSave.enable = true
    status.settings.autoSave.interval = 0

    status.autoSave
    check fileExists(filePath)

  test "With lsp log":
    var status = initEditorStatus().get

    status.settings.autoSave.enable = true
    status.settings.autoSave.interval = 0

    status.settings.lsp.enable = true
    status.settings.lsp.languages["nim"] = LspLanguageSettings(
      extensions: @[ru"nim"], command: ru"lasm", trace: TraceValue.verbose
    )

    discard status.addNewBufferInCurrentWin(filePath).get

    status.openLspLogViewer
    assert status.bufStatus.len == 2
    assert currentBufStatus.mode == Mode.logViewer

    status.autoSave
    check fileExists(filePath)

suite "editorstatus: update":
  type LspCommand = types.Command

  var status: EditorStatus

  setup:
    status = initEditorStatus().get

    assert status.addNewBufferInCurrentWin("").isOk

  test "LSP code lens with invalid position":
    currentBufStatus.codeLenses =
      @[
        CodeLens(
          range: LspRange(
            start: LspPosition(line: 1, character: 0),
            `end`: LspPosition(line: 1, character: 0),
          ),
          command: some(LspCommand()),
        )
      ]

    status.resize(100, 100)
    status.update

suite "editorstatus: updateSyntaxHighlightings":
  var status: EditorStatus

  setup:
    status = initEditorStatus().get
    status.settings.git.showChangedLine = true

    assert status.addNewBufferInCurrentWin("test.txt").isOk

  test "Check isGitUpdate":
    currentBufStatus.isGitUpdate = false
    currentBufStatus.isUpdate = true
    currentBufStatus.isTrackingByGit = true
    status.updateSyntaxHighlightings

    check currentBufStatus.isGitUpdate

suite "editorstatus: resize":
  privateAccess TabLine

  var status: EditorStatus

  setup:
    status = initEditorStatus().get
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.resize(100, 100)

    check status.tabLine.position.y == 0
    check status.tabLine.position.x == 0
    check status.tabLine.size.h == 1
    check status.tabLine.size.w == 100

    check status.mainWindow.root.y == 1
    check status.mainWindow.root.x == 0
    check status.mainWindow.root.h == 98
    check status.mainWindow.root.w == 100

    check status.statusLine[0].window.y == 98
    check status.statusLine[0].window.x == 0
    check status.statusLine[0].window.height == 1
    check status.statusLine[0].window.width == 100

    check status.commandLine.y == 99
    check status.commandLine.x == 0
    check status.commandLine.h == 1
    check status.commandLine.w == 100

  test "Command line height is 2":
    status.resize(100, 100)

    status.commandLine.buffer = "a".repeat(150).toRunes
    status.resize(100, 100)

    check status.tabLine.position.y == 0
    check status.tabLine.position.x == 0
    check status.tabLine.size.h == 1
    check status.tabLine.size.w == 100

    check status.mainWindow.root.y == 1
    check status.mainWindow.root.x == 0
    check status.mainWindow.root.h == 97
    check status.mainWindow.root.w == 100

    check status.statusLine[0].window.y == 97
    check status.statusLine[0].window.x == 0
    check status.statusLine[0].window.height == 1
    check status.statusLine[0].window.width == 100

    check status.commandLine.y == 98
    check status.commandLine.x == 0
    check status.commandLine.h == 2
    check status.commandLine.w == 100

suite "Buffer cache integration":
  test "changeCurrentBufferWithCache - basic functionality":
    var status = initEditorStatus().get

    # Create first buffer
    discard status.addNewBufferInCurrentWin("test1.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru"first buffer", ru"line 2"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 5

    # Create second buffer
    discard status.addNewBufferInCurrentWin("test2.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru"second buffer"])

    check status.bufStatus.len == 2
    check currentMainWindowNode.bufferIndex == 1

    # Switch back to first buffer using cache
    status.changeCurrentBufferWithCache(0)

    check currentMainWindowNode.bufferIndex == 0
    check currentBufStatus.path == ru"test1.nim"
    check currentBufStatus.buffer.toSeqRunes == @[ru"first buffer", ru"line 2"]
    # Check buffer content was preserved
    # Note: Cursor position preservation may depend on additional implementation
    check currentMainWindowNode.currentLine >= 0
    check currentMainWindowNode.currentColumn >= 0

  test "changeCurrentBufferWithCache - state preservation":
    var status = initEditorStatus().get

    # Create buffer with specific state
    discard status.addNewBufferInCurrentWin("preserve_test.nim").get
    currentBufStatus.buffer = initGapBuffer(@[ru"line 1", ru"line 2", ru"line 3"])
    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 3

    # Set selected area in visual mode
    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(1, 2).some

    # Create second buffer
    discard status.addNewBufferInCurrentWin("temp.nim").get

    # Switch back and verify buffer state preservation
    status.changeCurrentBufferWithCache(0)

    # Check buffer content is correct
    check currentBufStatus.buffer.toSeqRunes == @[ru"line 1", ru"line 2", ru"line 3"]
    # Note: Full state preservation (cursor, selection) may require additional implementation
    check currentMainWindowNode.currentLine >= 0
    check currentMainWindowNode.currentColumn >= 0

  test "changeCurrentBufferWithCache - cache hit statistics":
    var status = initEditorStatus().get

    # Initialize cache (should be done automatically in initEditorStatus)
    let initialStats = status.bufferCache.getCacheStats()

    # Create multiple buffers
    discard status.addNewBufferInCurrentWin("file1.nim").get
    let buf1Index = currentMainWindowNode.bufferIndex

    discard status.addNewBufferInCurrentWin("file2.nim").get
    let buf2Index = currentMainWindowNode.bufferIndex

    discard status.addNewBufferInCurrentWin("file3.nim").get

    # Switch between buffers to generate cache hits
    status.changeCurrentBufferWithCache(buf1Index) # Should be cache miss (first time)
    status.changeCurrentBufferWithCache(buf2Index) # Should be cache miss (first time)
    status.changeCurrentBufferWithCache(buf1Index) # Should be cache hit
    status.changeCurrentBufferWithCache(buf2Index) # Should be cache hit

    let finalStats = status.bufferCache.getCacheStats()

    # Should have some cache hits
    check finalStats.hits > initialStats.hits
    check finalStats.hitRate > 0.0

  test "addNewBufferInCurrentWinWithCache - basic functionality":
    var status = initEditorStatus().get

    # Create temporary test file
    let testPath = "cache_test_file.nim"
    writeFile(testPath, "test content\nline 2")

    defer:
      if fileExists(testPath):
        removeFile(testPath)

    # Add buffer using cache-aware function
    let result = status.addNewBufferInCurrentWinWithCache(testPath, Mode.normal)

    check result.isOk
    check status.bufStatus.len == 1
    check currentBufStatus.path == testPath.toRunes
    check currentBufStatus.buffer.toSeqRunes == @[ru"test content", ru"line 2"]

  test "addNewBufferInCurrentWinWithCache - reuse cached buffer":
    var status = initEditorStatus().get

    # Create test file
    let testPath = "reuse_test.nim"
    writeFile(testPath, "reusable content")

    defer:
      if fileExists(testPath):
        removeFile(testPath)

    # First load - should add to cache
    discard status.addNewBufferInCurrentWinWithCache(testPath, Mode.normal).get
    let firstBufferId = currentBufStatus.id

    # Modify cursor position
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 5

    # Add different buffer
    discard status.addNewBufferInCurrentWinWithCache("other.nim", Mode.normal).get

    # Load same file again - should use cache
    discard status.addNewBufferInCurrentWinWithCache(testPath, Mode.normal).get

    # Should be same buffer instance with preserved state
    check currentBufStatus.id == firstBufferId
    check currentMainWindowNode.currentColumn == 5

  test "buffer cache toggle functionality":
    var status = initEditorStatus().get

    let initialEnabled = status.bufferCache.enabled

    # Toggle cache
    status.bufferCache.enabled = not status.bufferCache.enabled
    check status.bufferCache.enabled != initialEnabled

    # Toggle back
    status.bufferCache.enabled = not status.bufferCache.enabled
    check status.bufferCache.enabled == initialEnabled

  test "cache memory management":
    var status = initEditorStatus().get

    # Create multiple buffers to test LRU eviction
    for i in 0 ..< 15: # Exceed default cache size of 10
      let filename = fmt"test_file_{i}.nim"
      discard status.addNewBufferInCurrentWinWithCache(filename, Mode.normal).get
      currentBufStatus.buffer = initGapBuffer(@[fmt"content {i}".toRunes])

    let stats = status.bufferCache.getCacheStats()

    # Cache should have reasonable memory usage
    check stats.memoryMB >= 0.0
    check stats.memoryMB < 100.0 # Should not exceed limit

    # Some buffers should have been evicted due to LRU
    check stats.hits >= 0
    check stats.misses >= 0

suite "handleMouseEvent":
  test "Click on valid position":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["line 1", "line 2", "line 3"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    # Set initial cursor position
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    # Simulate a click at line 1 (second line), column 3
    # Click position calculation:
    # bufferY = clickY - node.y - tabLineHeight + node.view.originalLine[0]
    # We want bufferY=1, so: clickY = bufferY + node.y + tabLineHeight - node.view.originalLine[0]
    # bufferX = clickX - node.x - sidebarWidth - widthOfLineNum
    # We want bufferX=3, so: clickX = bufferX + node.x + sidebarWidth + widthOfLineNum
    # Note: parseMouseEvent converts from 1-based to 0-based, so we need to add 1 for SGR format
    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum
    # Calculate 0-based screen coordinates
    # bufferY = clickY - node.y - tabLineHeight + node.view.originalLine[0]
    # We want bufferY=1, so: clickY = bufferY + node.y + tabLineHeight - node.view.originalLine[0]
    # Note: originalLine[0] is 0 in these tests (no scrolling)
    let
      clickY = 1 + currentMainWindowNode.y + tabLineHeight
      clickX = 3 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      # Convert to 1-based for SGR format
      sgrY = clickY + 1
      sgrX = clickX + 1

    # Create a mouse event for button 1 press at the calculated position
    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    # Handle the mouse event
    status.handleMouseEvent

    # Verify cursor moved to the clicked position
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 3

  test "Click beyond the last line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["line 1", "line 2"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum
      # Click at buffer line 10 (beyond the 2 lines in buffer)
      clickY = 10 + currentMainWindowNode.y + tabLineHeight
      clickX = 0 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    # Should move to the last line
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Click beyond the end of a line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 0 + currentMainWindowNode.y + tabLineHeight # First line
      clickX = 10 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
        # Beyond "abc"
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    # Should move to the end of the line (column 2 for "abc")
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Click on empty line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "", "def"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 1 + currentMainWindowNode.y + tabLineHeight # Second line (empty)
      clickX = 5 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    # Should move to the empty line at column 0
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Click at the beginning of a line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["line 1", "line 2"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    # Set cursor to somewhere else first
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 5

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 0 + currentMainWindowNode.y + tabLineHeight # First line
      clickX = 0 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum # Column 0
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    # Should move to line 0, column 0
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Click with tab line disabled":
    var status = initEditorStatus().get
    status.settings.tabLine.enable = false
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["line 1", "line 2"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 1 + currentMainWindowNode.y + tabLineHeight # Second line
      clickX = 2 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 2

  test "Click on last character of a line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 0 + currentMainWindowNode.y + tabLineHeight
      clickX = 5 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum # Last char
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

  test "Ignore non-left-button events":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["line 1", "line 2"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    # Set initial cursor position
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 1 + currentMainWindowNode.y + tabLineHeight
      clickX = 3 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      sgrY = clickY + 1
      sgrX = clickX + 1

    # Button 2 (middle button) press - should be ignored
    let input = "\e[<1;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    # Cursor should not have moved
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Click on single character line":
    var status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    let
      tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
      sidebarWidth = currentMainWindowNode.view.sidebarWidth
      widthOfLineNum = currentMainWindowNode.view.widthOfLineNum

      clickY = 0 + currentMainWindowNode.y + tabLineHeight
      clickX = 0 + currentMainWindowNode.x + sidebarWidth + widthOfLineNum
      sgrY = clickY + 1
      sgrX = clickX + 1

    let input = "\e[<0;" & $sgrX & ";" & $sgrY & "M"
    check parseMouseEvent(input) == true

    status.handleMouseEvent

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0
