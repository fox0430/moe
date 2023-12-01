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

import std/[unittest, tables, options]
import pkg/results
import moepkg/[unicodeext, bufferstatus, gapbuffer, editorstatus, ui,
               windownode, commandLine]

import moepkg/registers {.all.}
import moepkg/backupmanager {.all.}
import moepkg/exmode {.all.}
import moepkg/mainloop {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "mainloop: isExecMacroCommand":
  setup:
    initOperationRegisters()

  test "Except to true":
    let b = initBufferStatus("").get

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"@a"
    check b.isExecMacroCommand(Command)

  test "Except to true 2":
    let b = initBufferStatus("").get

    const RegisterName = '0'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"@0"
    check b.isExecMacroCommand(Command)

  test "Except to true 3":
    let b = initBufferStatus("").get

    const RegisterName = '0'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"1@0"
    check b.isExecMacroCommand(Command)

  test "Except to true 4":
    let b = initBufferStatus("").get

    const RegisterName = '0'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"10@0"
    check b.isExecMacroCommand(Command)

  test "Except to false":
    let b = initBufferStatus("").get

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru""
    check not b.isExecMacroCommand(Command)

  test "Except to false 2":
    let b = initBufferStatus("").get

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"@"
    check not b.isExecMacroCommand(Command)

  test "Except to false 3":
    var b = initBufferStatus("").get
    b.changeMode(Mode.insert)

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    const Command = ru"@a"
    check not b.isExecMacroCommand(Command)

  test "Except to false 4":
    var b = initBufferStatus("").get

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @[].toSeqRunes

    const Command = ru"@a"
    check not b.isExecMacroCommand(Command)

  test "Except to false 5":
    var b = initBufferStatus("").get

    const Command = ru"1@a"
    check not b.isExecMacroCommand(Command)

  test "Except to false 6":
    var b = initBufferStatus("").get

    const Command = ru"1@@"
    check not b.isExecMacroCommand(Command)

  test "Except to false 7":
    var b = initBufferStatus("").get

    const Command = ru"10"
    check not b.isExecMacroCommand(Command)

suite "mainloop: execMacro":
  setup:
    initOperationRegisters()

  test "Single dd command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd"].toSeqRunes
    status.execMacro(RegisterName.toRune)

    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Two dd commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd", "dd"].toSeqRunes
    status.execMacro(RegisterName.toRune)

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "j and dd commands":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["j", "dd"].toSeqRunes
    status.execMacro(RegisterName.toRune)

    check currentBufStatus.buffer.toSeqRunes == @["1", "3"].toSeqRunes

suite "mainloop: execEditorCommand":
  setup:
    initOperationRegisters()

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

    const RegisterName = 'a'
    status.recodingOperationRegister = some(RegisterName.toRune)

    block:
      const Command = ru"dd"
      check status.execEditorCommand(Command).isNone

    block:
      const Command = ru"yy"
      check status.execEditorCommand(Command).isNone

    check registers.operationRegisters[RegisterName] ==
      @["dd", "yy"].toSeqRunes
    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Exec macro":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["j", "dd"].toSeqRunes

    const Command = ru"@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["1", "3"].toSeqRunes

  test "Exec macro 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["2dd"].toSeqRunes

    const Command = ru"@a"
    check status.execEditorCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "Exec macro 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @[":", "vs", "dd"].toSeqRunes

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

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd"].toSeqRunes

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

    check status.registers.noNameRegisters == Register(
      name: "",
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

    check status.registers.noNameRegisters == Register(
      name: "",
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

    check status.registers.noNameRegisters == Register(
      name: "",
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

    check status.registers.noNameRegisters == Register(
      name: "",
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

    check status.registers.noNameRegisters == Register(
      name: "",
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

    check status.registers.noNameRegisters == Register(
      name: "",
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
