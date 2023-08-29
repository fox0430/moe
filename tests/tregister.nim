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

import std/[unittest, options]
import moepkg/[unicodeext, settings]

import moepkg/register {.all.}

suite "Register: Add a buffer to the no name register":
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

suite "Register: Add a buffer to the named register":
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

suite "Register: Add a buffer to the small delete register":
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

suite "Register: Add a buffer to the number register":
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

suite "Register: Search a register by name":
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
