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

import std/[unittest, importutils, sequtils, sugar, os, options, strformat]
import pkg/[ncurses, results]
import moepkg/syntax/highlite
import moepkg/[registers, settings, editorstatus, gapbuffer, unicodeext,
               bufferstatus, ui, windownode, quickrunutils]

import moepkg/normalmode {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Normal mode: Move to the right":
  test "Move tow to the right":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'l']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 2)

suite "Normal mode: Move to the left":
  test "Move one to the left":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    const Key = @[ru'h']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 1)

suite "Normal mode: Move to the down":
  test "Move two to the down":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'j']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 2)

suite "Normal mode: Move to the up":
  test "Move two to the up":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'k']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 0)

suite "Normal mode: Delete current character":
  test "Delete two current character":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'x']
    check status.normalCommand(Key).isNone
    status.update

    check status.bufStatus[0].buffer[0] == ru"c"

    let registers = status.registers
    check registers.noNameRegisters.buffer[0] == ru"ab"
    check registers.smallDeleteRegisters == registers.noNameRegisters

suite "Normal mode: Move to last of line":
  test "Move to last of line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'$']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 2)

suite "Normal mode: Move to first of line":
  test "Move to first of line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    const Key = @[ru'0']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 0)

suite "Normal mode: Move to first non blank of line":
  test "Move to first non blank of line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const Key = @[ru'^']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 2)

suite "Normal mode: Move to first of previous line":
  test "Move to first of previous line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"def", ru"ghi"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Key = @[ru'-']
    check status.normalCommand(Key).isNone
    status.update
    check(currentMainWindowNode.currentLine == 1)
    check(currentMainWindowNode.currentColumn == 0)

    check status.normalCommand(Key).isNone
    status.update
    check(currentMainWindowNode.currentLine == 0)
    check(currentMainWindowNode.currentColumn == 0)

suite "Normal mode: Move to first of next line":
  test "Move to first of next line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'+']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 1)
    check(currentMainWindowNode.currentColumn == 0)

suite "Normal mode: Move to last line":
  test "Move to last line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'G']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 2)

suite "Normal mode: Move to the top of the screen":
  test "Some lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = toSeq(0..101).map(x => toRunes($x))
    status.bufStatus[0].buffer = initGapBuffer(Buffer)

    currentMainWindowNode.currentLine = 100

    status.resize(100, 100)
    status.update

    const Key = @[ru'H']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentLine == 4
    check currentMainWindowNode.currentColumn == 0

  test "Some empty lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = toSeq(0..101).map(x => toRunes($x))
    status.bufStatus[0].buffer = initGapBuffer(Buffer)

    currentMainWindowNode.currentLine = 100

    status.resize(100, 100)
    status.update

    const Key = @[ru'H']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentLine == 4
    check currentMainWindowNode.currentColumn == 0

  test "Empty buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.resize(100, 100)
    status.update

    const Key = @[ru'H']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Page down":
  test "Page down":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
    for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

    status.settings.smoothScroll.enable = false

    status.resize(100, 100)
    status.update

    const Key = @[KEY_NPAGE.toRune]
    check status.normalCommand(Key).isNone
    status.update

    let
      currentLine = currentMainWindowNode.currentLine
      viewHeight = currentMainWindowNode.view.height

    check currentLine == viewHeight

suite "Normal mode: Page up":
  test "Page up":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
    for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

    status.settings.smoothScroll.enable = false

    status.resize(100, 100)
    status.update

    block:
      const Key = @[KEY_NPAGE.toRune]
      check status.normalCommand(Key).isNone
    status.update

    block:
      const Key = @[KEY_PPAGE.toRune]
      check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 0)

suite "Normal mode: Move to forward word":
  test "Move to forward word":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'w']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 8)

suite "Normal mode: Move to backward word":
  test "Move to backward word":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])
    currentMainWindowNode.currentColumn = 8

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 1
    const Key = @[ru'b']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 4)

suite "Normal mode: Move to forward end of word":
  test "Move to forward end of word":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'e']
    check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentColumn == 6)

suite "Normal mode: Open blank line below":
  test "Open blank line below":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'o']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].buffer.len == 2)
    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"")

    check(currentMainWindowNode.currentLine == 1)

    check(status.bufStatus[0].mode == Mode.insert)

suite "Normal mode: Open blank line below":
  test "Open blank line below":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'O']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].buffer.len == 2)
    check(status.bufStatus[0].buffer[0] == ru"")
    check(status.bufStatus[0].buffer[1] == ru"a")

    check(currentMainWindowNode.currentLine == 0)

    check(status.bufStatus[0].mode == Mode.insert)

suite "Normal mode: Add indent":
  test "Add indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'>']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].buffer[0] == ru"  a")

suite "Normal mode: Delete indent":
  test "Normal mode: Delete indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'<']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].buffer[0] == ru"a")

suite "Normal mode: Join line":
  test "Join line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'J']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].buffer[0] == ru"ab")

suite "Normal mode: Replace mode":
  test "Replace mode":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'R']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].mode == Mode.replace)

suite "Normal mode: Move right and enter insert mode":
  test "Move right and enter insert mode":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'a']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].mode == Mode.insert)
    check(currentMainWindowNode.currentColumn == 1)

suite "Normal mode: Move last of line and enter insert mode":
  test "Move last of line and enter insert mode":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const Key = @[ru'A']
    check status.normalCommand(Key).isNone
    status.update

    check(status.bufStatus[0].mode == Mode.insert)
    check(currentMainWindowNode.currentColumn == 3)

suite "Normal mode: Repeat last command":
  test "Repeat last command":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru "x"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Key = @[ru'.']
      check status.normalCommand(Key).isNone
      status.update

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0].len == 2)

  test "Repeat last command 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru ">"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    currentMainWindowNode.currentColumn = 0

    block:
      const Command = ru "x"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = ru "."
      check status.normalCommand(Command).isNone
      status.update

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru" abc")

  test "Repeat last command 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru "j"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = @[ru'.']

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    check(currentMainWindowNode.currentLine == 1)

suite "Normal mode: Delete the current line":
  test "Delete the current line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    status.resize(100, 100)
    status.update

    const Command = @[ru'd', ru'd']
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru "b"
    check currentBufStatus.buffer[1] == ru "c"
    check currentBufStatus.buffer[2] == ru "d"

    check status.registers.noNameRegisters == Register(buffer: @[ru "a"], isLine: true)

    check status.registers.numberRegisters[1] == Register(buffer: @[ru "a"], isLine: true)

suite "Normal mode: Delete the line from current line to last line":
  test "Delete the line from current line to last line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Command = @[ru'd', ru'G']

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

    check status.normalCommand(Command).isNone
    status.update

    let buffer = currentBufStatus.buffer
    check buffer.len == 1 and buffer[0] == ru"a"

    check status.registers.noNameRegisters.buffer == @[ru"b", ru"c", ru"d"]

suite "Normal mode: Delete the line from first line to current line":
  test "Delete the line from first line to current line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'g', ru'g']
    check status.normalCommand(Commands).isNone
    status.update

    let buffer = status.bufStatus[0].buffer
    check buffer.len == 1 and buffer[0] == ru"d"

    check status.registers.noNameRegisters.buffer == @[ru "a", ru "b", ru "c"]

suite "Normal mode: Delete inside paren and enter insert mode":
  test "Delete inside double quotes and enter insert mode (ci\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru """abc "def" "ghi""""])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'"']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside double quotes and enter insert mode (ci' command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc 'def' 'ghi'"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'\'']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc '' 'ghi'"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside curly brackets and enter insert mode (ci{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc {def} {ghi}"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc {} {ghi}"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside round brackets and enter insert mode (ci( command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc (def) (ghi)"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'(']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc () (ghi)"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside square brackets and enter insert mode (ci[ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc [def] [ghi]"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'[']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc [] [ghi]"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

suite "Normal mode: Delete current word and enter insert mode":
  test "Delete current word and enter insert mode (ciw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "def"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 0

    check status.registers.noNameRegisters.buffer[0] == ru"abc "

  test "Delete current word and enter insert mode when empty line (ciw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru""
    check currentBufStatus.buffer[1] == ru"abc"
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Delete inside paren":
  test "Delete inside double quotes and enter insert mode (di\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru """abc "def" "ghi""""])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'"']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside double quotes (di' command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc 'def' 'ghi'"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'\'']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc '' 'ghi'"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside curly brackets (di{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc {def} {ghi}"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc {} {ghi}"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside round brackets (di( command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc (def) (ghi)"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'(']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc () (ghi)"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

  test "Delete inside square brackets (di[ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc [def] [ghi]"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'[']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc [] [ghi]"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.noNameRegisters.buffer[0] == ru"def"

suite "Normal mode: Delete current word":
  test "Delete current word and (diw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "def"

    check currentMainWindowNode.currentColumn == 0

    check status.registers.noNameRegisters.buffer[0] == ru"abc "

  test "Delete current word when empty line (diw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru""
    check currentBufStatus.buffer[1] == ru"abc"

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Delete current character and enter insert mode":
  test "Delete current character and enter insert mode (s command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"bc"
    check currentBufStatus.mode == Mode.insert

    check status.registers.noNameRegisters.buffer[0] == ru"a"

  test "Delete current character and enter insert mode when empty line (s command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"", ru""])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.len == 3
    for i in  0 ..< currentBufStatus.buffer.len:
      check currentBufStatus.buffer[i] == ru""

    check currentBufStatus.mode == Mode.insert

  test "Delete 3 characters and enter insert mode(3s command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcdef"])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"def"
    check currentBufStatus.mode == Mode.insert

    check status.registers.noNameRegisters.buffer[0] == ru"abc"

  test "Delete current character and enter insert mode (cu command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'l']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"bc"
    check currentBufStatus.mode == Mode.insert

  test "Delete current character and enter insert mode when empty line (s command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"", ru""])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'l']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.len == 3
    for i in  0 ..< currentBufStatus.buffer.len:
      check currentBufStatus.buffer[i] == ru""

    check currentBufStatus.mode == Mode.insert

suite "Normal mode: Yank lines":
  test "Yank to the previous blank line (y{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"", ru"def", ru"ghi", ru"", ru"jkl"])
    currentMainWindowNode.currentLine = 4

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer.len == 4
    check status.registers.noNameRegisters.buffer == @[ru "", ru"def", ru"ghi", ru""]

  test "Yank to the first line (y{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru""])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer.len == 3
    check status.registers.noNameRegisters.buffer == @[ru "abc", ru"def", ru""]

  test "Yank to the next blank line (y} command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc", ru"def", ru""])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'}']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer.len == 4
    check status.registers.noNameRegisters.buffer == @[ru"", ru "abc", ru"def", ru""]

  test "Yank to the last line (y} command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru ""])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'}']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer.len == 3
    check status.registers.noNameRegisters.buffer == @[ru "abc", ru"def", ru""]

  test "Yank a line (yy command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'y']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[0] ==  ru "abc"

  test "Yank a line (Y command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'Y']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[0] == ru "abc"

suite "Normal mode: Delete the characters from current column to end of line":
  test "Delete 5 characters (d$ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcdefgh"])
    currentMainWindowNode.currentColumn = 3

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'$']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"abc"

    check status.registers.noNameRegisters.buffer[0] == ru"defgh"

suite "Normal mode: delete from the beginning of the line to current column":
  test "Delete 5 characters (d0 command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcdefgh"])
    currentMainWindowNode.currentColumn = 5

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'0']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"fgh"

    check status.registers.noNameRegisters.buffer[0] == ru"abcde"

suite "Normal mode: Yank string":
  test "yank character (yl command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcdefgh"])

    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.noNameRegisters.buffer[0] == ru"a"

  test "yank 3 characters (3yl command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.noNameRegisters.buffer[0] == ru"abc"

  test "yank 5 characters (10yl command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    currentBufStatus.cmdLoop = 10
    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.noNameRegisters.buffer[0] == ru"abcde"

suite "Normal mode: Cut character before cursor":
  test "Cut character before cursor (X command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 1

    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer[0] == ru"bcde"

    check status.registers.noNameRegisters.buffer[0] == ru"a"

  test "Cut 3 characters before cursor (3X command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 3

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer[0] == ru"de"

    check status.registers.noNameRegisters.buffer[0] == ru"abc"

  test "Do nothing (X command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer[0] == ru"abcde"

    check status.registers.noNameRegisters.buffer.len == 0

  test "Cut character before cursor (dh command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'h']
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer[0] == ru"bcde"

    check status.registers.noNameRegisters.buffer[0] == ru"a"

suite "Add buffer to the register":
  test "Add a character to the register (\"\"ayl\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayl"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "a"], isLine: false, name: "a")

  test "Add 2 characters to the register (\"\"a2yl\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yl"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "ab"], isLine: false, name: "a")

  test "Add a word to the register (\"\"ayw\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayw"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc "], isLine: false, name: "a")

  test "Add 2 words to the register (\"\"a2yw\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yw"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc def"], isLine: false, name: "a")

  test "Add a line to the register (\"\"ayy\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayy"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc"], isLine: true, name: "a")

  test "Add a line to the register (\"\"ayy\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yy"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc", ru "def"], isLine: true, name: "a")

  test "Add 2 lines to the register (\"\"a2yy\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yy"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc", ru "def"], isLine: true, name: "a")

  test "Add up to the next blank line to the register (\"ay} command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ay}"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc", ru "def", ru ""], isLine: true, name: "a")

  test "Delete and ynak a line (\"add command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"add"
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc"], isLine: true, name: "a")

  test "Add to the named register up to the previous blank line (\"ay{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru"ghi"])
    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ay{"
    check status.normalCommand(Commands).isNone

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "", ru "def", ru "ghi"], isLine: true, name: "a")

  test "Delete and yank a word (\"adw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"adw"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc "], isLine: false, name: "a")

  test "Delete and yank characters to the end of the line (\"ad$ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad$"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc def"], isLine: false, name: "a")

  test "Delete and yank characters to the beginning of the line (\"ad0 command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad0"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc "], isLine: false, name: "a")

  test "Delete and yank lines to the last line (\"adG command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adG"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "a"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "b", ru "c", ru "d"], isLine: true, name: "a")

  test "Delete and yank lines from the first line to the current line (\"adgg command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Command = ru "\"adgg"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "d"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "a", ru "b", ru "c"], isLine: true, name: "a")

  test "Delete and yank lines from the previous blank line to the current line (\"ad{ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"b", ru"c"])
    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad{"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "a"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "", ru "b"], isLine: true, name: "a")

  test "Delete and yank lines from the current linet o the next blank line (\"ad} command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"", ru"c"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad}"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "c"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "a", ru "b"], isLine: true, name: "a")

  test "Delete and yank characters in the paren (\"adi[ command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a[abc]"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adi["
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "a[]"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "abc"], isLine: false, name: "a")

  test "Delete and yank characters befor cursor (\"adh command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adh"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "bc"

    check status.registers.noNameRegisters == Register(
      buffer: @[ru "a"], isLine: false, name: "a")

suite "Normal mode: Validate normal mode command":
  test "\"0 (Expect to Valid)":
    const Command = ru"0"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "\" (Expect to continue)":
    const Command = ru "\""
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"a (Expect to continue)":
    const Command = ru "\"a"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"ay (Expect to continue)":
    const Command = ru "\"ay"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"1 (Expect to Continue)":
    const Command = ru"1"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"10 (Expect to Continue)":
    const Command = ru"10"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"100 (Expect to Continue)":
    const Command = ru"100"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "\"ayy (Expect to validate)":
    const Command = ru "\"ayy"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "\"y ESC (Expect to invalid)":
    const Command = @['y'.toRune, KEY_ESC.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

  test "\"1 y ESC (Expect to invalid)":
    const Command = @['1'.toRune, 'y'.toRune, KEY_ESC.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

  test "\"10 y ESC (Expect to invalid)":
    const Command = @['1'.toRune, '0'.toRune, 'y'.toRune, KEY_ESC.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

suite "Normal mode: Yank and delete words":
  test "Ynak and delete a word (dw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def ghi"])

    const Command = ru"dw"
    check status.normalCommand(Command).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def ghi"

    check status.registers.noNameRegisters == Register(buffer: @[ru "abc "])
    check status.registers.noNameRegisters == status.registers.smallDeleteRegisters

  test "Ynak and delete 2 words (2dw command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def ghi"])

    const Command = ru"dw"
    currentBufStatus.cmdLoop = 2
    check status.normalCommand(Command).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "ghi"

    check status.registers.noNameRegisters == Register(buffer: @[ru "abc def "])
    check status.registers.noNameRegisters == status.registers.smallDeleteRegisters

suite "Editor: Yank characters in the current line":
  test "Yank characters in the currentLine (cc command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "cc"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegisters == Register(buffer: @[ru "abc def"])
    check status.registers.smallDeleteRegisters ==  status.registers.noNameRegisters

  test "Yank characters in the currentLine (S command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "S"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegisters == Register(buffer: @[ru "abc def"])
    check status.registers.smallDeleteRegisters ==  status.registers.noNameRegisters

suite "Normal mode: Open the blank line below and enter insert mode":
  test "Open the blank line (\"o\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru ""

    check currentMainWindowNode.currentLine == 1

  test "Open the blank line 2 (\"3o\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    currentBufStatus.cmdLoop = 3
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru ""

    check currentMainWindowNode.currentLine == 1

suite "Normal mode: Open the blank line above and enter insert mode":
  test "Open the blank line (\"O\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    currentBufStatus.cmdLoop = 1
    check status.normalCommand(Command).isNone


    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "abc"

    check currentMainWindowNode.currentLine == 0

  test "Open the blank line (\"3O\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    currentBufStatus.cmdLoop = 3
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "abc"

    check currentMainWindowNode.currentLine == 0

suite "Normal mode: Run command when Readonly mode":
  test "Enter insert mode (\"i\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "i"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Enter insert mode (\"I\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "I"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Open the blank line and enter insert mode (\"o\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Open the blank line and enter insert mode (\"O\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter replace mode (\"R\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "R"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Delete lines (\"dd\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "dd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Paste lines (\"p\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var settings = initEditorSettings()
    settings.clipboard.enable = false

    status.registers.addRegister(ru "def", settings)

    const Command = ru "p"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Normal mode: Move to the next any character on the current line":
  test "Move to the next 'c' (\"fc\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "fc"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Move to the next 'i' (\"fi\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "fi"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == Buffer.high

  test "Do nothing (\"fz\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "fz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Move to forward word in the current line":
  test "Move to the before 'e' (\"Fe\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    currentMainWindowNode.currentColumn = Buffer.high

    const Command = ru "Fe"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

  test "Do nothing (\"Fz\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    currentMainWindowNode.currentColumn = Buffer.high

    const Command = ru "Fz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == Buffer.high

suite "Normal mode: Move to the left of the next any character":
  test "Move to the character next the next 'e' (\"tf\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "tf"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

  test "Do nothing (\"tz\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "tz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Move to the right of the back character":
  test "Move to the character before the next 'f' (\"Te\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    currentMainWindowNode.currentColumn = Buffer.high

    const Command = ru "Te"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 6

  test "Do nothing (\"Tz\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc def ghi"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "Tz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Yank characters to any character":
  test "Case 1: Yank characters before 'd' (\"ytd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check not status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[0] == ru "abc"

  test "Case 2: Yank characters before 'd' (\"ytd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "ab c d"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check not status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[0] == ru "ab c "

  test "Case 1: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.noNameRegisters.buffer.len == 0

  test "Case 2: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd efg"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])
    currentMainWindowNode.currentColumn = 3

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.noNameRegisters.buffer.len == 0

  test "Case 3: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd efg"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])
    currentMainWindowNode.currentColumn = Buffer.high

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.noNameRegisters.buffer.len == 0

suite "Normal mode: Delete characters to any characters and Enter insert mode":
  test "Case 1: Delete characters to 'd' and enter insert mode (\"cfd\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "cfd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru ""

    check not status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[0] == ru "abcd"

    check currentBufStatus.mode == Mode.insert

  test "Case 1: Do nothing (\"cfz\" command)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "cfz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.noNameRegisters.buffer.len == 0

    check currentBufStatus.mode == Mode.normal

suite "Normal mode: execNormalModeCommand":
  test "'/' key":
    # Change mode to searchForward

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Command = ru"/"
    check status.execNormalModeCommand(Command).isNone

    check currentBufStatus.isSearchForwardMode
    check status.commandLine.buffer == "".toRunes

    privateAccess(status.commandLine.type)

    check status.commandLine.prompt == "/".toRunes

  test "'?' key":
    # Change mode to searchBackward

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Command = ru"?"
    check status.execNormalModeCommand(Command).isNone

    check currentBufStatus.isSearchBackwardMode
    check status.commandLine.buffer == "".toRunes

    privateAccess(status.commandLine.type)

    check status.commandLine.prompt == "?".toRunes

  test "':' key":
    # Change mode to ex

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    const Command = ru":"
    check status.execNormalModeCommand(Command).isNone

    check currentBufStatus.isExmode
    check status.commandLine.buffer == "".toRunes

    privateAccess(status.commandLine.type)

    check status.commandLine.prompt == ":".toRunes

  test "\"ESC ESC\" keys":
    # Trun off highlightings

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    let beforeBufStatus = currentBufStatus

    status.isSearchHighlight = true

    const Commands = @[KEY_ESC.toRune, KEY_ESC.toRune]
    check status.execNormalModeCommand(Commands).isNone

    check currentBufStatus == beforeBufStatus

    check not status.isSearchHighlight

  test "\"ESC /\" keys":
    # Remove ESC from top of the command and exec commands.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Commands = @[KEY_ESC.toRune, '/'.toRune]
    check status.execNormalModeCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.isSearchForwardMode
    check status.commandLine.buffer == "".toRunes

    privateAccess(status.commandLine.type)

    check status.commandLine.prompt == "/".toRunes

  test "\"yy\" keys":
    # Yank the line

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = @["a".toRunes]
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"yy"
    check status.execNormalModeCommand(Command).isNone

    check status.registers.noNameRegisters == Register(
      buffer: Buffer,
      isLine: true)

  test "\"2yy\" keys":
    # Yank lines

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = @["a".toRunes, "b".toRunes]
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"2yy"
    check status.execNormalModeCommand(Command).isNone

    check status.registers.noNameRegisters == Register(
      buffer: Buffer,
      isLine: true)

  test "\"10yy\" keys":
    # Yank lines

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = toSeq(0..9).mapIt(it.toRunes)
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"10yy"
    check status.execNormalModeCommand(Command).isNone

    check status.registers.noNameRegisters == Register(
      buffer: Buffer,
      isLine: true)

  test "'0' command":
    # Move to top of the line.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    const Buffer = @["abc".toRunes]
    currentBufStatus.buffer = Buffer.initGapBuffer
    currentMainWindowNode.currentColumn =
      currentBufStatus.buffer[currentMainWindowNode.currentLine].high

    status.resize(100, 100)
    status.update

    const Command = ru"0"
    check status.execNormalModeCommand(Command).isNone

    check currentMainWindowNode.currentColumn == 0

  test "'%' command":
    # Move to matching pair of paren.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    currentBufStatus.buffer = @["( )".toRunes].initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"%"

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid
    check status.execNormalModeCommand(Command).isNone

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "'*' command":
    # Search the currnet words.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    currentBufStatus.buffer = @["abc def abc".toRunes].initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"*"

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid
    check status.execNormalModeCommand(Command).isNone

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 8

  test "'*' command 2":
    # Fix https://github.com/fox0430/moe/issues/1689.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    currentBufStatus.buffer = @["abc def abc".toRunes].initGapBuffer
    status.searchHistory = @["def".toRunes]

    status.resize(100, 100)
    status.update

    const Command = ru"*"
    check status.execNormalModeCommand(Command).isNone

    check status.searchHistory == @["def".toRunes, "abc".toRunes]

  test "'#' command":
    # Search the currnet words.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    currentBufStatus.buffer = @["abc def abc".toRunes].initGapBuffer
    currentMainWindowNode.currentColumn = 8

    status.resize(100, 100)
    status.update

    const Command = ru"#"

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid
    check status.execNormalModeCommand(Command).isNone

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "'#' command 2":
    # Fix https://github.com/fox0430/moe/issues/1689.

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    currentBufStatus.buffer = @["abc def abc".toRunes].initGapBuffer
    currentMainWindowNode.currentColumn = 8
    status.searchHistory = @["def".toRunes]

    status.resize(100, 100)

    status.update

    const Command = ru"#"
    check status.execNormalModeCommand(Command).isNone

    check status.searchHistory == @["def".toRunes, "abc".toRunes]

suite "Ex mode: Quickrun command wihtout file":
  test "Exec Quickrun without file":
    # Create a file for the test.
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].language = SourceLanguage.langNim
    status.bufStatus[0].buffer = toGapBuffer(@[ru"echo 1"])

    status.resize(100, 100)
    status.update

    const Command = @[ru'\\', ru'r']
    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    for w in mainWindowNode.getAllWindowNode:
      if w.bufferIndex == 1:
        # 1 is the quickrun window.
        check w.view.height > status.bufStatus[1].buffer.high

    var timeout = true
    for _ in 0 .. 20:
      sleep 500
      if status.backgroundTasks.quickRun[0].isFinish:
        let r = status.backgroundTasks.quickRun[0].result.get
        check r[^1] == "1"

        timeout = false
        break

    check not timeout

  test "Exec Quickrun without file twice":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.bufStatus[0].language = SourceLanguage.langNim
    status.bufStatus[0].buffer = toGapBuffer(@[ru"echo 1"])

    status.resize(100, 100)
    status.update

    const Command = @[ru'\\', ru'r']

    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    status.movePrevWindow

    # Edit the buffer and exec Quickrun again.
    status.bufStatus[0].buffer[0] = ru"echo 2"
    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 2
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    block:
      # Wait for the first quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[0].isFinish:
          let r = status.backgroundTasks.quickRun[0].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

    block:
      # Wait for the second quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[1].isFinish:
          let r = status.backgroundTasks.quickRun[1].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

suite "Normal mode: Quickrun command with file":
  const
    TestfileDir = "quickrunTestDir"
    TestfilePath = TestfileDir / "quickrunTest.nim"

  setup:
    createDir(TestfileDir)
    writeFile(TestfilePath, "echo 1")

  teardown:
    removeDir(TestfileDir)

  test "Exec Quickrun with file":
    # Create a file for the test.
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(TestfilePath, Mode.normal)

    status.resize(100, 100)
    status.update

    const Command = @[ru'\\', ru'r']
    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

      for w in mainWindowNode.getAllWindowNode:
        if w.bufferIndex == 1:
          # 1 is the quickrun result.
          check w.view.height > status.bufStatus[1].buffer.high

    var timeout = true
    for _ in 0 .. 20:
      sleep 500
      if status.backgroundTasks.quickRun[0].isFinish:
        let r = status.backgroundTasks.quickRun[0].result.get
        check r[^1] == "1"

        timeout = false
        break

    check not timeout

  test "Noarma mode: Quickrun with file twice":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(TestfilePath, Mode.normal)

    status.resize(100, 100)
    status.update

    const Command = @[ru'\\', ru'r']

    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      check status.backgroundTasks.quickRun.len == 1
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    status.movePrevWindow

    # Edit the buffer and exec Quickrun again.
    status.settings.quickRun.saveBufferWhenQuickRun = true
    status.bufStatus[0].buffer[0] = ru"echo 2"
    status.update

    check status.execNormalModeCommand(Command).isNone
    status.update

    # Wait just in case
    sleep 100

    block:
      # 1 is the quickrun window.
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

      check status.backgroundTasks.quickRun.len == 2
      check mainWindowNode.getAllWindowNode.len == 2

      # 1 is the quickrun buffer.
      check status.bufStatus[1].path.len > 0
      check status.bufStatus[1].mode == Mode.quickRun
      check status.bufStatus[1].buffer.toRunes ==
        quickRunStartupMessage($status.bufStatus[1].path).toRunes

    block:
      # Wait for the first quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[0].isFinish:
          let r = status.backgroundTasks.quickRun[0].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

    block:
      # Wait for the second quickrun.

      var timeout = true
      for _ in 0 .. 20:
        sleep 500
        if status.backgroundTasks.quickRun[1].isFinish:
          let r = status.backgroundTasks.quickRun[1].result.get
          check r[^1] == "2"

          timeout = false
          break

      check not timeout

suite "Normal mode: startRecordingOperations":
  test "startRecordingOperations 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    initOperationRegisters()

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    status.startRecordingOperations(RegisterName.toRune)

    check status.recodingOperationRegister == some(ru'a')

  test "startRecordingOperations 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    initOperationRegisters()

    status.resize(100, 100)
    status.update

    const RegisterName = '0'
    status.startRecordingOperations(RegisterName.toRune)
    status.update

    check status.recodingOperationRegister == some(ru'0')

    check status.commandLine.buffer == (fmt"recording @{$RegisterName}").toRunes

suite "Normal mode: stopRecordingOperations":
  test "stopRecordingOperations":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    initOperationRegisters()

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    status.startRecordingOperations(RegisterName.toRune)
    status.update

    status.stopRecordingOperations
    status.update

    check status.recodingOperationRegister.isNone

    check status.commandLine.buffer.len == 0

suite "Normal mode: pasteAfterCursor":
  test "Paste the line 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    status.registers.noNameRegisters = Register(
      buffer: @[ru "line"],
      isLine: true)
    status.pasteAfterCursor

    check currentBufStatus.buffer.toSeqRunes == @[ru"", ru"line"]
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Paste the line 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = toGapBuffer(@[ru"", ru""])

    status.resize(100, 100)
    status.update

    status.registers.noNameRegisters = Register(
      buffer: @[ru "  line"],
      isLine: true)
    status.pasteAfterCursor

    check currentBufStatus.buffer.toSeqRunes == @[ru"", ru"  line", ru""]
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 2

suite "Normal mode: pasteBeforeCursor":
  test "Paste the line 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.resize(100, 100)
    status.update

    status.registers.noNameRegisters = Register(
      buffer: @[ru "line"],
      isLine: true)
    status.pasteBeforeCursor

    check currentBufStatus.buffer.toSeqRunes == @[ru"line", ru""]
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste the line 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = toGapBuffer(@[ru"", ru""])

    status.resize(100, 100)
    status.update

    status.registers.noNameRegisters = Register(
      buffer: @[ru "  line"],
      isLine: true)
    status.pasteBeforeCursor

    check currentBufStatus.buffer.toSeqRunes == @[ru"  line", ru"", ru""]
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2
