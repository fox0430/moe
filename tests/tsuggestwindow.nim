import std/[unittest, macros, options, critbits, strutils]
import moepkg/[unicodeext, editorstatus, gapbuffer]
include moepkg/suggestionwindow

suite "suggestionwindow: buildSuggestionWindow":
  test "Case 1":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(
      @["test".ru,
        "test2".ru,
        "abc".ru,
        "efg".ru,
        "t".ru])

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    currentMainWindowNode.currentColumn = 1

    const currentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isSome

    check suggestionWin.get.wordDictionary.len == 4

    check suggestionWin.get.oldLine == "t".ru
    check suggestionWin.get.inputWord== "t".ru

    check suggestionWin.get.firstColumn == 0
    check suggestionWin.get.lastColumn == 0

    check suggestionWin.get.suggestoins == @["test2".ru, "test".ru]

    check suggestionWin.get.selectedSuggestion == -1

    check not suggestionWin.get.isPath

  test "Case 2":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(
      @["/".ru])

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high
    currentMainWindowNode.currentColumn = 1

    const currentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isSome

    check suggestionWin.get.wordDictionary.len == 0

    check suggestionWin.get.oldLine == "/".ru
    check suggestionWin.get.inputWord.len == 0

    check suggestionWin.get.firstColumn == 0
    check suggestionWin.get.lastColumn == 0

    check suggestionWin.get.suggestoins in "home".ru
    check suggestionWin.get.suggestoins in "root".ru
    check suggestionWin.get.suggestoins in "etc".ru

    check suggestionWin.get.selectedSuggestion == -1

    check suggestionWin.get.isPath

  test "Case 3":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].buffer = initGapBuffer(@["a".ru])

    currentMainWindowNode.currentColumn = 1

    const currentBufferIndex = 0

    let suggestionWin = status.wordDictionary.buildSuggestionWindow(
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    check suggestionWin.isNone
