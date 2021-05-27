import unittest, options
import moepkg/unicodeext
include moepkg/[register]

suite "Register: Add a buffer to the no name register":
  test "Add a string to the no name register":
    var registers: Registers

    registers.addRegister(ru "abc")

    check registers.noNameRegister == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: "")

  test "Overwrite a string in the no name register":
    var registers: Registers
    registers.noNameRegister = Register(buffer: @[ru "abc"])

    registers.addRegister(ru "def")

    check registers.noNameRegister == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: "")

  test "Add a line to the no name register":
    var registers: Registers

    const isLine = true
    registers.addRegister(ru "abc", isLine)

    check registers.noNameRegister == Register(
      buffer: @[ru "abc"],
      isLine: true,
      name: "")

  test "Add 2 lines to the no name register":
    var registers: Registers

    const isLine = true
    registers.addRegister(@[ru "abc", ru "def"], isLine)

    check registers.noNameRegister == Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true,
      name: "")

suite "Register: Add a buffer to the named register":
  test "Add a string to the named register":
    var registers: Registers

    const name = "a"
    registers.addRegister(ru "abc", name)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

  test "Overwrite a string to the named register":
    var registers: Registers
    const name = "a"
    registers.namedRegister.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    registers.addRegister(ru "def", name)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: name)

  test "Overwrite a line to the named register":
    var registers: Registers
    const name = "a"
    registers.namedRegister.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    const isLine = true
    registers.addRegister(ru "def", isLine, name)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "def"],
      isLine: true,
      name: name)

  test "Not added to the register (_ register)":
    var registers: Registers
    const name = "_"
    registers.addRegister(ru "def", name)

    check registers.namedRegister.len == 0
    check registers.noNameRegister == Register()

suite "Register: Add a buffer to the small delete register":
  test "Add a deleted string to the small deleted register":
    var registers: Registers

    const
      isLine = false
      isDelete = true
    registers.addRegister(ru "abc", isLine, isDelete)
    registers.addRegister(ru "def", isLine, isDelete)

    check registers.noNameRegister == Register(buffer: @[ru "def"])

    check registers.smallDeleteRegister == Register(buffer: @[ru "def"])

    for i in 0 ..< 10:
      let r = registers.numberRegister[i]
      check r == Register()

suite "Register: Add a buffer to the number register":
  test "Add a yanked string to the number register":
    var registers: Registers

    registers.addRegister(ru "abc")
    registers.addRegister(ru "def")

    for i in 0 ..< 10:
      let r  = registers.numberRegister[i]
      if i == 0:
        check r == Register(buffer: @[ru "def"])
      else:
        check r == Register()

  test "Add a line to the number register":
    var registers: Registers

    const number = 0
    registers.addRegister(@[ru "abc"])

    const
      isDelete = true
      isLine = true
    registers.addRegister(ru "def", isLine, isDelete)

    for i in 0 ..< 10:
      let r = registers.numberRegister[i]
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

    registers.namedRegister = @[r1, r2, r3]

    check registers.searchByName("b").isSome
    check registers.searchByName("b").get == r2

  test "Search a register by number string":
    var registers: Registers
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")

      r3 = Register(buffer: @[ru "ghi"], name: "0")

    registers.namedRegister = @[r1, r2]
    registers.numberRegister[0] = r3

    check registers.searchByName("0").isSome
    check registers.searchByName("0").get == r3

  test "Return empty":
    var registers: Registers
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    registers.namedRegister = @[r1, r2, r3]

    check registers.searchByName("z").isNone
