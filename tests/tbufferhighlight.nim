import std/[unittest, heapqueue, options]
import moepkg/[editorstatus, highlight, color, editorview, gapbuffer,
               unicodeext, movement, window]

import moepkg/bufferhighlight {.all.}

template initHighlight() =
  currentMainWindowNode.highlight = initHighlight(
    $currentBufStatus.buffer,
    status.settings.highlight.reservedWords,
    currentBufStatus.language)

test "Highlight of a pair of paren 1":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin

  block:
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    initHighlight()
    status.update

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)

    check(highlight[1].color == EditorColorPair.parenText)
    check(highlight[1].firstColumn == 1)

  block:
    currentBufStatus.buffer = initGapBuffer(@[ru"[]"])
    initHighlight()
    status.update

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)
    check(highlight[1].color == EditorColorPair.parenText)
    check(highlight[1].firstColumn == 1)

  block:
    currentBufStatus.buffer = initGapBuffer(@[ru"{}"])
    initHighlight()
    status.update

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)
    check(highlight[1].color == EditorColorPair.parenText)
    check(highlight[1].firstColumn == 1)

  block:
    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
    initHighlight()
    status.update

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check(highlight[0].color == EditorColorPair.defaultChar)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastColumn == 2)

test "Highlight of a pair of paren 2":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
  initHighlight()
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[0].firstColumn == 0)
  check(highlight[0].lastColumn == 2)
  check(highlight[1].color == EditorColorPair.parenText)
  check(highlight[1].firstColumn == 3)

test "Highlight of a pair of paren 3":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])
  initHighlight()
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[0].firstRow == 0)

  check(highlight[1].color == EditorColorPair.parenText)
  check(highlight[1].firstRow == 1)

test "Highlight of a pair of paren 4":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"a)"])
  initHighlight()
  status.resize(100, 100)

  currentBufStatus.keyDown(currentMainWindowNode)
  status.update

test "Highlight current word 1":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  currentBufStatus.buffer = initGapBuffer(@[ru"test abc test"])
  initHighlight()
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

  status.resize(100, 100)
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

  status.resize(100, 100)
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
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.start
    endLine = if currentBufStatus.buffer.len > range.end + 1: range.end + 2
              elif currentBufStatus.buffer.len > range.end: range.end + 1
              else: range.end
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
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.start
    endLine = if currentBufStatus.buffer.len > range.end + 1: range.end + 2
              elif currentBufStatus.buffer.len > range.end: range.end + 1
              else: range.end
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
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.start
    endLine = if currentBufStatus.buffer.len > range.end + 1: range.end + 2
              elif currentBufStatus.buffer.len > range.end: range.end + 1
              else: range.end
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
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range.start
    endLine = if currentBufStatus.buffer.len > range.end + 1: range.end + 2
              elif currentBufStatus.buffer.len > range.end: range.end + 1
              else: range.end
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

    initHighlight()

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

    initHighlight()

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

suite "Highlight paren":
  test "Highlight ')'":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru"proc test(a: string) ="])

    status.resize(100, 100)
    status.update()

    currentMainWindowNode.currentColumn = 9

    initHighlight()

    var highlight = currentMainWindowNode.highlight
    highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

    check highlight[8] == ColorSegment(
      firstRow: 0, firstColumn: 19, lastRow: 0, lastColumn: 19,
      color: EditorColorPair.parenText)

  test "Highlight '('":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru"proc test(a: string) ="])

    status.resize(100, 100)
    status.update()

    currentMainWindowNode.currentColumn = 19

    initHighlight()

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

    status.resize(100, 100)
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

    status.resize(100, 100)
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
