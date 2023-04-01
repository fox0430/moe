import std/[unittest, heapqueue, options, macros, strformat]
import moepkg/[editorstatus, highlight, color, editorview, gapbuffer,
               unicodeext, movement, windownode, ui, independentutils,
               searchutils]

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
    status.settings.editorColorTheme)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.currentWord)

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
    status.settings.editorColorTheme)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.currentWord)

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
    status.settings.editorColorTheme)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.currentWord)

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
    endLine = if currentBufStatus.buffer.len > range.last + 1: range.last + 2
              elif currentBufStatus.buffer.len > range.last: range.last + 1
              else: range.last
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)

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
    endLine = if currentBufStatus.buffer.len > range.last + 1: range.last + 2
              elif currentBufStatus.buffer.len > range.last: range.last + 1
              else: range.last
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)

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
    endLine = if currentBufStatus.buffer.len > range.last + 1: range.last + 2
              elif currentBufStatus.buffer.len > range.last: range.last + 1
              else: range.last
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.highlightFullWidthSpace)

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
    endLine = if currentBufStatus.buffer.len > range.last + 1: range.last + 2
              elif currentBufStatus.buffer.len > range.last: range.last + 1
              else: range.last
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)
  check(highlight[2].color == EditorColorPair.defaultChar)

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
      status.settings)

    updateTerminalSize(100, 100)
    status.resize
    status.update

    let node = currentMainWindowNode
    check(node.highlight[0].color == EditorColorPair.defaultChar)
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
      status.settings)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastColumn == -1)

    check(highlight[1].color == EditorColorPair.defaultChar)
    check(highlight[1].firstColumn == 0)
    check(highlight[1].lastColumn == 2)

    check(highlight[2].color == EditorColorPair.highlightTrailingSpaces)
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
      status.settings)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastColumn == 0)

suite "highlightPairOfParen":
  const
    openParens = @[ru'(', ru'{', ru'[']
    closeParens = @[ru')', ru'}', ru']']

  ## Generate test code
  macro highlightParenPairTest(
    testIndex: int,
    paren: Rune,
    buffer: seq[Runes],
    position: BufferPosition,
    expectHighlight: Highlight): untyped =

      quote do:
        let testTitle =
          "Case " & $`testIndex` & ": highlightParenPair: '" & $`paren` & "'"

        test testTitle:
          var status = initEditorStatus()
          status.addNewBufferInCurrentWin

          status.bufStatus[0].buffer = `buffer`.toGapBuffer

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
      testIndex = 1
      buffer = @[ru""]
      position = BufferPosition(line: 0, column: 0)
      expectHighlight = Highlight(colorSegments: @[
        ColorSegment(firstRow: 0, firstColumn: 0, lastRow: 0, lastColumn: -1, color: EditorColorPair.defaultChar),
      ])

    for i in 0 ..< openParens.len:
      block open:
        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)
      block close:
        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase2:
    const testIndex = 2

    for i in 0 ..< openParens.len:
      let buffer = @[toRunes(fmt"{openParens[i]}{closeParens[i]}")]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPair.parenText),
          ])

        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 0, column: 1)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.parenText),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPair.defaultChar)
          ])

        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase3:
    const testIndex = 3

    for i in 0 ..< openParens.len:
      let buffer = @[toRunes(fmt"{openParens[i]} {closeParens[i]}")]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 1,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 0,
              firstColumn: 2,
              lastRow: 0,
              lastColumn: 2,
              color: EditorColorPair.parenText),
          ])

        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 0, column: 2)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.parenText),
            ColorSegment(
              firstRow: 0,
              firstColumn: 1,
              lastRow: 0,
              lastColumn: 2,
              color: EditorColorPair.defaultChar),
          ])

        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase4:
    const testIndex = 4

    for i in 0 ..< openParens.len:
      let buffer = @[openParens[i].toRunes, closeParens[i].toRunes]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPair.parenText),
          ])

        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 1, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.parenText),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
          ])

        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase5:
    const testIndex = 5

    for i in 0 ..< openParens.len:
      let buffer = @[openParens[i].toRunes, ru"", closeParens[i].toRunes]

      block open:
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 2,
              firstColumn: 0,
              lastRow: 2,
              lastColumn: 0,
              color: EditorColorPair.parenText),
          ])

        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)

      block close:
        const
          position = BufferPosition(line: 2, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.parenText),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 2,
              firstColumn: 0,
              lastRow: 2,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
          ])

        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase6:
    const testIndex = 6

    for i in 0 ..< openParens.len:

      block open:
        let buffer = @[openParens[i].toRunes, ru""]
        const
          position = BufferPosition(line: 0, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: 0,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: -1,
              color: EditorColorPair.defaultChar)
          ])

        highlightParenPairTest(testIndex, openParens[i], buffer, position, expectHighlight)

      block close:
        let buffer = @[ru"", closeParens[i].toRunes]
        const
          position = BufferPosition(line: 1, column: 0)
          expectHighlight = Highlight(colorSegments: @[
            ColorSegment(
              firstRow: 0,
              firstColumn: 0,
              lastRow: 0,
              lastColumn: -1,
              color: EditorColorPair.defaultChar),
            ColorSegment(
              firstRow: 1,
              firstColumn: 0,
              lastRow: 1,
              lastColumn: 0,
              color: EditorColorPair.defaultChar)
          ])

        highlightParenPairTest(testIndex, closeParens[i], buffer, position, expectHighlight)

  block highlightParenPairTestCase7:
    ## matchingParenPair should ignore '"'.
    const
      testIndex = 7
      buffer = @["\"\"".toRunes]
      position = BufferPosition(line: 0, column: 0)
      paren = ru'"'
      expectHighlight = Highlight(colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 1,
          color: EditorColorPair.defaultChar)
      ])

    highlightParenPairTest(testIndex, paren, buffer, position, expectHighlight)


  block highlightParenPairTestCase8:
    ## matchingParenPair should ignore '''.
    const
      testIndex = 8
      buffer = @["''".toRunes]
      position = BufferPosition(line: 0, column: 0)
      paren = ru'\''
      expectHighlight = Highlight(colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 1,
          color: EditorColorPair.defaultChar)
      ])

    highlightParenPairTest(testIndex, paren, buffer, position, expectHighlight)

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
      color: EditorColorPair.parenText)

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
      color: EditorColorPair.parenText)

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
      status.settings)

    check highlight.len == 3
    check highlight[0].color == EditorColorPair.searchResult
    check highlight[1].color == EditorColorPair.defaultChar
    check highlight[2].color == EditorColorPair.defaultChar

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
            status.settings)

          check highlight.len == 3
          check highlight[0].color == EditorColorPair.searchResult
          check highlight[1].color == EditorColorPair.defaultChar
          check highlight[2].color == EditorColorPair.defaultChar
