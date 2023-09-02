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
import moepkg/[unicodeext, bufferstatus, gapbuffer, editorstatus, ui, windownode]

import moepkg/registers {.all.}
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
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd"].toSeqRunes
    status.execMacro(RegisterName.toRune)

    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Two dd commands":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd", "dd"].toSeqRunes
    status.execMacro(RegisterName.toRune)

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "j and dd commands":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
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
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"dd"
    status.execEditorCommand(Command)

    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes
    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Enter to Ex mode":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru":"
    status.execEditorCommand(Command)

    check currentBufStatus.isExMode

  test "Recoding commands":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    status.recodingOperationRegister = some(RegisterName.toRune)

    block:
      const Command = ru"dd"
      status.execEditorCommand(Command)

    block:
      const Command = ru"yy"
      status.execEditorCommand(Command)

    check registers.operationRegisters[RegisterName] ==
      @["dd", "yy"].toSeqRunes
    check currentBufStatus.buffer.toSeqRunes == @["2"].toSeqRunes

  test "Exec macro":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["j", "dd"].toSeqRunes

    const Command = ru"@a"
    status.execEditorCommand(Command)

    check currentBufStatus.buffer.toSeqRunes == @["1", "3"].toSeqRunes

  test "Exec macro 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["2dd"].toSeqRunes

    const Command = ru"@a"
    status.execEditorCommand(Command)

    check currentBufStatus.buffer.toSeqRunes == @["3"].toSeqRunes

  test "Exec macro 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2", "3"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @[":", "vs", "dd"].toSeqRunes

    const Command = ru"@a"
    status.execEditorCommand(Command)

    check currentBufStatus.buffer.toSeqRunes == @["2", "3"].toSeqRunes
    check mainWindow.numOfMainWindow == 2

  test "Repeat macro":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["1", "2"].toSeqRunes.initGapBuffer

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["dd"].toSeqRunes

    const Command = ru"2@a"
    status.execEditorCommand(Command)

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes
