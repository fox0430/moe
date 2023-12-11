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

import std/[unittest, options, tables, importutils, osproc]
import pkg/results
import moepkg/[unicodeext, settings, independentutils]

import moepkg/registers {.all.}

proc isXAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0

proc isXselAvailable(): bool {.inline.} =
  isXAvailable() and execCmdExNoOutput("xsel --version") == 0

proc isXclipAvailable(): bool {.inline.} =
  isXAvailable() and execCmdExNoOutput("xclip -version") == 0

proc getClipboardBuffer(tool: ClipboardTool): string =
  case tool:
    of none:
      discard
    of xsel:
      let r = execCmdEx("xsel -o")
      return r.output[0 .. r.output.high - 1]
    of xclip:
      let r =execCmdEx("xclip -o")
      return r.output[0 .. r.output.high - 1]
    of wlClipboard:
      let r = execCmdEx("wl-paste")
      return r.output[0 .. r.output.high - 1]
    of wslDefault:
      # On the WSL
      let r = execCmdEx("powershell.exe -Command Get-Clipboard")
      return r.output[0 .. r.output.high - 2]
    of macOsDefault:
      let r = execCmdEx("pbpaste -o")
      return r.output[0 .. r.output.high - 1]

suite "registers: update (Register)":
  setup:
    var r = Register()

  test "Runes":
    r.set(ru"abc")

    check r == Register(buffer: @["abc"].toSeqRunes, isLine: false)

  test "Lines":
    r.set(@["abc"].toSeqRunes)

    check r == Register(buffer: @["abc"].toSeqRunes, isLine: true)

  test "Lines 2":
    r.set(@["abc", "def"].toSeqRunes)

    check r == Register(buffer: @["abc", "def"].toSeqRunes, isLine: true)

  test "Overwrite":
    r.set(ru"abc")
    check r == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    r.set(ru"def")
    check r == Register(buffer: @["def"].toSeqRunes, isLine: false)

suite "registers: setNoNamedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    r.setNoNamedRegister(ru"abc")

    check r.noNamed == Register(buffer: @["abc"].toSeqRunes, isLine: false)

  test "Lines":
    r.setNoNamedRegister(@["abc"].toSeqRunes)

    check r.noNamed == Register(buffer: @["abc"].toSeqRunes, isLine: true)

  test "Lines 2":
    r.setNoNamedRegister(@["abc", "def"].toSeqRunes)

    check r.noNamed == Register(
      buffer: @["abc", "def"].toSeqRunes,
      isLine: true)

  test "Overwrite":
    r.setNoNamedRegister(ru"abc")
    check r.noNamed == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    r.setNoNamedRegister(ru"def")
    check r.noNamed == Register(buffer: @["def"].toSeqRunes, isLine: false)

  test "Runes with Clipboad (xsel)":
    if not isXAvailable(): skip()

    r.setClipboardTool(ClipboardTool.xsel)
    r.setNoNamedRegister(ru"abc")

    check "abc" == getClipboardBuffer(ClipboardTool.xsel)

  test "Lines with Clipboad (xsel)":
    if not isXAvailable(): skip()

    r.setClipboardTool(ClipboardTool.xsel)
    r.setNoNamedRegister(@["abc", "def"].toSeqRunes)

    check "abc\ndef" == getClipboardBuffer(ClipboardTool.xsel)

suite "registers: update (NumberRegister)":
  setup:
    var r: NumberRegisters

  test "Runes (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.set(ru"abc", RegisterNumber, IsShift)

    check r[0] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

  test "Lines (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.set(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    check r[0] == Register(buffer: @["abc"].toSeqRunes, isLine: true)

  test "Overwrite Yank register (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0

    r.set(ru"abc", RegisterNumber, IsShift)
    check r[0] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    r.set(ru"def", RegisterNumber, IsShift)
    check r[0] == Register(buffer: @["def"].toSeqRunes, isLine: false)

  test "Latest delete runes (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1
    r.set(ru"abc", RegisterNumber, IsShift)

    check r[1] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

  test "Latest delete lines (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1
    r.set(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    check r[1] == Register(buffer: @["abc"].toSeqRunes, isLine: true)

  test "Shift previous registers (Register 1 ~ 9)":
    for i in 1 .. 9:
      const
        IsShift = true
        RegisterNumber = 1
      r.set(toRunes($i), RegisterNumber, IsShift)

    var exceptBuffer = 9
    for i in 1 .. 9:
      check r[i] == Register(buffer: @[toRunes($exceptBuffer)], isLine: false)
      exceptBuffer.dec

    # Stat shift
    for i in 1 .. 10:
      const
        IsShift = true
        RegisterNumber = 1
      r.set(toRunes($(i + 10)), RegisterNumber, IsShift)

      if i > 1 and i < 10:
        for j in countdown(i, 1):
          check r[j] == Register(
            buffer: @[$(i + 11 - j)].toSeqRunes,
            isLine: false)

  test "Don't shift":
    for i in 1 .. 9:
      # Prepare registers
      const
        IsShift = true
        RegisterNumber = 1
      r.set(toRunes($i), RegisterNumber, IsShift)

    block:
      # Set to 1
      const
        IsShift = false
        RegisterNumber = 1
      r.set(ru"a", RegisterNumber, IsShift)

      var exceptBuffer = 9
      for i in 1 .. 9:
        if i == 1:
          check r[i] == Register(buffer: @["a"].toSeqRunes, isLine: false)
        else:
          check r[i] == Register(buffer: @[$exceptBuffer].toSeqRunes, isLine: false)

        exceptBuffer.dec

    block:
      # Set to 5
      const
        IsShift = false
        RegisterNumber = 5
      r.set(ru"b", RegisterNumber, IsShift)

      var exceptBuffer = 9
      for i in 1 .. 9:
        if i == 1:
          check r[i] == Register(buffer: @["a"].toSeqRunes, isLine: false)
        elif i == 5:
          check r[i] == Register(buffer: @["b"].toSeqRunes, isLine: false)
        else:
          check r[i] == Register(buffer: @[$exceptBuffer].toSeqRunes, isLine: false)

        exceptBuffer.dec

suite "registers: setNumberRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.setNumberRegister(ru"abc", RegisterNumber, IsShift)

    for i in 0 .. 9:
      if i == 0:
        check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: false)
      else:
        check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Lines (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    for i in 0 .. 9:
      if i == 0:
        check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
      else:
        check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Runes (Register 1)":
    const
      IsShift = false
      RegisterNumber = 1

    block:
      r.setNumberRegister(ru"abc", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setNumberRegister(ru"def", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Lines (Register 1)":
    const
      IsShift = false
      RegisterNumber = 1

    block:
      r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setNumberRegister(@["def"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Runes and shift (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1

    block:
      r.setNumberRegister(ru"abc", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setNumberRegister(ru"def", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: false)
        elif i == 2:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Lines and shift (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1

    block:
      r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setNumberRegister(@["def"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: true)
        elif i == 2:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

suite "registers: setYankedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    block:
      r.setYankedRegister(ru"abc")
      for i in 0 .. 9:
        if i == 0:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setYankedRegister(ru"def")
      for i in 0 .. 9:
        if i == 0:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: false)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

  test "Lines":
    block:
      r.setYankedRegister(@["abc"].toSeqRunes)
      for i in 0 .. 9:
        if i == 0:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setYankedRegister(@["def"].toSeqRunes)
      for i in 0 .. 9:
        if i == 0:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

suite "registers: setDeletedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes (Small delete)":
    block:
      r.setDeletedRegister(ru"abc")
      check r.smallDelete == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setDeletedRegister(ru"def")
      check r.smallDelete == Register(buffer: @["def"].toSeqRunes, isLine: false)

  test "Lines":
    block:
      r.setDeletedRegister(@["abc"].toSeqRunes)
      check r.smallDelete == Register(buffer: @[].toSeqRunes, isLine: false)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setDeletedRegister(@["def"].toSeqRunes)
      check r.smallDelete == Register(buffer: @[].toSeqRunes, isLine: false)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i] == Register(buffer: @["def"].toSeqRunes, isLine: true)
        elif i == 2:
          check r.number[i] == Register(buffer: @["abc"].toSeqRunes, isLine: true)
        else:
          check r.number[i] == Register(buffer: @[].toSeqRunes, isLine: false)

suite "registers: setNamedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    block:
      const RegisterName = 'a'

      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    block:
      const RegisterName = 'A'

      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

  test "Lines":
    block:
      const RegisterName = 'a'

      r.setNamedRegister(@["abc"].toSeqRunes, RegisterName)
      check r.named[RegisterName] == Register(buffer: @["abc"].toSeqRunes, isLine: true)

    block:
      const RegisterName = 'A'

      r.setNamedRegister(@["abc"].toSeqRunes, RegisterName)
      check r.named[RegisterName] == Register(buffer: @["abc"].toSeqRunes, isLine: true)

  test "Overwrite":
    const RegisterName = 'a'

    block:
      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName] == Register(buffer: @["abc"].toSeqRunes, isLine: false)

    block:
      # Again.
      r.setNamedRegister(ru"def", RegisterName)
      check r.named[RegisterName] == Register(buffer: @["def"].toSeqRunes, isLine: false)


suite "registers: addNormalModeOperation":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Add 2 operations":
    r.addNormalModeOperation(ru"yy")
    r.addNormalModeOperation(ru"dd")

    check r.normalModeOperations == NormalModeOperationsRegister(
      commands: @["yy", "dd"].toSeqRunes)

suite "registers: getNormalModeOperations":
  setup:
    var r = initRegisters()

  test "Get 2 operations":
    r.addNormalModeOperation(ru"yy")
    r.addNormalModeOperation(ru"dd")

    check r.getNormalModeOperations == NormalModeOperationsRegister(
      commands: @["yy", "dd"].toSeqRunes)

suite "registers: isOperationRegisterName":
  test "Except to true":
    for ch in '0'..'9':
      check isOperationRegisterName(ch.toRune)

  test "Except to true 2":
    for ch in 'A'..'Z':
      check isOperationRegisterName(ch.toRune)

  test "Except to true 3":
    for ch in 'a'..'z':
      check isOperationRegisterName(ch.toRune)

  test "Except to false":
    check not isOperationRegisterName(ru'@')

suite "registers: getLatestNormalModeOperation":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Get 2 operations":
    r.addNormalModeOperation ru"yy"
    r.addNormalModeOperation ru"dd"

    check r.getLatestNormalModeOperation == some(ru"dd")

  test "Except to none":
    check r.getLatestNormalModeOperation.isNone

suite "registers: clearOperations":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Clear the operation register":
    const RegisterName = 'a'
    check r.addOperation(RegisterName.toRune, ru"yy").isOk

    check r.clearOperations(RegisterName.toRune).isOk
    check r.operations[RegisterName].commands.len == 0

suite "registers: addOperation":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Add 2 operations":
    const RegisterName = 'a'

    block:
      const Operation = ru"yy"
      check r.addOperation(RegisterName.toRune, Operation).isOk

    block:
      const Operation = ru"dd"
      check r.addOperation(RegisterName.toRune, Operation).isOk

    check r.operations[RegisterName].commands == @["yy", "dd"].toSeqRunes

suite "registers: getOperations":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Get 2 operations":
    const RegisterName = 'a'
    check r.addOperation(RegisterName.toRune, ru"yy").isOk
    check r.addOperation(RegisterName.toRune, ru"dd").isOk

    check r.getOperations(RegisterName.toRune).get.commands ==
      @["yy", "dd"].toSeqRunes
