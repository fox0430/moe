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

import std/[unittest, options, strutils]

import pkg/results

import
  ../src/moepkg/[
    buffer, types, modes, editor, config, key_bindings, handler, registers, visual_block
  ]

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  # newEditor's registers reach the system clipboard.
  result.state.registers = initRegisters()
  result.state.config.standard.tabStop = 4
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

proc lines(e: Editor): seq[string] =
  for i in 0 ..< e.activeBuffer.len:
    result.add e.activeBuffer.getLine(i)

proc yanked(e: Editor): string =
  e.state.registers.getNoNamedRegister().getContent()

proc areaOf(lines: openArray[string], anchor, cursor: BufferPosition): BlockArea =
  let buf = newTextBuffer(lines.join("\n"))
  buf.blockArea(
    VisualSelection(start: anchor, current: cursor, active: true, kind: vskBlock),
    tabStop = 4,
  )

suite "blockArea":
  test "takes a tab's cells from where it starts to where it ends":
    # The cursor on the tab (cells 1-3) starts the block at the tab.
    let area = areaOf(
      ["abcdefgh", "a\tb"],
      BufferPosition(line: 0, column: 2),
      BufferPosition(line: 1, column: 1),
    )
    check area.startCell == 1
    check area.endCell == 3
    check area.topLeft == BufferPosition(line: 0, column: 1)

  test "takes both cells of a wide character":
    let area = areaOf(
      ["日本", "abcd"],
      BufferPosition(line: 0, column: 0),
      BufferPosition(line: 1, column: 0),
    )
    check area.startCell == 0
    check area.endCell == 1

  test "after <C-v>$ ends where the widest line does":
    let buf = newTextBuffer("abcdef\nab\nabcdefgh")
    let area = buf.blockArea(
      VisualSelection(
        start: BufferPosition(line: 0, column: 3),
        current: BufferPosition(line: 2, column: 8),
        active: true,
        kind: vskBlock,
        extendsToLineEnd: true,
      ),
      tabStop = 4,
    )
    check area.toLineEnd
    check area.startCell == 3
    check area.endCell == 8

suite "blockLine":
  test "a yank leaves a tab the edge cuts through out, counting its inner cells":
    let area = BlockArea(startCell: 2, endCell: 4)
    let cut = area.blockLine("a\tb", 4, buTake)
    check cut.textCol == 2
    check cut.textLen == 1
    check cut.startSpaces == 2
    check cut.takenText("a\tb") == "  b"

  test "a delete takes the cut tab whole, with its outer cells as blanks":
    let area = BlockArea(startCell: 2, endCell: 4)
    let cut = area.blockLine("a\tb", 4, buDelete)
    check cut.textCol == 1
    check cut.textLen == 2
    check cut.startSpaces == 1

  test "a line ending before the block is short, and a yank fills it":
    let area = BlockArea(startCell: 3, endCell: 6)
    let cut = area.blockLine("ab", 4, buTake)
    check cut.isShort
    check cut.takenText("ab") == "    "

  test "a line ending where the block starts gives nothing":
    let area = BlockArea(startCell: 2, endCell: 4)
    check area.blockLine("ab", 4, buTake).takenText("ab") == ""

  test "a combining mark goes with the character it follows":
    let area = BlockArea(startCell: 1, endCell: 1)
    check area.blockLine("ae\u0301x", 4, buTake).takenText("ae\u0301x") == "e\u0301"
    check area.blockLine("e\u0301x", 4, buTake).takenText("e\u0301x") == "x"

suite "rewriteBlock":
  test "starts the change at the top left, or a line below at its start":
    let buf = newTextBuffer("abcdef\nabcdef\nabcdef")
    var area = BlockArea(
      firstLine: 0,
      lastLine: 2,
      startCell: 2,
      endCell: 3,
      topLeft: BufferPosition(column: 2),
    )
    let append = proc(area: BlockArea, text: string, cut: BlockLine): string =
      text & "x"
    check buf.rewriteBlock(area, 4, buTake, append).isOk
    check buf.changeList[^1] == BufferPosition(line: 0, column: 2)
    # The copy of what an insert typed, as Vim's block_insert reports it.
    area.firstLine = 1
    check buf.rewriteBlock(area, 4, buTake, append).isOk
    check buf.changeList[^1] == BufferPosition(line: 1, column: 0)

suite "shownOn":
  test "covers a tab any of whose cells the block covers":
    let shown = BlockArea(startCell: 2, endCell: 4).shownOn(0, "a\tbc", 4)
    check shown.columns == 1 .. 2
    # The tab's first cell is left of the block.
    check shown.leadCells == 1
    check shown.trailCells == 0

  test "counts the cells of a tab right of the block":
    let shown = BlockArea(startCell: 1, endCell: 2).shownOn(0, "ab\tc", 4)
    check shown.columns == 1 .. 2
    check shown.leadCells == 0
    check shown.trailCells == 1

  test "covers a wide character half inside, with no cells left out":
    let shown = BlockArea(startCell: 1, endCell: 1).shownOn(0, "日本", 4)
    check shown.columns == 0 .. 0
    check shown.leadCells == 0
    check shown.trailCells == 0

  test "shows over nothing by default":
    check BlockShown().columns.len == 0

  test "runs to the line end after <C-v>$":
    check BlockArea(startCell: 1, endCell: 2, toLineEnd: true).shownOn(0, "abcdef", 4).columns ==
      1 .. 5

  test "is empty on a line ending before the block":
    let shown = BlockArea(startCell: 4, endCell: 6).shownOn(0, "ab", 4).columns
    check shown.b < shown.a

  test "shows the end of an empty first or last line, not of one between":
    let area = BlockArea(firstLine: 0, lastLine: 2, startCell: 0, endCell: 1)
    check area.shownOn(0, "", 4).lineEnd
    check area.shownOn(2, "", 4).lineEnd
    check not area.shownOn(1, "", 4).lineEnd

  test "shows the end of a first or last line it starts at":
    # The cursor rests past the end of `ab` after `<C-v>j` from `f` of `abcdef`.
    let area = BlockArea(firstLine: 0, lastLine: 1, startCell: 2, endCell: 5)
    let shown = area.shownOn(1, "ab", 4)
    check shown.lineEnd
    check shown.columns.len == 0
    check not area.shownOn(0, "abcdef", 4).lineEnd

  test "leaves a combining mark to draw with its character":
    check BlockArea(startCell: 0, endCell: 0).shownOn(0, "e\u0301x", 4).columns == 0 .. 0
    # The tab is still the last character, so its cells right of the block
    # show unselected.
    let shown = BlockArea(startCell: 1, endCell: 2).shownOn(0, "a\t\u0301b", 4)
    check shown.columns == 1 .. 1
    check shown.trailCells == 1

suite "Visual block operators count screen cells":
  # Expectations measured in Vim 9.2 with tabstop=4.
  test "yank pads a line too short for the block":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("5", "|", "C-v", "j", "j", "7", "|", "y")
    check e.yanked == "ef\n   \nef"
    check e.cursor == BufferPosition(line: 0, column: 4)

  test "yank after <C-v>$ pads from where the widest line ends":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "y")
    check e.yanked == "def\n    \ndef"

  test "yank takes a tab's inner cells as blanks":
    let e = newTestEditor("abcdefgh\na\tb")
    e.press("3", "|", "C-v", "j", "l", "y")
    check e.yanked == "cde\n  b"
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "yank leaves the cursor on the block's top left":
    let e = newTestEditor("abcdef\nabcdef")
    e.press("4", "|", "C-v", "j", "h", "h", "y")
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "yank takes a wide character whole":
    let e = newTestEditor("abcdef\na日b")
    e.press("3", "|", "C-v", "j", "y")
    check e.yanked == "bc\n日"
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "delete leaves blanks for a cut tab's outer cells":
    let e = newTestEditor("abcdefgh\na\tb")
    e.press("3", "|", "C-v", "j", "l", "d")
    check e.lines == @["abfgh", "a "]
    check e.yanked == "cde\n  b"
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "change types at the block's left edge on each line":
    let e = newTestEditor("abcdefgh\na\tb")
    e.press("3", "|", "C-v", "j", "l", "c", "X", "Y", "Escape")
    check e.lines == @["abXYfgh", "a XY"]

  test "change skips a line ending before the block":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "l", "c", "X", "Y", "Escape")
    check e.lines == @["abcXYf", "ab", "abcXYf"]

  test "replace fills the cells, a cut tab's outer ones with blanks":
    let e = newTestEditor("abcdefgh\na\tb")
    e.press("3", "|", "C-v", "j", "l", "r", "Z")
    check e.lines == @["abZZZfgh", "a ZZZ"]
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "replace with a wide character goes in once for every two cells":
    let e = newTestEditor("日本語\nabcdef")
    e.press("C-v", "j", "r", "x")
    check e.lines == @["xx本語", "xxcdef"]

  test "replace after <C-v>$ stops at each line's end":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "r", "Z")
    check e.lines == @["abcZZZ", "ab", "abcZZZ"]

  test "a repeated replace covers as many cells from the cursor":
    let e = newTestEditor("a\tbcd\na\tbcd\nabcdefgh\nabcdefgh")
    # The block is the tab, cells 1-3.
    e.press("3", "|", "C-v", "j", "r", "Z", "j", "j", "0", ".")
    check e.lines == @["aZZZbcd", "aZZZbcd", "ZZZdefgh", "ZZZdefgh"]
    check e.cursor == BufferPosition(line: 2, column: 0)

  test "a repeated replace after <C-v>$ goes to each line's end":
    let e = newTestEditor("abcdefgh\nab\nabcdefgh\nabcdefgh\nab")
    e.press("3", "|", "C-v", "j", "$", "r", "Z", "j", "j", "0", ".")
    check e.lines == @["abZZZZZZ", "ab", "ZZZZZZZZ", "ZZZZZZZZ", "ab"]

  test "a case change leaves the cursor on the block's top left":
    let e = newTestEditor("abcdef\nxy")
    e.press("$", "C-v", "j", "U")
    check e.lines == @["abCDEF", "xy"]
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "insert splits a tab the block's edge cuts through":
    let e = newTestEditor("abcdefgh\nab\tc\nabcdefgh")
    # The block starts at cell 3, inside the tab (cells 2-3) on line 1.
    e.press("4", "|", "C-v", "j", "j", "I", "X", "Y", "Escape")
    check e.lines == @["abcXYdefgh", "ab XY c", "abcXYdefgh"]

  test "append goes right of a tab inside the block":
    let e = newTestEditor("abcdefgh\na\tb")
    e.press("3", "|", "C-v", "j", "A", "X", "Y", "Escape")
    check e.lines == @["abcdXYefgh", "a\tXYb"]

  test "append pads a first line too short for the block":
    let e = newTestEditor("ab\nabcdef")
    e.press("2", "|", "C-v", "j", "3", "|", "A", "X", "Y", "Escape")
    check e.lines == @["ab XY", "abcXYdef"]
    # The change list takes where typing started, not the padding.
    check e.activeBuffer.changeList[^1] == BufferPosition(line: 0, column: 3)
    e.press("u")
    check e.lines == @["ab", "abcdef"]

  test "append leaves the cursor where it was when the padding fails":
    let e = newTestEditor("ab\nabcdef")
    e.press("2", "|", "C-v", "j", "3", "|")
    let before = e.cursor
    e.activeBuffer.readOnly = true
    e.press("A")
    check e.lines == @["ab", "abcdef"]
    check e.cursor == before

  test "append after <C-v>$ goes at each line's end":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "$", "A", "X", "Y", "Escape")
    check e.lines == @["abcdefXY", "abXY", "abcdefXY"]

  test "put goes into each line at the first line's screen cell":
    let e = newTestEditor("abcdefghij\nxy\tz\nabcdefghij")
    e.state.registers.storeYanked(none(char), "Q", false)
    # Cells 4-6; on line 1 only `z` (cell 4) is inside.
    e.press("5", "|", "C-v", "j", "j", "7", "|", "p")
    check e.lines == @["abcdQhij", "xy\tQ", "abcdQhij"]

  test "surround leaves the cursor on the first line's last character":
    # The cursor rests past the end of `ab`, where the block starts.
    let e = newTestEditor("ab\nabcdef")
    e.press("j", "6", "|", "C-v", "k", "S", "(")
    check e.lines == @["ab", "ab(cdef)"]
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "keeps undecodable bytes on the lines it rewrites":
    let e = newTestEditor("abcd\xff\nabc\xe3e")
    e.activeBuffer.keepRaw = true
    e.press("2", "|", "C-v", "j", "l", "d")
    check e.lines == @["ad\xff", "a\xe3e"]
    e.press("u", "g", "g", "2", "|", "C-v", "j", "I", "X", "Escape")
    check e.lines == @["aXbcd\xff", "aXbc\xe3e"]

  test "takes a combining mark with the character it follows":
    let e = newTestEditor("e\u0301x\nab")
    e.press("C-v", "j", "d")
    check e.lines == @["x", "b"]
    check e.yanked == "e\u0301\na"

  test "keeps a combining mark on its character for the other operators":
    let e = newTestEditor("abcd\ne\u0301xy")
    e.state.registers.storeYanked(none(char), "Q", false)
    e.press("2", "|", "C-v", "j", "p")
    check e.lines == @["aQcd", "e\u0301Qy"]
    e.press("u", "g", "g", "C-v", "j", "A", "Z", "Escape")
    check e.lines == @["aZbcd", "e\u0301Zxy"]
    e.press("u", "g", "g", "2", "|", "C-v", "j", "I", "Z", "Escape")
    check e.lines == @["aZbcd", "e\u0301Zxy"]
    e.press("u", "g", "g", "C-v", "j", "~")
    check e.lines == @["Abcd", "E\u0301xy"]

  test "marks only the lines it changes as modified":
    let e = newTestEditor("abcdef\n\nab\nabcdef")
    e.press("4", "|", "C-v", "3", "j", "l", "d")
    check e.lines == @["abcf", "", "ab", "abcf"]
    check e.activeBuffer.modifiedLines[1] == lmkUnmodified
    check e.activeBuffer.modifiedLines[2] == lmkUnmodified
    check e.activeBuffer.modifiedLines[3] == lmkModified

  test "marks only the lines a copied insert changes as modified":
    let e = newTestEditor("abcdef\nab\nabcdef")
    e.press("4", "|", "C-v", "j", "j", "I", "X", "Escape")
    check e.lines == @["abcXdef", "ab", "abcXdef"]
    check e.activeBuffer.modifiedLines[1] == lmkUnmodified
    check e.activeBuffer.modifiedLines[2] == lmkModified
