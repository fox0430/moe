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

## Ctrl-R and Ctrl-V at the prompts, through the keys. The results are Vim
## 9.2's, the ones with 'incsearch' and a typed Ctrl-C measured in a terminal.

import std/[options, os, strutils, tables, unittest]

import pkg/results

import
  ../src/moepkg/[
    buffer, command_completion, config, editor, handler, key_bindings, keybind_config,
    modes, prompt_line, registers, render_utils, types,
  ]

import clipboard_test_helper

proc createEditor(lines: seq[string], line = 0, column = 0, incsearch = false): Editor =
  var cfg = newEditorConfig()
  cfg.standard.incrementalSearch = incsearch
  cfg.standard.smartcase = false
  cfg.standard.ignorecase = false
  cfg.clipboard.enable = false
  result = newEditor(cfg)
  result.state.registers = initRegisters()
  result.state.input.commandState.history = @[]
  result.state.input.search.history = @[]
  let buf = newTextBuffer(lines.join("\n") & "\n")
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftCell: 0)
  result.motionController.bindToWindow(result.activeWindow)
  result.state.mode = EditorMode.Normal
  result.activeWindow.cursor = BufferPosition(line: line, column: column)

proc press(e: Editor, keys: varargs[string]) =
  ## Type `keys`, a name each. A string of one character is that character.
  for k in keys:
    if k == "C-c":
      discard e.handleInterrupt()
    else:
      discard e.handleKeyCombo(parseKeyCombo(k).get)

proc typeText(e: Editor, text: string) =
  for r in text:
    e.press($r)

proc setReg(e: Editor, name: char, text: string, isLine = false) =
  check e.state.registers.setRegister(name, text, isLine).isOk

template line(e: Editor): string =
  e.state.input.line.text

template cursorChar(e: Editor): int =
  e.state.input.line.cursor

suite "prompt: Ctrl-R":
  test "the text goes in at the cursor, and typing goes on after it":
    let e = createEditor(@["x"])
    e.setReg('a', "foo bar")
    e.press(":", "x", "y", "Left", "C-r", "a")
    check e.line == "xfoo bary"
    check e.cursorChar == 8
    e.press("z")
    check e.line == "xfoo barzy"

  test "an upper case name reads the same register":
    let e = createEditor(@["x"])
    e.setReg('a', "foo")
    e.press("/", "C-r", "A")
    check e.line == "foo"

  test "lines end in a CR, linewise text the last one too":
    let e = createEditor(@["x"])
    e.setReg('a', "l1\nl2", isLine = true)
    e.setReg('b', "m1\nm2")
    e.press(":", "C-r", "a")
    check e.line == "l1\rl2\r"
    e.press("C-u", "C-r", "b")
    check e.line == "m1\rm2"

  test "a key that names no register, or a register with no text, adds nothing":
    let e = createEditor(@["x"])
    e.press(":", "x")
    for key in ["z", "!", "_", "Up", "Enter", "Backspace", "Escape", "C-f"]:
      e.press("C-r", key)
      check e.line == "x"
    e.press("y")
    check e.line == "xy"

  test "Ctrl-R Ctrl-R and Ctrl-R Ctrl-O put the text in literally":
    let e = createEditor(@["x"])
    e.setReg('a', "ab\x08c\x1b")
    e.press(":", "C-r", "C-r", "a")
    check e.line == "ab\x08c\x1b"
    e.press("C-u", "C-r", "C-o", "a")
    check e.line == "ab\x08c\x1b"

  test "the text goes in as typed but for what would end the line":
    let e = createEditor(@["x"])
    e.setReg('a', "ab\x08c\x1bd\re\x03f\x0cg")
    e.press(":", "C-r", "a")
    check e.line == "ac\x1bd\re\x03f\x0cg"

  test "keys in the text run, and a Ctrl-V there covers the next character":
    let e = createEditor(@["x"])
    e.setReg('a', "ab cd\x17e\x02f\x05g\x16\x08h\x16")
    e.press(":", "C-r", "a")
    check e.line == "fab eg\x08h\x16"

  test "text after a key that runs is still put in as it is":
    let e = createEditor(@["x"])
    e.setReg('a', "a\x08\x1bb\x18c\td\x7fe")
    e.press(":", "C-r", "a")
    check e.line == "\x1bb\x18c\td\x7fe"

  test "a Ctrl-V that ends a line of a register covers nothing":
    for (text, isLine, typedIn) in [
      ("b\x16\nc", false, "b\x16\rc"),
      ("b\x16\nc", true, "b\x16\rc\r"),
      ("\x02b\nc\x16\nd", false, "b\rc\x16\rd"),
    ]:
      let e = createEditor(@["x"])
      e.setReg('a', text, isLine)
      e.press(":", "C-r", "a")
      check e.line == typedIn

  test "a CR in the text after a Ctrl-V is covered, as it is not a line's end":
    let e = createEditor(@["x"])
    e.setReg('a', "a\x16\rb")
    e.press(":", "C-r", "a")
    check e.line == "a\rb"

  test "keys that only edit the line run with the text, not one by one":
    let e = createEditor(@["x"])
    e.setReg('a', "ab\x08c\x02d\x05e\x15f\x16\x1bg\n" & "h".repeat(1000))
    e.press(":", "C-r")
    discard e.state.editPrompt(e.activeBuffer, parseKeyCombo("a").get, @[])
    check e.state.stuffedKeys.len == 0
    check e.line == "f\x1bg\r" & "h".repeat(1000)

  test "text goes in where the keys before it left the cursor":
    let e = createEditor(@["x"])
    e.setReg('a', "\x02ab\x05cd\x02\x16\te")
    e.press(":", "z", "C-r", "a")
    check e.line == "\teabzcd"
    check e.cursorChar == 2

  test "text before a key that stops them goes in":
    let e = createEditor(@["x"])
    e.setReg('a', "\x05a\x10b")
    e.press(":", "C-r", "a", "y")
    check e.line == "ay"

  test "text after a key that runs keeps its bytes":
    # 0xE9 leads a three byte character but must not take what follows it.
    for text in ["caf\xE9 x", "\xE9", "a\xE3\x81", "\xE9\nb"]:
      let e = createEditor(@["x"])
      e.setReg('a', "\x02" & text)
      e.press(":", "z", "C-r", "a")
      check e.line == text.replace('\n', '\r') & "z"

  test "a Ctrl-V covers the last character of the text":
    for (text, expected) in [("a\x16\x02", "a\x02"), ("\x05\x16\x02", "\x02")]:
      let e = createEditor(@["x"])
      e.setReg('a', text)
      e.press(":", "C-r", "a")
      check e.line == expected

  test "a byte a Ctrl-V covers goes in as it is":
    let e = createEditor(@["x"])
    e.setReg('a', "\x02\x16\xE9 x")
    e.press(":", "C-r", "a")
    check e.line == "\xE9 x"

  test "a selection that cannot be read has no text, and stops nothing":
    let fakeDir = installFakeClipboardTool("")
    if fakeDir.len == 0:
      skip()
    else:
      try:
        writeFile(fakeDir / "xclip", "#!/bin/sh\nexit 1\n")
        let e = createEditor(@["x"])
        e.state.config.clipboard = ClipboardConfig(enable: true, tool: cbtXclip)
        e.state.registers.setClipboardTool(cbtXclip)
        e.state.pendingInput.macroState.registers['m'] = @[":", "<C-r>", "+", "z"]
        e.press("@", "m")
        check e.line == "z"
      finally:
        removeFakeClipboardTool(fakeDir)

  test "a key the line does not take goes on as a key":
    # The Ctrl-Q takes the Ctrl-V that covers the Esc, which then runs the line.
    let e = createEditor(@["x"])
    e.setReg('a', "qq\x11\x1bb")
    e.press("/", "C-r", "a")
    check not e.state.isSearchOverlay
    check e.state.input.search.last.pattern == "qq\x16"

  test "a Ctrl-R in the text reads a register in place":
    let e = createEditor(@["x"])
    e.setReg('a', "a\x12gb")
    e.setReg('g', "GG")
    e.press(":", "C-r", "a")
    check e.line == "aGGb"

  test "a register that puts in itself ends":
    let e = createEditor(@["x"])
    e.setReg('a', "a\x12a")
    e.press(":", "C-r", "a")
    check e.state.isCommandOverlay
    check e.line.startsWith("aa")
    check "recursive" in e.state.statusMessage

  test "keys that end the line go on in the mode it returns to":
    let e = createEditor(@["foo"])
    e.setReg('a', "\x08x")
    e.press(":", "C-r", "a")
    check not e.state.isCommandOverlay
    check e.activeBuffer.getLine(0) == "oo"

  test "keys in the text stop at a beep, the typed ones do not":
    let e = createEditor(@["x"])
    e.setReg('a', "a\x10b")
    e.press(":", "C-r", "a", "y")
    check e.line == "ay"

  test "a mapping does not take what Ctrl-R reads":
    let e = createEditor(@["x"])
    e.setReg('a', "A")
    e.setReg('b', "B")
    check e.keyRouter.registry.addRuntimeMappingExpanded(
      EditorMode.Command, "a", "b", forceKeySeq = true
    ).len == 0
    e.press(":", "C-r", "a")
    check e.line == "A"

  test "a mapping can run Ctrl-R":
    let e = createEditor(@["x"])
    e.setReg('a', "A")
    check e.keyRouter.registry.addRuntimeMappingExpanded(
      EditorMode.Command, "q", "C-r a", forceKeySeq = true
    ).len == 0
    e.press(":", "q")
    check e.line == "A"

  test "a typed Ctrl-C leaves the prompt, as after any key":
    let e = createEditor(@["foo"])
    e.press(":", "a", "C-r", "C-c")
    check not e.state.isCommandOverlay
    e.press("/", "a", "C-r", "C-r", "C-c")
    check not e.state.isSearchOverlay

  test "Esc only ends the Ctrl-R":
    let e = createEditor(@["x"])
    e.press(":", "a", "C-r", "Escape")
    check e.state.isCommandOverlay
    check e.line == "a"

suite "prompt: Ctrl-R, registers of their own":
  test "% is the file name, and E32 without one":
    let e = createEditor(@["x"])
    e.press(":", "C-r", "%")
    check e.state.statusMessage == "E32: No file name"
    e.press("x")
    check e.line == "x"
    e.activeBuffer.filePath = some("dir/foo.txt")
    e.press("C-u", "C-r", "%")
    check e.line == "dir/foo.txt"

  test "/ is the last search, and E35 without one":
    let e = createEditor(@["x"])
    e.state.input.search.last = SearchSpec()
    e.press(":", "C-r", "/")
    check e.state.statusMessage.startsWith("E35")
    e.state.input.search.last = SearchSpec(pattern: "pat")
    e.press("C-r", "/")
    check e.line == "pat"

  test ": is the last command line, and E30 without one":
    let e = createEditor(@["x"])
    e.press(":", "C-r", ":")
    check e.state.statusMessage.startsWith("E30")
    e.press("Escape", ":")
    e.typeText("noh")
    e.press("Enter", ":", "C-r", ":")
    check e.line == "noh"

  test "an error stops the keys after it in a register, and stays in the prompt":
    for keys in [@[":", "<C-r>", "%", "z"], @["/", "<C-r>", ":", "z"]]:
      let e = createEditor(@["x"])
      e.state.pendingInput.macroState.registers['m'] = keys
      e.press("@", "m")
      check e.state.hasOverlay
      check e.line == ""

suite "prompt: Ctrl-R and what is under the cursor":
  const Lines = @["  foo-bar baz.qux  ", "", "日本語 abc"]

  test "Ctrl-W takes the word, Ctrl-A the WORD, under or after the cursor":
    for (column, word, bigWord) in [
      (0, "foo", "foo-bar"),
      (4, "foo", "foo-bar"),
      (5, "bar", "foo-bar"),
      (9, "baz", "baz.qux"),
      (12, "baz", "baz.qux"),
      (16, "qux", "baz.qux"),
    ]:
      let e = createEditor(Lines, column = column)
      e.press(":", "C-r", "C-w")
      check e.line == word
      e.press("C-u", "C-r", "C-a")
      check e.line == bigWord

  test "E348 past the last word or on an empty line":
    for (line, column) in [(0, 17), (1, 0)]:
      let e = createEditor(Lines, line, column)
      e.press(":", "C-r", "C-w")
      check e.state.statusMessage.startsWith("E348")
      e.press("x")
      check e.line == "x"

  test "Ctrl-W and Ctrl-A take a run of one class in Japanese":
    let e = createEditor(Lines, 2, 1)
    e.press(":", "C-r", "C-w")
    check e.line == "日本語"
    e.press("C-u", "C-r", "C-a")
    check e.line == "日本語"

  test "Ctrl-L takes the line, which may be empty":
    let e = createEditor(Lines)
    e.press(":", "C-r", "C-l")
    check e.line == Lines[0]
    let empty = createEditor(Lines, 1)
    empty.press(":", "x", "C-r", "C-l")
    check empty.line == "x"

  test "Ctrl-R Ctrl-R takes them too":
    let e = createEditor(Lines, column = 3)
    e.press(":", "C-r", "C-r", "C-w")
    check e.line == "foo"
    e.press("C-u", "C-r", "C-o", "C-a")
    check e.line == "foo-bar"

suite "prompt: Ctrl-R Ctrl-W with 'incsearch'":
  const Lines = @["one foobar two", "three foo four foobaz"]

  proc lineAfter(keys: openArray[string], line = 1, column = 0): string =
    let e = createEditor(Lines, line, column, incsearch = true)
    e.press(keys)
    e.line

  test "it reads just past the match, and leaves out what was typed of the word":
    check lineAfter(["/", "f", "o", "C-r", "C-w"]) == "foo"
    check lineAfter(["/", "t", "h", "r", "C-r", "C-w"]) == "three"
    check lineAfter(["/", "o", "n", "C-r", "C-w"]) == "one"
    check lineAfter(["?", "f", "o", "C-r", "C-w"]) == "foobar"
    check lineAfter(["/", "f", "o", "o", " ", "f", "C-r", "C-w"]) == "foo four"

  test "a whole word typed goes on to the next":
    check lineAfter(["/", "f", "o", "C-r", "C-w", "C-r", "C-w"]) == "foofour"

  test "with no match it reads where the search began":
    check lineAfter(["/", "z", "z", "C-r", "C-w"]) == "zzthree"

  test "Ctrl-A and Ctrl-L read there too, and drop nothing":
    check lineAfter(["/", "f", "o", "C-r", "C-a"]) == "fofoo"
    check lineAfter(["/", "f", "o", "C-r", "C-l"]) == "fothree foo four foobaz"

  test "the text before the cursor must start the word":
    check lineAfter([":", "f", "o", "o", "C-r", "C-w"], 0, 5) == "foobar"
    check lineAfter([":", "x", "y", "C-r", "C-w"], 0, 5) == "xyfoobar"
    check lineAfter([":", "t", ".", "f", "o", "o", "C-r", "C-w"], 0, 5) == "t.foobar"
    check lineAfter([":", "F", "O", "O", "C-r", "C-w"], 0, 5) == "FOOfoobar"

  test "'ignorecase' goes for that check":
    let e = createEditor(Lines, 0, 5, incsearch = true)
    e.state.input.search.ignorecase = true
    e.press(":", "F", "O", "O", "C-r", "C-w")
    check e.line == "FOObar"

  test "without 'incsearch' the word goes in whole":
    let e = createEditor(Lines, 0, 5)
    e.press(":", "f", "o", "o", "C-r", "C-w")
    check e.line == "foofoobar"

  test ":s reads as a search does until the pattern is followed by more":
    check lineAfter([":", "s", "/", "f", "o", "C-r", "C-w"]) == "s/foo"
    check lineAfter([":", "s", "/", "f", "o", "C-r", "C-l"]) ==
      "s/fothree foo four foobaz"
    check lineAfter([":", "s", "/", "f", "o", "/", "C-r", "C-w"]) == "s/fo/three"

  test "the line a :s preview has changed is read as it was":
    let e = createEditor(@["foobar baz"])
    e.press(":", "s", "/", "f", "o", "o", "/", "C-r", "C-w")
    check e.line == "s/foo/foobar"
    e.press("C-u", "s", "/", "f", "o", "o", "/", "C-r", "C-l")
    check e.line == "s/foo/foobar baz"

  test "a line below one a :s preview has broken is read as it was":
    let e = createEditor(@["a,b", "foo bar"], 1, 0)
    e.typeText(":%s/,/\\r/")
    check e.activeBuffer.len == 3
    e.press("C-r", "C-l")
    check e.line == "%s/,/\\r/foo bar"

  test "without 'incsearch' :s reads where the cursor was":
    let e = createEditor(Lines, 1, 0)
    e.press(":", "s", "/", "f", "o", "C-r", "C-w")
    check e.line == "s/fothree"

suite "prompt: where :s leaves the cursor as it is typed":
  const Lines = @["one", "two", "foo"]

  test "without 'incsearch' it stays":
    let e = createEditor(Lines)
    e.press(":", "%", "s", "/", "f", "o", "o")
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "with 'incsearch' it goes to the match":
    let e = createEditor(Lines, incsearch = true)
    e.press(":", "%", "s", "/", "f", "o", "o")
    check e.cursor == BufferPosition(line: 2, column: 0)

suite "prompt: Ctrl-V":
  test "a key goes in as it is":
    for (key, text) in [
      ("a", "a"),
      ("Escape", "\x1b"),
      ("Enter", "\r"),
      ("Tab", "\t"),
      ("Backspace", "\x7f"),
      ("C-a", "\x01"),
      ("C-u", "\x15"),
      ("C-r", "\x12"),
      ("C-v", "\x16"),
      ("あ", "あ"),
      ("Up", "<Up>"),
      ("F2", "<F2>"),
      ("S-Up", "<S-Up>"),
      ("C-Left", "<C-Left>"),
      ("Delete", "<Del>"),
    ]:
      for lead in ["C-v", "C-q"]:
        let e = createEditor(@["x"])
        e.press(":", lead, key)
        check e.line == text
        check e.state.isCommandOverlay

  test "Ctrl-@ goes in as the line feed Vim keeps a NUL as":
    let e = createEditor(@["x"])
    e.press(":", "C-v")
    # The terminal sends it as Ctrl-Space.
    discard e.handleKeyCombo(KeyCombo(isSpecial: false, char: " ", modifiers: {kmCtrl}))
    check e.line == "\n"

  test "a code is decimal, or octal, hex or Unicode after a letter":
    for (keys, text) in [
      ("065", "A"),
      ("1234", "{4"),
      ("256", "ÿ"),
      ("999", "ÿ"),
      ("x41", "A"),
      ("X41y", "Ay"),
      ("xx41", "A"),
      ("o101", "A"),
      ("O777", "ÿ"),
      ("u3042", "あ"),
      ("U0001f600", "😀"),
      ("U1f600x", "😀"),
      ("000", "\n"),
      ("x00", "\n"),
      ("xe9", "é"),
    ]:
      let e = createEditor(@["x"])
      e.press(":", "C-v")
      e.typeText(keys)
      check e.line == text

  test "a key that ends a code runs on its own":
    for (keys, text) in [
      ("65z", "Az"),
      ("o8", "8"),
      ("x4g", "\x04g"),
      ("u30g", "0g"),
      ("xg", "g"),
      ("65x1", "A1"),
      ("o12x", "\n"),
    ]:
      let e = createEditor(@["x"])
      e.press(":", "C-v")
      e.typeText(keys)
      check e.line == text

  test "Enter, Esc and Ctrl-U do what they do after a code":
    let e = createEditor(@["foo"])
    e.press("/", "C-v", "6", "6", "Enter")
    check not e.state.isSearchOverlay
    check e.state.input.search.last.pattern == "B"

    e.press("/", "C-v", "6", "6", "Escape")
    check not e.state.isSearchOverlay
    check e.state.input.search.last.pattern == "B"

    e.press("/", "C-v", "6", "6", "C-u", "x")
    check e.line == "x"

  test "the typed key that ends a code runs at the depth stuffed keys stop at":
    let e = createEditor(@["foo"])
    e.keyRouter.mapExpandDepth = 1000
    e.press("/", "C-v", "6", "5", "Escape")
    check not e.state.isSearchOverlay

  test "a mapping takes neither the key nor the digits, nor the key after a code":
    let e = createEditor(@["x"])
    for lhs in ["a", "6"]:
      check e.keyRouter.registry.addRuntimeMappingExpanded(
        EditorMode.Command, lhs, "b", forceKeySeq = true
      ).len == 0
    e.press(":", "C-v", "a")
    check e.line == "a"
    e.press("C-u", "C-v", "6", "5", "a")
    check e.line == "Aa"

  test "a typed Ctrl-C goes in, but ends a code and leaves":
    let e = createEditor(@["x"])
    e.press(":", "a", "C-v", "C-c", "x")
    check e.line == "a\x03x"
    e.press("C-v", "x", "C-c")
    check e.line == "a\x03x\x03"
    e.press("C-v", "6", "C-c")
    check not e.state.isCommandOverlay

  test "Ctrl-W treats a control character as punctuation":
    let e = createEditor(@["x"])
    e.press(":", "f", "o", "o", "C-v", "C-a", "b", "C-w")
    check e.line == "foo\x01"
    e.press("C-w")
    check e.line == "foo"

  test "in a search it finds what it put in":
    let e = createEditor(@["ab\tc"])
    e.press("/", "C-v", "Tab", "Enter")
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 2)
    let wide = createEditor(@["xyあ"])
    wide.press("/", "C-v", "u", "3", "0", "4", "2", "Enter")
    check wide.activeWindow.cursor == BufferPosition(line: 0, column: 2)

  test "in a macro the keys are read too":
    let e = createEditor(@["x"])
    e.state.pendingInput.macroState.registers['m'] = @[":", "<C-v>", "<Escape>", "z"]
    e.press("@", "m")
    check e.line == "\x1bz"

suite "prompt: what shows":
  test "a control character shows as ^X, and the cursor stays on its character":
    let e = createEditor(@["x"])
    e.press(":", "a", "C-v", "Enter", "b", "C-v", "Tab", "Left")
    check e.state.overlayInput == (":a^Mb^I", 5)

  test "a waiting Ctrl-R and Ctrl-V show at the cursor with the rest after them":
    let e = createEditor(@["x"])
    e.press(":", "a", "b", "Left", "C-r")
    check e.state.overlayInput == (":a\"b", 2)
    e.press("Escape", "C-v")
    check e.state.overlayInput == (":a^b", 2)
    e.press("6")
    check e.state.overlayInput == (":a^b", 2)
    e.press("5", "x")
    check e.state.overlayInput == (":aAb", 3)

  test "a C1 control character shows by its code":
    let e = createEditor(@["x"])
    e.press(":", "C-v", "1", "5", "5", "a", "C-v", "u", "0", "0", "8", "5", "é")
    check e.state.overlayInput == (":<9b>a<85>é", 11)

  test "a line feed shows as the NUL it stands for":
    let e = createEditor(@["x"])
    e.press(":", "C-v", "0", "0", "0")
    check e.line == "\n"
    check e.state.overlayInput == (":^@", 3)

suite "prompt: what follows the line":
  test "the substitute preview goes with the `s/` Ctrl-U or Ctrl-W takes":
    let e = createEditor(@["aa foo bar"])
    e.press(":", "s", "/", "f", "o", "o", "/", "z")
    check e.activeBuffer.getLine(0) == "aa z bar"
    e.press("C-u")
    check not e.state.ui.substitutePreview.isActive
    check e.activeBuffer.getLine(0) == "aa foo bar"
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 0)

    e.press("s", "/", "f", "o", "o", "/", "z", "C-w", "C-w", "C-w", "C-w")
    check e.line == "s"
    check not e.state.ui.substitutePreview.isActive
    check e.activeBuffer.getLine(0) == "aa foo bar"

  test "completions go with the text they were for":
    let e = createEditor(@["x"])
    e.press(":", "w", "r", "i")
    check e.state.commandCompletionManager.isActive()
    e.press("C-u")
    check not e.state.commandCompletionManager.isActive()
    e.press("Escape", ":", "e", " ")
    e.press("C-w")
    check e.line == ""
    check not e.state.commandCompletionManager.isActive()

  test "an erase within the command name still narrows the completions":
    let e = createEditor(@["x"])
    e.press(":", "w", "r", "i", "Backspace")
    check e.state.commandCompletionManager.isActive()

  test "a paste into the line ends what Ctrl-V waits for":
    let e = createEditor(@["x"])
    e.press(":", "C-v")
    discard e.state.input.line.insertPasted("foo")
    e.press("Enter")
    check not e.state.isCommandOverlay

  test "the search follows Ctrl-R and Ctrl-U":
    let e = createEditor(@["aa", "foo"], incsearch = true)
    e.setReg('a', "foo")
    e.press("/", "C-r", "a")
    check e.activeWindow.cursor == BufferPosition(line: 1, column: 0)
    e.press("C-u")
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 0)

  test "the substitute preview follows Ctrl-R":
    let e = createEditor(@["aa", "foo"], incsearch = true)
    e.setReg('a', "foo")
    e.press(":", "%", "s", "/", "C-r", "a")
    check e.activeWindow.cursor == BufferPosition(line: 1, column: 0)

  test "Ctrl-R puts a register in a line that then runs":
    let e = createEditor(@["xy foo"])
    e.setReg('a', "foo")
    e.press("/", "C-r", "a", "Enter")
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 3)

  test "a macro records the keys, and the text is not recorded twice":
    let e = createEditor(@["foo", "foo"])
    e.setReg('a', "a\x08o")
    e.press("q", "m", "/", "C-r", "a", "Enter", "q")
    check e.state.pendingInput.macroState.registers['m'] ==
      @["/", "<C-r>", "a", "<Enter>"]

suite "prompt: the rename prompt":
  test "it takes the same keys, and an empty line stays open":
    let e = createEditor(@["foo bar"], column = 4)
    e.setReg('a', "reg")
    e.state.enterRenameOverlay("word", 0, 4)
    e.press("C-u")
    check e.line == ""
    check e.state.isRenameOverlay
    e.press("C-r", "a", " ", "C-r", "C-w")
    check e.line == "reg bar"
    e.press("C-w")
    check e.line == "reg "
    e.press("C-w", "C-w", "C-v", "x", "4", "1")
    check e.line == "A"
    check e.state.isRenameOverlay
