#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import pkg/results

import moepkg/syntax/highlite
import moepkg/[registers, settings, editorstatus, gapbuffer, unicodeext,
               bufferstatus, ui, windownode, quickrunutils, viewhighlight,
               folding, editorview]

import utils

import moepkg/normalmode {.all.}

suite "Normal mode: Move to the right":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Move 2 col":
    status.bufStatus[0].buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'l']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 2

  test "Ignore":
    status.bufStatus[0].buffer = @["abc"].toSeqRunes.toGapBuffer

    currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    const Key = @[ru'l']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 2

  test "On Folding line":
    status.bufStatus[0].buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'l']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 1
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to the left":
  test "Move one to the left":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Delete 2 characters":
    status.bufStatus[0].buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'x']
    check status.normalCommand(Key).isNone
    status.update

    check status.bufStatus[0].buffer[0] == ru"c"

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @[ru "ab"]
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @[ru "ab"]
      check not r.isLine

  test "On folding line":
    status.bufStatus[0].buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'x']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["bc", "def"].toSeqRunes
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to last of line":
  test "Move to last of line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
    for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

    status.settings.smoothScroll.enable = false

    status.resize(100, 100)
    status.update

    const Key = @[PageDownKey.toRune]
    check status.normalCommand(Key).isNone
    status.update

    let
      currentLine = currentMainWindowNode.currentLine
      viewHeight = currentMainWindowNode.view.height

    check currentLine == viewHeight

suite "Normal mode: Page up":
  test "Page up":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
    for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

    status.settings.smoothScroll.enable = false

    status.resize(100, 100)
    status.update

    block:
      const Key = @[PageDownKey.toRune]
      check status.normalCommand(Key).isNone
    status.update

    block:
      const Key = @[PageUpKey.toRune]
      check status.normalCommand(Key).isNone
    status.update

    check(currentMainWindowNode.currentLine == 0)

suite "Normal mode: Move to forward word":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.bufStatus[0].buffer = @["abc def ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'w']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 8

  test "On folding line":
    status.bufStatus[0].buffer = @["abc def ghi", "jkl"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'w']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 4
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to backward word":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.bufStatus[0].buffer = @["abc def ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 8

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 1
    const Key = @[ru'b']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 4

  test "On folding line":
    status.bufStatus[0].buffer = @["abc def ghi", "jkl"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Key = @[ru'b']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 8
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to forward end of word":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.bufStatus[0].buffer = @["abc def ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const Key = @[ru'e']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 6

  test "On folding line":
    status.bufStatus[0].buffer = @["abc def ghi", "jkl"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'e']
    check status.normalCommand(Key).isNone
    status.update

    check currentMainWindowNode.currentColumn == 2
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Open blank line below":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.bufStatus[0].buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'o']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 1

    check currentBufStatus.mode == Mode.insert

  test "On folding line":
    status.bufStatus[0].buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 2)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'o']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a", "b", "c", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 3
    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 2)
    ]

    check currentBufStatus.mode == Mode.insert

suite "Normal mode: Open blank line below":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    status.bufStatus[0].buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'O']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "a"].toSeqRunes

    check currentMainWindowNode.currentLine == 0

    check currentBufStatus.mode == Mode.insert

  test "On folding line":
    status.bufStatus[0].buffer = @["a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'O']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "a", "b"].toSeqRunes

    check currentMainWindowNode.currentLine == 0

    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 1, last: 2)
    ]

suite "Normal mode: Indent":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'>']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["  a"].toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'>']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["  a", "b"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Unindent":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["  a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'<']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a"].toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["  a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'<']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a", "b"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Join line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a", "b"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'J']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["ab"].toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'J']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["ab", "c"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Change mode to Replace mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'R']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.replace

  test "On folding line":
    currentBufStatus.buffer = @["a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'R']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.replace

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move right and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'a']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.insert
    check currentMainWindowNode.currentColumn == 1

  test "On folding line":
    currentBufStatus.buffer = @["a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'a']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 1
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move last of line and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Key = @[ru'A']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.insert
    check currentMainWindowNode.currentColumn == 3

  test "On folding line":
    currentBufStatus.buffer = @["abc", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Key = @[ru'A']
    check status.normalCommand(Key).isNone
    status.update

    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 3
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Repeat last command":
  test "Repeat last command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru">"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.execNormalModeCommand(Command).isNone
      status.update

    currentMainWindowNode.currentColumn = 0

    block:
      const Command = ru"x"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = ru"."
      check status.execNormalModeCommand(Command).isNone
      status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru"abc"

  test "Repeat last command 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru"j"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = @[ru'.']

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.execNormalModeCommand(Command).isNone
      status.update

    check(currentMainWindowNode.currentLine == 1)

  test "Repeat last command 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru"dw"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = @[ru'.']

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.execNormalModeCommand(Command).isNone
      status.update

      check currentBufStatus.buffer.toSeqRunes == @[ru""]

  test "Repeat last command 5":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

    status.resize(100, 100)
    status.update

    block:
      const Command = ru"dw"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = ru"j"

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      # Dont' save "j"
      check status.normalCommand(Command).isNone
      status.update

    block:
      const Command = @[ru'.']

      check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

      # Repeat "dw"
      check status.execNormalModeCommand(Command).isNone
      status.update

      check currentBufStatus.buffer.toSeqRunes == @[ru"ghi"]

suite "Normal mode: Delete lines":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"dd"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["b", "c", "d"].toSeqRunes

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @[ru "a"]
      check r.isLine

    block:
      let r = status.registers.getNumberRegister(1)
      check r.buffer == @[ru "a"]
      check r.isLine

  test "On folding line":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru"dd"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["c", "d"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @["a", "b"].toSeqRunes
      check r.isLine

    block:
      let r = status.registers.getNumberRegister(1)
      check r.buffer == @["a", "b"].toSeqRunes
      check r.isLine

  test "Before folding line":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]

    status.resize(100, 100)
    status.update

    const Command = ru"dd"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["b", "c"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @["a"].toSeqRunes
      check r.isLine

    block:
      let r = status.registers.getNumberRegister(1)
      check r.buffer == @["a"].toSeqRunes
      check r.isLine

suite "Normal mode: Delete lines from the current line to the last line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Command = @[ru'd', ru'G']

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a"].toSeqRunes

    check status.registers.getNoNamedRegister.buffer == @["b", "c", "d"]
      .toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Command = @[ru'd', ru'G']

    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["b", "c", "d"]
      .toSeqRunes

suite "Normal mode: Delete lines from the first line to the current line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'g', ru'g']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["d"].toSeqRunes

    check status.registers.getNoNamedRegister.buffer == @["a", "b", "c"]
      .toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["a", "b", "c", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'g', ru'g']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["d"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["a", "b", "c"]
      .toSeqRunes

suite "Normal mode: Delete inside paren and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic (ci\" command)":
    currentBufStatus.buffer = @["""abc "def" "ghi""""].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'"']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["""abc "" "ghi""""].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer == @["def"].toSeqRunes

  test "Delete inside double quotes and enter insert mode (ci' command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside curly brackets and enter insert mode (ci{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside round brackets and enter insert mode (ci( command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside square brackets and enter insert mode (ci[ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
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

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

suite "Normal mode: Delete current word and enter insert mode (ciw command)":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "First of the line":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = ru"ciw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

  test "Empty line":
    currentBufStatus.buffer = @["", "abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "abc"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic 1":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer

    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Commands = ru"ciw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

  test "Basic 2":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer

    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const Commands = ru"ciw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["abc "].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.currentColumn == 4

    check status.registers.getNoNamedRegister.buffer == @["def"].toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["abc def", "g"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = ru"ciw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def", "g"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

suite "Normal mode: Delete inside paren":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic (di\" command)":
    currentBufStatus.buffer = @["""abc "def" "ghi""""].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'"']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside double quotes (di' command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc 'def' 'ghi'"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'\'']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc '' 'ghi'"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside curly brackets (di{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc {def} {ghi}"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc {} {ghi}"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside round brackets (di( command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc (def) (ghi)"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'(']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc () (ghi)"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "Delete inside square brackets (di[ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc [def] [ghi]"])
    currentMainWindowNode.currentColumn = 6

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'[']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru "abc [] [ghi]"

    check currentMainWindowNode.currentColumn == 5

    check status.registers.getNoNamedRegister.buffer[0] == ru"def"

  test "On folding line":
    currentBufStatus.buffer = @["\"abc\"", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'"']
    check status.normalCommand(Commands).isNone
    status.update

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Delete current word (diw command)":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "First of line":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = ru"diw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def"].toSeqRunes

    check currentMainWindowNode.currentColumn == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

  test "Empty line":
    currentBufStatus.buffer = @["", "abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'i', ru'w']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "abc"].toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic 1":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Commands = ru"diw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def"].toSeqRunes

    check currentMainWindowNode.currentColumn == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

  test "Basic 2":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const Commands = ru"diw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["abc "].toSeqRunes

    check currentMainWindowNode.currentColumn == 3

    check status.registers.getNoNamedRegister.buffer == @["def"].toSeqRunes

  test "On folding line":
    currentBufStatus.buffer = @["abc def", "g"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = ru"diw"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[" def", "g"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["abc"].toSeqRunes

suite "Normal mode: Delete current character and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Basic (s command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"bc"
    check currentBufStatus.mode == Mode.insert

    check status.registers.getNoNamedRegister.buffer[0] == ru"a"

  test "Basic 2 (s command)":
    currentBufStatus.buffer = @["", "", ""].toSeqRunes.toGapBuffer
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

  test "Basic 3 (3s command)":
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"def"
    check currentBufStatus.mode == Mode.insert

    check status.registers.getNoNamedRegister.buffer[0] == ru"abc"

  test "Basic 4 (cu command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'l']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["bc"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

  test "Basic 5 (s command)":
    currentBufStatus.buffer = @["", "", ""].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Commands = @[ru'c', ru'l']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "", ""].toSeqRunes

    check currentBufStatus.mode == Mode.insert

  test "On folding line":
    currentBufStatus.buffer = @["abc", "d"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = @[ru's']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["bc", "d"].toSeqRunes
    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["a"].toSeqRunes

suite "Normal mode: Yank lines":
  test "Yank to the previous blank line (y{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"", ru"def", ru"ghi", ru"", ru"jkl"])
    currentMainWindowNode.currentLine = 4

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer.len == 4
    check status.registers.getNoNamedRegister.buffer == @[ru "", ru"def", ru"ghi", ru""]

  test "Yank to the first line (y{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru""])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'{']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer.len == 3
    check status.registers.getNoNamedRegister.buffer == @[ru "abc", ru"def", ru""]

  test "Yank to the next blank line (y} command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc", ru"def", ru""])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'}']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer.len == 4
    check status.registers.getNoNamedRegister.buffer == @[ru"", ru "abc", ru"def", ru""]

  test "Yank to the last line (y} command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru ""])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'}']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer.len == 3
    check status.registers.getNoNamedRegister.buffer == @[ru "abc", ru"def", ru""]

  test "Yank a line (yy command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'y']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer[0] ==  ru "abc"

  test "Yank a line (Y command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(
      @[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'Y']
    check status.normalCommand(Commands).isNone
    status.update

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer[0] == ru "abc"

  test "On folding line (yy command)":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = @[ru'y', ru'y']
    check status.normalCommand(Commands).isNone
    status.update

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @["abc", "def"]
      .toSeqRunes


suite "Normal mode: Delete the characters from current column to end of line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Delete 5 characters (d$ command)":
    currentBufStatus.buffer = @["abcdefgh"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 3

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'$']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes

    check status.registers.getNoNamedRegister.buffer == @["defgh"].toSeqRunes

  test "On folding line (d$ command)":
    currentBufStatus.buffer = @["abc", "def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Commands = ru"d$"
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    check status.registers.getNoNamedRegister.buffer == @["abc", "def"]
      .toSeqRunes

suite "Normal mode: delete from the beginning of the line to current column":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Delete 5 characters (d0 command)":
    currentBufStatus.buffer = @["abcdefgh"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 5

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'0']
    check status.normalCommand(Commands).isNone
    status.update

    check currentBufStatus.buffer[0] == ru"fgh"

    check status.registers.getNoNamedRegister.buffer[0] == ru"abcde"

suite "Normal mode: Yank characters":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Yank character (yl command)":
    currentBufStatus.buffer = @["abcdefgh"].toSeqRunes.toGapBuffer

    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.getNoNamedRegister.buffer[0] == ru"a"

  test "Yank 3 characters (3yl command)":
    currentBufStatus.buffer = @["abcde"].toSeqRunes.toGapBuffer

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.getNoNamedRegister.buffer[0] == ru"abc"

  test "Yank 5 characters (10yl command)":
    currentBufStatus.buffer = @["abcde"].toSeqRunes.toGapBuffer

    currentBufStatus.cmdLoop = 10
    const Commands = @[ru'y', ru'l']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check status.registers.getNoNamedRegister.buffer[0] == ru"abcde"

suite "Normal mode: Yank characters from the begin of the line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "y0 command":
    currentBufStatus.buffer = @["abcde"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 2

    const Command = ru"y0"
    check status.normalCommand(Command).isNone

    check status.registers.getNoNamedRegister.buffer[0] == ru"ab"

  test "Basic 2":
    currentBufStatus.buffer = @["abcde"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 4

    const Command = ru"y0"
    check status.normalCommand(Command).isNone

    check status.registers.getNoNamedRegister.buffer[0] == ru"abcd"

  test "currentColumn == 0":
    currentBufStatus.buffer = @["abcde"].toSeqRunes.toGapBuffer

    const Command = ru"y0"
    check status.normalCommand(Command).isNone

    check status.registers.getNoNamedRegister.buffer.len == 0

  test "Empty line":
    currentBufStatus.buffer = @[""].toSeqRunes.toGapBuffer

    const Command = ru"y0"
    check status.normalCommand(Command).isNone

    check status.registers.getNoNamedRegister.buffer.len == 0

suite "Normal mode: yank characters to the end of the line":
  test "y$ command":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 2

    const Command = ru"y$"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid
    check status.normalCommand(Command).isNone

    check status.registers.getNoNamedRegister.buffer[0] == ru"cde"

  test "Basic 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.yankCharactersToEndOfLine

    check status.registers.getNoNamedRegister.buffer[0] == ru"abcde"

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 4

    status.yankCharactersToEndOfLine

    check status.registers.getNoNamedRegister.buffer[0] == ru"e"

  test "Empty line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.yankCharactersToEndOfLine

    check status.registers.getNoNamedRegister.buffer.len == 0

suite "Normal mode: Cut character before cursor":
  test "Cut character before cursor (X command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 1

    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer[0] == ru"bcde"

    check status.registers.getNoNamedRegister.buffer[0] == ru"a"

  test "Cut 3 characters before cursor (3X command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 3

    currentBufStatus.cmdLoop = 3
    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer[0] == ru"de"

    check status.registers.getNoNamedRegister.buffer[0] == ru"abc"

  test "Do nothing (X command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = @[ru'X']
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer[0] == ru"abcde"

    check status.registers.getNoNamedRegister.buffer.len == 0

  test "Cut character before cursor (dh command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Commands = @[ru'd', ru'h']
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer[0] == ru"bcde"

    check status.registers.getNoNamedRegister.buffer[0] == ru"a"

suite "Add buffer to the register":
  test "Add a character to the register (\"\"ayl\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayl"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @[ru "a"]
    check not r.isLine

  test "Add 2 characters to the register (\"\"a2yl\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcde"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yl"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @[ru "ab"]
    check not r.isLine

  test "Add a word to the register (\"\"ayw\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayw"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @[ru "abc "]
    check not r.isLine

  test "Add 2 words to the register (\"\"a2yw\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yw"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @[ru "abc def"]
    check not r.isLine

  test "Add a line to the register (\"\"ayy\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ayy"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @[ru "abc"]
    check r.isLine

  test "Add a line to the register (\"\"ayy\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yy"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc", "def"].toSeqRunes
    check r.isLine

  test "Add 2 lines to the register (\"\"a2yy\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"a2yy"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc", "def"].toSeqRunes
    check r.isLine

  test "Add up to the next blank line to the register (\"ay} command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ay}"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc", "def", ""].toSeqRunes
    check r.isLine

  test "Delete and ynak a line (\"add command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.resize(100, 100)
    status.update

    const Commands = ru "\"add"
    check status.normalCommand(Commands).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc"].toSeqRunes
    check r.isLine

  test "Add to the named register up to the previous blank line (\"ay{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru"ghi"])
    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)
    status.update

    const Commands = ru "\"ay{"
    check status.normalCommand(Commands).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["", "def", "ghi"].toSeqRunes
    check r.isLine

  test "Delete and yank a word (\"adw command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"adw"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc "].toSeqRunes
    check not r.isLine

  test "Delete and yank characters to the end of the line (\"ad$ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad$"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc def"].toSeqRunes
    check not r.isLine

  test "Delete and yank characters to the beginning of the line (\"ad0 command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad0"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "def"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc "].toSeqRunes
    check not r.isLine

  test "Delete and yank lines to the last line (\"adG command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adG"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "a"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["b", "c", "d"].toSeqRunes
    check r.isLine

  test "Delete and yank lines from the first line to the current line (\"adgg command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Command = ru "\"adgg"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "d"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["a", "b", "c"].toSeqRunes
    check r.isLine

  test "Delete and yank lines from the previous blank line to the current line (\"ad{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"b", ru"c"])
    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad{"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "a"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["", "b"].toSeqRunes
    check r.isLine

  test "Delete and yank lines from the previous blank line to the current line (\"ad{ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"b", ru"c"])
    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad{"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "a"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["", "b"].toSeqRunes
    check r.isLine

  test "Delete and yank lines from the current linet o the next blank line (\"ad} command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"", ru"c"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad}"
    check status.normalCommand(Command).isNone
    status.update

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["a", "b"].toSeqRunes
    check r.isLine

  test "Delete and yank lines from the current linet o the next blank line (\"ad} command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"", ru"c"])

    status.resize(100, 100)
    status.update

    const Command = ru "\"ad}"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "c"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["a", "b"].toSeqRunes
    check r.isLine

  test "Delete and yank characters in the paren (\"adi[ command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a[abc]"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adi["
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "a[]"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["abc"].toSeqRunes
    check not r.isLine

  test "Delete and yank characters befor cursor (\"adh command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru "\"adh"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "bc"

    let r = status.registers.getNoNamedRegister
    check r.buffer == @["a"].toSeqRunes
    check not r.isLine

suite "Normal mode: Validate normal mode command":
  test "0 (Expect to Valid)":
    const Command = ru"0"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "1x (Expect to Valid)":
    const Command = ru"1x"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "1dd (Expect to Valid)":
    const Command = ru"1dd"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "10dd (Expect to Valid)":
    const Command = ru"10dd"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "1diw (Expect to Valid)":
    const Command = ru"1diw"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "10diw (Expect to Valid)":
    const Command = ru"10diw"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "\" (Expect to Continue)":
    const Command = ru "\""
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "a (Expect to Continue)":
    const Command = ru "\"a"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "ay (Expect to Continue)":
    const Command = ru "\"ay"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "1 (Expect to Continue)":
    const Command = ru"1"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "10 (Expect to Continue)":
    const Command = ru"10"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "100 (Expect to Continue)":
    const Command = ru"100"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Continue

  test "ayy (Expect to Valid)":
    const Command = ru "\"ayy"
    check isNormalModeCommand(Command, none(Rune)) == InputState.Valid

  test "y ESC (Expect to Invalid)":
    const Command = @['y'.toRune, EscKey.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

  test "1 y ESC (Expect to Invalid)":
    const Command = @['1'.toRune, 'y'.toRune, EscKey.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

  test "10 y ESC (Expect to invalid)":
    const Command = @['1'.toRune, '0'.toRune, 'y'.toRune, EscKey.toRune]
    check isNormalModeCommand(Command, none(Rune)) == InputState.Invalid

suite "Normal mode: Yank and delete words":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Ynak and delete a word (dw command)":
    currentBufStatus.buffer = @["abc def ghi"].toSeqRunes.toGapBuffer

    const Command = ru"dw"
    check status.normalCommand(Command).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["def ghi"].toSeqRunes

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @["abc "].toSeqRunes
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @["abc "].toSeqRunes
      check not r.isLine

  test "Ynak and delete 2 words (2dw command)":
    currentBufStatus.buffer = @["abc def ghi"].toSeqRunes.toGapBuffer

    const Command = ru"dw"
    currentBufStatus.cmdLoop = 2
    check status.normalCommand(Command).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["ghi"].toSeqRunes

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @["abc def "].toSeqRunes
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @["abc def "].toSeqRunes
      check not r.isLine

  test "On folding line (dw command)":
    currentBufStatus.buffer = @["abc def ghi", "jkl"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    const Command = ru"dw"
    check status.normalCommand(Command).isNone

    status.resize(100, 100)
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["def ghi", "jkl"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @["abc "].toSeqRunes
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @["abc "].toSeqRunes
      check not r.isLine

suite "Editor: Yank characters in the current line":
  test "Yank characters in the currentLine (cc command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "cc"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @[ru "abc def"]
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @[ru "abc def"]
      check not r.isLine

  test "Yank characters in the currentLine (S command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def", ru "ghi"])

    status.resize(100, 100)
    status.update

    const Command = ru "S"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    block:
      let r = status.registers.getNoNamedRegister
      check r.buffer == @[ru "abc def"]
      check not r.isLine

    block:
      let r = status.registers.getSmallDeleteRegister
      check r.buffer == @[ru "abc def"]
      check not r.isLine

suite "Normal mode: Open the blank line below and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Open the blank line (\"o\" command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["abc", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 1

  test "Open the blank line 2 (\"3o\" command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    currentBufStatus.cmdLoop = 3
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["abc", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 1

  test "On folding line (\"o\" command)":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru "o"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["a", "b", "", "c"].toSeqRunes

    check currentMainWindowNode.currentLine == 2

suite "Normal mode: Open the blank line above and enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Open the blank line (\"O\" command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    currentBufStatus.cmdLoop = 1
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["", "abc"].toSeqRunes

    check currentMainWindowNode.currentLine == 0

  test "Open the blank line (\"3O\" command)":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    currentBufStatus.cmdLoop = 3
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["", "abc"].toSeqRunes

    check currentMainWindowNode.currentLine == 0

  test "On folding line (\"O\" command)":
    currentBufStatus.buffer = @["a", "b"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru "O"
    currentBufStatus.cmdLoop = 1
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @["", "a", "b"].toSeqRunes

    check currentMainWindowNode.currentLine == 0

suite "Normal mode: Run command when Readonly mode":
  test "Enter insert mode (\"i\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "i"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Enter insert mode (\"I\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "I"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Open the blank line and enter insert mode (\"o\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    status.resize(100, 100)
    status.update

    const Command = ru "R"
    check status.normalCommand(Command).isNone

    check currentBufStatus.mode == Mode.normal

  test "Delete lines (\"dd\") command":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var settings = initEditorSettings()
    settings.clipboard.enable = false

    status.registers.setYankedRegister(ru"def")

    const Command = ru "p"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Normal mode: Move to the next any character on the current line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Move to the next 'c' (\"fc\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "fc"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Move to the next 'i' (\"fi\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "fi"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == Buffer[0].high

  test "Do nothing (\"fz\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "fz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "On folding line (\"fc\" command)":
    const Buffer = @["abc", "def"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru "fc"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to forward word in the current line":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Move to the before 'e' (\"Fe\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentColumn = Buffer[0].high

    const Command = ru "Fe"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

  test "Do nothing (\"Fz\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentColumn = Buffer[0].high

    const Command = ru "Fz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == Buffer[0].high

suite "Normal mode: Move to the before of the next any character":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Move to the next 'e' (\"tf\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "tf"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

  test "Do nothing (\"tz\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "tz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "On folding line (\"tf\" command)":
    const Buffer = @["abc def ghi", "jkl"].toSeqRunes
    currentBufStatus.buffer = Buffer.initGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru "tf"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Move to the next of the back character":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Move to the character the befor 'f' (\"Te\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentColumn = Buffer[0].high

    const Command = ru "Te"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 6

  test "Do nothing (\"Tz\" command)":
    const Buffer = @["abc def ghi"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "Tz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "Normal mode: Yank characters to any character":
  test "Case 1: Yank characters before 'd' (\"ytd\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer[0] == ru "abc"

  test "Case 2: Yank characters before 'd' (\"ytd\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Buffer = ru "ab c d"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer[0] == ru "ab c "

  test "Case 1: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Buffer = ru "abc"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.getNoNamedRegister.buffer.len == 0

  test "Case 2: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd efg"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])
    currentMainWindowNode.currentColumn = 3

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.getNoNamedRegister.buffer.len == 0

  test "Case 3: Do nothing (\"ytd\" command)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const Buffer = ru "abcd efg"
    currentBufStatus.buffer = initGapBuffer(@[Buffer])
    currentMainWindowNode.currentColumn = Buffer.high

    const Command = ru "ytd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == Buffer

    check status.registers.getNoNamedRegister.buffer.len == 0

suite "Normal mode: Delete characters to any characters and Enter insert mode":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Delete characters to 'd' and enter insert mode (\"cfd\" command)":
    const Buffer = @["abcd"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "cfd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == Buffer

    check currentBufStatus.mode == Mode.insert

  test "Do nothing (\"cfz\" command)":
    const Buffer = @["abcd"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru "cfz"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check status.registers.getNoNamedRegister.buffer == @[].toSeqRunes

    check currentBufStatus.mode == Mode.normal

  test "On folding line (\"cfd\" command)":
    const Buffer = @["abcd"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru "cfd"
    check status.normalCommand(Command).isNone

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == Buffer

    check currentBufStatus.mode == Mode.insert

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Expand folding lines":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Nothing to do (zo command)":
    const Buffer = @["a", "b", "c"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"zo"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic (zo command)":
    const Buffer = @["a", "b", "c"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru"zo"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0
    check currentMainWindowNode.view.foldingRanges.len == 0

  test "Nested (zo command)":
    const Buffer = @["a", "b", "c", "d"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 0, last: 1)
    ]

    status.resize(100, 100)
    status.update

    const Command = ru"zo"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0
    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

  test "Nested 2 (2zo command)":
    const Buffer = @["a", "b", "c", "d"].toSeqRunes
    currentBufStatus.buffer = Buffer.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 0, last: 1)
    ]

    status.resize(100, 100)
    status.update

    currentBufStatus.cmdLoop = 2
    const Command = ru"zo"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == Buffer

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: execNormalModeCommand":
  test "'/' key":
    # Change mode to searchForward

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    let beforeBufStatus = currentBufStatus

    status.highlightingText = HighlightingText(
      kind: HighlightingTextKind.search,
      text: @["a"].toSeqRunes)
      .some

    const Commands = @[EscKey.toRune, EscKey.toRune]
    check status.execNormalModeCommand(Commands).isNone

    check currentBufStatus == beforeBufStatus

    check status.highlightingText.isNone

  test "\"ESC /\" keys":
    # Remove ESC from top of the command and exec commands.

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Commands = @[EscKey.toRune, '/'.toRune]
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
    discard status.addNewBufferInCurrentWin.get

    const Buffer = @["a".toRunes]
    currentBufStatus.buffer = Buffer.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"yy"
    check status.execNormalModeCommand(Command).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == Buffer
    check r.isLine

  test "\"2yy\" keys":
    # Yank lines

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Buffer = @["a".toRunes, "b".toRunes]
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"2yy"
    check status.execNormalModeCommand(Command).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == Buffer
    check r.isLine

  test "\"10yy\" keys":
    # Yank lines

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const Buffer = toSeq(0..9).mapIt(it.toRunes)
    currentBufStatus.buffer = Buffer.initGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"10yy"
    check status.execNormalModeCommand(Command).isNone

    let r = status.registers.getNoNamedRegister
    check r.buffer == Buffer
    check r.isLine

  test "'0' command":
    # Move to top of the line.

    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin.get
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
    discard status.addNewBufferInCurrentWin(TestfilePath, Mode.normal).get

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
    discard status.addNewBufferInCurrentWin(TestfilePath, Mode.normal).get

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
    discard status.addNewBufferInCurrentWin.get

    status.resize(100, 100)
    status.update

    const RegisterName = 'a'
    status.startRecordingOperations(RegisterName.toRune)

    check status.recodingOperationRegister == some(ru'a')

  test "startRecordingOperations 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

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
    discard status.addNewBufferInCurrentWin.get

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
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Paste the line (p command)":
    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"line"])

    const Command = ru"p"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "line"].toSeqRunes

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Paste the line 2 (p command)":
    currentBufStatus.buffer = @["", ""].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"  line"])

    const Command = ru"p"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["", "  line", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 2

  test "Before folding line":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]

    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"d"])

    const Command = ru"p"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["a", "d", "b", "c"].toSeqRunes

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0
    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 2, last: 3)
    ]

suite "Normal mode: pasteBeforeCursor":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Paste the line (P command)":
    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"line"])

    const Command = ru"P"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["line", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Paste the line 2 (P command)":
    currentBufStatus.buffer = @["", ""].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"  line"])

    const Command = ru"P"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["  line", "", ""].toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Before folding line (P command)":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]

    status.resize(100, 100)
    status.update

    status.registers.setYankedRegister(@[ru"d"])

    const Command = ru"P"
    check status.normalCommand(Command).isNone
    status.update

    check currentBufStatus.buffer.toSeqRunes == @["d", "a", "b", "c"].toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0
    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 2, last: 3)
    ]

suite "Normal mode: Delete characters until the character and enter Insert mode (ct`x` command)":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Not found":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"ctz"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes
    check currentBufStatus.isNormalMode

  test "Basic 1":
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"ctf"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["f"].toSeqRunes
    check currentBufStatus.isInsertMode

  test "Basic 2":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru"ctd"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["adef"].toSeqRunes
    check currentBufStatus.isInsertMode

    check currentMainWindowNode.currentColumn == 1

  test "On folding line":
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru"ctf"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["f"].toSeqRunes
    check currentBufStatus.isInsertMode

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: Delete characters until the character (dt`x` command)":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Not found":
    currentBufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"dtz"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes
    check currentBufStatus.isNormalMode

  test "Basic 1":
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Command = ru"dtf"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["f"].toSeqRunes
    check currentBufStatus.isNormalMode

  test "Basic 2":
    currentBufStatus.buffer = @["abc def"].toSeqRunes.toGapBuffer
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    const Command = ru"dtd"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["adef"].toSeqRunes
    check currentBufStatus.isNormalMode

    check currentMainWindowNode.currentColumn == 1

  test "On folding line":
    currentBufStatus.buffer = @["abcdef", "ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    status.resize(100, 100)
    status.update

    const Command = ru"dtf"
    check status.normalCommand(Command).isNone

    status.update

    check currentBufStatus.buffer.toSeqRunes == @["f", "ghi"].toSeqRunes
    check currentBufStatus.isNormalMode

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: searchNextOccurrence":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Empty":
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru""
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Not found":
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"xyz"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Basic":
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"de"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 3

  test "Basic 2":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"def"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

  test "Basic 3":
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"ef"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 1

  test "Basic 4":
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"abc"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "With newline":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = "ef\nghi".toRunes
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 1

  test "Move twice":
    currentBufStatus.buffer = @["abc", "def", "abc", "def"]
      .toSeqRunes
      .toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"def"

    status.searchNextOccurrence(Keyword)
    status.update
    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0

    status.searchNextOccurrence(Keyword)
    status.update
    check currentMainWindowNode.currentLine == 3
    check currentMainWindowNode.currentColumn == 0

  test "On folding line":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]

    status.resize(100, 100)
    status.update

    const Keyword = ru"ef"
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 1
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: searchNextOccurrenceReversely":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Empty":
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru""
    status.searchNextOccurrence(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Not found":
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"xyz"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Basic":
    currentMainWindowNode.currentColumn = 5
    currentBufStatus.buffer = @["abcdef"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"bc"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "Basic 2":
    currentMainWindowNode.currentColumn = 2
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"abc"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic 3":
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"ef"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 1

  test "Basic 4":
    currentMainWindowNode.currentLine = 1
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"ghi"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 2
    check currentMainWindowNode.currentColumn == 0

  test "With newline":
    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 2
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = "ef\ngh".toRunes
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 1

  test "Move twice":
    currentMainWindowNode.currentLine = 3
    currentMainWindowNode.currentColumn = 2
    currentBufStatus.buffer = @["abc", "def", "abc", "def"]
      .toSeqRunes
      .toGapBuffer

    status.resize(100, 100)
    status.update

    const Keyword = ru"abc"

    status.searchNextOccurrenceReversely(Keyword)
    status.update
    check currentMainWindowNode.currentLine == 2
    check currentMainWindowNode.currentColumn == 0

    status.searchNextOccurrenceReversely(Keyword)
    status.update
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const Keyword = ru"bc"
    status.searchNextOccurrenceReversely(Keyword)
    status.update

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1
    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Normal mode: requestHover":
  test "Disable LSP":
    var status = initEditorStatus()
    status.settings.lsp.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["echo 1"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    # Nothing to do
    status.requestHover

    status.update

suite "Normal mode: requestGotoDefinition":
  test "Disable LSP":
    var status = initEditorStatus()
    status.settings.lsp.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["echo 1"].toSeqRunes.toGapBuffer

    status.resize(100, 100)
    status.update

    # Nothing to do
    status.requestGotoDefinition

    status.update
