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

import std/[unittest, options, tables]
import pkg/results
import moepkg/[unicodeext, settings]

import moepkg/registers {.all.}

suite "registers: Add a buffer to the no name register":
  test "Add a string to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    registers.addRegister(ru "abc", settings)

    check registers.noNameRegisters == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: "")

  test "Overwrite a string in the no name register":
    var registers: Registers
    registers.noNameRegisters = Register(buffer: @[ru "abc"])
    let settings = initEditorSettings()

    registers.addRegister(ru "def", settings)

    check registers.noNameRegisters == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: "")

  test "Add a line to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    const isLine = true
    registers.addRegister(ru "abc", isLine, settings)

    check registers.noNameRegisters == Register(
      buffer: @[ru "abc"],
      isLine: true,
      name: "")

  test "Add 2 lines to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    const isLine = true
    registers.addRegister(@[ru "abc", ru "def"], isLine, settings)

    check registers.noNameRegisters == Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true,
      name: "")

suite "registers: Add a buffer to the named register":
  test "Add a string to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.addRegister(ru "abc", name, settings)

    check registers.namedRegisters[0] == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

  test "Overwrite a string to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.namedRegisters.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    registers.addRegister(ru "def", name, settings)

    check registers.namedRegisters[0] == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: name)

  test "Overwrite a line to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.namedRegisters.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    const isLine = true
    registers.addRegister(ru "def", isLine, name, settings)

    check registers.namedRegisters[0] == Register(
      buffer: @[ru "def"],
      isLine: true,
      name: name)

  test "Not added to the register (_ register)":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "_"
    registers.addRegister(ru "def", name, settings)

    check registers.namedRegisters.len == 0
    check registers.noNameRegisters == Register()

suite "registers: Add a buffer to the small delete register":
  test "Add a deleted string to the small deleted register":
    var registers: Registers
    let settings = initEditorSettings()

    const
      isLine = false
      isDelete = true
    registers.addRegister(ru "abc", isLine, isDelete, settings)
    registers.addRegister(ru "def", isLine, isDelete, settings)

    check registers.noNameRegisters == Register(buffer: @[ru "def"])

    check registers.smallDeleteRegisters == Register(buffer: @[ru "def"])

    for i in 0 ..< 10:
      let r = registers.numberRegisters[i]
      check r == Register()

suite "registers: Add a buffer to the number register":
  test "Add a yanked string to the number register":
    var registers: Registers
    let settings = initEditorSettings()

    registers.addRegister(ru "abc", settings)
    registers.addRegister(ru "def", settings)

    for i in 0 ..< 10:
      let r  = registers.numberRegisters[i]
      if i == 0:
        check r == Register(buffer: @[ru "def"])
      else:
        check r == Register()

  test "Add a line to the number register":
    var registers: Registers
    let settings = initEditorSettings()

    registers.addRegister(@[ru "abc"], settings)

    const
      isDelete = true
      isLine = true
    registers.addRegister(ru "def", isLine, isDelete, settings)

    for i in 0 ..< 10:
      let r = registers.numberRegisters[i]
      if i == 0:
        check r == Register(buffer: @[ru "abc"], isLine: true)
      elif i == 1:
        check r == Register(buffer: @[ru "def"], isLine: true)
      else:
        check r == Register()

suite "registers: Search a register by name":
  test "Search a register by name":
    var registers: Registers
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    registers.namedRegisters = @[r1, r2, r3]

    check registers.searchByName("b").isSome
    check registers.searchByName("b").get == r2

  test "Search a register by number string":
    var registers: Registers
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")

      r3 = Register(buffer: @[ru "ghi"], name: "0")

    registers.namedRegisters = @[r1, r2]
    registers.numberRegisters[0] = r3

    check registers.searchByName("0").isSome
    check registers.searchByName("0").get == r3

  test "Return empty":
    var registers: Registers
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    registers.namedRegisters = @[r1, r2, r3]

    check registers.searchByName("z").isNone

suite "registers: addOperationToNormalModeOperationsRegister":
  setup:
    normalModeOperationsRegister = @[]

  test "Add operations":
    addOperationToNormalModeOperationsRegister(ru"yy")
    addOperationToNormalModeOperationsRegister(ru"dd")

    check normalModeOperationsRegister == @["yy", "dd"].toSeqRunes

suite "registers: getOperationsFromNormalModeOperationsRegister":
  setup:
    normalModeOperationsRegister = @[]

  test "Get operations":
    addOperationToNormalModeOperationsRegister(ru"yy")
    addOperationToNormalModeOperationsRegister(ru"dd")

    check getOperationsFromNormalModeOperationsRegister() ==
      @["yy", "dd"].toSeqRunes

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
  setup:
    normalModeOperationsRegister = @[]

  test "Get operations":
    normalModeOperationsRegister = @["yy", "dd"].toSeqRunes

    check getLatestNormalModeOperation() == some(ru"dd")

  test "Except to none":
    check getLatestNormalModeOperation().isNone

suite "registers: clearOperationToRegister":
  setup:
    initOperationRegisters()

  test "Clear the operation register":
    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy"].toSeqRunes

    check clearOperationToRegister(RegisterName.toRune).isOk
    check registers.operationRegisters[RegisterName].len == 0

suite "registers: addOperationToRegister":
  setup:
    initOperationRegisters()

  test "Add operations":
    const RegisterName = 'a'

    block:
      const Operation = ru"yy"
      check addOperationToRegister(RegisterName.toRune, Operation).isOk

    block:
      const Operation = ru"dd"
      check addOperationToRegister(RegisterName.toRune, Operation).isOk

    check registers.operationRegisters[RegisterName] == @["yy", "dd"].toSeqRunes

suite "registers: getOperationsFromRegister":
  setup:
    initOperationRegisters()

  test "Get operations":
    const RegisterName = 'a'
    registers.operationRegisters[RegisterName] = @["yy", "dd"].toSeqRunes

    check getOperationsFromRegister(RegisterName.toRune).get ==
      @["yy", "dd"].toSeqRunes
