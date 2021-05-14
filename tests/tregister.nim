import unittest
include moepkg/[register]

suite "Register: Add a string to the register":
  test "Add 2 string to the register":
    var registers: seq[Register]

    registers.addRegister(ru "abc")
    registers.addRegister(ru "def")

    check registers.len == 2

    check registers[0] == Register(buffer: @[ru "abc"], isLine: false, name: "")
    check registers[1] == Register(buffer: @[ru "def"], isLine: false, name: "")

  test "Add string with name to the register":
    var registers: seq[Register]

    const name = "a"
    registers.addRegister(ru "abc", name)

    check registers.len == 1

    check registers[0] == Register(
      buffer: @[ru "abc"], isLine: false, name: name)

  test "Overwrite a string with name to the register":
    var registers: seq[Register]
    const name = "a"
    registers.add Register(buffer: @[ru "abc"], isLine: false, name: name)

    registers.addRegister(ru "def", name)

    check registers.len == 1
    check registers[0] == Register(
      buffer: @[ru "def"], isLine: false, name: name)

suite "Register: Add a line to the register":
  test "Add a line to the register":
    var registers: seq[Register]

    const isLine = true
    registers.addRegister(ru "abc", isLine)

    check registers.len == 1

    check registers[0] == Register(buffer: @[ru "abc"], isLine: true, name: "")

  test "Add 2 lines to the register":
    var registers: seq[Register]

    const isLine = true
    registers.addRegister(@[ru "abc", ru "def"], isLine)

    check registers.len == 1

    check registers[0] == Register(
      buffer: @[ru "abc", ru "def"], isLine: true, name: "")

  test "Overwrite a line with name to the register":
    var registers: seq[Register]
    const name = "a"
    registers.add Register(buffer: @[ru "abc"], isLine: false, name: name)

    const isLine = true
    registers.addRegister(ru "def", isLine, name)

    check registers.len == 1
    check registers[0] == Register(buffer: @[ru "def"], isLine: true, name: name)

suite "Register: Search a register by name":
  test "Search a register by name":
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    let registers = @[r1, r2, r3]

    check registers.searchByName("b") == r2

  test "Return empty":
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    let registers = @[r1, r2, r3]

    check registers.searchByName("z") == Register()
