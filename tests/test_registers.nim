#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import std/[unittest, strutils]

import pkg/results

import ../src/moepkg/registers

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

  test "isNamedRegisterName":
    check isNamedRegisterName('a')
    check isNamedRegisterName('z')
    check isNamedRegisterName('A')
    check isNamedRegisterName('Z')
    check not isNamedRegisterName('0')
    check not isNamedRegisterName('"')
    check not isNamedRegisterName('-')

  test "isNumberRegisterName":
    check isNumberRegisterName('0')
    check isNumberRegisterName('9')
    check not isNumberRegisterName('a')
    check not isNumberRegisterName('"')

  test "isSmallDeleteRegisterName":
    check isSmallDeleteRegisterName('-')
    check not isSmallDeleteRegisterName('a')
    check not isSmallDeleteRegisterName('0')

  test "isPrimarySelectionRegisterName":
    check isPrimarySelectionRegisterName('*')
    check not isPrimarySelectionRegisterName('+')
    check not isPrimarySelectionRegisterName('~')

  test "isClipboardSelectionRegisterName":
    check isClipboardSelectionRegisterName('+')
    check isClipboardSelectionRegisterName('~')
    check not isClipboardSelectionRegisterName('*')

  test "isClipboardRegisterName":
    check isClipboardRegisterName('*')
    check isClipboardRegisterName('+')
    check isClipboardRegisterName('~')
    check not isClipboardRegisterName('a')
    check not isClipboardRegisterName('"')

  test "isEmpty":
    let r = initRegisters()
    check r.getNoNamedRegister().isEmpty
    check r.getNumberRegister(0).isEmpty

    r.setYankedRegister("content", false)
    check not r.getNoNamedRegister().isEmpty
    check not r.getNumberRegister(0).isEmpty

  test "isEmpty with empty string":
    let r = initRegisters()
    r.setYankedRegister("", false)
    check r.getNoNamedRegister().isEmpty

  test "getContent empty register":
    let r = initRegisters()
    check r.getNoNamedRegister().getContent() == ""

  test "getContent characterwise":
    let r = initRegisters()
    r.setYankedRegister("hello world", false)
    check r.getNoNamedRegister().getContent() == "hello world"
    check not r.getNoNamedRegister().isLine

  test "getContent linewise":
    let r = initRegisters()
    r.setYankedRegister("line1\nline2\nline3", true)
    check r.getNoNamedRegister().getContent() == "line1\nline2\nline3"
    check r.getNoNamedRegister().isLine

  test "getLines":
    let r = initRegisters()
    r.setYankedRegister("line1\nline2", true)
    let lines = r.getNoNamedRegister().getLines()
    check lines.len == 2
    check lines[0] == "line1"
    check lines[1] == "line2"

  test "setYankedRegister with seq[string]":
    let r = initRegisters()
    r.setYankedRegister(@["line1", "line2", "line3"], true)

    check r.getNoNamedRegister().getLines() == @["line1", "line2", "line3"]
    check r.getNumberRegister(0).getLines() == @["line1", "line2", "line3"]
    check r.getNoNamedRegister().isLine
    check r.getNumberRegister(0).isLine

  test "setDeletedRegister with seq[string]":
    let r = initRegisters()
    r.setDeletedRegister(@["deleted1", "deleted2"], true)
    r.setDeletedRegister(@["deleted3", "deleted4"], true)

    check r.getNumberRegister(1).getLines() == @["deleted3", "deleted4"]
    check r.getNumberRegister(2).getLines() == @["deleted1", "deleted2"]

  test "setDeletedRegister characterwise single line goes to small delete":
    let r = initRegisters()
    r.setDeletedRegister("small", false)

    check r.getSmallDeleteRegister().getContent() == "small"
    check r.getNoNamedRegister().getContent() == "small"
    # Should not be in number register 1
    check r.getNumberRegister(1).isEmpty

  test "setDeletedRegister characterwise multiline goes to number register":
    let r = initRegisters()
    r.setDeletedRegister("line1\nline2", false)

    check r.getNumberRegister(1).getContent() == "line1\nline2"
    check r.getSmallDeleteRegister().isEmpty

  test "setNamedRegister with seq[string]":
    let r = initRegisters()
    discard r.setNamedRegister('d', @["line1", "line2"], true)

    check r.getNamedRegister('d').getLines() == @["line1", "line2"]
    check r.getNamedRegister('d').isLine

  test "setNamedRegister uppercase with seq[string] appends":
    let r = initRegisters()
    discard r.setNamedRegister('e', @["first"], true)
    discard r.setNamedRegister('E', @["second"], true)

    check r.getNamedRegister('e').getContent() == "first\nsecond"

  test "setNamedRegister invalid name returns error":
    let r = initRegisters()
    let result = r.setNamedRegister('0', "content", false)

    check result.isErr
    check "Invalid register name" in result.error

  test "setClipboardRegister with + register":
    let r = initRegisters()
    r.setClipboardRegister('+', "clipboard content", false)

    check r.getClipboardRegister('+').getContent() == "clipboard content"
    check r.getNoNamedRegister().getContent() == "clipboard content"

  test "setClipboardRegister with * register":
    let r = initRegisters()
    r.setClipboardRegister('*', "primary content", false)

    check r.getClipboardRegister('*').getContent() == "primary content"
    check r.getNoNamedRegister().getContent() == "primary content"

  test "setClipboardRegister linewise":
    let r = initRegisters()
    r.setClipboardRegister('+', "line1\nline2", true)

    check r.getClipboardRegister('+').getContent() == "line1\nline2"
    check r.getClipboardRegister('+').isLine

  test "* and + registers are independent":
    let r = initRegisters()
    r.setClipboardRegister('*', "primary text", false)
    r.setClipboardRegister('+', "clipboard text", false)

    check r.getClipboardRegister('*').getContent() == "primary text"
    check r.getClipboardRegister('+').getContent() == "clipboard text"

  test "~ register behaves same as +":
    let r = initRegisters()
    r.setClipboardRegister('~', "tilde content", false)

    check r.getClipboardRegister('~').getContent() == "tilde content"
    check r.getClipboardRegister('+').getContent() == "tilde content"

  test "setting * does not affect +":
    let r = initRegisters()
    r.setClipboardRegister('+', "plus content", false)
    r.setClipboardRegister('*', "star content", false)

    check r.getClipboardRegister('+').getContent() == "plus content"
    check r.getClipboardRegister('*').getContent() == "star content"

  test "setNoNamedRegister string":
    let r = initRegisters()
    r.setNoNamedRegister("unnamed content", false)

    check r.getNoNamedRegister().getContent() == "unnamed content"
    check not r.getNoNamedRegister().isLine

  test "setNoNamedRegister seq[string]":
    let r = initRegisters()
    r.setNoNamedRegister(@["line1", "line2"], true)

    check r.getNoNamedRegister().getLines() == @["line1", "line2"]
    check r.getNoNamedRegister().isLine

  test "setRegister clipboard registers are separate":
    let r = initRegisters()
    discard r.setRegister('*', "star content", false)
    check r.getClipboardRegister('*').getContent() == "star content"
    check r.getClipboardRegister('+').getContent() == "" # + unaffected

    discard r.setRegister('+', "plus content", false)
    check r.getClipboardRegister('+').getContent() == "plus content"
    check r.getClipboardRegister('*').getContent() == "star content" # * unaffected

  test "setRegister invalid name returns error":
    let r = initRegisters()
    let result = r.setRegister('!', "content", false)

    check result.isErr
    check "Invalid register name" in result.error

  test "getNumberRegister with out of range index":
    let r = initRegisters()
    check r.getNumberRegister(-1).isEmpty
    check r.getNumberRegister(10).isEmpty

  test "getNumberRegister with char":
    let r = initRegisters()
    r.setYankedRegister("yanked", false)

    check r.getNumberRegister('0').getContent() == "yanked"
    check r.getNumberRegister('x').isEmpty # Invalid char

  test "getRegisterContent":
    let r = initRegisters()
    r.setYankedRegister("content", false)

    check r.getRegisterContent('0') == "content"
    check r.getRegisterContent('"') == "content"

  test "isRegisterLinewise":
    let r = initRegisters()
    r.setYankedRegister("line", false)
    check not r.isRegisterLinewise('0')

    r.setYankedRegister("line1\nline2", true)
    check r.isRegisterLinewise('0')

  test "getRegister with invalid name returns empty register":
    let r = initRegisters()
    let reg = r.getRegister('!')

    check reg.isEmpty
    check reg.getContent() == ""

  test "delete register shifts up to 9":
    let r = initRegisters()
    # Fill registers 1-9
    for i in 1 .. 10:
      r.setDeletedRegister("delete" & $i & "\nline", true)

    # Register 9 should have delete2 (oldest kept)
    check r.getNumberRegister(9).getContent() == "delete2\nline"
    # Register 1 should have delete10 (most recent)
    check r.getNumberRegister(1).getContent() == "delete10\nline"

  test "yank does not affect delete registers":
    let r = initRegisters()
    r.setDeletedRegister("deleted\nline", true)
    r.setYankedRegister("yanked", false)

    # Yank should go to register 0
    check r.getNumberRegister(0).getContent() == "yanked"
    # Delete should stay in register 1
    check r.getNumberRegister(1).getContent() == "deleted\nline"
