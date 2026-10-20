import std/[unittest, options]

import
  ../src/moepkg/[buffer, types, modes, editor, config, key_bindings, handler, registers]
import visual_test_helper

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  # newEditor's registers reach the system clipboard.
  result.state.registers = initRegisters()
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.syncActiveWindow()
  result.state.mode = EditorMode.Normal

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

suite "ScreenColumn (|)":
  test "moves to the first column":
    let e = newTestEditor("hello")
    e.press("l", "l", "|")
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "moves to the counted screen column":
    let e = newTestEditor("hello")
    e.press("3", "|")
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "counts a tab's display cells":
    let e = newTestEditor("\thello")
    e.state.config.standard.tabStop = 8
    e.press("9", "|")
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "keeps its column over a vertical move":
    let e = newTestEditor("abcdefgh\nab\nabcdefgh")
    e.press("8", "|", "j")
    check e.cursor == BufferPosition(line: 1, column: 1)
    e.press("j")
    check e.cursor == BufferPosition(line: 2, column: 7)

  test "delete to a screen column is exclusive":
    let e = newTestEditor("hello world")
    e.press("d", "3", "|")
    check e.activeBuffer.getLine(0) == "llo world"

suite "Visual block with extendsToLineEnd (<C-v>$)":
  test "yanks to each line end":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("C-v", "j", "j", "$", "y")
    check e.state.registers.getNoNamedRegister().getContent() ==
      "short\na very long line\nmid"

  test "deletes to each line end":
    let e = newTestEditor("abXX\ncDEFGH\nIJ")
    e.press("l", "C-v", "j", "j", "$", "d")
    check e.activeBuffer.getLine(0) == "a"
    check e.activeBuffer.getLine(1) == "c"
    check e.activeBuffer.getLine(2) == "I"

  test "yanks from the left edge when the anchor is right of the cursor":
    let e = newTestEditor("0123456789\nab")
    e.press("9", "|", "C-v", "j", "$", "y")
    check e.state.registers.getNoNamedRegister().getContent() == "23456789\n"

  test "deletes from the left edge when the anchor is right of the cursor":
    let e = newTestEditor("0123456789\nab")
    e.press("9", "|", "C-v", "j", "$", "d")
    check e.activeBuffer.getLine(0) == "01"
    check e.activeBuffer.getLine(1) == "ab"

  test "gv reselects a block that extended to the line end":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("C-v", "j", "$", "y")
    e.press("g", "v")
    check e.state.mode == EditorMode.VisualBlock
    check e.state.visualSelection.extendsToLineEnd
    e.press("Esc")

  test "gv after a put over the block keeps following line ends":
    let e = newTestEditor("abc\nabcdefgh\nxy\nabcdefghijkl")
    e.press("y", "i", "w", "j", "$", "C-v", "j", "p", "g", "v")
    check e.state.mode == EditorMode.VisualBlock
    check e.state.visualSelection.extendsToLineEnd
    e.press("Esc")

  test "a $ before the block extends it":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("$", "C-v", "j", "j", "d")
    check e.activeBuffer.getLine(0) == "sho"
    check e.activeBuffer.getLine(1) == "a v"
    check e.activeBuffer.getLine(2) == "mid"

  test "a $ in a Visual mode before the block extends it":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("v", "$", "C-v", "j", "j", "d")
    check e.activeBuffer.getLine(0) == ""
    check e.activeBuffer.getLine(1) == ""
    check e.activeBuffer.getLine(2) == ""

  test "a g_ that fails before the block extends it":
    let e = newTestEditor("ab\ncd")
    e.press("j", "2", "g", "_", "C-v", "d")
    check e.activeBuffer.getLine(0) == "ab"
    check e.activeBuffer.getLine(1) == ""

  test "swapping the ends in place drops the extension":
    let e = newTestEditor("abc\nabcdefgh")
    e.press("$", "C-v", "o", "j", "y")
    check e.state.registers.getNoNamedRegister().getContent() == "c\nc"

  test "r repeats to each line end":
    let e = newTestEditor("abcdef\nab\nabcdef\nabcdefghij")
    e.press("l", "C-v", "j", "$", "r", "x", "2", "j", ".")
    check e.activeBuffer.getLine(0) == "axxxxx"
    check e.activeBuffer.getLine(1) == "ax"
    check e.activeBuffer.getLine(2) == "axxxxx"
    check e.activeBuffer.getLine(3) == "axxxxxxxxx"

  test "I leaves a line that ends before the block alone":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "I", "x", "Esc")
    check e.activeBuffer.getLine(0) == "abcxdef"
    check e.activeBuffer.getLine(1) == "ab"
    check e.activeBuffer.getLine(2) == "abcxdef"

  test "c leaves a line that ends before the block alone":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "c", "X", "Esc")
    check e.activeBuffer.getLine(0) == "abcX"
    check e.activeBuffer.getLine(1) == "ab"
    check e.activeBuffer.getLine(2) == "abcX"

  test "c inserts on a line that ends at the block":
    let e = newTestEditor("abcdef\nabc\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "c", "X", "Esc")
    check e.activeBuffer.getLine(0) == "abcX"
    check e.activeBuffer.getLine(1) == "abcX"
    check e.activeBuffer.getLine(2) == "abcX"

  test "swapping the ends drops the extension":
    let e = newTestEditor("abcdef\n0123456789012345678901234567890\nab")
    e.press("C-v", "j", "j", "$", "o", "y")
    check e.state.registers.getNoNamedRegister().getContent() == "abc\n012\nab"

  test "moving the block's right edge drops the extension":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("C-v", "j", "j", "$", "h", "d")
    check e.activeBuffer.getLine(0) == "rt"
    check e.activeBuffer.getLine(1) == "ery long line"
    check e.activeBuffer.getLine(2) == ""

  test "appends to each line end":
    let e = newTestEditor("short\na very long line\nmid")
    e.press("C-v", "j", "j", "$", "A", "X", "Esc")
    check e.activeBuffer.getLine(0) == "shortX"
    check e.activeBuffer.getLine(1) == "a very long lineX"
    check e.activeBuffer.getLine(2) == "midX"

  test "appends to each line end when the anchor is right of the cursor":
    let e = newTestEditor("0123456789\nab")
    e.press("9", "|", "C-v", "j", "$", "A", "X", "Esc")
    check e.activeBuffer.getLine(0) == "0123456789X"
    check e.activeBuffer.getLine(1) == "abX"

suite "gv restores the column vertical moves aimed for":
  test "after a charwise $":
    let e = newTestEditor("abc\nabcdefgh")
    e.press("v", "$", "Esc", "g", "v", "j", "y")
    check e.state.registers.getNoNamedRegister().getContent() == "abc\nabcdefgh"

  test "after a block whose cursor fell short of the column":
    let e = newTestEditor("abcdefgh\nab\nabcdefgh")
    e.press("7", "|", "C-v", "j", "Esc", "g", "v", "j")
    check e.cursor == BufferPosition(line: 2, column: 6)
    e.press("Esc")
