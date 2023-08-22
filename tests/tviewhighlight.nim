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

import std/[unittest, heapqueue, options, strformat, strutils]
import pkg/results
import moepkg/syntax/highlite
import moepkg/[editorstatus, highlight, color, editorview, gapbuffer,
               unicodeext, movement, windownode, ui, independentutils,
               bufferstatus]

import moepkg/viewhighlight {.all.}

proc initHighlight(status: EditorStatus) {.inline.} =
  currentMainWindowNode.highlight = initHighlight(
    $currentBufStatus.buffer,
    status.settings.highlight.reservedWords,
    currentBufStatus.language)

test "Highlight current word 1":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"test abc test"])
  status.initHighlight

  updateTerminalSize(100, 100)
  status.resize
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightOtherUsesCurrentWord(
    currentBufStatus,
    currentMainWindowNode,
    status.settings.editorColorTheme,
    status.settings.colorMode)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.currentWord)

test "Highlight current word 2":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"test", ru"test"])

  updateTerminalSize(100, 100)
  status.resize
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightOtherUsesCurrentWord(
    currentBufStatus,
    currentMainWindowNode,
    status.settings.editorColorTheme,
    status.settings.colorMode)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.currentWord)

test "Highlight current word 3":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"[test]", ru"test"])

  updateTerminalSize(100, 100)
  status.resize
  currentBufStatus.keyRight(currentMainWindowNode)
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightOtherUsesCurrentWord(
    currentBufStatus,
    currentMainWindowNode,
    status.settings.editorColorTheme,
    status.settings.colorMode)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.currentWord)

test "Highlight full width space 1":
  var status = initEditorStatus()

  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"", ru"　"])

  status.settings.highlight.currentWord = false
  status.initHighlight

  updateTerminalSize(100, 100)
  status.resize
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.first
    endLine =
      if currentBufStatus.buffer.len > range.last + 1: range.last + 2
      elif currentBufStatus.buffer.len > range.last: range.last + 1
      else: range.last
  var bufferInView = initGapBuffer[Runes]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.highlightFullWidthSpace)

test "Highlight full width space 2":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"abc　"])

  status.settings.highlight.currentWord = false
  status.initHighlight

  updateTerminalSize(100, 100)
  status.resize
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.first
    endLine =
      if currentBufStatus.buffer.len > range.last + 1: range.last + 2
      elif currentBufStatus.buffer.len > range.last: range.last + 1
      else: range.last
  var bufferInView = initGapBuffer[Runes]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.highlightFullWidthSpace)

test "Highlight full width space 3":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"　"])

  status.settings.highlight.currentWord = false
  status.initHighlight

  updateTerminalSize(100, 100)
  status.resize
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.first
    endLine =
      if currentBufStatus.buffer.len > range.last + 1: range.last + 2
     elif currentBufStatus.buffer.len > range.last: range.last + 1
     else: range.last
  var bufferInView = initGapBuffer[Runes]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPairIndex.highlightFullWidthSpace)

test "Highlight full width space 4":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"a　b"])

  status.settings.highlight.currentWord = false
  status.initHighlight

  updateTerminalSize(100, 100)
  status.resize
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.first
    endLine =
      if currentBufStatus.buffer.len > range.last + 1: range.last + 2
      elif currentBufStatus.buffer.len > range.last: range.last + 1
      else: range.last
  var bufferInView = initGapBuffer[Runes]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPairIndex.default)
  check(highlight[1].color == EditorColorPairIndex.highlightFullWidthSpace)
  check(highlight[2].color == EditorColorPairIndex.default)

suite "Highlight trailing spaces":
  test "Highlight trailing spaces 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.settings.highlight.currentWord = false

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings,
      status.settings.colorMode)

    updateTerminalSize(100, 100)
    status.resize
    status.update

    let node = currentMainWindowNode
    check(node.highlight[0].color == EditorColorPairIndex.default)
    check(node.highlight[0].firstColumn == 0)
    check(node.highlight[0].lastColumn == 2)

  test "Highlight trailing spaces 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc  "])

    status.settings.highlight.currentWord = false

    status.initHighlight

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings,
      status.settings.colorMode)

    check(highlight[0].color == EditorColorPairIndex.default)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastColumn == -1)

    check(highlight[1].color == EditorColorPairIndex.default)
    check(highlight[1].firstColumn == 0)
    check(highlight[1].lastColumn == 2)

    check(highlight[2].color == EditorColorPairIndex.highlightTrailingSpaces)
    check(highlight[2].firstColumn == 3)
    check(highlight[2].lastColumn == 4)

  test "Highlight trailing spaces 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru" "])

    status.settings.highlight.currentWord = false

    status.initHighlight

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings,
      status.settings.colorMode)

    check(highlight[0].color == EditorColorPairIndex.default)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastColumn == 0)

suite "highlightPairOfParen":
  const
    OpenParens = @[ru'(', ru'{', ru'[']
    CloseParens = @[ru')', ru'}', ru']']

  proc highlightParenPairTest(
    TestIndex: int,
    paren: Rune,
    buffer: seq[Runes],
    position: BufferPosition,
    expectHighlight: Highlight) =

      let testTitle =
        "Case " & $TestIndex & ": highlightParenPair: '" & $paren & "'"

      test testTitle:
        var status = initEditorStatus()
        status.addNewBufferInCurrentWin

        status.bufStatus[0].buffer = buffer.toGapBuffer

        status.mainWindow.currentMainWindowNode.currentLine = position.line
        status.mainWindow.currentMainWindowNode.currentColumn = position.column

        updateTerminalSize(100, 100)
        status.resize
        status.update()

        status.initHighlight

        var highlight = status.mainWindow.currentMainWindowNode.highlight
        highlight.highlightPairOfParen(
          status.bufStatus[0],
          status.mainWindow.currentMainWindowNode)

        check highlight == `expectHighlight`

  block highlightParenPairTestCase1:
    ## Case 1 is starting the search on an empty line.
    const
      TestIndex = 1
      Buffer = @[ru""]
      Position = BufferPosition(line: 0, column: 0)
      ExpectHighlight = Highlight(colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: -1,
          color: EditorColorPairIndex.default),
      ])

    for i in 0 ..< OpenParens.len:
      block open:
        highlightParenPairTest(
          TestIndex,
          OpenParens[i],
          Buffer,
          Position,
          ExpectHighlight)
      block close:
        highlightParenPairTest(
          TestIndex,
          CloseParens[i],
          Buffer,
          Position,
          ExpectHighlight)

  block highlightParenPairTestCase2:
    const TestIndex = 2

    for i in 0 ..< OpenParens.len:
      let buffer = @[toRunes(fmt"{OpenParens[i]}{CloseParens[i]}")]

      block open:
        const
          Position = BufferPosition(line: 0, column: 0)
          ExpectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPairIndex.parenPair),
          ])

        highlightParenPairTest(TestIndex, OpenParens[i], buffer, Position, ExpectHighlight)

      block close:
        const
          position = BufferPosition(line: 0, column: 1)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPairIndex.default)
          ])

        highlightParenPairTest(TestIndex, CloseParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase3:
    const TestIndex = 3

    for i in 0 ..< OpenParens.len:
      let buffer = @[toRunes(fmt"{OpenParens[i]} {CloseParens[i]}")]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 0,
              firstColumn: 2,
              lastRow: 0,
              lastColumn: 2,
              color: EditorColorPairIndex.parenPair),
          ])

        highlightParenPairTest(TestIndex, OpenParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 0, column: 2)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 2,
              color: EditorColorPairIndex.default),
          ])

        highlightParenPairTest(TestIndex, CloseParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase4:
    const TestIndex = 4

    for i in 0 ..< OpenParens.len:
      let buffer = @[OpenParens[i].toRunes, CloseParens[i].toRunes]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
          ])

        highlightParenPairTest(TestIndex, OpenParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 1, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
          ])

        highlightParenPairTest(TestIndex, CloseParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase5:
    const TestIndex = 5

    for i in 0 ..< OpenParens.len:
      let buffer = @[OpenParens[i].toRunes, ru"", CloseParens[i].toRunes]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 2,
              firstColumn: 0,
              lastRow: 2,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
          ])

        highlightParenPairTest(TestIndex, OpenParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 2, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.parenPair),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 2,
              firstColumn: 0,
              lastRow: 2,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
          ])

        highlightParenPairTest(TestIndex, CloseParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase6:
    const TestIndex = 6

    for i in 0 ..< OpenParens.len:

      block open:
        let buffer = @[OpenParens[i].toRunes, ru""]
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPairIndex.default)
          ])

        highlightParenPairTest(TestIndex, OpenParens[i], buffer, position, expectHighlight)

      block close:
        let buffer = @[ru"", CloseParens[i].toRunes]
        const
          position = BufferPosition(line: 1, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: -1,
              color: EditorColorPairIndex.default),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPairIndex.default)
          ])

        highlightParenPairTest(TestIndex, CloseParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase7:
    ## matchingParenPair should ignore '"'.
    const
      TestIndex = 7
      Buffer = @["\"\"".toRunes]
      Position = BufferPosition(line: 0, column: 0)
      Paren = ru'"'
      ExpectHighlight = Highlight(colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 1,
          color: EditorColorPairIndex.default)
      ])

    highlightParenPairTest(TestIndex, Paren, Buffer, Position, ExpectHighlight)


  block highlightParenPairTestCase8:
    ## matchingParenPair should ignore '''.
    const
      TestIndex = 8
      Buffer = @["''".toRunes]
      Position = BufferPosition(line: 0, column: 0)
      Paren = ru'\''
      ExpectHighlight = Highlight(colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 1,
          color: EditorColorPairIndex.default)
      ])

    highlightParenPairTest(TestIndex, Paren, Buffer, Position, ExpectHighlight)

  block highlightParenPairTestCase9:
    const TestIndex = 9

    for i in 0 ..< OpenParens.len:
      let buffer = @[CloseParens[i].toRunes]

      const
        Position = BufferPosition(line: 0, column: 0)
        ExpectHighlight = Highlight(colorSegments: @[
          ColorSegment(
            firstRow: 0,
            firstColumn: 0,
            lastRow: 0,
            lastColumn: 0,
            color: EditorColorPairIndex.default)
        ])

      highlightParenPairTest(TestIndex, CloseParens[i], buffer, Position, ExpectHighlight)

suite "Highlight paren":
  test "Highlight ')'":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru"proc test(a: string) ="])

    updateTerminalSize(100, 100)
    status.resize
    status.update()

    currentMainWindowNode.currentColumn = 9

    status.initHighlight

    var highlight = currentMainWindowNode.highlight
    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check highlight[8] == ColorSegment(
      firstRow: 0, firstColumn: 19, lastRow: 0, lastColumn: 19,
      color: EditorColorPairIndex.parenPair)

  test "Highlight '('":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru"proc test(a: string) ="])

    updateTerminalSize(100, 100)
    status.resize
    status.update()

    currentMainWindowNode.currentColumn = 19

    status.initHighlight

    var highlight = currentMainWindowNode.highlight
    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check highlight[3] == ColorSegment(
      firstRow: 0, firstColumn: 9, lastRow: 0, lastColumn: 9,
      color: EditorColorPairIndex.parenPair)

suite "Update search highlight":
  test "single window":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    updateTerminalSize(100, 100)
    status.resize
    status.update

    status.searchHistory = @[ru "abc"]
    status.isSearchHighlight = true

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings,
      status.settings.colorMode)

    check highlight.len == 3
    check highlight[0].color == EditorColorPairIndex.searchResult
    check highlight[1].color == EditorColorPairIndex.default
    check highlight[2].color == EditorColorPairIndex.default

  test "two windows":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    updateTerminalSize(100, 100)
    status.resize
    status.update

    status.verticalSplitWindow

    status.searchHistory = @[ru "abc"]
    status.isSearchHighlight = true

    var queue = initHeapQueue[WindowNode]()
    for node in mainWindowNode.child:
      queue.push(node)

    while queue.len > 0:
      for i in  0 ..< queue.len:
        var node = queue.pop

        if node.window.isSome:
          var highlight = node.highlight
          highlight.updateHighlight(
            currentBufStatus,
            node,
            status.isSearchHighlight,
            status.searchHistory,
            status.settings,
            status.settings.colorMode)

          check highlight.len == 3
          check highlight[0].color == EditorColorPairIndex.searchResult
          check highlight[1].color == EditorColorPairIndex.default
          check highlight[2].color == EditorColorPairIndex.default

suite "Highlighting git conflicts":
  test "highlightGitConflicts":
    const
      Range = Range(first: 0, last: 100)
      Buffer = """
<<<<<<< HEAD
echo 1
echo 2
=======
echo "test"
>>>>>>> new_branch
""".splitLines.toSeqRunes

    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = Buffer.toGapBuffer
    var h = initHighlight($bufStatus.buffer, @[], SourceLanguage.langNim)

    h.highlightGitConflicts(bufStatus, Range)

    check h.colorSegments == @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 0,
        lastColumn: 6,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 0,
        firstColumn: 7,
        lastRow: 0,
        lastColumn: 7,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 0,
        firstColumn: 8,
        lastRow: 0,
        lastColumn: 11,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 1,
        firstColumn: 0,
        lastRow: 1,
        lastColumn: 3,
        color: EditorColorPairIndex.builtin,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 1,firstColumn: 4,
        lastRow: 1,lastColumn: 4,
        color: EditorColorPairIndex.default,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 1,
        firstColumn: 5,
        lastRow: 1,
        lastColumn: 5,
        color: EditorColorPairIndex.decNumber,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 2,
        firstColumn: 0,
        lastRow: 2, lastColumn: 3,
        color: EditorColorPairIndex.builtin,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 2,
        firstColumn: 4,
        lastRow: 2,
        lastColumn: 4,
        color: EditorColorPairIndex.default,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 2,
        firstColumn: 5,
        lastRow: 2,
        lastColumn: 5,
        color: EditorColorPairIndex.decNumber,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 3,
        firstColumn: 0,
        lastRow: 3,
        lastColumn: 6,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 4,
        firstColumn: 0,
        lastRow: 4,
        lastColumn: 3,
        color: EditorColorPairIndex.builtin,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 4,
        firstColumn: 4,
        lastRow: 4,
        lastColumn: 4,
        color: EditorColorPairIndex.default,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 4,
        firstColumn: 5,
        lastRow: 4,
        lastColumn: 10,
        color: EditorColorPairIndex.stringLit,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 5,
        firstColumn: 0,
        lastRow: 5,
        lastColumn: 6,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 5,
        firstColumn: 7,
        lastRow: 5,
        lastColumn: 7,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal),
      ColorSegment(
        firstRow: 5,
        firstColumn: 8,
        lastRow: 5,
        lastColumn: 17,
        color: EditorColorPairIndex.gitConflict,
        attribute: Attribute.normal)
    ]

  test "Out of range":
    const
      Range = Range(first: 0, last: 100)
      Code = """
<<<<<<< HEAD
echo 1
echo 2
=======
echo "test"
>>>>>>> new_branch
""".splitLines

    var bufStatus = initBufferStatus("").get
    for i in 0..100:
      bufStatus.buffer.add ru""
    for line in Code:
      bufStatus.buffer.add line.toRunes

    var h = initHighlight($bufStatus.buffer, @[], SourceLanguage.langNim)

    h.highlightGitConflicts(bufStatus, Range)

    for cs in h.colorSegments:
      check cs.color != EditorColorPairIndex.gitConflict
