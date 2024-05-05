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

import std/[unittest, os, oids, deques, strformat, importutils, osproc, tables,
            json, times]

import pkg/results

import moepkg/syntax/highlite
import moepkg/lsp/client
import moepkg/[ui, editorstatus, gapbuffer, unicodeext, bufferstatus, settings,
               windownode, helputils, backgroundprocess, quickrunutils,
               exmodeutils]

import utils

import moepkg/lsp {.all.}
import moepkg/exmode {.all.}

proc isValidWindowSize(n: WindowNode) =
  check n.w > 0
  check n.h > 1
  check n.view.height > 1
  check n.view.width > 1
  check n.view.lines.len > 1
  check n.view.start.len > 1
  check n.view.originalLine.len > 1
  check n.view.length.len > 1

suite "Ex mode: isExCommandBuffer":
  ## Generate test code
  template isExCommandBufferTest(command: Runes, exceptInputState: InputState) =
    let testTitle = "isExCommandBuffer: " & $`command`
    test testTitle:
      check isExCommandBuffer(`command`) == `exceptInputState`

  # Check valid Commands
  for cmd in ExCommandInfoList:
    case cmd.argsType:
      of ArgsType.none:
        isExCommandBufferTest(cmd.command.toRunes, InputState.Valid)
      of ArgsType.toggle:
        isExCommandBufferTest(toRunes(fmt"{cmd.command} on"), InputState.Valid)
        isExCommandBufferTest(toRunes(fmt"{cmd.command} off"), InputState.Valid)
      of ArgsType.number:
        isExCommandBufferTest(toRunes(fmt"{cmd.command} 0"), InputState.Valid)
      of ArgsType.text:
        isExCommandBufferTest(toRunes(fmt"{cmd.command} text"), InputState.Valid)
      of ArgsType.path:
        if "e" == cmd.command:
          isExCommandBufferTest(toRunes(fmt"{cmd.command} /"), InputState.Valid)
        else:
          # TODO: Add path And fix tests
          isExCommandBufferTest(toRunes(fmt"{cmd.command}"), InputState.Valid)
      of ArgsType.theme:
        for t in @["vivid", "dark", "light", "config", "vscode"]:
          isExCommandBufferTest(toRunes(fmt"{cmd.command} {t}"), InputState.Valid)
  # Check the empty
  isExCommandBufferTest("".toRunes, InputState.Continue)

  # Check the Invalid command
  isExCommandBufferTest("abcxyz".toRunes, InputState.Invalid)

suite "Ex mode: Edit command":
  test "Edit command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"e", ru"test"]
    status.exModeCommand(Command)

  test "Edit command 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("test").get

    status.resize(100, 100)
    status.verticalSplitWindow
    status.resize(100, 100)

    status.changeMode(Mode.ex)
    const Command = @[ru"e", ru"test2"]
    status.exModeCommand(Command)

    check(status.bufStatus[0].mode == Mode.normal)
    check(status.bufStatus[1].mode == Mode.normal)

suite "Fix #1581":
  let
    dirPath = getAppDir() / "exmodetestfiles"
    filePaths: seq[string] = @[dirPath / $genOid(), dirPath / $genOid()]

  setup:
    # Create dir and test file
    createDir(dirPath)
    for p in filePaths: writeFile(p, "1\n2\n3\n")

  teardown:
    # Clean up the test dir
    removeDir(dirPath)

  test "Open a new buffer using the edit command":
    # For https://github.com/fox0430/moe/issues/1581

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(filePaths[0]).get
    status.resize(100, 100)

    status.changeMode(Mode.ex)

    let command = @[ru"e", filePaths[1].toRunes]
    status.exModeCommand(command)

    currentMainWindowNode.isValidWindowSize

suite "Ex mode: Write command":
  const
    TestDir = "./ExModeWriteTest"
    TestFilePath = TestDir / "test.nim"

  setup:
    createDir(TestDir)

  teardown:
    removeDir(TestDir)

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(TestFilePath).get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    const Command = @[ru"w"]
    status.exModeCommand(Command)

  test "buildOnSave":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(TestFilePath).get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"echo 1"])

    status.settings.buildOnSave.enable = true

    const Command = @[ru"w"]
    status.exModeCommand(Command)

    check status.backgroundTasks.build.len == 1

    status.backgroundTasks.build[0].process.kill

  test "Enable LSP":
    if not isNimlangserverAvailable():
      skip()
    else:
      var status = initEditorStatus()

      status.settings.lsp.enable = true

      discard status.addNewBufferInCurrentWin(TestFilePath).get
      status.bufStatus[0].buffer = initGapBuffer(@[ru"echo 1"])

      block initLsp:
        let workspaceRoot = TestDir
        const LangId = "nim"

        assert status.lspInitialize(workspaceRoot, LangId).isOk

        const Timeout = 5000
        assert lspClient.readable(Timeout).get

        let resJson = lspClient.read.get
        assert status.lspInitialized(resJson).isOk
        assert lspClient.isInitialized

      const Command = @[ru"w"]
      status.exModeCommand(Command)

suite "Ex mode: Change next buffer command":
 test "Change next buffer command 1":
   var status = initEditorStatus()
   for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get
   status.bufStatus[1].isUpdate = false

   currentMainWindowNode.bufferIndex = 0
   const Command = @[ru"bnext"]
   status.exModeCommand(Command)

   check currentMainWindowNode.bufferIndex == 1
   check status.bufStatus[1].isUpdate

 test "Change next buffer command":
   var status = initEditorStatus()
   for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

   status.resize(100, 100)
   status.update

   check currentMainWindowNode.bufferIndex == 1
   const Command = @[ru"bnext"]
   status.exModeCommand(Command)

   status.update

suite "Ex mode: Change prev buffer command":
  test "Change prev buffer command 1":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].isUpdate = false

    currentMainWindowNode.bufferIndex = 1
    const Command = @[ru"bprev"]
    status.exModeCommand(Command)

    check currentMainWindowNode.bufferIndex == 0
    check status.bufStatus[0].isUpdate

  test "Change prev buffer command 2":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    currentMainWindowNode.bufferIndex = 0
    const Command = @[ru"bprev"]
    status.exModeCommand(Command)

    status.update

suite "Ex mode: Open buffer by number command":
  test "Open buffer by number command":
    var status = initEditorStatus()
    for i in 0 ..< 3: discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"b", ru"1"]
      status.exModeCommand(Command)

    block:
      const Command = @[ru"b", ru"0"]
      status.exModeCommand(Command)

    block:
      const Command = @[ru"b", ru"2"]
      status.exModeCommand(Command)

suite "Ex mode: Change to first buffer command":
  test "Change to first buffer command":
    var status = initEditorStatus()
    for i in 0 ..< 3: discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.bufferIndex = 2
    const Command = @[ru"bfirst"]
    status.exModeCommand(Command)

    check(currentMainWindowNode.bufferIndex == 0)

suite "Ex mode: Change to last buffer command":
  test "Change to last buffer command":
    var status = initEditorStatus()
    for i in 0 ..< 3: discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.bufferIndex = 0
    const Command = @[ru"blast"]
    status.exModeCommand(Command)
    check(currentMainWindowNode.bufferIndex == 2)

suite "Ex mode: Replace buffer command":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(
      @["xyz", "abcdefghijk", "Hello"].toSeqRunes)

    const Command = @[ru"%s/efg/zzzzzz"]
    status.exModeCommand(Command)

    check status.bufStatus[0].buffer.toSeqRunes ==
      @["xyz", "abcdzzzzzzhijk", "Hello"].toSeqRunes

  test "Incomplete command":
    # NOTE: https://github.com/fox0430/moe/issues/1912

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = initGapBuffer(
      @["abc", "", "def"].toSeqRunes)

    const Command = @[ru"%s/ab"]
    status.exModeCommand(Command)

    check status.bufStatus[0].buffer.toSeqRunes ==
      @["abc", "", "def"].toSeqRunes

  test "Replace all":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].buffer = @[
      "xyzabc",
      "abcxyz",
      "abc",
      "abcxyzabc",
      "",
      "xyzabcxyz"]
      .toSeqRunes
      .initGapBuffer

    const Command = @[ru"%s/abc/iii/g"]
    status.exModeCommand(Command)

    check status.bufStatus[0].buffer.toSeqRunes == @[
      "xyziii",
      "iiixyz",
      "iii",
      "iiixyziii",
      "",
      "xyziiixyz"]
      .toSeqRunes

suite "Ex mode: Turn off highlighting command":
  test "Turn off highlighting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"noh"]
    status.exModeCommand(Command)

suite "Ex mode: Tab line setting command":
  test "Tab line setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"tab", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.tabLine.enable == false)
    block:
      const Command = @[ru"tab", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.tabLine.enable == true)

suite "Ex mode: StatusLine setting command":
  test "StatusLine setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"statusline", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.statusLine.enable == false)
    block:
      const Command = @[ru"statusline", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.statusLine.enable == true)

suite "Ex mode: Line number setting command":
  test "Line number setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"linenum", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.view.lineNumber == false)
    block:
      const Command = @[ru"linenum", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.view.lineNumber == true)

suite "Ex mode: Auto indent setting command":
  test "Auto indent setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"indent", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoIndent == false)
    block:
      const Command = @[ru"indent", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoIndent == true)

suite "Ex mode: Auto close paren setting command":
  test "Auto close paren setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"paren", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoCloseParen == false)
    block:
      const Command = @[ru"paren", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoCloseParen == true)

suite "Ex mode: Tab stop setting command":
  test "Tab stop setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"paren", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoCloseParen == false)
    block:
      const Command = @[ru"paren", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.standard.autoCloseParen == true)

suite "Ex mode: Syntax setting command":
  test "Syntax setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"syntax", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.standard.syntax == false)
    block:
      const Command = @[ru"syntax", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.standard.syntax == true)

suite "Ex mode: Change cursor line command":
  test "Change cursor line command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"cursorLine", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.view.cursorLine == true)
    block:
      const Command = @[ru"cursorLine", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.view.cursorLine == false)

suite "Ex mode: Split window command":
  test "Split window command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)

    const Command = @[ru"vs"]
    status.exModeCommand(Command)
    check(status.mainWindow.numOfMainWindow == 2)

suite "Ex mode: Live reload of configuration file setting command":
  test "Live reload of configuration file setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"livereload", ru"on"]
      status.exModeCommand(Command)
    check(status.settings.standard.liveReloadOfConf == true)
    block:
      const Command = @[ru"livereload", ru"off"]
      status.exModeCommand(Command)
    check(status.settings.standard.liveReloadOfConf == false)

suite "Ex mode: Incremental search setting command":
  test "Incremental search setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"incrementalSearch", ru"off"]
      status.exModeCommand(Command)
    check not status.settings.standard.incrementalSearch
    block:
      const Command = @[ru"incrementalSearch", ru"on"]
      status.exModeCommand(Command)
    check status.settings.standard.incrementalSearch

suite "Ex mode: Change theme command":
  test "Change theme command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    startUi()

    block:
      const Command = @[ru"theme", ru"vivid"]
      status.exModeCommand(Command)

    block:
      const Command = @[ru"theme", ru"dark"]
      status.exModeCommand(Command)

    block:
      const Command = @[ru"theme", ru"light"]
      status.exModeCommand(Command)

    block:
      const Command = @[ru"theme", ru"config"]
      status.exModeCommand(Command)

suite "Ex mode: Open buffer manager":
  test "Open buffer manager":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    startUi()

    const Command = @[ru"buf"]
    status.exModeCommand(Command)

suite "Ex mode: Open editor log viewer":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"log"]
    status.exModeCommand(Command)

    check status.mainWindow.numOfMainWindow == 2
    check currentMainWindowNode.view.height > 1

suite "Ex mode: Open LSP log viewer":
  var status: EditorStatus

  setup:
    status = initEditorStatus()

  test "Ininitialize LSP":
    let filename = $genOid() & ".nim"

    discard status.addNewBufferInCurrentWin(filename).get

    const Command = @[ru"lspLog"]
    status.exModeCommand(Command)

    status.update

    check status.mainWindow.numOfMainWindow == 2
    check currentMainWindowNode.view.height > 1

    check currentBufStatus.buffer.len > 0

  test "Without log":
    let filename = $genOid() & ".nim"

    discard status.addNewBufferInCurrentWin(filename).get
    currentBufStatus.langId = "nim"

    status.lspClients["nim"] = LspClient()

    const Command = @[ru"lspLog"]
    status.exModeCommand(Command)

    status.update

    check status.mainWindow.numOfMainWindow == 2
    check currentMainWindowNode.view.height > 1

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

  test "Basic":
    let filename = $genOid() & ".nim"

    discard status.addNewBufferInCurrentWin(filename).get
    currentBufStatus.langId = "nim"

    status.lspClients["nim"] = LspClient()
    status.lspClients["nim"].log = @[
      LspMessage(
        timestamp: now(),
        kind: LspMessageKind.request,
        message: %*{"message1": "message1"}),
      LspMessage(
        timestamp: now(),
        kind: LspMessageKind.response,
        message: %*{"message2": "message2"})
    ]

    const Command = @[ru"lspLog"]
    status.exModeCommand(Command)

    status.update

    check status.mainWindow.numOfMainWindow == 2
    check currentMainWindowNode.view.height > 1

    check currentBufStatus.buffer.toSeqRunes == @[
      "",
      $status.lspClients["nim"].log[0].timestamp & " -- " & "request",
      "{",
      """  "message1": "message1"""",
      "}",
      "",
      $status.lspClients["nim"].log[1].timestamp & " -- " & "response",
      "{",
      """  "message2": "message2"""",
      "}",
      ""
    ].toSeqRunes

suite "Ex mode: Highlight pair of paren settig command":
  test "Highlight pair of paren settig command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"highlightparen", ru"off"]
      status.exModeCommand(Command)
      check(status.settings.highlight.pairOfParen == false)
    block:
      const Command = @[ru"highlightparen", ru"on"]
      status.exModeCommand(Command)
      check(status.settings.highlight.pairOfParen == true)

suite "Ex mode: Auto delete paren setting command":
  test "Auto delete paren setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"deleteparen", ru"off"]
      status.exModeCommand(Command)
      check(status.settings.standard.autoDeleteParen == false)

    block:
      const Command = @[ru"deleteparen", ru"on"]
      status.exModeCommand(Command)
      check(status.settings.standard.autoDeleteParen == true)

suite "Ex mode: Smooth scroll setting command":
  test "Smooth scroll setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"smoothscroll", ru"off"]
      status.exModeCommand(Command)
      check not status.settings.smoothScroll.enable

    block:
      const Command = @[ru"smoothscroll", ru"on"]
      status.exModeCommand(Command)
      check status.settings.smoothScroll.enable

suite "Ex mode: Smooth scroll min delay setting command":
  test "Set to 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"scrollMinDelay", ru"1"]
    status.exModeCommand(Command)

    check status.settings.smoothScroll.minDelay == 1

  test "Invalid value":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let defaultSpeed = status.settings.smoothScroll.minDelay

    const Command = @[ru"scrollMinDelay", ru"a"]
    status.exModeCommand(Command)

    check status.settings.smoothScroll.minDelay == defaultSpeed

suite "Ex mode: Smooth scroll max delay setting command":
  test "Set to 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"scrollMaxDelay", ru"1"]
    status.exModeCommand(Command)

    check status.settings.smoothScroll.maxDelay == 1

  test "Invalid value":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let defaultSpeed = status.settings.smoothScroll.maxDelay

    const Command = @[ru"scrollMaxDelay", ru"a"]
    status.exModeCommand(Command)

    check status.settings.smoothScroll.maxDelay == defaultSpeed

suite "Ex mode: Highlight current word setting command":
  test "Highlight current word setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"highlightcurrentword", ru"off"]
      status.exModeCommand(Command)
      check(status.settings.highlight.currentWord == false)

    block:
      const Command = @[ru"highlightcurrentword", ru"on"]
      status.exModeCommand(Command)
      check(status.settings.highlight.currentWord == true)

suite "Ex mode: Clipboard setting command":
  test "Clipboard setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"clipboard", ru"off"]
      status.exModeCommand(Command)
      check(status.settings.clipboard.enable == false)

    block:
      const Command = @[ru"clipboard", ru"on"]
      status.exModeCommand(Command)
      check(status.settings.clipboard.enable == true)

suite "Ex mode: Highlight full width space command":
  test "Highlight full width space command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"highlightfullspace", ru"off"]
      status.exModeCommand(Command)
      check(status.settings.highlight.fullWidthSpace == false)

    block:
      const Command = @[ru"highlightfullspace", ru"on"]
      status.exModeCommand(Command)
      check(status.settings.highlight.fullWidthSpace == true)

  test "Ex mode: Tab stop setting command 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let defaultTabStop = status.settings.standard.tabStop

    const Command = @[ru"tabstop", ru"a"]
    status.exModeCommand(Command)

    check(status.settings.standard.tabStop == defaultTabStop)

suite "Ex mode: Delete buffer status command":
  test "Delete buffer status command":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"bd", ru"0"]
    status.exModeCommand(Command)

    check(status.bufStatus.len == 1)

  test "Delete buffer status command 2":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"bd", ru"a"]
    status.exModeCommand(Command)

    check(status.bufStatus.len == 2)

suite "Ex mode: Open buffer by number command":
  test "Open buffer by number command":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"b", ru"0"]
    status.exModeCommand(Command)

    check(status.bufferIndexInCurrentWindow == 0)

  test "Open buffer by number command 2":
    var status = initEditorStatus()
    for i in 0 ..< 2: discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"b", ru"a"]
    status.exModeCommand(Command)

    check(status.bufferIndexInCurrentWindow == 1)

suite "Ex mode: help command":
  test "Open help":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"help"]
    status.exModeCommand(Command)

    status.update

    check status.mainWindow.numOfMainWindow == 2
    check status.bufferIndexInCurrentWindow == 1

    currentMainWindowNode.isValidWindowSize

    check status.bufStatus[1].mode == Mode.help
    check status.bufStatus[1].isReadonly

    let help = initHelpModeBuffer()
    for i, line in help:
      check status.bufStatus[1].buffer[i] == line

suite "Ex mode: split window vertically":
  test "In Normal mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.ex)

    const Command = @[ru"sp"]
    status.exModeCommand(Command)

    check status.mainWindow.numOfMainWindow == 2
    check status.bufStatus.len == 1

    check status.bufStatus[0].prevMode == Mode.ex
    check status.bufStatus[0].mode == Mode.normal

  test "In Filer mode":
    var status = initEditorStatus()
    const Path = "./"
    discard status.addNewBufferInCurrentWin(Path, Mode.filer).get

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.ex)

    const Command = @[ru"sp"]
    status.exModeCommand(Command)

    check status.mainWindow.numOfMainWindow == 2
    check status.bufStatus.len == 2

    privateAccess(status.type)
    check status.filerStatuses.len == 2

    check status.bufStatus[0].prevMode == Mode.ex
    check status.bufStatus[0].mode == Mode.filer

    check status.bufStatus[1].prevMode == Mode.filer
    check status.bufStatus[1].mode == Mode.filer

suite "Ex mode: Open in horizontal split window":
  test "Open in horizontal split window":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"sp", ru"newfile"]
    status.exModeCommand(Command)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 2)

  test "Open in horizontal split window 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"sp"]
    status.exModeCommand(Command)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 1)

suite "Ex mode: Open in vertical split window":
  test "Open in vertical split window":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"vs", ru"newfile"]
    status.exModeCommand(Command)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 2)

suite "Ex mode: Create new empty buffer":
  test "Create new empty buffer":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("a").get

    status.resize(100, 100)
    status.update

    const Command = @[ru"ene"]
    status.exModeCommand(Command)

    check status.bufStatus.len == 2

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

  test "Create new empty buffer 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.bufStatus[0].countChange = 1

    status.resize(100, 100)
    status.update

    const Command = @[ru"ene"]
    status.exModeCommand(Command)

    check status.bufStatus.len == 1

    check status.bufferIndexInCurrentWindow == 0

suite "Ex mode: New empty buffer in split window horizontally":
  test "New empty buffer in split window horizontally":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("a").get

    status.resize(100, 100)
    status.update

    const Command = @[ru"new"]
    status.exModeCommand(Command)

    check status.bufStatus.len == 2

    check status.bufferIndexInCurrentWindow == 1

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

    check status.mainWindow.numOfMainWindow == 2

    status.update

suite "Ex mode: New empty buffer in split window vertically":
  test "New empty buffer in split window vertically":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin("a").get

    status.resize(100, 100)
    status.update

    const Command = @[ru"vnew"]
    status.exModeCommand(Command)

    check status.bufStatus.len == 2

    check status.bufferIndexInCurrentWindow == 1

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

    check status.mainWindow.numOfMainWindow == 2

    status.update

suite "Ex mode: Filer icon setting command":
  test "Filer icon setting command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"icon", ru"on"]
    status.exModeCommand(Command)

    check status.settings.filer.showIcons

  test "Filer icon setting command 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"icon", ru"off"]
    status.exModeCommand(Command)

    check status.settings.filer.showIcons == false

suite "Ex mode: Put config file command":
  test "Put config file command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"putConfigFile"]
    status.exModeCommand(Command)

    check fileExists(getHomeDir() / ".config" / "moe" / "moerc.toml")

suite "Ex mode: Show/Hide git branch name in status line when inactive window":
  test "Show/Hide git branch name in status line when inactive window":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    block:
      const Command = @[ru"showGitInactive", ru"off"]
      status.exModeCommand(Command)
      check not status.settings.statusLine.showGitInactive

    block:
      const Command = @[ru"showGitInactive", ru"on"]
      status.exModeCommand(Command)
      check status.settings.statusLine.showGitInactive

suite "Ex mode: Quickrun command wihtout file":
  test "Exec Quickrun without file":
    # Create a file for the test.
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].language = SourceLanguage.langNim
    status.bufStatus[0].buffer = toGapBuffer(@[ru"echo 1"])

    const Command = @[ru"run"]
    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

      for w in mainWindowNode.getAllWindowNode:
        if w.bufferIndex == 1:
          # 1 is the quickrun window.
          check w.view.height > status.bufStatus[1].buffer.high

    var timeout = true
    for _ in 0 .. 20:
      sleep 500
      if status.backgroundTasks.quickRun[0].isFinish:
        let r = status.backgroundTasks.quickRun[0].result.get
        check r[^1] == "1"

        timeout = false
        break

    check not timeout

  test "Exec Quickrun without file twice":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].language = SourceLanguage.langNim
    status.bufStatus[0].buffer = toGapBuffer(@[ru"echo 1"])

    const Command = @[ru"run"]

    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    status.movePrevWindow

    # Edit the buffer and exec Quickrun again.
    status.bufStatus[0].buffer[0] = ru"echo 2"
    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 2
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    block:
      # Wait for the first quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[0].isFinish:
          let r = status.backgroundTasks.quickRun[0].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

    block:
      # Wait for the second quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[1].isFinish:
          let r = status.backgroundTasks.quickRun[1].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

suite "Ex mode: Quickrun command with file":
  const
    TestfileDir = "quickrunTestDir"
    TestfilePath = TestfileDir / "quickrunTest.nim"

  setup:
    createDir(TestfileDir)
    writeFile(TestfilePath, "echo 1")

  teardown:
    removeDir(TestfileDir)

  test "Exec Quickrun with file":
    # Create a file for the test.
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(TestfilePath, Mode.normal).get

    const Command = @[ru"run"]
    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

      for w in mainWindowNode.getAllWindowNode:
        if w.bufferIndex == 1:
          # 1 is the quickrun result.
          check w.view.height > status.bufStatus[1].buffer.high

    var timeout = true
    for _ in 0 .. 20:
      sleep 500
      if status.backgroundTasks.quickRun[0].isFinish:
        let r = status.backgroundTasks.quickRun[0].result.get
        check r[^1] == "1"

        timeout = false
        break

    check not timeout

  test "Exec Quickrun with file twice":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(TestfilePath, Mode.normal).get

    const Command = @[ru"run"]

    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    status.movePrevWindow

    # Edit the buffer and exec Quickrun again.
    status.settings.quickRun.saveBufferWhenQuickRun = true
    status.bufStatus[0].buffer[0] = ru"echo 2"
    status.update

    status.exModeCommand(Command)
    status.update

    # Wait just in case
    sleep 100

    block:
      # 1 is the quickrun window.
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

      check status.backgroundTasks.quickRun.len == 2
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    block:
      # Wait for the first quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[0].isFinish:
          let r = status.backgroundTasks.quickRun[0].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

    block:
      # Wait for the second quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[1].isFinish:
          let r = status.backgroundTasks.quickRun[1].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

suite "Ex mode: Workspace list command":
  test "Workspace list command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"lsw"]
    status.exModeCommand(Command)

suite "Ex mode: Change ignorecase setting command":
  test "Enable ignorecase":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.settings.standard.ignorecase = false

    const Command = @[ru"ignorecase", ru"on"]
    status.exModeCommand(Command)

    check status.settings.standard.ignorecase

  test "Disale ignorecase":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.settings.standard.ignorecase = true

    const Command = @[ru"ignorecase", ru"off"]
    status.exModeCommand(Command)

    check not status.settings.standard.ignorecase

suite "Ex mode: Change smartcase setting command":
  test "Enable smartcase":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.settings.standard.smartcase = false

    const Command = @[ru"smartcase", ru"on"]
    status.exModeCommand(Command)

    check status.settings.standard.ignorecase

  test "Disale smartcase":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.settings.standard.smartcase = true

    const Command = @[ru"smartcase", ru"off"]
    status.exModeCommand(Command)

    check not status.settings.standard.smartcase

suite "Ex mode: e command":
  test "Open dicrecoty (#1042)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"e", ru"./"]
    status.exModeCommand(Command)

    check status.bufStatus[1].mode == Mode.filer
    check status.bufStatus[1].path == getCurrentDir().toRunes

suite "Ex mode: q command":
  test "Run q command when opening multiple windows (#1056)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)

    status.verticalSplitWindow
    status.resize(100, 100)
    status.changeMode(Mode.ex)

    const Command = @[ru"q"]
    status.exModeCommand(Command)

    check status.bufStatus[0].mode == Mode.normal

suite "Ex mode: w! command":
  test "Run Force write command":
    const Filename = "forceWriteTest.txt"
    writeFile(Filename, "test")

    # Set readonly
    setFilePermissions(Filename, {fpUserRead})

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Filename).get
    status.resize(100, 100)

    status.bufStatus[0].buffer[0] = ru"abc"

    const Command = @[ru"w!"]
    status.exModeCommand(Command)

    let entireFile = readFile(Filename)
    check entireFile == "abc"

    removeFile(Filename)

suite "Ex mode: wq! command":
  test "Run Force write and close window":
    const Filename = "forceWriteAndQuitTest.txt"
    writeFile(Filename, "test")

    # Set readonly
    setFilePermissions(Filename, {fpUserRead})

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Filename).get
    status.resize(100, 100)

    status.verticalSplitWindow
    status.resize(100, 100)

    status.bufStatus[0].buffer[0] = ru"abc"

    const Command = @[ru"wq!"]
    status.exModeCommand(Command)
    check status.mainWindow.numOfMainWindow == 1

    let entireFile = readFile(Filename)
    check entireFile == "abc"

    removeFile(Filename)

suite "Ex mode: debug command":
  test "Start debug mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.changeMode(Mode.ex)

    status.resize(100, 100)
    status.update

    const Command = @[ru"debug"]
    status.exModeCommand(Command)

    status.resize(100, 100)
    status.update

    check status.mainWindow.numOfMainWindow == 2

    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[0].prevMode == Mode.ex

    check status.bufStatus[1].mode == Mode.debug
    check status.bufStatus[1].prevMode == Mode.debug

    check currentMainWindowNode.bufferIndex == 0

  test "Start debug mode (Disable all info)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.changeMode(Mode.ex)

    status.settings.debugMode.windowNode.enable = false
    status.settings.debugMode.bufStatus.enable = false

    status.resize(100, 100)
    status.update

    const Command = @[ru"debug"]
    status.exModeCommand(Command)

    status.resize(100, 100)
    status.update

    check status.mainWindow.numOfMainWindow == 2

    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[0].prevMode == Mode.ex

    check status.bufStatus[1].mode == Mode.debug
    check status.bufStatus[1].prevMode == Mode.debug

    check currentMainWindowNode.bufferIndex == 0

suite "Ex mode: highlight current line setting command":
  test "Enable current line highlighting":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"highlightCurrentLine", ru"off"]
    status.exModeCommand(Command)
    check not status.settings.view.highlightCurrentLine

  test "Disable current line highlighting":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"highlightCurrentLine", ru"on"]
    status.exModeCommand(Command)
    check status.settings.view.highlightCurrentLine

suite "Ex mode: Save Ex command history":
  test "Save \"noh\" command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Command = @[ru"noh"]
    status.exModeCommand(Command)

    check status.exCommandHistory == @[ru "noh"]

  test "Save \"noh\" command 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    for i in 0 ..< 2:
      const Command = @[ru"noh"]
      status.exModeCommand(Command)

    check status.exCommandHistory == @[ru "noh"]

  test "Save 2 Commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    block:
      const Command = @[ru"noh"]
      status.exModeCommand(Command)

    status.update

    block:
      const Command = @[ru"vs"]
      status.exModeCommand(Command)

    check status.exCommandHistory == @[ru "noh", ru "vs"]

  test "Fix #1304":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Command = @[ru"buildOnSave off"]
    status.exModeCommand(Command)

    check status.exCommandHistory == @[ru "buildOnSave off"]

suite "Ex mode: Open backup manager":
  test "backup command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.resize(100, 100)

    status.changeMode(Mode.ex)

    const Command = @[ru"backup"]
    status.exModeCommand(Command)

    currentMainWindowNode.isValidWindowSize

    check status.bufStatus.len == 2
    check status.bufStatus[0].isNormalMode
    check status.bufStatus[1].isBackupManagerMode

suite "saveExCommandHistory":
  test "Save command history 1":
    var commandHistory: seq[Runes]
    const
      Commands = @[@[ru"abb"], @[ru"cd"]]
      Limit = 1000

    for cmd in Commands:
      commandHistory.saveExCommandHistory(cmd, Limit)

    check commandHistory == @[Commands[0].join(ru" "), Commands[1].join(ru" ")]

  test "Save command history 2":
    var commandHistory: seq[Runes]
    const
      Commands = @[@[ru"ab"], @[ru"cd"]]
      Limit = 1

    for cmd in Commands:
      commandHistory.saveExCommandHistory(cmd, Limit)

    check commandHistory == @[Commands[1].join(ru" ")]

  test "Save command history 3":
    var commandHistory: seq[Runes]
    const
      Commands = @[@[ru"ab"], @[ru"cd"]]
      Limit = 0

    for cmd in Commands:
      commandHistory.saveExCommandHistory(cmd, Limit)
      check commandHistory.len == 0

  test "Save command history 4":
    var commandHistory: seq[Runes]
    const
      Commands = @[@[ru"q"], @[ru"Q"]]
      Limit = 1000

    for cmd in Commands:
      commandHistory.saveExCommandHistory(cmd, Limit)
      check commandHistory.len == 1

suite "Ex mode: Open configuration mode":
  test "Open config mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.openConfigMode

    # Check for crashes when updating
    status.update

suite "Ex mode: deleteTrailingSpaces":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"test  "])

    status.resize(100, 100)
    status.update

    status.deleteTrailingSpacesCommand
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[ru"test"]

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"test  "])
    currentMainWindowNode.currentColumn = 5

    status.resize(100, 100)
    status.update

    status.deleteTrailingSpacesCommand
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[ru"test"]
    check currentMainWindowNode.currentColumn == 3

  test "Only spaces":
    # NOTE: https://github.com/fox0430/moe/issues/1849
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  "])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    status.deleteTrailingSpacesCommand
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[ru""]
    check currentMainWindowNode.currentColumn == 0

suite "exmode: startRecentFileMode":
  test "start Recentfile mode":
    # NOTE: https://github.com/fox0430/moe/issues/1875
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    status.startRecentFileMode
    status.update

suite "exmode: openBufferManager":
  test "Open Buffer Manager 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    status.openBufferManager
    status.update

    check status.bufStatus[0].mode.isNormalMode
    check status.bufStatus[1].mode.isBufferManagerMode

    check mainWindow.numOfMainWindow == 2
