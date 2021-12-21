import std/unittest
import moepkg/[ui, highlight, editorview, gapbuffer, unicodeext,
               editor, window, color, bufferstatus, settings]

from moepkg/movement import keyDown, keyRight

include moepkg/editorstatus

template initHighlight() =
  currentMainWindowNode.highlight = initHighlight(
    $currentBufStatus.buffer,
    status.settings.highlightSettings.reservedWords,
    currentBufStatus.language)

suite "Add new buffer":
  test "Add 2 uffers":
    var status = initEditorStatus()

    status.addNewBuffer

    status.resize(100, 100)
    status.update

    status.addNewBuffer

    check status.bufStatus.len == 2

  test "Add new buffer (Dir)":
    var status = initEditorStatus()

    status.addNewBuffer("./")

    status.resize(100, 100)
    status.update

test "Add new buffer and update editor view when disabling current line highlighting (Fix #1189)":
  var status = initEditorStatus()
  status.addNewBuffer
  status.settings.view.highlightCurrentLine = false

  status.resize(100, 100)
  status.update

test "Vertical split window":
  var status = initEditorStatus()
  status.addNewBuffer
  status.resize(100, 100)
  status.verticalSplitWindow

test "Horizontal split window":
  var status = initEditorStatus()
  status.addNewBuffer
  status.resize(100, 100)
  status.horizontalSplitWindow

test "resize 1":
  var status = initEditorStatus()
  status.addNewBuffer
  status.resize(100, 100)
  currentBufStatus.buffer = initGapBuffer(@[ru"a"])

  currentMainWindowNode.highlight =
    initHighlight($currentBufStatus.buffer,
    status.settings.highlightSettings.reservedWords,
    currentBufStatus.language)

  currentMainWindowNode.view =
    initEditorView(currentBufStatus.buffer, 1, 1)

  status.resize(0, 0)

test "resize 2":
  var status = initEditorStatus()
  status.addNewBuffer
  status.resize(100, 100)
  currentBufStatus.buffer = initGapBuffer(@[ru"a"])

  initHighlight()

  currentMainWindowNode.view =
    initEditorView(currentBufStatus.buffer, 20, 4)

  status.resize(20, 4)

  currentMainWindowNode.currentColumn = 1
  status.changeMode(Mode.insert)

  for i in 0 ..< 10:
    currentBufStatus.keyEnter(currentMainWindowNode,
                                 status.settings.autoCloseParen,
                                 status.settings.tabStop)
    status.update

test "Highlight of a pair of paren 1":
  var status = initEditorStatus()
  status.addNewBuffer

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
  status.addNewBuffer
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
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])
  initHighlight()
  status.update

  var highlight = currentMainWindowNode.highlight
  highlight.highlightPairOfParen(currentBufStatus, currentMainWindowNode)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[0].firstRow == 0)

  check(highlight[1].color == EditorColorPair.parenText)
  check(highlight[1].firstRow == 1)

test "Highlight of a pair of paren 5":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"a)"])
  initHighlight()
  status.resize(100, 100)

  currentBufStatus.keyDown(currentMainWindowNode)
  status.update

test "Auto delete paren 1":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")

test "Auto delete paren 2":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])

    for i in 0 ..< 2:
     currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(())"])
    for i in 0 ..< 3:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

test "Auto delete paren 3":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer

    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(()"])
    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"(")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])
    currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru")")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"())"])

    for i in 0 ..< 3:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"()")

test "Auto delete paren 4":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")
    check(currentBufStatus.buffer[1] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(", ru")"])
    currentBufStatus.keyDown(currentMainWindowNode)

    currentBufStatus.deleteCharacter(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn,
      status.settings.autoDeleteParen)

    check(currentBufStatus.buffer[0] == ru"")
    check(currentBufStatus.buffer[1] == ru"")

test "Auto delete paren 5":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    currentBufStatus.keyRight(currentMainWindowNode)
    currentBufStatus.keyBackspace(currentMainWindowNode,
                                  status.settings.autoDeleteParen,
                                  status.settings.tabStop)

    check(currentBufStatus.buffer[0] == ru"")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"()"])
    status.changeMode(Mode.insert)
    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
    currentBufStatus.keyBackspace(currentMainWindowNode,
                                  status.settings.autoDeleteParen,
                                  status.settings.tabStop)

    check(currentBufStatus.buffer[0] == ru"")

test "Auto delete paren 6":
  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

    status.changeMode(Mode.insert)

    for i in 0 ..< 5:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.keyBackspace(currentMainWindowNode,
                                  status.settings.autoDeleteParen,
                                  status.settings.tabStop)

    check(currentBufStatus.buffer[0] == ru"(aa)")

  block:
    var status = initEditorStatus()
    status.settings.autoDeleteParen = true

    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"(a(a))"])

    status.changeMode(Mode.insert)

    for i in 0 ..< 6:
      currentBufStatus.keyRight(currentMainWindowNode)

    currentBufStatus.keyBackspace(currentMainWindowNode,
                                  status.settings.autoDeleteParen,
                                  status.settings.tabStop)

    check(currentBufStatus.buffer[0] == ru"a(a)")

test "Highlight current word 1":
  var status = initEditorStatus()
  status.addNewBuffer
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
  status.addNewBuffer
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
  status.addNewBuffer
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

  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"", ru"　"])

  status.settings.highlightSettings.currentWord = false
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if currentBufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif currentBufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)

test "Highlight full width space 2":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"abc　"])

  status.settings.highlightSettings.currentWord = false
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if currentBufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif currentBufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)

test "Highlight full width space 3":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"　"])

  status.settings.highlightSettings.currentWord = false
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if currentBufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif currentBufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.highlightFullWidthSpace)

test "Highlight full width space 4":
  var status = initEditorStatus()
  status.addNewBuffer
  currentBufStatus.buffer = initGapBuffer(@[ru"a　b"])

  status.settings.highlightSettings.currentWord = false
  initHighlight()
  status.update

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if currentBufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif currentBufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(currentBufStatus.buffer[i])

  var highlight = currentMainWindowNode.highlight
  highlight.highlightFullWidthSpace(currentMainWindowNode, bufferInView, range)

  check(highlight[0].color == EditorColorPair.defaultChar)
  check(highlight[1].color == EditorColorPair.highlightFullWidthSpace)
  check(highlight[2].color == EditorColorPair.defaultChar)

test "Write tab line":
  var status = initEditorStatus()
  status.addNewBuffer("test.txt")

  status.resize(100, 100)

  check(status.tabWindow.width == 100)

test "Close window":
  var status = initEditorStatus()
  status.addNewBuffer
  status.resize(100, 100)
  status.verticalSplitWindow
  status.closeWindow(currentMainWindowNode, 100, 100)

test "Close window 2":
  var status = initEditorStatus()
  status.addNewBuffer

  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode, 100, 100)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 1)

  check(currentMainWindowNode.h == 98)
  check(currentMainWindowNode.w == 100)

test "Close window 3":
  var status = initEditorStatus()
  status.addNewBuffer

  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode, 100, 100)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 2)

  for n in windowNodeList:
    check(n.w == 50)
    check(n.h == 98)

test "Close window 4":
  var status = initEditorStatus()
  status.addNewBuffer

  status.resize(100, 100)
  status.update

  status.horizontalSplitWindow
  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode, 100, 100)
  status.resize(100, 100)
  status.update

  let windowNodeList = mainWindowNode.getAllWindowNode

  check(windowNodeList.len == 2)

  check(windowNodeList[0].w == 100)
  check(windowNodeList[0].h == 49)

  check(windowNodeList[1].w == 100)
  check(windowNodeList[1].h == 49)

test "Close window 5":
  var status = initEditorStatus()
  status.addNewBuffer("test.nim")

  status.resize(100, 100)
  status.update

  status.verticalSplitWindow
  status.resize(100, 100)
  status.update

  status.moveCurrentMainWindow(1)
  status.addNewBuffer("test2.nim")
  status.changeCurrentBuffer(1)
  status.resize(100, 100)
  status.update

  status.closeWindow(currentMainWindowNode, 100, 100)
  status.resize(100, 100)
  status.update

  check(currentMainWindowNode.bufferIndex == 0)

# Fix #611
test "Change current buffer":
  var status = initEditorStatus()

  status.addNewBuffer
  currentBufStatus.path = ru"test"
  currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

  status.resize(100, 100)
  status.update

  let
    currentLine = currentBufStatus.buffer.high
    currentColumn = currentBufStatus.buffer[currentLine].high
  currentMainWindowNode.currentLine = currentLine
  currentMainWindowNode.currentColumn = currentColumn

  status.addNewBuffer
  currentBufStatus.path = ru"test2"
  currentBufStatus.buffer =  initGapBuffer(@[ru""])

  status.changeCurrentBuffer(1)

  status.resize(100, 100)
  status.update

suite "editorstatus: Highlight trailing spaces":
  test "Highlight trailing spaces":
    var status = initEditorStatus()
    status.addNewBuffer

    status.settings.highlightSettings.currentWord = false

    currentMainWindowNode.highlight = initHighlight(
      $currentBufStatus.buffer,
      status.settings.highlightSettings.reservedWords,
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
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc  "])

    status.settings.highlightSettings.currentWord = false

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
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru" "])

    status.settings.highlightSettings.currentWord = false

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

suite "editorstatus: Highlight paren":
  test "Highlight ')'":
    var status = initEditorStatus()
    status.addNewBuffer("test.nim")
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
    status.addNewBuffer("test.nim")
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

suite "editorstatus: Updates/Restore the last cursor postion":
  test "Update the last cursor position (3 lines)":
    var status = initEditorStatus()

    status.addNewBuffer("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.updateLastCursorPostion

    check status.lastPosition[0].path == absolutePath("test.nim").ru
    check status.lastPosition[0].line == 1
    check status.lastPosition[0].column == 1

  test "Update and restore the last cursor position (3 lines and edit the buffer after save)":
    var status = initEditorStatus()

    status.addNewBuffer("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru "e"])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    status.updateLastCursorPostion

    # Edit buffer after update the last cursor position
    currentBufStatus.buffer[1] = ru ""

    currentMainWindowNode.restoreCursorPostion(currentBufStatus,
                                               status.lastPosition)
    status.update

    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

  test "Update and restore the last cursor position (3 lines and last line is empty)":
    var status = initEditorStatus()

    status.addNewBuffer("test.nim")

    status.addNewBuffer("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru "a", ru "bcd", ru ""])

    status.resize(100, 100)
    status.update

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    status.update

    status.updateLastCursorPostion

    currentMainWindowNode.restoreCursorPostion(currentBufStatus,
                                               status.lastPosition)

    status.update

    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 0

suite "Update search highlight":
  test "single window":
    var status = initEditorStatus()
    status.addNewBuffer("test.nim")
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
    status.addNewBuffer("test.nim")
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

suite "Fix #1361":
  test "Insert a character after split window":
    var status = initEditorStatus()
    status.addNewBuffer("test.nim")
    currentBufStatus.buffer = initGapBuffer(@[ru ""])

    status.resize(100, 100)
    status.update

    status.verticalSplitWindow

    const key = ru 'a'
    currentBufStatus.insertCharacter(
      currentMainWindowNode,
      status.settings.autoCloseParen,
      key)

    status.update

    let nodes = mainWindowNode.getAllWindowNode
    check nodes[0].highlight == nodes[1].highlight
