import std/[unittest, options]
import moepkg/[unicodeext, settings]
include moepkg/[register]

suite "Register: Add a buffer to the no name register":
  test "Add a string to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    registers.addRegister(ru "abc", settings)

    check registers.noNameRegister == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: "")

  test "Overwrite a string in the no name register":
    var registers: Registers
    registers.noNameRegister = Register(buffer: @[ru "abc"])
    let settings = initEditorSettings()

    registers.addRegister(ru "def", settings)

    check registers.noNameRegister == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: "")

  test "Add a line to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    const isLine = true
    registers.addRegister(ru "abc", isLine, settings)

    check registers.noNameRegister == Register(
      buffer: @[ru "abc"],
      isLine: true,
      name: "")

  test "Add 2 lines to the no name register":
    var registers: Registers
    let settings = initEditorSettings()

    const isLine = true
    registers.addRegister(@[ru "abc", ru "def"], isLine, settings)

    check registers.noNameRegister == Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true,
      name: "")

suite "Register: Add a buffer to the named register":
  test "Add a string to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.addRegister(ru "abc", name, settings)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

  test "Overwrite a string to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.namedRegister.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    registers.addRegister(ru "def", name, settings)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "def"],
      isLine: false,
      name: name)

  test "Overwrite a line to the named register":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "a"
    registers.namedRegister.add Register(
      buffer: @[ru "abc"],
      isLine: false,
      name: name)

    const isLine = true
    registers.addRegister(ru "def", isLine, name, settings)

    check registers.namedRegister[0] == Register(
      buffer: @[ru "def"],
      isLine: true,
      name: name)

  test "Not added to the register (_ register)":
    var registers: Registers
    let settings = initEditorSettings()

    const name = "_"
    registers.addRegister(ru "def", name, settings)

    check registers.namedRegister.len == 0
    check registers.noNameRegister == Register()

suite "Register: Add a buffer to the small delete register":
  test "Add a deleted string to the small deleted register":
    var registers: Registers
    let settings = initEditorSettings()

    const
      isLine = false
      isDelete = true
    registers.addRegister(ru "abc", isLine, isDelete, settings)
    registers.addRegister(ru "def", isLine, isDelete, settings)

    check registers.noNameRegister == Register(buffer: @[ru "def"])

    check registers.smallDeleteRegister == Register(buffer: @[ru "def"])

    for i in 0 ..< 10:
      let r = registers.numberRegister[i]
      check r == Register()

suite "Register: Add a buffer to the number register":
  test "Add a yanked string to the number register":
    var registers: Registers
    let settings = initEditorSettings()

    registers.addRegister(ru "abc", settings)
    registers.addRegister(ru "def", settings)

    for i in 0 ..< 10:
      let r  = registers.numberRegister[i]
      if i == 0:
        check r == Register(buffer: @[ru "def"])
      else:
        check r == Register()

  test "Add a line to the number register":
    var registers: Registers
    let settings = initEditorSettings()

    const number = 0
    registers.addRegister(@[ru "abc"], settings)

    const
      isDelete = true
      isLine = true
    registers.addRegister(ru "def", isLine, isDelete, settings)

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
    let settings = initEditorSettings()
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    registers.namedRegister = @[r1, r2, r3]

    check registers.searchByName("b").isSome
    check registers.searchByName("b").get == r2

  test "Search a register by number string":
    var registers: Registers
    let settings = initEditorSettings()
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
    let settings = initEditorSettings()
    const
      r1 = Register(buffer: @[ru "abc"], name: "a")
      r2 = Register(buffer: @[ru "def"], name: "b")
      r3 = Register(buffer: @[ru "ghi"], name: "c")

    registers.namedRegister = @[r1, r2, r3]

    check registers.searchByName("z").isNone
