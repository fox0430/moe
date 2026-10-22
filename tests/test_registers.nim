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

import std/[monotimes, options, os, osproc, strutils, tempfiles, times, unittest]

import pkg/results

import ../src/moepkg/registers
import ../src/moepkg/clipboard {.all.}
import ../src/moepkg/config

import clipboard_test_helper

suite "Registers":
  test "initRegisters creates empty registers":
    let r = initRegisters()
    check r.getNoNamedRegister().isEmpty
    check r.getSmallDeleteRegister().isEmpty
    for i in 0 .. 9:
      check r.getNumberRegister(i).isEmpty
    for c in 'a' .. 'z':
      check r.getNamedRegister(c).isEmpty

  test "a yank goes to register 0 and the unnamed register":
    let r = initRegisters()
    r.storeYanked(none(char), "hello", false)

    check r.getNoNamedRegister().getContent() == "hello"
    check r.getNumberRegister(0).getContent() == "hello"
    check not r.getNoNamedRegister().isLine
    check not r.getNumberRegister(0).isLine

  test "linewise text ends every line with a line break":
    let r = initRegisters()
    r.storeYanked(none(char), "line1\nline2\n", true)

    check r.getNoNamedRegister().getContent() == "line1\nline2\n"
    check r.getNoNamedRegister().getLines() == @["line1", "line2"]
    check r.getNoNamedRegister().isLine

  test "linewise text keeps its empty lines, the last ones too":
    # The line break that ends linewise text ends its last line, as Vim's
    # setreg() takes it, so text without one holds the same lines.
    for (content, lines) in [
      ("line1\nline2", @["line1", "line2"]),
      ("foo\n\n\n", @["foo", "", ""]),
      ("\n\n", @["", ""]),
      ("\n", @[""]),
      ("", @[""]),
    ]:
      let r = initRegisters()
      r.storeYanked(none(char), content, true)
      check r.getNumberRegister(0).getLines() == lines
      check not r.getNumberRegister(0).isEmpty

  test "a carriage return in linewise text stays in its line":
    # A raw buffer keeps the CR of a CRLF line, and a line may hold a lone CR.
    for (content, lines) in [("a\rb\n", @["a\rb"]), ("a\r\nb\r\n", @["a\r", "b\r"])]:
      let r = initRegisters()
      r.storeYanked(none(char), content, true)
      check r.getNumberRegister(0).getLines() == lines
      check r.getNumberRegister(0).getContent() == content

  test "a delete over lines shifts the numbered registers":
    let r = initRegisters()
    r.storeDeleted(none(char), "first delete\nsecond line\n", true)
    r.storeDeleted(none(char), "second delete\nanother line\n", true)
    r.storeDeleted(none(char), "third delete\nmore lines\n", true)

    # Most recent should be in register 1
    check r.getNumberRegister(1).getLines() == @["third delete", "more lines"]
    check r.getNumberRegister(2).getLines() == @["second delete", "another line"]
    check r.getNumberRegister(3).getLines() == @["first delete", "second line"]

  test "a delete within a line goes to the small delete register":
    let r = initRegisters()
    r.storeDeleted(none(char), "seed\n", true)
    r.storeDeleted(none(char), "small", false)

    check r.getSmallDeleteRegister().getContent() == "small"
    check r.getNoNamedRegister().getContent() == "small"
    check r.getNumberRegister(1).getLines() == @["seed"]
    check r.getNumberRegister(2).isEmpty

  test "a characterwise delete over lines goes to register 1, not -":
    let r = initRegisters()
    r.storeDeleted(none(char), "line1\nline2", false)

    check r.getNumberRegister(1).getContent() == "line1\nline2"
    check not r.getNumberRegister(1).isLine
    check r.getSmallDeleteRegister().isEmpty

  test "a delete over % and the like goes to register 1 and - within a line":
    let r = initRegisters()
    r.storeDeleted(none(char), "(a b)", false, useRegOne = true)

    check r.getNumberRegister(1).getContent() == "(a b)"
    check r.getSmallDeleteRegister().getContent() == "(a b)"
    check r.getNoNamedRegister().getContent() == "(a b)"

  test "a delete into a named register also goes to 1 when it is over lines":
    # Vim 9.2: `"add` puts the line in a and "1, shifting the old "1 to "2.
    let r = initRegisters()
    r.storeDeleted(none(char), "old\n", true)
    r.storeDeleted(some('a'), "one\n", true)

    check r.getNamedRegister('a').getLines() == @["one"]
    check r.getNumberRegister(1).getLines() == @["one"]
    check r.getNumberRegister(2).getLines() == @["old"]
    check r.getNoNamedRegister().getLines() == @["one"]

  test "a delete within a line into a clipboard register also fills -":
    # The unnamed register mirrors the clipboard, as Vim's
    # clipboard=unnamedplus, which fills "- for `"+x`.
    let r = initRegisters()
    r.storeDeleted(some('+'), "o", false)

    check r.getSmallDeleteRegister().getContent() == "o"
    check r.getNumberRegister(1).isEmpty

  test "a delete into a named register within a line leaves 1 and -":
    let r = initRegisters()
    r.storeDeleted(some('a'), "one", false)

    check r.getNamedRegister('a').getContent() == "one"
    check r.getNumberRegister(1).isEmpty
    check r.getSmallDeleteRegister().isEmpty
    check r.getNoNamedRegister().getContent() == "one"

  test "a delete into a named register over % goes to 1 but not -":
    let r = initRegisters()
    r.storeDeleted(some('a'), "(a b)", false, useRegOne = true)

    check r.getNamedRegister('a').getContent() == "(a b)"
    check r.getNumberRegister(1).getContent() == "(a b)"
    check r.getSmallDeleteRegister().isEmpty

  test "a delete into a numbered register is shifted on with the others":
    # Vim 9.2: `"3dd` writes "3, then shifts it to "4 as it fills "1.
    let r = initRegisters()
    discard r.setRegister('2', "R2", false)
    discard r.setRegister('3', "R3", false)
    r.storeDeleted(some('3'), "one\n", true)

    check r.getNumberRegister(1).getLines() == @["one"]
    check r.getNumberRegister(3).getContent() == "R2"
    check r.getNumberRegister(4).getLines() == @["one"]

  test "adding a delete to a named register leaves its whole text unnamed":
    # Vim 9.2: after `"ayy` `"Add`, `p` puts both lines, and "1 holds the
    # deleted one.
    let r = initRegisters()
    r.storeYanked(some('a'), "one\n", true)
    r.storeDeleted(some('A'), "two\n", true)

    check r.getNamedRegister('a').getLines() == @["one", "two"]
    check r.getNumberRegister(1).getLines() == @["two"]
    check r.getNoNamedRegister().getLines() == @["one", "two"]

  test "a yank into a numbered register or - leaves register 0":
    let r = initRegisters()
    r.storeYanked(some('3'), "two\n", true)
    r.storeYanked(some('-'), "three\n", true)

    check r.getNumberRegister(3).getLines() == @["two"]
    check r.getSmallDeleteRegister().getLines() == @["three"]
    check r.getSmallDeleteRegister().isLine
    check r.getNumberRegister(0).isEmpty
    check r.getNoNamedRegister().getLines() == @["three"]

  test "a yank into the unnamed register writes register 0":
    let r = initRegisters()
    r.storeYanked(some('"'), "two", false)

    check r.getNumberRegister(0).getContent() == "two"
    check r.getNoNamedRegister().getContent() == "two"

  test "the black hole register keeps nothing":
    let r = initRegisters()
    r.storeYanked(none(char), "kept", false)
    r.storeYanked(some('_'), "yanked", false)
    r.storeDeleted(some('_'), "deleted\n", true)

    check r.getNoNamedRegister().getContent() == "kept"
    check r.getNumberRegister(0).getContent() == "kept"
    check r.getNumberRegister(1).isEmpty

  test "a lowercase name overwrites":
    let r = initRegisters()
    r.storeYanked(some('a'), "first", false)
    r.storeYanked(some('a'), "second", false)

    check r.getNamedRegister('a').getContent() == "second"

  test "an uppercase name appends, and the unnamed register holds it all":
    let r = initRegisters()
    r.storeYanked(some('a'), "first", false)
    r.storeYanked(some('A'), "second", false)

    check r.getNamedRegister('a').getContent() == "firstsecond"
    check r.getNoNamedRegister().getContent() == "firstsecond"

  test "an uppercase name appends lines with no blank line between":
    let r = initRegisters()
    r.storeYanked(some('e'), "first\n", true)
    r.storeYanked(some('E'), "second\n", true)

    check r.getNamedRegister('e').getLines() == @["first", "second"]
    check r.getNamedRegister('e').getContent() == "first\nsecond\n"

  test "an uppercase name appends charwise text to lines as a new line":
    let r = initRegisters()
    r.storeYanked(some('f'), "line1\nline2\n", true)
    r.storeYanked(some('F'), "abc", false)

    check r.getNamedRegister('f').isLine
    check r.getNamedRegister('f').getLines() == @["line1", "line2", "abc"]

  test "an uppercase name appends lines to charwise text as new lines":
    let r = initRegisters()
    r.storeYanked(some('g'), "hello", false)
    r.storeYanked(some('G'), "line1\nline2\n", true)

    check r.getNamedRegister('g').isLine
    check r.getNamedRegister('g').getLines() == @["hello", "line1", "line2"]

  test "an uppercase name adds to an empty register as a write does":
    let r = initRegisters()
    r.storeYanked(some('H'), "one\n", true)

    check r.getNamedRegister('h').getLines() == @["one"]

  test "a block keeps its rows and width, and reads as its rows joined":
    let r = initRegisters()
    r.storeYanked(none(char), blockRegister(@["ab", "  "], 2))

    let reg = r.getNumberRegister(0)
    check reg.kind == rkBlock
    check reg.width == 2
    check reg.getLines() == @["ab", "  "]
    check reg.getContent() == "ab\n  "
    check r.getNoNamedRegister().kind == rkBlock

  test "an uppercase name appends to a block as rows and keeps its width":
    # Vim's op_yank: the register keeps its type unless lines are added.
    let r = initRegisters()
    r.storeYanked(some('i'), blockRegister(@["ab", "cd"], 2))
    r.storeYanked(some('I'), "xyz", false)

    let reg = r.getNamedRegister('i')
    check reg.kind == rkBlock
    check reg.width == 2
    check reg.getLines() == @["ab", "cd", "xyz"]

  test "an uppercase name appends a block to characters as characters":
    let r = initRegisters()
    r.storeYanked(some('j'), "x", false)
    r.storeYanked(some('J'), blockRegister(@["ab", "cd"], 2))

    check r.getNamedRegister('j').kind == rkChars
    check r.getNamedRegister('j').getContent() == "xab\ncd"

  test "an uppercase name appends a block to lines as lines":
    let r = initRegisters()
    r.storeYanked(some('k'), "x\n", true)
    r.storeYanked(some('K'), blockRegister(@["ab", "cd"], 2))

    check r.getNamedRegister('k').kind == rkLines
    check r.getNamedRegister('k').getLines() == @["x", "ab", "cd"]

  test "an uppercase name adds to what an empty yank left":
    # Vim 9.2: `"ayl` on an empty line keeps "", and a block `"Ay` then
    # continues it as characters.
    let r = initRegisters()
    r.storeYanked(some('l'), "", false)
    r.storeYanked(some('L'), blockRegister(@["ab", "cd"], 2))

    check r.getNamedRegister('l').kind == rkChars
    check r.getNamedRegister('l').getContent() == "ab\ncd"

  test "a delete of a block within a line goes to -, of one over lines to 1":
    let r = initRegisters()
    r.storeDeleted(none(char), blockRegister(@["ab"], 2))

    check r.getSmallDeleteRegister().kind == rkBlock
    check r.getNumberRegister(1).isEmpty

    r.storeDeleted(none(char), blockRegister(@["ab", "cd"], 2))

    check r.getNumberRegister(1).kind == rkBlock
    check r.getSmallDeleteRegister().getLines() == @["ab"]

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
    r.storeYanked(none(char), "yanked", false)
    discard r.setRegister('b', "named-b", false)
    r.storeDeleted(none(char), "small", false)

    check r.getRegister('"').getContent() == "small" # Last operation
    check r.getRegister('0').getContent() == "yanked" # Yank register preserved
    check r.getRegister('b').getContent() == "named-b"
    check r.getRegister('-').getContent() == "small"

  test "setRegister writes a register as Vim's setreg(), leaving the unnamed one":
    # Vim 9.2: `:let @a = "x"` leaves "" alone; `:let @" = "x"` writes "0 and
    # makes it the unnamed register.
    let r = initRegisters()
    discard r.setRegister('"', "unnamed", false)
    discard r.setRegister('5', "num5", false)
    discard r.setRegister('c', "named-c", false)
    discard r.setRegister('-', "small-del", false)
    discard r.setRegister('C', "-more", false)

    check r.getRegister('0').getContent() == "unnamed"
    check r.getRegister('"').getContent() == "unnamed"
    check r.getRegister('5').getContent() == "num5"
    check r.getRegister('c').getContent() == "named-c-more"
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

    r.storeYanked(none(char), "content", false)
    check not r.getNoNamedRegister().isEmpty
    check not r.getNumberRegister(0).isEmpty

  test "an empty yank leaves one empty line, not an empty register":
    # As Vim's y_array: only a register never written is E353 to put.
    let r = initRegisters()
    r.storeYanked(none(char), "", false)
    check not r.getNoNamedRegister().isEmpty
    check r.getNoNamedRegister().getLines() == @[""]

  test "getContent empty register":
    let r = initRegisters()
    check r.getNoNamedRegister().getContent() == ""

  test "getContent characterwise":
    let r = initRegisters()
    r.storeYanked(none(char), "hello world", false)
    check r.getNoNamedRegister().getContent() == "hello world"
    check not r.getNoNamedRegister().isLine

  test "a yank into + also fills the unnamed register":
    let r = initRegisters()
    r.storeYanked(some('+'), "clipboard content", false)

    check r.getClipboardRegister('+').getContent() == "clipboard content"
    check r.getNoNamedRegister().getContent() == "clipboard content"

  test "a yank into * also fills the unnamed register":
    let r = initRegisters()
    r.storeYanked(some('*'), "primary content", false)

    check r.getClipboardRegister('*').getContent() == "primary content"
    check r.getNoNamedRegister().getContent() == "primary content"

  test "a yank into + keeps linewise text":
    let r = initRegisters()
    r.storeYanked(some('+'), "line1\nline2\n", true)

    check r.getClipboardRegister('+').getLines() == @["line1", "line2"]
    check r.getClipboardRegister('+').isLine

  test "* and + registers are independent":
    let r = initRegisters()
    r.storeYanked(some('*'), "primary text", false)
    r.storeYanked(some('+'), "clipboard text", false)

    check r.getClipboardRegister('*').getContent() == "primary text"
    check r.getClipboardRegister('+').getContent() == "clipboard text"

  test "~ register behaves same as +":
    let r = initRegisters()
    r.storeYanked(some('~'), "tilde content", false)

    check r.getClipboardRegister('~').getContent() == "tilde content"
    check r.getClipboardRegister('+').getContent() == "tilde content"

  test "setting * does not affect +":
    let r = initRegisters()
    r.storeYanked(some('+'), "plus content", false)
    r.storeYanked(some('*'), "star content", false)

    check r.getClipboardRegister('+').getContent() == "plus content"
    check r.getClipboardRegister('*').getContent() == "star content"

  test "setRegister clipboard registers are separate":
    let r = initRegisters()
    r.storeYanked(some('*'), "star content", false)
    check r.getClipboardRegister('*').getContent() == "star content"
    check r.getClipboardRegister('+').getContent() == "" # + unaffected

    r.storeYanked(some('+'), "plus content", false)
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
    r.storeYanked(none(char), "yanked", false)

    check r.getNumberRegister('0').getContent() == "yanked"
    check r.getNumberRegister('x').isEmpty # Invalid char

  test "getRegisterContent":
    let r = initRegisters()
    r.storeYanked(none(char), "content", false)

    check r.getRegisterContent('0') == "content"
    check r.getRegisterContent('"') == "content"

  test "isRegisterLinewise":
    let r = initRegisters()
    r.storeYanked(none(char), "line", false)
    check not r.isRegisterLinewise('0')

    r.storeYanked(none(char), "line1\nline2", true)
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
      r.storeDeleted(none(char), "delete" & $i & "\nline", true)

    # Register 9 should have delete2 (oldest kept)
    check r.getNumberRegister(9).getLines() == @["delete2", "line"]
    # Register 1 should have delete10 (most recent)
    check r.getNumberRegister(1).getLines() == @["delete10", "line"]

  test "yank does not affect delete registers":
    let r = initRegisters()
    r.storeDeleted(none(char), "deleted\nline", true)
    r.storeYanked(none(char), "yanked", false)

    # Yank should go to register 0
    check r.getNumberRegister(0).getContent() == "yanked"
    # Delete should stay in register 1
    check r.getNumberRegister(1).getLines() == @["deleted", "line"]

  test "getNoNamedRegister without clipboard tool returns internal register":
    let r = initRegisters()
    r.storeYanked(none(char), "internal", false)

    # Without clipboard tool, should just return internal register
    check r.getNoNamedRegister().getContent() == "internal"

  test "getNoNamedRegister reads the CLIPBOARD selection on every put":
    # Put reads the CLIPBOARD selection each time, so an external copy is
    # picked up even right after a yank.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "cached", false)

        # Overwrite CLIPBOARD to simulate an external copy.
        writeFile(clipboardFilePath(fakeDir), fakeClipboardContent)
        check r.getNoNamedRegister().getContent() == fakeClipboardContent

        # A newer external change is picked up by the next put too.
        writeFile(clipboardFilePath(fakeDir), "newer external content")
        check r.getNoNamedRegister().getContent() == "newer external content"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "put keeps the linewise type when CLIPBOARD holds moe's own write":
    # A linewise yank writes the line break that ends its last line, and the
    # internal type is kept when the selection matches.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "single line", true)

        check readFile(clipboardFilePath(fakeDir)) == "single line\n"
        let reg = r.getNoNamedRegister()
        check reg.getContent() == "single line\n"
        check reg.isLine == true
      finally:
        removeFakeClipboardTool(fakeDir)

  test "put keeps the characterwise type for multiline content moe wrote":
    # Regression: a multiline characterwise yank is exported newline-joined,
    # so the read would infer linewise from the newline alone; the internal
    # type must be kept when the selection matches.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "first\nsecond", false)

        let reg = r.getNoNamedRegister()
        check reg.getContent() == "first\nsecond"
        check reg.isLine == false
      finally:
        removeFakeClipboardTool(fakeDir)

  test "a block goes to the selections a line to a row and comes back a block":
    # As Vim's clip_convert_selection: every row of a block ends in a line
    # break.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), blockRegister(@["ab", "cd"], 3))

        check readFile(clipboardFilePath(fakeDir)) == "ab\ncd\n"
        check readFile(primaryFilePath(fakeDir)) == "ab\ncd\n"
        let reg = r.getNoNamedRegister()
        check reg.kind == rkBlock
        check reg.width == 3
        check reg.getLines() == @["ab", "cd"]
        check r.getClipboardRegister('*').kind == rkBlock
      finally:
        removeFakeClipboardTool(fakeDir)

  test "text from the clipboard is linewise when it ends in a line break":
    # As Vim takes the clipboard: "a\nb" is characterwise, "a\nb\n" two lines.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)

        writeFile(clipboardFilePath(fakeDir), "a\nb")
        var reg = r.getNoNamedRegister()
        check not reg.isLine
        check reg.getContent() == "a\nb"

        writeFile(clipboardFilePath(fakeDir), "a\nb\n")
        reg = r.getNoNamedRegister()
        check reg.isLine
        check reg.getLines() == @["a", "b"]
      finally:
        removeFakeClipboardTool(fakeDir)

  test "a CRLF line break from the clipboard is a line break":
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)

        writeFile(clipboardFilePath(fakeDir), "foo\r\nbar\r\n")
        let reg = r.getNoNamedRegister()
        check reg.isLine
        check reg.getLines() == @["foo", "bar"]
      finally:
        removeFakeClipboardTool(fakeDir)

  test "the clipboard read back keeps the CR of a raw buffer's lines":
    # A raw buffer of a CRLF file keeps the CR in its lines; reading moe's own
    # write back must not take it away.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "a\r\n", true)

        check readFile(clipboardFilePath(fakeDir)) == "a\r\n"
        let reg = r.getNoNamedRegister()
        check reg.getLines() == @["a\r"]
        check reg.isLine
      finally:
        removeFakeClipboardTool(fakeDir)

  test "a selection that made moe's line breaks CRLF still holds moe's text":
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "foo\nbar", false)

        writeFile(clipboardFilePath(fakeDir), "foo\r\nbar")
        let reg = r.getNoNamedRegister()
        check reg.getContent() == "foo\nbar"
        check not reg.isLine
      finally:
        removeFakeClipboardTool(fakeDir)

  test "getNoNamedRegister ignores PRIMARY selection changes":
    # Put reads CLIPBOARD only; PRIMARY is reachable through the `*`
    # register and must not affect put.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        r.storeYanked(none(char), "cached", false)

        writeFile(clipboardFilePath(fakeDir), "clip content")
        writeFile(primaryFilePath(fakeDir), "mouse selected content")

        check r.getNoNamedRegister().getContent() == "clip content"
        check r.getClipboardRegister('*').getContent() == "mouse selected content"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "unnamed put after a CLIPBOARD-only register write returns the CLIPBOARD content":
    # `"+y` writes CLIPBOARD only, so every put returns the written content.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)

        # A prior yank leaves both selections holding the same value.
        writeFile(clipboardFilePath(fakeDir), "old value")
        writeFile(primaryFilePath(fakeDir), "old value")
        r.storeYanked(none(char), "old value", false)

        # `"+y "new value"` writes the CLIPBOARD selection only.
        r.storeYanked(some('+'), "new value", false)

        # Every put returns the written content (no PRIMARY-based oscillation).
        check r.getNoNamedRegister().getContent() == "new value"
        check r.getNoNamedRegister().getContent() == "new value"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "unnamed put after a PRIMARY-only register write reads CLIPBOARD":
    # `"*y` writes PRIMARY only; put still reads the old CLIPBOARD value.
    # The new value is reachable through `"*p`.
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)

        writeFile(clipboardFilePath(fakeDir), "old value")
        writeFile(primaryFilePath(fakeDir), "old value")
        r.storeYanked(none(char), "old value", false)

        writeFile(primaryFilePath(fakeDir), "new value")
        r.storeYanked(some('*'), "new value", false)

        check r.getNoNamedRegister().getContent() == "old value"
        check r.getClipboardRegister('*').getContent() == "new value"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "unnamed put keeps moe's own write inside the wl-copy claim window":
    # A non-forking wl-copy keeps running, so a read shortly after moe's own
    # write can still return the previous content; the internal register
    # must be kept inside the claim window instead.
    let fakeDir = installFakeWlClipboardTool("old external content", stayRunning = true)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtWlClipboard)
        # Wait for the fake wl-copy to record the write before reading back.
        r.storeYanked(none(char), "new content\n", true)
        waitForClipboardWrite(fakeDir, "new content\n")

        # Restart the claim window so the wait above cannot move the put
        # past it.
        restartClipboardClaimWindow(r)

        # The first read returns the pre-write content; the claim window
        # keeps the internal register instead of adopting the stale read.
        var reg = r.getNoNamedRegister()
        check reg.getContent() == "new content\n"
        check reg.isLine == true

        # After the claim window has expired, an external change is picked
        # up by the next put.
        expireClipboardClaimWindow(r)
        writeFile(clipboardFilePath(fakeDir), "external copy")
        reg = r.getNoNamedRegister()
        check reg.getContent() == "external copy"
        check reg.isLine == false
      finally:
        removeFakeClipboardTool(fakeDir)

  test "clipboardFallbackRead reports content the claim window suppressed":
    # Inside the claim window a successful read is deliberately not adopted
    # into the register. A paste falling back to the clipboard must still see
    # what that read returned instead of concluding the clipboard is empty.
    let fakeDir = installFakeWlClipboardTool("external content")
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtWlClipboard)
        restartClipboardClaimWindow(r)

        check r.getNoNamedRegister().getContent() == ""

        let fallback = r.clipboardFallbackRead(cbtWlClipboard, '"')
        check fallback.isOk
        check fallback.get() == "external content"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "clipboardFallbackRead reuses the read the register resolution just did":
    # Resolving the register already ran the tool, so the fallback reuses that
    # read instead of spawning it again. The cache is consumed, so a second
    # fallback with no register read in between goes back to the tool.
    let fakeDir = installFakeClipboardTool("first content")
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        # Populate `clipboardReadOutcome=croSucceeded` with "first content".
        check r.getNoNamedRegister().getContent() == "first content"
        check r.clipboardReadOutcome == croSucceeded
        writeFile(clipboardFilePath(fakeDir), "second content")
        let fb = r.clipboardFallbackRead(cbtXclip, '"')
        check fb.isOk
        check fb.get() == "first content"
        # Cache consumed: the next fallback runs the tool again.
        check r.clipboardReadOutcome == croNotAttempted
        let fb2 = r.clipboardFallbackRead(cbtXclip, '"')
        check fb2.isOk
        check fb2.get() == "second content"
        # Non-clipboard register must always re-read, never hit the cache.
        writeFile(clipboardFilePath(fakeDir), "third content")
        let fb3 = r.clipboardFallbackRead(cbtXclip, 'a')
        check fb3.isOk
        check fb3.get() == "third content"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "an empty-clipboard paste runs the clipboard tool only once":
    # The ordinary "nothing yanked, empty clipboard" paste resolves the unnamed
    # register and then falls back. Both steps used to run the tool, doubling
    # the synchronous stall - and the bounded timeout - on every such paste.
    when defined(posix):
      let fakeDir = createTempDir("moe-registers-test-count-", "")
      let origPath = getEnv("PATH")
      let counter = fakeDir / "runs"
      let fakeTool = fakeDir / "xclip"
      writeFile(fakeTool, "#!/bin/sh\nprintf x >>\"" & counter & "\"\n")
      setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
      writeFile(counter, "")
      putEnv("PATH", fakeDir & ":" & origPath)
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        check r.getNoNamedRegister().getContent() == ""
        let fb = r.clipboardFallbackRead(cbtXclip, '"')
        check fb.isOk
        check fb.get() == ""
        check readFile(counter).len == 1
      finally:
        putEnv("PATH", origPath)
        removeDir(fakeDir)

  test "clipboardFallbackRead on `*` reads PRIMARY, not CLIPBOARD":
    # `*` names the PRIMARY selection. Falling back to CLIPBOARD would paste
    # the other selection's content whenever PRIMARY is empty.
    let fakeDir = installFakeClipboardTool("")
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        writeFile(clipboardFilePath(fakeDir), "clipboard content")
        writeFile(primaryFilePath(fakeDir), "primary content")
        let fb = r.clipboardFallbackRead(cbtXclip, '*')
        check fb.isOk
        check fb.get() == "primary content"
        # An empty PRIMARY stays empty instead of borrowing CLIPBOARD.
        writeFile(primaryFilePath(fakeDir), "")
        let fbEmpty = r.clipboardFallbackRead(cbtXclip, '*')
        check fbEmpty.isOk
        check fbEmpty.get() == ""
      finally:
        removeFakeClipboardTool(fakeDir)

  test "clipboardFallbackRead on failed read does not double the timeout":
    # The hung/oversized case must not cost a second bounded read. A failed
    # getRegister read is cached and the fallback returns the cached error
    # without re-invoking the tool, so the second call is near-instant.
    when defined(posix):
      let fakeDir = createTempDir("moe-registers-test-hang-", "")
      let origPath = getEnv("PATH")
      let fakeTool = fakeDir / "xclip"
      # Hanging tool for reads: sleep longer than ReadTimeoutMs.
      writeFile(fakeTool, "#!/bin/sh\nsleep 10\n")
      setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
      putEnv("PATH", fakeDir & ":" & origPath)
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        let start1 = getMonoTime()
        discard r.getNoNamedRegister()
        let elapsed1 = (getMonoTime() - start1).inMilliseconds
        check r.clipboardReadOutcome == croFailed
        # Second call must not re-invoke the hanging tool: should be fast.
        let start2 = getMonoTime()
        let fb = r.clipboardFallbackRead(cbtXclip, '"')
        let elapsed2 = (getMonoTime() - start2).inMilliseconds
        check fb.isErr
        # First read took the bounded timeout (ReadTimeoutMs); fallback must not
        # add a second one. Upper bound is generous for loaded CI.
        check elapsed1 >= ReadTimeoutMs div 2
        check elapsed1 < ReadTimeoutMs + 3_000
        check elapsed2 < 500
        # Total must be ~one timeout, not two. Primary detector is elapsed2 <500;
        # total is a sanity bound (generous for CI, not for double detection).
        check (elapsed1 + elapsed2) < ReadTimeoutMs + 3_000
        # Non-clipboard register must still re-read (even if it hangs).
        # We only check it is attempted, not timing, to avoid double hang.
        r.clipboardReadOutcome = croSucceeded
          # reset to verify non-cache path would re-read
        # Restore PATH before checking non-clipboard path to avoid hanging again
        # on cleanup; use a fast fake for the second probe.
        writeFile(fakeTool, "#!/bin/sh\ncat \"" & fakeDir & "/clipboard.txt\"\n")
        writeFile(fakeDir / "clipboard.txt", "third content")
        let fb2 = r.clipboardFallbackRead(cbtXclip, 'a')
        check fb2.isOk
      finally:
        putEnv("PATH", origPath)
        removeDir(fakeDir)
    else:
      skip()

  test "clipboardFallbackRead on `*` does not double the timeout":
    # `"*p` reads PRIMARY through the register, then falls back for an empty
    # register. A hung tool must not be spawned a second time for a second
    # bounded read: PRIMARY keeps its own cached outcome.
    when defined(posix):
      let fakeDir = createTempDir("moe-registers-test-primary-hang-", "")
      let origPath = getEnv("PATH")
      let fakeTool = fakeDir / "xclip"
      writeFile(fakeTool, "#!/bin/sh\nsleep 10\n")
      setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
      putEnv("PATH", fakeDir & ":" & origPath)
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtXclip)
        let start1 = getMonoTime()
        discard r.getRegister('*')
        let elapsed1 = (getMonoTime() - start1).inMilliseconds
        check r.primaryReadOutcome == croFailed
        let start2 = getMonoTime()
        let fb = r.clipboardFallbackRead(cbtXclip, '*')
        let elapsed2 = (getMonoTime() - start2).inMilliseconds
        check fb.isErr
        check elapsed1 >= ReadTimeoutMs div 2
        check elapsed1 < ReadTimeoutMs + 3_000
        check elapsed2 < 500
        check (elapsed1 + elapsed2) < ReadTimeoutMs + 3_000
      finally:
        putEnv("PATH", origPath)
        removeDir(fakeDir)
    else:
      skip()

  test "unnamed put adopts an external change made right after moe's own write":
    # A forking wl-copy confirms the write, so no claim window opens and an
    # external copy right after moe's own write is picked up by the next put.
    let fakeDir = installFakeWlClipboardTool("old external content")
    if fakeDir.len == 0:
      skip()
    else:
      try:
        # The write counts as confirmed only if the fake exits within the
        # short early-exit poll, and a loaded CI box can overrun it. Retry
        # the whole write so a slow exit is not reported as a missed adoption.
        var reg: Register
        for _ in 0 ..< 10:
          let r = initRegisters()
          r.setClipboardTool(cbtWlClipboard)
          r.storeYanked(none(char), "new content\n", true)
          waitForClipboardWrite(fakeDir, "new content\n")

          # The write is confirmed (the fake exits right away), so the
          # immediate external change is adopted by the next put.
          writeFile(clipboardFilePath(fakeDir), "external copy")
          reg = r.getNoNamedRegister()
          if reg.getContent() == "external copy":
            break
          sleep(100)
        check reg.getContent() == "external copy"
        check reg.isLine == false
      finally:
        removeFakeClipboardTool(fakeDir)

  test "+ register put returns the yanked content inside the wl-copy claim window":
    # Regression: sendToClipboard must keep the `+` cache in sync like the
    # copy command does, otherwise `"+p` right after a yank returns the
    # pre-yank content for the whole claim window.
    let fakeDir = installFakeWlClipboardTool("old external content", stayRunning = true)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtWlClipboard)

        # The fake selection holds pre-yank content so the read differs
        # from the yanked content.
        writeFile(clipboardFilePath(fakeDir), "old external content")

        r.storeYanked(none(char), "yanked line\n", true)
        waitForClipboardWrite(fakeDir, "yanked line\n")

        # Restart the claim window so the wait above cannot move the put
        # past it.
        restartClipboardClaimWindow(r)

        let reg = r.getClipboardRegister('+')
        check reg.getContent() == "yanked line\n"
        check reg.isLine == true
      finally:
        removeFakeClipboardTool(fakeDir)

  test "claim window boundary is decided by real elapsed time":
    # Regression: the boundary must hold against actual elapsed time, not
    # only against the restart/expire test seams.
    let fakeDir = installFakeWlClipboardTool("old external content", stayRunning = true)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let r = initRegisters()
        r.setClipboardTool(cbtWlClipboard)

        r.storeYanked(none(char), "new content\n", true)
        waitForClipboardWrite(fakeDir, "new content\n")

        # Inside the 500ms boundary the pre-write read is not adopted.
        # 250ms leaves margin for the fake wl-paste spawn on a slow CI.
        setClipboardWriteAgo(r, 250)
        check r.getNoNamedRegister().getContent() == "new content\n"

        # Outside the boundary an external change is adopted by the next put.
        setClipboardWriteAgo(r, 750)
        writeFile(clipboardFilePath(fakeDir), "external copy")
        check r.getNoNamedRegister().getContent() == "external copy"
      finally:
        removeFakeClipboardTool(fakeDir)

proc isToolAvailable(cmd: string): bool =
  try:
    let (_, exitCode) = execCmdEx("which " & cmd)
    result = exitCode == 0
  except CatchableError:
    result = false

proc isXselAvailable(): bool =
  existsEnv("DISPLAY") and isToolAvailable("xsel")

proc isXclipAvailable(): bool =
  existsEnv("DISPLAY") and isToolAvailable("xclip")

proc isWlClipboardAvailable(): bool =
  existsEnv("WAYLAND_DISPLAY") and isToolAvailable("wl-copy")

proc getAvailableTool(): (bool, ClipboardTool) =
  if isWlClipboardAvailable():
    return (true, cbtWlClipboard)
  elif isXselAvailable():
    return (true, cbtXsel)
  elif isXclipAvailable():
    return (true, cbtXclip)
  return (false, cbtXsel)

proc readClipboardWithRetry(
    tool: ClipboardTool, expected: string, maxRetries: int = 10, delayMs: int = 100
): Result[string, string] =
  ## Retry reading from CLIPBOARD selection until the expected value is returned.
  ## Clipboard writes may not be visible immediately in CI environments.
  for i in 0 ..< maxRetries:
    result = readFromClipboardSync(tool)
    if result.isOk and result.get() == expected:
      return
    sleep(delayMs)
  return readFromClipboardSync(tool)

proc readPrimaryWithRetry(
    tool: ClipboardTool, expected: string, maxRetries: int = 10, delayMs: int = 100
): Result[string, string] =
  ## Retry reading from PRIMARY selection until the expected value is returned.
  ## Selection writes may not be visible immediately in CI environments.
  for i in 0 ..< maxRetries:
    result = readFromPrimarySelectionSync(tool)
    if result.isOk and result.get() == expected:
      return
    sleep(delayMs)
  return readFromPrimarySelectionSync(tool)

proc cleanup(tool: ClipboardTool) =
  ## Clean up clipboard tool processes spawned by writes during tests.
  ## Uses -f flag to match only processes started from the test's working dir,
  ## avoiding killing unrelated user processes.
  let pid = getCurrentProcessId()
  case tool
  of cbtXsel:
    discard execCmdEx("pkill -P " & $pid & " xsel")
  of cbtXclip:
    discard execCmdEx("pkill -P " & $pid & " xclip")
  else:
    discard
  sleep(100)

suite "Registers clipboard integration":
  test "getNoNamedRegister syncs from system clipboard":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)
      r.storeYanked(none(char), "old internal", false)

      # storeYanked writes to both CLIPBOARD and PRIMARY synchronously.
      # Verify they landed before our explicit sync write below.
      let clipSeeded = readClipboardWithRetry(tool, "old internal")
      check clipSeeded.isOk and clipSeeded.get() == "old internal"
      let primarySeeded = readPrimaryWithRetry(tool, "old internal")
      check primarySeeded.isOk and primarySeeded.get() == "old internal"

      # Write directly to system clipboard (simulating external app copy)
      let testText = "external clipboard content"
      let writeResult = writeToClipboardSync(tool, testText)
      check writeResult.isOk

      # Wait for clipboard to be readable before testing getNoNamedRegister
      let clipReady = readClipboardWithRetry(tool, testText)
      check clipReady.isOk and clipReady.get() == testText

      # On Wayland, expire the claim window so the external change is
      # observed.
      if tool == cbtWlClipboard:
        expireClipboardClaimWindow(r)

      # getNoNamedRegister should pick up the external clipboard content
      let reg = r.getNoNamedRegister()
      check reg.getContent() == testText

      cleanup(tool)

  test "PRIMARY changes do not affect the unnamed put":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)
      r.storeYanked(none(char), "old internal", false)

      # storeYanked writes to both CLIPBOARD and PRIMARY synchronously.
      # Verify they landed before our explicit sync write below.
      let clipSeeded = readClipboardWithRetry(tool, "old internal")
      check clipSeeded.isOk and clipSeeded.get() == "old internal"
      let primarySeeded = readPrimaryWithRetry(tool, "old internal")
      check primarySeeded.isOk and primarySeeded.get() == "old internal"

      # Write directly to PRIMARY selection (simulating mouse selection in browser)
      let testText = "mouse selected text"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk

      # Wait for PRIMARY selection to be readable
      let primaryReady = readPrimaryWithRetry(tool, testText)
      check primaryReady.isOk and primaryReady.get() == testText

      # Put reads CLIPBOARD only, so the unnamed put keeps the old value;
      # the PRIMARY content is reachable through the `*` register.
      let reg = r.getNoNamedRegister()
      check reg.getContent() == "old internal"
      check r.getClipboardRegister('*').getContent() == testText

      cleanup(tool)

  test "getNoNamedRegister picks up external CLIPBOARD changes after a yank":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)
      r.storeYanked(none(char), "cached internal", false)

      # storeYanked writes synchronously; verify they landed before
      # the external write below.
      let clipSeeded = readClipboardWithRetry(tool, "cached internal")
      check clipSeeded.isOk and clipSeeded.get() == "cached internal"
      let primarySeeded = readPrimaryWithRetry(tool, "cached internal")
      check primarySeeded.isOk and primarySeeded.get() == "cached internal"

      # An external copy after moe's yank is picked up by the next put.
      let testText = "external copy after yank"
      let writeResult = writeToClipboardSync(tool, testText)
      check writeResult.isOk

      let clipReady = readClipboardWithRetry(tool, testText)
      check clipReady.isOk and clipReady.get() == testText

      # On Wayland, expire the claim window so the external change is
      # observed.
      if tool == cbtWlClipboard:
        expireClipboardClaimWindow(r)

      let reg = r.getNoNamedRegister()
      check reg.getContent() == testText

      cleanup(tool)

  test "a yank writes to PRIMARY selection":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)

      let testText = "primary selection test"
      r.storeYanked(none(char), testText, false)

      # Read back from PRIMARY selection (writes are synchronous)
      let readResult = readPrimaryWithRetry(tool, testText)
      check readResult.isOk
      check readResult.get() == testText

      cleanup(tool)

  test "a yank writes to both CLIPBOARD and PRIMARY":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)

      let testText = "dual clipboard test"
      r.storeYanked(none(char), testText, false)

      # Writes are synchronous
      let clipResult = readClipboardWithRetry(tool, testText)
      check clipResult.isOk
      check clipResult.get() == testText

      let primaryResult = readPrimaryWithRetry(tool, testText)
      check primaryResult.isOk
      check primaryResult.get() == testText

      cleanup(tool)

  test "yank syncs to PRIMARY selection":
    let (available, tool) = getAvailableTool()
    if not available:
      skip()
    else:
      let r = initRegisters()
      r.setClipboardTool(tool)

      let testText = "yanked to primary"
      r.storeYanked(none(char), testText, false)

      let primaryResult = readPrimaryWithRetry(tool, testText)
      check primaryResult.isOk
      check primaryResult.get() == testText

      cleanup(tool)
