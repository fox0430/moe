import unittest
import ../src/moepkg/registers
import ../src/moepkg/config

suite "Registers":
  test "initRegisters creates empty registers":
    let r = initRegisters()
    check r.getNoNamedRegister().isEmpty
    check r.getSmallDeleteRegister().isEmpty
    for i in 0 .. 9:
      check r.getNumberRegister(i).isEmpty
    for c in 'a' .. 'z':
      check r.getNamedRegister(c).isEmpty

  test "setYankedRegister stores in register 0 and unnamed":
    let r = initRegisters()
    r.setYankedRegister("hello", false)

    check r.getNoNamedRegister().getContent() == "hello"
    check r.getNumberRegister(0).getContent() == "hello"
    check not r.getNoNamedRegister().isLine
    check not r.getNumberRegister(0).isLine

  test "setYankedRegister with linewise":
    let r = initRegisters()
    r.setYankedRegister("line1\nline2", true)

    check r.getNoNamedRegister().getContent() == "line1\nline2"
    check r.getNoNamedRegister().isLine

  test "setDeletedRegister shifts number registers":
    let r = initRegisters()
    r.setDeletedRegister("first delete\nsecond line", true)
    r.setDeletedRegister("second delete\nanother line", true)
    r.setDeletedRegister("third delete\nmore lines", true)

    # Most recent should be in register 1
    check r.getNumberRegister(1).getContent() == "third delete\nmore lines"
    check r.getNumberRegister(2).getContent() == "second delete\nanother line"
    check r.getNumberRegister(3).getContent() == "first delete\nsecond line"

  test "setSmallDeleteRegister for single line deletions":
    let r = initRegisters()
    r.setSmallDeleteRegister("small")

    check r.getSmallDeleteRegister().getContent() == "small"
    check r.getNoNamedRegister().getContent() == "small"

  test "setNamedRegister lowercase overwrites":
    let r = initRegisters()
    discard r.setNamedRegister('a', "first", false)
    discard r.setNamedRegister('a', "second", false)

    check r.getNamedRegister('a').getContent() == "second"

  test "setNamedRegister uppercase appends":
    let r = initRegisters()
    discard r.setNamedRegister('a', "first", false)
    discard r.setNamedRegister('A', "second", false)

    check r.getNamedRegister('a').getContent() == "firstsecond"

  test "isValidRegisterName":
    check isValidRegisterName('"')
    check isValidRegisterName('a')
    check isValidRegisterName('z')
    check isValidRegisterName('A')
    check isValidRegisterName('Z')
    check isValidRegisterName('0')
    check isValidRegisterName('9')
    check isValidRegisterName('-')
    check isValidRegisterName('*')
    check isValidRegisterName('+')
    check not isValidRegisterName('!')
    check not isValidRegisterName('@')

  test "getRegister returns correct register":
    let r = initRegisters()
    r.setYankedRegister("yanked", false)
    discard r.setNamedRegister('b', "named-b", false)
    r.setSmallDeleteRegister("small")

    # Note: setSmallDeleteRegister also updates unnamed register
    check r.getRegister('"').getContent() == "small" # Last operation
    check r.getRegister('0').getContent() == "yanked" # Yank register preserved
    check r.getRegister('b').getContent() == "named-b"
    check r.getRegister('-').getContent() == "small"

  test "setRegister by name":
    let r = initRegisters()
    discard r.setRegister('"', "unnamed", false)
    discard r.setRegister('5', "num5", false)
    discard r.setRegister('c', "named-c", false)
    discard r.setRegister('-', "small-del", false)

    check r.getRegister('"').getContent() == "small-del"
      # small-del was last set to unnamed
    check r.getRegister('5').getContent() == "num5"
    check r.getRegister('c').getContent() == "named-c"
    check r.getRegister('-').getContent() == "small-del"
