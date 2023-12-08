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

import std/[unittest, options, importutils]
import pkg/results
import moepkg/[unicodeext, bufferstatus, gapbuffer, editorstatus, windownode,
               ui, commandLine, viewhighlight, visualmode, suggestionwindow,
               independentutils]

import moepkg/registers {.all.}
import moepkg/backupmanager {.all.}
import moepkg/exmode {.all.}
import moepkg/insertmode {.all.}
import moepkg/mainloop {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "mainloop: isExecMacroCommand":
  setup:
    var registers = initRegisters()

  test "Except to true":
    let b = initBufferStatus("").get

    const
      RegisterName = ru'a'
      Operation = ru"yy"
    check registers.addOperation(RegisterName, Operation).isOk

    const Command = ru"@a"
    check b.isExecMacroCommand(registers, Command)

  test "Except to true 2":
    let b = initBufferStatus("").get

    const RegisterName = ru'0'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru"@0"
    check b.isExecMacroCommand(registers, Command)

  test "Except to true 3":
    let b = initBufferStatus("").get

    const RegisterName = ru'0'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru"1@0"
    check b.isExecMacroCommand(registers, Command)

  test "Except to true 4":
    let b = initBufferStatus("").get

    const RegisterName = ru'0'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru"10@0"
    check b.isExecMacroCommand(registers, Command)

  test "Except to false":
    let b = initBufferStatus("").get

    const RegisterName = ru'a'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru""
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 2":
    let b = initBufferStatus("").get

    const RegisterName = ru'a'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru"@"
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 3":
    var b = initBufferStatus("").get
    b.changeMode(Mode.insert)

    const RegisterName = ru'a'
    check registers.addOperation(RegisterName, ru"yy").isOk

    const Command = ru"@a"
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 4":
    var b = initBufferStatus("").get

    const RegisterName = ru'a'
    check not registers.addOperation(RegisterName, ru"").isOk

    const Command = ru"@a"
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 5":
    var b = initBufferStatus("").get

    const Command = ru"1@a"
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 6":
    var b = initBufferStatus("").get

    const Command = ru"1@@"
    check not b.isExecMacroCommand(registers, Command)

  test "Except to false 7":
    var b = initBufferStatus("").get

    const Command = ru"10"
    check not b.isExecMacroCommand(registers, Command)

suite "mainloop: execMacro":
  test "Single dd command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru"dd").isOk
    status.execMacro(RegisterName)

    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Two dd commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    for i in 0 .. 1:
      check status.registers.addOperation(RegisterName, ru"dd").isOk
    status.execMacro(RegisterName)

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "j and dd commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru"j").isOk
    check status.registers.addOperation(RegisterName, ru"dd").isOk
    status.execMacro(RegisterName)

    check currentBufStatus.buffer.toSeqRunes == @["1", "3"].toSeqRunes

suite "mainloop: execEditorCommand":
  test "Exec normal mode commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"dd"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes
    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Enter to Ex mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru":"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.isExMode

  test "Recoding commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    status.recodingOperationRegister = some(RegisterName)

    block:
      const Command = ru"dd"
      check status.execEditorCommand(Command).isNone

    block:
      const Command = ru"yy"
      check status.execEditorCommand(Command).isNone

    check status.registers.addOperation(RegisterName, ru"dd").isOk
    check status.registers.addOperation(RegisterName, ru"yy").isOk
    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Exec macro":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru"j").isOk
    check status.registers.addOperation(RegisterName, ru"dd").isOk

    const Command = ru"@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["1", "3"].toSeqRunes

  test "Exec macro 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru"2dd").isOk

    const Command = ru"@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "Exec macro 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru":").isOk
    check status.registers.addOperation(RegisterName, ru"vs").isOk
    check status.registers.addOperation(RegisterName, ru"dd").isOk

    const Command = ru"@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["2", "3"].toSeqRunes
    check mainWindow.numOfMainWindow == 2

  test "Repeat macro":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = ru'a'
    check status.registers.addOperation(RegisterName, ru"dd").isOk

    const Command = ru"2@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

suite "mainloop: insertPasteBuffer":
  test "Ignore":
    for mode in Mode:
      case mode:
        of insert,
           insertMulti,
           replace,
           ex,
           searchForward,
           searchBackward:
             continue
        else:
          var status = initEditorStatus()

          case mode:
            of filer:
              discard status.addNewBufferInCurrentWin("./", mode).get
            of backup:
              discard status.addNewBufferInCurrentWin().get
              status.startBackupManager
            of diff:
              discard status.addNewBufferInCurrentWin().get
              status.openDiffViewer("")
            else:
              discard status.addNewBufferInCurrentWin(mode).get

          currentBufStatus.buffer = @[""].toSeqRunes.initGapBuffer

          if currentBufStatus.isVisualMode:
            currentBufStatus.selectedArea = initSelectedArea(
              currentMainWindowNode.currentLine,
              currentMainWindowNode.currentColumn)
              .some

          status.resize(100, 100)
          status.update

          let beforeBuffer = currentBufStatus.buffer

          const PasteBuffer = @["abc"].toSeqRunes
          status.insertPasteBuffer(PasteBuffer)

          check currentBufStatus.buffer == beforeBuffer

  test "Insert mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.insert).get
    currentBufStatus.buffer = @[""].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["abc"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["abc"].toSeqRunes,
      isLine: false)

  test "Insert mode 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.insert).get
    currentBufStatus.buffer = @["abc"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["axyzbc"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["xyz"].toSeqRunes,
      isLine: false)

  test "Insert mode 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.insert).get
    currentBufStatus.buffer = @[""].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["a", "b", "c"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["", "a", "b", "c"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["a", "b", "c"].toSeqRunes,
      isLine: true)

  test "Replace mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.replace).get
    currentBufStatus.buffer = @[""].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["abc"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["abc"].toSeqRunes,
      isLine: false)

  test "Replace mode 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.replace).get
    currentBufStatus.buffer = @["abc"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["xyz"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["xyz"].toSeqRunes,
      isLine: false)

  test "Replace mode 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.replace).get
    currentBufStatus.buffer = @["abcd"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["x", "y", "z"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check currentBufStatus.buffer.toSeqRunes == @["x", "y", "zd"].toSeqRunes

    check status.registers.getNoNamedRegister == Register(
      buffer: @["x", "y", "z"].toSeqRunes,
      isLine: true)

  test "Ex mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.ex).get

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["abc"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abc"

  test "Ex mode 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.ex).get
    status.commandLine.buffer = ru"abc"
    status.commandLine.moveEnd

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abcxyz"

  test "Ex mode 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.ex).get
    status.commandLine.buffer = ru"abc"
    status.commandLine.moveEnd

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abcxyz"

  test "Ex mode 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.ex).get
    status.commandLine.buffer = ru""
    status.commandLine.moveEnd

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["a", "b", "c"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"a\nb\nc"

  test "Search mode":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.searchForward).get

    status.searchHistory = @[ru""]

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["abc"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abc"

  test "Search mode 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.searchForward).get
    status.commandLine.buffer = ru"abc"
    status.commandLine.moveEnd

    status.searchHistory = @[ru""]

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abcxyz"

  test "Search mode 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.searchForward).get
    status.commandLine.buffer = ru"abc"
    status.commandLine.moveEnd

    status.searchHistory = @[ru""]

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["xyz"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"abcxyz"

  test "Search mode 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin(Mode.searchForward).get
    status.commandLine.buffer = ru""
    status.commandLine.moveEnd

    status.searchHistory = @[ru""]

    status.resize(100, 100)
    status.update

    const PasteBuffer = @["a", "b", "c"].toSeqRunes
    status.insertPasteBuffer(PasteBuffer)

    check status.commandLine.buffer == ru"a\nb\nc"

suite "mainloop: jumpAndHighlightInReplaceCommand":
  test "Check jump":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    status.searchHistory = @[ru""]

    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    status.commandLine.buffer = ru"%s/a"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    status.commandLine.buffer = ru"%s/ab"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    status.commandLine.buffer = ru"%s/abc"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0
  test "Check jump 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["", "abc", "", "abc"].toSeqRunes.toGapBuffer
    status.searchHistory = @[ru""]

    status.resize(100, 100)
    status.update

    status.commandLine.buffer = ru"%s/a"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    status.commandLine.buffer = ru"%s/ab"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    status.commandLine.buffer = ru"%s/abc"
    status.jumpAndHighlightInReplaceCommand
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

suite "mainloop: jumpAndHighlightInReplaceCommand":
  test "Ignore":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["", "abc"].toSeqRunes.toGapBuffer

    status.commandLine.buffer = ru"%s/"

    status.jumpAndHighlightInReplaceCommand

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

    check status.highlightingText.isNone

  test "Ignore 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc"].toSeqRunes.toGapBuffer

    status.commandLine.buffer = ru"%s/abc/def"

    status.jumpAndHighlightInReplaceCommand

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

    check status.highlightingText.isNone

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["  abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    block:
      status.commandLine.buffer = ru"%s/a"
      status.jumpAndHighlightInReplaceCommand

      check currentMainWindowNode.currentLine == 0
      check currentMainWindowNode.currentColumn == 2

      check status.highlightingText.get.kind ==  HighlightingTextKind.replace
      check status.highlightingText.get.text == @["a"].toSeqRunes

    block:
      status.commandLine.buffer = ru"%s/ab"
      status.jumpAndHighlightInReplaceCommand

      check currentMainWindowNode.currentLine == 0
      check currentMainWindowNode.currentColumn == 2

      check status.highlightingText.get.kind ==  HighlightingTextKind.replace
      check status.highlightingText.get.text == @["ab"].toSeqRunes

    block:
      status.commandLine.buffer = ru"%s/abc"
      status.jumpAndHighlightInReplaceCommand

      check currentMainWindowNode.currentLine == 0
      check currentMainWindowNode.currentColumn == 2

      check status.highlightingText.get.kind ==  HighlightingTextKind.replace
      check status.highlightingText.get.text == @["abc"].toSeqRunes

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.commandLine.buffer = ru"%s/def"
    status.jumpAndHighlightInReplaceCommand

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    check status.highlightingText.get.kind ==  HighlightingTextKind.replace
    check status.highlightingText.get.text == @["def"].toSeqRunes

suite "mainloop: initBeforeLineForIncrementalReplace":
  privateAccess(BeforeLine)

  test "Ignore":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc"]
      .toSeqRunes
      .toGapBuffer

    status.commandLine.buffer = ru"%s/abc"

    check status.initBeforeLineForIncrementalReplace.len == 0

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc"]
      .toSeqRunes
      .toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz"

    check status.initBeforeLineForIncrementalReplace == @[
      BeforeLine(lineNumber: 0, lineBuffer: ru"abc"),
      BeforeLine(lineNumber: 1, lineBuffer: ru"abc def"),
      BeforeLine(lineNumber: 3, lineBuffer: ru"def abc")
    ]

  test "Replace all":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc"]
      .toSeqRunes
      .toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz/g"

    check status.initBeforeLineForIncrementalReplace == @[
      BeforeLine(lineNumber: 0, lineBuffer: ru"abc"),
      BeforeLine(lineNumber: 1, lineBuffer: ru"abc def"),
      BeforeLine(lineNumber: 3, lineBuffer: ru"def abc")
    ]

suite "mainloop: execIncrementalReplace":
  privateAccess(IncrementalReplaceInfo)

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    let incReplaceInfo = IncrementalReplaceInfo(
      sub: ru"abc",
      by: ru"xyz",
      isGlobal: false,
      beforeLines: status.initBeforeLineForIncrementalReplace)

    status.execIncrementalReplace(incReplaceInfo)

    check currentBufStatus.buffer.toSeqRunes == @[
      "xyz", "xyz def", "", "def xyz", "xyz abc"]
      .toSeqRunes

  test "Replace all":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    let incReplaceInfo = IncrementalReplaceInfo(
      sub: ru"abc",
      by: ru"xyz",
      isGlobal: true,
      beforeLines: status.initBeforeLineForIncrementalReplace)

    status.execIncrementalReplace(incReplaceInfo)

    check currentBufStatus.buffer.toSeqRunes == @[
      "xyz", "xyz def", "", "def xyz", "xyz xyz"]
      .toSeqRunes

suite "mainloop: incrementalReplace":
  privateAccess(BeforeLine)
  privateAccess(IncrementalReplaceInfo)

  test "Init and replace":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz"

    var incReplaceInfo = none(IncrementalReplaceInfo)
    status.incrementalReplace(incReplaceInfo)

    check incReplaceInfo.get.sub == ru"abc"
    check incReplaceInfo.get.by == ru"xyz"
    check not incReplaceInfo.get.isGlobal

    check incReplaceInfo.get.beforeLines[0].lineNumber == 0
    check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"

  test "Init and replace 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz/g"

    var incReplaceInfo = none(IncrementalReplaceInfo)
    status.incrementalReplace(incReplaceInfo)

    check incReplaceInfo.get.sub == ru"abc"
    check incReplaceInfo.get.by == ru"xyz"
    check incReplaceInfo.get.isGlobal

    check incReplaceInfo.get.beforeLines[0].lineNumber == 0
    check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"

    check currentBufStatus.buffer.toSeqRunes == @["xyz"].toSeqRunes

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz"

    var incReplaceInfo = none(IncrementalReplaceInfo)
    status.incrementalReplace(incReplaceInfo)

    check incReplaceInfo.get.sub == ru"abc"
    check incReplaceInfo.get.by == ru"xyz"
    check not incReplaceInfo.get.isGlobal

    check incReplaceInfo.get.beforeLines[0].lineNumber == 0
    check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
    check incReplaceInfo.get.beforeLines[1].lineNumber == 1
    check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
    check incReplaceInfo.get.beforeLines[2].lineNumber == 3
    check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
    check incReplaceInfo.get.beforeLines[3].lineNumber == 4
    check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

    check currentBufStatus.buffer.toSeqRunes == @[
      "xyz", "xyz def", "", "def xyz", "xyz abc"]
      .toSeqRunes

  test "Replace all":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    status.commandLine.buffer = ru"%s/abc/xyz/g"

    var incReplaceInfo = none(IncrementalReplaceInfo)
    status.incrementalReplace(incReplaceInfo)

    check incReplaceInfo.get.sub == ru"abc"
    check incReplaceInfo.get.by == ru"xyz"
    check incReplaceInfo.get.isGlobal

    check incReplaceInfo.get.beforeLines[0].lineNumber == 0
    check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
    check incReplaceInfo.get.beforeLines[1].lineNumber == 1
    check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
    check incReplaceInfo.get.beforeLines[2].lineNumber == 3
    check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
    check incReplaceInfo.get.beforeLines[3].lineNumber == 4
    check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

    check currentBufStatus.buffer.toSeqRunes == @[
      "xyz", "xyz def", "", "def xyz", "xyz xyz"]
      .toSeqRunes

  test "Restore lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    var incReplaceInfo = none(IncrementalReplaceInfo)

    block:
      status.commandLine.buffer = ru"%s/abc/x"
      status.incrementalReplace(incReplaceInfo)

      check incReplaceInfo.get.sub == ru"abc"
      check incReplaceInfo.get.by == ru"x"
      check not incReplaceInfo.get.isGlobal

      check incReplaceInfo.get.beforeLines[0].lineNumber == 0
      check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
      check incReplaceInfo.get.beforeLines[1].lineNumber == 1
      check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
      check incReplaceInfo.get.beforeLines[2].lineNumber == 3
      check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
      check incReplaceInfo.get.beforeLines[3].lineNumber == 4
      check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

      check currentBufStatus.buffer.toSeqRunes == @[
        "x", "x def", "", "def x", "x abc"]
        .toSeqRunes

    block:
      status.commandLine.buffer = ru"%s/abc/z"
      status.incrementalReplace(incReplaceInfo)

      check incReplaceInfo.get.sub == ru"abc"
      check incReplaceInfo.get.by == ru"z"
      check not incReplaceInfo.get.isGlobal

      check incReplaceInfo.get.beforeLines[0].lineNumber == 0
      check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
      check incReplaceInfo.get.beforeLines[1].lineNumber == 1
      check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
      check incReplaceInfo.get.beforeLines[2].lineNumber == 3
      check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
      check incReplaceInfo.get.beforeLines[3].lineNumber == 4
      check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

      check currentBufStatus.buffer.toSeqRunes == @[
        "z", "z def", "", "def z", "z abc"]
        .toSeqRunes

  test "Restore lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc", "abc def", "", "def abc", "abc abc"]
      .toSeqRunes
      .toGapBuffer

    var incReplaceInfo = none(IncrementalReplaceInfo)

    block:
      status.commandLine.buffer = ru"%s/abc/x"
      status.incrementalReplace(incReplaceInfo)

      check incReplaceInfo.get.sub == ru"abc"
      check incReplaceInfo.get.by == ru"x"
      check not incReplaceInfo.get.isGlobal

      check incReplaceInfo.get.beforeLines[0].lineNumber == 0
      check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
      check incReplaceInfo.get.beforeLines[1].lineNumber == 1
      check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
      check incReplaceInfo.get.beforeLines[2].lineNumber == 3
      check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
      check incReplaceInfo.get.beforeLines[3].lineNumber == 4
      check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

      check currentBufStatus.buffer.toSeqRunes == @[
        "x", "x def", "", "def x", "x abc"]
        .toSeqRunes

    block:
      status.commandLine.buffer = ru"%s/abc/x/g"
      status.incrementalReplace(incReplaceInfo)

      check incReplaceInfo.get.sub == ru"abc"
      check incReplaceInfo.get.by == ru"x"
      check incReplaceInfo.get.isGlobal

      check incReplaceInfo.get.beforeLines[0].lineNumber == 0
      check incReplaceInfo.get.beforeLines[0].lineBuffer == ru"abc"
      check incReplaceInfo.get.beforeLines[1].lineNumber == 1
      check incReplaceInfo.get.beforeLines[1].lineBuffer == ru"abc def"
      check incReplaceInfo.get.beforeLines[2].lineNumber == 3
      check incReplaceInfo.get.beforeLines[2].lineBuffer == ru"def abc"
      check incReplaceInfo.get.beforeLines[3].lineNumber == 4
      check incReplaceInfo.get.beforeLines[3].lineBuffer == ru"abc abc"

      check currentBufStatus.buffer.toSeqRunes == @[
        "x", "x def", "", "def x", "x x"]
        .toSeqRunes

suite "mainloop: updateAfterInsertFromSuggestion":
  privateAccess(SuggestionWindow)

  test "Ignore":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc a"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insert
    currentMainWindowNode.currentColumn = 5

    status.tryOpenSuggestWindow
    check status.suggestionWindow.get.suggestoins == @["abc"].toSeqRunes

    status.updateAfterInsertFromSuggestion

    check currentBufStatus.buffer.toSeqRunes == @["abc a"].toSeqRunes

  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc a"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insert
    currentMainWindowNode.currentColumn = 5

    status.tryOpenSuggestWindow
    check status.suggestionWindow.get.suggestoins == @["abc"].toSeqRunes

    status.suggestionWindow.get.selectedSuggestion = 0
    status.updateAfterInsertFromSuggestion

    check currentBufStatus.buffer.toSeqRunes == @["abc abc"].toSeqRunes

  test "Multi lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin().get
    currentBufStatus.buffer = @["abc ", "def xyz", "", "ghi xyz"].toSeqRunes.toGapBuffer
    currentBufStatus.selectedArea = SelectedArea(
      startLine: 0,
      startColumn: 5,
      endLine: 3,
      endColumn: 5)
      .some
    currentBufStatus.mode = Mode.insertMulti
    currentMainWindowNode.currentColumn = 4

    status.insertToBuffer(ru'a')

    status.tryOpenSuggestWindow
    check status.suggestionWindow.get.suggestoins == @["axyz", "abc"].toSeqRunes

    status.suggestionWindow.get.selectedSuggestion = 1
    status.updateAfterInsertFromSuggestion

    check currentBufStatus.buffer.toSeqRunes == @[
      "abc abc", "def abcxyz", "", "ghi abcxyz"].toSeqRunes
