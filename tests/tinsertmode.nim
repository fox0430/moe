import unittest, options
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, suggestionwindow]
include moepkg/insertmode

suite "Insert mode":
  test "Issue #474":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.workSpace[0].currentMainWindowNode.highlight = initHighlight(
      $status.bufStatus[0].buffer,
      status.settings.reservedWords,
      status.bufStatus[0].language)

    status.resize(10, 10)

    for i in 0..<100:
      insertCharacter(status.bufStatus[0],
                      status.workSpace[0].currentMainWindowNode,
                      status.settings.autoCloseParen,
                      ru'a')

    status.update

  test "Insert the character which is below the cursor":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.bufStatus[0].insertCharacterBelowCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"ba")
    check(buffer[1] == ru"b")

  test "Insert the character which is below the cursor 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].insertCharacterBelowCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abc")

  test "Insert the character which is below the cursor 3":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"e"])

    status.workspace[0].currentMainWindowNode.currentColumn = 2

    status.bufStatus[0].insertCharacterBelowCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"abc")
    check(buffer[1] == ru"e")

  test "Insert the character which is above the cursor":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.workspace[0].currentMainWindowNode.currentLine = 1

    status.bufStatus[0].insertCharacterAboveCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"a")
    check(buffer[1] == ru"ab")

  test "Insert the character which is above the cursor":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"bcd"])

    status.workspace[0].currentMainWindowNode.currentLine = 1
    status.workspace[0].currentMainWindowNode.currentColumn = 2

    status.bufStatus[0].insertCharacterAboveCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"a")
    check(buffer[1] == ru"bcd")

  test "Insert the character which is above the cursor 3":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.bufStatus[0].insertCharacterAboveCursor(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"a")

  test "Delete the word before the cursor":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def"])

    status.workspace[0].currentMainWindowNode.currentColumn = 4

    status.bufStatus[0].deleteWordBeforeCursor(
      status.workSpace[0].currentMainWindowNode,
      status.settings.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"def")

  test "Delete the word before the cursor 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].deleteWordBeforeCursor(
      status.workSpace[0].currentMainWindowNode,
      status.settings.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abc")

  test "Delete the word before the cursor 3":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.workspace[0].currentMainWindowNode.currentLine = 1

    status.bufStatus[0].deleteWordBeforeCursor(
      status.workSpace[0].currentMainWindowNode,
      status.settings.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abcdef")

  test "Delete characters before the cursor in current line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abcdef"])

    status.workspace[0].currentMainWindowNode.currentColumn = 4

    status.bufStatus[0].deleteCharactersBeforeCursorInCurrentLine(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"ef")

  test "Delete characters before the cursor in current line 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.bufStatus[0].deleteCharactersBeforeCursorInCurrentLine(
      status.workSpace[0].currentMainWindowNode
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"a")

  test "Add indent in current line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].addIndentInCurrentLine(
      status.workSpace[0].currentMainWindowNode,
      status.settings.view.tabStop
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"  abc")

    check(status.workSpace[0].currentMainWindowNode.currentColumn == 2)

  test "Delete indent in current line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])

    status.bufStatus[0].deleteIndentInCurrentLine(
      status.workSpace[0].currentMainWindowNode,
      status.settings.view.tabStop
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"abc")

    check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

  test "Delete indent in current line 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].deleteIndentInCurrentLine(
      status.workSpace[0].currentMainWindowNode,
      status.settings.view.tabStop
    )

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"abc")

    check(status.workSpace[0].currentMainWindowNode.currentColumn == 0)

  test "Move to last of line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    status.bufStatus[0].mode = Mode.insert

    status.bufStatus[0].moveToLastOfLine(status.workspace[0].currentMainWindowNode)

    check status.workspace[0].currentMainWindowNode.currentColumn == 3

  test "General-purpose autocomplete window position 1":
    const buffer = @[ru"a", ru"aba", ru"abb", ru"abc", ru"abd", ru"abe", ru"abf"]
    var status = initEditorStatus()
    status.addNewBuffer(Mode.insert)
    status.bufStatus[0].buffer = initGapBuffer(buffer)
    status.workspace[0].currentMainWindowNode.currentColumn = 1

    var suggestionWindow = none(SuggestionWindow)

    status.resize(100, 100)
    status.update

    suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
    let
      mainWindowHeight = status.settings.getMainWindowHeight(100)
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindow,
        mainWindowHeight)

    suggestionWindow.get.writeSuggestionWindow(y, x)

    check y == 2
    check x == 1

  test "General-purpose autocomplete window position 2":
    const buffer = @[ru"aba", ru"abb", ru"abc", ru"abcd", ru"", ru"a"]
    var status = initEditorStatus()
    status.addNewBuffer(Mode.insert)
    status.bufStatus[0].buffer = initGapBuffer(buffer)
    status.workspace[0].currentMainWindowNode.currentLine = buffer.high
    status.workspace[0].currentMainWindowNode.currentColumn = 1

    var suggestionWindow = none(SuggestionWindow)

    const terminalHeight = 10

    status.resize(terminalHeight, 100)
    status.update

    suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
    let
      mainWindowHeight = status.settings.getMainWindowHeight(terminalHeight)
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindow,
        mainWindowHeight)

    suggestionWindow.get.writeSuggestionWindow(y, x)

    check y == 2
    check x == 1

  test "General-purpose autocomplete (Fix #1032)":
    const buffer = @[
      ru"import os, unicode, times",
      ru"import"]

    var status = initEditorStatus()
    status.addNewBuffer(Mode.insert)
    status.bufStatus[0].buffer = initGapBuffer(buffer)
    status.workspace[0].currentMainWindowNode.currentColumn = 1

    var suggestionWindow = none(SuggestionWindow)

    status.resize(100, 100)
    status.update

    suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
    let
      mainWindowHeight = status.settings.getMainWindowHeight(100)
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindow,
        mainWindowHeight)

    suggestionWindow.get.writeSuggestionWindow(y, x)

  test "General-purpose autocomplete (the cursor position): Selecting a suggestion which is length 1 when the buffer contains some lines.":
    const buffer = @[
      ru"",
      ru"",
      ru"a"]

    var status = initEditorStatus()
    status.addNewBuffer(Mode.insert)
    status.bufStatus[0].buffer = initGapBuffer(buffer)

    status.resize(100, 100)
    status.update

    insertCharacter(currentBufStatus,
                    currentMainWindow,
                    status.settings.autoCloseParen,
                    ru'a')
    var suggestionWindow = tryOpenSuggestionWindow(currentBufStatus,
                                                   currentMainWindow)
    status.update

    suggestionWindow.get.handleKeyInSuggestionWindow(currentBufStatus,
                                                     currentMainWindow,
                                                     ru'\t')

    check currentMainWindow.currentLine == 0

  test "General-purpose autocomplete (the cursor position): Selecting a suggestion which is length 1 when the buffer contains a line.":
    const buffer = @[ru" a"]

    var status = initEditorStatus()
    status.addNewBuffer(Mode.insert)
    status.bufStatus[0].buffer = initGapBuffer(buffer)

    status.resize(100, 100)
    status.update

    insertCharacter(currentBufStatus,
                    currentMainWindow,
                    status.settings.autoCloseParen,
                    ru'a')
    var suggestionWindow = tryOpenSuggestionWindow(currentBufStatus,
                                                   currentMainWindow)
    status.update

    suggestionWindow.get.handleKeyInSuggestionWindow(currentBufStatus,
                                                     currentMainWindow,
                                                     ru'\t')

    check currentMainWindow.currentColumn == 1
