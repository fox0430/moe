import std/unittest
import moepkg/[editorstatus, bufferstatus, unicodeext]
include moepkg/replacemode

template recordCurrentPosition() =
  let
    windowNode = currentMainWindowNode
    bufferIndex = windowNode.bufferIndex

  status.bufStatus[bufferIndex].buffer.beginNewSuitIfNeeded
  status.bufStatus[bufferIndex].tryRecordCurrentPosition(windowNode)

suite "Replace mode: Replace current Character":
  test "Replace current character":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    var
      isMoved = false
      undoLastSuitId =
        status.bufStatus[0].buffer.lastSuitId
    const key = ru'z'

    status.bufStatus[0].replaceCurrentCharacter(
      currentMainWindowNode,
      isMoved,
      key,
      status.settings)

    check status.bufStatus[0].buffer[0] == ru"zbc"

  test "Replace current character 2":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    var
      isMoved = false
      undoLastSuitId =
        status.bufStatus[0].buffer.lastSuitId
    const key = ru'z'

    for i in 0 ..< 5:
      status.bufStatus[0].replaceCurrentCharacter(
        currentMainWindowNode,
        isMoved,
        key,
        status.settings)

    check status.bufStatus[0].buffer[0] == ru"zzzzz"

suite "Replace mode: Undo":
  test "undo":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    var
      isMoved = false
      undoLastSuitId =
        status.bufStatus[0].buffer.lastSuitId
    const key = ru'z'

    recordCurrentPosition()

    status.bufStatus[0].replaceCurrentCharacter(
      currentMainWindowNode,
      isMoved,
      key,
      status.settings)

    recordCurrentPosition()

    status.bufStatus[0].undoOrMoveCursor(
      currentMainWindowNode,
      isMoved,
      undoLastSuitId)

    check status.bufStatus[0].buffer[0] == ru"abc"

  test "undo 2":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    var
      isMoved = false
      undoLastSuitId =
        status.bufStatus[0].buffer.lastSuitId
    const key = ru'z'

    recordCurrentPosition()

    status.bufStatus[0].replaceCurrentCharacter(
      currentMainWindowNode,
      isMoved,
      key,
      status.settings)

    recordCurrentPosition()

    status.bufStatus[0].moveRight(currentMainWindowNode,
                                  isMoved,
                                  undoLastSuitId)

    status.bufStatus[0].undoOrMoveCursor(
      currentMainWindowNode,
      isMoved,
      undoLastSuitId)

    check status.bufStatus[0].buffer[0] == ru"zbc"

  test "undo 3":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    var
      isMoved = false
      undoLastSuitId =
        status.bufStatus[0].buffer.lastSuitId
    const key = ru'z'

    recordCurrentPosition()

    status.bufStatus[0].replaceCurrentCharacter(
      currentMainWindowNode,
      isMoved,
      key,
      status.settings)

    recordCurrentPosition()

    status.bufStatus[0].moveRight(currentMainWindowNode,
                                  isMoved,
                                  undoLastSuitId)

    status.bufStatus[0].undoOrMoveCursor(
      currentMainWindowNode,
      isMoved,
      undoLastSuitId)

    check status.bufStatus[0].buffer[0] == ru"abc"

suite "Replace mode: New line":
  test "New line and replace character":
    var status = initEditorStatus()
    status.addNewBuffer
    status.bufStatus[0].mode = Mode.replace
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 1

    recordCurrentPosition()

    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 status.settings.autoIndent,
                                 status.settings.tabStop)

    var isMoved = false
    const key = ru'z'

    status.bufStatus[0].replaceCurrentCharacter(
      currentMainWindowNode,
      isMoved,
      key,
      status.settings)

    check status.bufStatus[0].buffer.len == 2
    check status.bufStatus[0].buffer[0] == ru"a"
    check status.bufStatus[0].buffer[1] == ru"zc"
