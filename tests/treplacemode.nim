import std/unittest
include moepkg/replacemode

template recordCurrentPosition() =
  currentBufStatus.buffer.beginNewSuitIfNeeded
  currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

suite "Replace mode: Replace current Character":
  test "Replace current character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    const key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)

    check currentBufStatus.buffer[0] == ru"zbc"

  test "Replace current character 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    for i in 0 ..< 5:
      const key = ru'z'
      currentBufStatus.replaceCurrentCharacter(
        currentMainWindowNode,
        status.settings,
        key)

    check currentBufStatus.buffer[0] == ru"zzzzz"

suite "Replace mode: Undo":
  test "undo":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    recordCurrentPosition()

    const key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)

    recordCurrentPosition()

    currentBufStatus.undoOrMoveCursor(
      currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"abc"

  test "undo 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    recordCurrentPosition()

    const key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)

    recordCurrentPosition()

    currentBufStatus.moveRight(currentMainWindowNode)

    currentBufStatus.undoOrMoveCursor(currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"zbc"

  test "undo 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 2

    recordCurrentPosition()

    const key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)

    recordCurrentPosition()

    currentBufStatus.moveRight(currentMainWindowNode)

    currentBufStatus.undoOrMoveCursor(currentMainWindowNode)

    check currentBufStatus.buffer[0] == ru"abc"

suite "Replace mode: New line":
  test "New line and replace character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.mode = Mode.replace
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.currentColumn = 1

    recordCurrentPosition()

    currentBufStatus.keyEnter(
      currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.tabStop)

    const key = ru'z'
    currentBufStatus.replaceCurrentCharacter(
      currentMainWindowNode,
      status.settings,
      key)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"a"
    check currentBufStatus.buffer[1] == ru"zc"
