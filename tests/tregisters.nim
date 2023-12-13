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

import std/[unittest, options, tables, importutils, osproc, os]
import pkg/results
import moepkg/[unicodeext, settings, independentutils]
import utils

import moepkg/registers {.all.}

proc getClipboardBuffer(tool: ClipboardTool): string =
  case tool:
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

    check r.buffer == @["abc"].toSeqRunes
    check not r.isLine

  test "Lines":
    r.set(@["abc"].toSeqRunes)

    check r.buffer == @["abc"].toSeqRunes
    check r.isLine

  test "Lines 2":
    r.set(@["abc", "def"].toSeqRunes)

    check r.buffer == @["abc", "def"].toSeqRunes
    check r.isLine

  test "Overwrite":
    r.set(ru"abc")
    check r.buffer == @["abc"].toSeqRunes
    check not r.isLine

    r.set(ru"def")
    check r.buffer == @["def"].toSeqRunes
    check not r.isLine

suite "registers: setNoNamedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    r.setNoNamedRegister(ru"abc")

    check r.noNamed.buffer == @["abc"].toSeqRunes
    check not r.noNamed.isLine

  test "Lines":
    r.setNoNamedRegister(@["abc"].toSeqRunes)

    check r.noNamed.buffer == @["abc"].toSeqRunes
    check r.noNamed.isLine

  test "Lines 2":
    r.setNoNamedRegister(@["abc", "def"].toSeqRunes)

    check r.noNamed.buffer == @["abc", "def"].toSeqRunes
    check r.noNamed.isLine

  test "Overwrite":
    r.setNoNamedRegister(ru"abc")
    check r.noNamed.buffer == @["abc"].toSeqRunes
    check not r.noNamed.isLine

    r.setNoNamedRegister(ru"def")
    check r.noNamed.buffer == @["def"].toSeqRunes
    check not r.noNamed.isLine

  test "Runes with Clipboad (xsel)":
    if not isXAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xsel)
      r.setNoNamedRegister(ru"abc")

    check "abc" == getClipboardBuffer(ClipboardTool.xsel)

  test "Lines with Clipboad (xsel)":
    if not isXAvailable():
      skip()
    else:
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

    check r[0].buffer == @["abc"].toSeqRunes
    check not r[0].isLine

  test "Lines (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.set(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    check r[0].buffer == @["abc"].toSeqRunes
    check r[0].isLine

  test "Overwrite Yank register (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0

    r.set(ru"abc", RegisterNumber, IsShift)
    check r[0].buffer == @["abc"].toSeqRunes
    check not r[0].isLine

    r.set(ru"def", RegisterNumber, IsShift)
    check r[0].buffer == @["def"].toSeqRunes
    check not r[0].isLine

  test "Latest delete runes (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1
    r.set(ru"abc", RegisterNumber, IsShift)

    check r[1].buffer == @["abc"].toSeqRunes
    check not r[1].isLine

  test "Latest delete lines (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1
    r.set(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    check r[1].buffer == @["abc"].toSeqRunes
    check r[1].isLine

  test "Shift previous registers (Register 1 ~ 9)":
    for i in 1 .. 9:
      const
        IsShift = true
        RegisterNumber = 1
      r.set(toRunes($i), RegisterNumber, IsShift)

    var exceptBuffer = 9
    for i in 1 .. 9:
      check r[i].buffer == @[$exceptBuffer].toSeqRunes
      check not r[i].isLine

      exceptBuffer.dec

    # Stat shift
    for i in 1 .. 10:
      const
        IsShift = true
        RegisterNumber = 1
      r.set(toRunes($(i + 10)), RegisterNumber, IsShift)

      if i > 1 and i < 10:
        for j in countdown(i, 1):
          check r[j].buffer == @[$(i + 11 - j)].toSeqRunes
          check not r[j].isLine

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
          check r[i].buffer == @["a"].toSeqRunes
          check not r[i].isLine
        else:
          check r[i].buffer == @[$exceptBuffer].toSeqRunes
          check not r[i].isLine

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
          check r[i].buffer == @["a"].toSeqRunes
          check not r[i].isLine
        elif i == 5:
          check r[i].buffer == @["b"].toSeqRunes
          check not r[i].isLine
        else:
          check r[i].buffer == @[$exceptBuffer].toSeqRunes
          check not r[i].isLine

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
        check r.number[i].buffer == @["abc"].toSeqRunes
        check not r.number[i].isLine
      else:
        check r.number[i].buffer == @[].toSeqRunes
        check not r.number[i].isLine

  test "Lines (Register 0)":
    const
      IsShift = false
      RegisterNumber = 0
    r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)

    for i in 0 .. 9:
      if i == 0:
        check r.number[i].buffer == @["abc"].toSeqRunes
        check r.number[i].isLine
      else:
        check r.number[i].buffer == @[].toSeqRunes
        check not r.number[i].isLine

  test "Runes (Register 1)":
    const
      IsShift = false
      RegisterNumber = 1

    block:
      r.setNumberRegister(ru"abc", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setNumberRegister(ru"def", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["def"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

  test "Lines (Register 1)":
    const
      IsShift = false
      RegisterNumber = 1

    block:
      r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setNumberRegister(@["def"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["def"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

  test "Runes and shift (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1

    block:
      r.setNumberRegister(ru"abc", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setNumberRegister(ru"def", RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["def"].toSeqRunes
          check not r.number[i].isLine
        elif i == 2:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

  test "Lines and shift (Register 1)":
    const
      IsShift = true
      RegisterNumber = 1

    block:
      r.setNumberRegister(@["abc"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setNumberRegister(@["def"].toSeqRunes, RegisterNumber, IsShift)
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["def"].toSeqRunes
          check r.number[i].isLine
        elif i == 2:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

suite "registers: setYankedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    block:
      r.setYankedRegister(ru"abc")
      for i in 0 .. 9:
        if i == 0:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setYankedRegister(ru"def")
      for i in 0 .. 9:
        if i == 0:
          check r.number[i].buffer == @["def"].toSeqRunes
          check not r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

  test "Lines":
    block:
      r.setYankedRegister(@["abc"].toSeqRunes)
      for i in 0 .. 9:
        if i == 0:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setYankedRegister(@["def"].toSeqRunes)
      for i in 0 .. 9:
        if i == 0:
          check r.number[i].buffer == @["def"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

suite "registers: setDeletedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes (Small delete)":
    block:
      r.setDeletedRegister(ru"abc")
      check r.smallDelete.buffer == @["abc"].toSeqRunes
      check not r.smallDelete.isLine

    block:
      # Again.
      r.setDeletedRegister(ru"def")
      check r.smallDelete.buffer == @["def"].toSeqRunes
      check not r.smallDelete.isLine

  test "Lines":
    block:
      r.setDeletedRegister(@["abc"].toSeqRunes)
      check r.smallDelete.buffer == @[].toSeqRunes
      check not r.smallDelete.isLine

      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

    block:
      # Again.
      r.setDeletedRegister(@["def"].toSeqRunes)

      check r.smallDelete.buffer == @[].toSeqRunes
      check not r.smallDelete.isLine
      for i in 0 .. 9:
        if i == 1:
          check r.number[i].buffer == @["def"].toSeqRunes
          check r.number[i].isLine
        elif i == 2:
          check r.number[i].buffer == @["abc"].toSeqRunes
          check r.number[i].isLine
        else:
          check r.number[i].buffer == @[].toSeqRunes
          check not r.number[i].isLine

suite "registers: setNamedRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    block:
      const RegisterName = 'a'

      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName].buffer == @["abc"].toSeqRunes
      check not r.named[RegisterName].isLine

    block:
      const RegisterName = 'A'

      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName].buffer == @["abc"].toSeqRunes
      check not r.named[RegisterName].isLine

  test "Lines":
    block:
      const RegisterName = 'a'

      r.setNamedRegister(@["abc"].toSeqRunes, RegisterName)
      check r.named[RegisterName].buffer == @["abc"].toSeqRunes
      check r.named[RegisterName].isLine

    block:
      const RegisterName = 'A'

      r.setNamedRegister(@["abc"].toSeqRunes, RegisterName)
      check r.named[RegisterName].buffer == @["abc"].toSeqRunes
      check r.named[RegisterName].isLine

  test "Overwrite":
    const RegisterName = 'a'

    block:
      r.setNamedRegister(ru"abc", RegisterName)
      check r.named[RegisterName].buffer == @["abc"].toSeqRunes
      check not r.named[RegisterName].isLine

    block:
      # Again.
      r.setNamedRegister(ru"def", RegisterName)
      check r.named[RegisterName].buffer == @["def"].toSeqRunes
      check not r.named[RegisterName].isLine

suite "registers: setClipBoardRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "Runes":
    r.setClipBoardRegister(ru"abc")

    check r.clipboard.buffer == @["abc"].toSeqRunes
    check not r.clipboard.isLine

  test "Lines":
    r.setClipBoardRegister(@["abc"].toSeqRunes)

    check r.clipboard.buffer == @["abc"].toSeqRunes
    check r.clipboard.isLine

suite "registers: trySetClipBoardRegister":
  privateAccess(Registers)

  setup:
    var r = initRegisters()

  test "xsel: Runes":
    if not isXselAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xsel)

      assert clearXsel()
      assert setBufferToXsel("abc")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc"].toSeqRunes
      check not r.clipboard.isLine

      check r.noNamed.buffer == @["abc"].toSeqRunes
      check not r.noNamed.isLine

  test "xsel: Lines":
    if not isXselAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xsel)

      assert clearXsel()
      assert setBufferToXsel("abc\ndef")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc", "def"].toSeqRunes
      check r.clipboard.isLine

      check r.noNamed.buffer == @["abc", "def"].toSeqRunes
      check r.noNamed.isLine

  test "xclip: Runes":
    if not isXclipAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xclip)

      assert clearXclip()
      assert setBufferToXclip("abc")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc"].toSeqRunes
      check not r.clipboard.isLine

      check r.noNamed.buffer == @["abc"].toSeqRunes
      check not r.noNamed.isLine

  test "xclip: Lines":
    if not isXselAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xclip)

      assert clearXclip()
      assert setBufferToXsel("abc\ndef")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc", "def"].toSeqRunes
      check r.clipboard.isLine

      check r.noNamed.buffer == @["abc", "def"].toSeqRunes
      check r.noNamed.isLine

  test "wl-clipboard: Runes":
    if not isWlClipboardAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.wlClipboard)

      assert clearWlClipboard()
      assert setBufferToWlClipboard("abc")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc"].toSeqRunes
      check not r.clipboard.isLine

      check r.noNamed.buffer == @["abc"].toSeqRunes
      check not r.noNamed.isLine

  test "wl-clipboard: Lines":
    if not isWlClipboardAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.wlClipboard)

      assert clearWlClipboard()
      assert setBufferToWlClipboard("abc\ndef")

      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["abc", "def"].toSeqRunes
      check r.clipboard.isLine

      check r.noNamed.buffer == @["abc", "def"].toSeqRunes
      check r.noNamed.isLine

  test "Don't set":
    if not isXclipAvailable():
      skip()
    else:
      r.setClipboardTool(ClipboardTool.xclip)

      assert clearXclip()
      assert setBufferToXclip("abc")

      check r.trySetClipBoardRegister
      r.setYankedRegister(ru"def")

      # Again and ignore.
      check r.trySetClipBoardRegister

      check r.clipboard.buffer == @["def"].toSeqRunes
      check not r.clipboard.isLine

      check r.noNamed.buffer == @["def"].toSeqRunes
      check not r.noNamed.isLine

suite "registers: getClipBoardRegister":
  privateAccess(Registers)

  test "Basic":
    if not isXclipAvailable():
      skip()
    else:
      var registers = initRegisters()

      registers.setClipboardTool(ClipboardTool.xclip)

      assert clearXclip()
      assert setBufferToXclip("abc")

      check registers.trySetClipBoardRegister

      let r = registers.getClipBoardRegister

      check r.buffer == @["abc"].toSeqRunes
      check not r.isLine

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
