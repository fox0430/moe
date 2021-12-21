import std/[terminal, times, unicode]
import editorstatus, ui, movement, editor, bufferstatus, gapbuffer,
       window, settings

proc moveRight(bufStatus: var BufferStatus,
               windowNode: var WindowNode,
               isMoved: var bool,
               undoLastSuitId: var int) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyRight(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    isMoved = true
    undoLastSuitId = bufStatus.buffer.lastSuitId

proc moveLeft(bufStatus: var BufferStatus,
              windowNode: var WindowNode,
              isMoved: var bool,
              undoLastSuitId: var int) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  windowNode.keyLeft

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    isMoved = true
    undoLastSuitId = bufStatus.buffer.lastSuitId

proc moveUp(bufStatus: var BufferStatus,
            windowNode: var WindowNode,
            isMoved: var bool,
            undoLastSuitId: var int) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyUp(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    isMoved = true
    undoLastSuitId = bufStatus.buffer.lastSuitId

proc moveDown(bufStatus: var BufferStatus,
              windowNode: var WindowNode,
              isMoved: var bool,
              undoLastSuitId: var int) =
  let
    beforeLine = windowNode.currentLine
    beforeColumn = windowNode.currentColumn
  bufStatus.keyDown(windowNode)

  if beforeLine != windowNode.currentLine or
     beforeColumn != windowNode.currentColumn:
    isMoved = true
    undoLastSuitId = bufStatus.buffer.lastSuitId

# Repace the current chracter or insert the character and move to the right
proc replaceCurrentCharacter(bufStatus: var BufferStatus,
                             windowNode: var WindowNode,
                             isMoved: var bool,
                             key: Rune,
                             settings: EditorSettings) =

  if windowNode.currentColumn < bufStatus.buffer[windowNode.currentLine].len:
    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]
    newLine[currentColumn] = key

    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
  else:
    insertCharacter(bufStatus, windowNode, settings.autoCloseParen, key)

  bufStatus.keyRight(windowNode)
  isMoved = false

proc undoOrMoveCursor(bufStatus: var BufferStatus,
                      windowNode: var WindowNode,
                      isMoved: bool,
                      undoLastSuitId: int) =

  # Can undo until you enter Replace mode
  # Do not undo if the cursor is moved and re-enable undo if the character is replaced
  if not isMoved and
     bufStatus.buffer.lastSuitId > undoLastSuitId:
    undo(bufStatus, windowNode)
  else:
    if windowNode.currentColumn == 0 and
       windowNode.currentLine > 0:
      # Jump to the end of the above line
      bufStatus.keyUp(windowNode)
      bufStatus.moveToLastOfLine(windowNode)
    else:
      # Move to left once
      windowNode.keyLeft

proc replaceMode*(status: var EditorStatus) =
  var
    isMoved = false
    undoLastSuitId = currentBufStatus.buffer.lastSuitId

  while isReplaceMode(currentBufStatus.mode):

    status.update

    var key = errorKey
    while key == errorKey:
      if not pressCtrlC:
        status.eventLoopTask
        key = getKey(currentMainWindowNode)
      else:
        # Exit replace mode

        pressCtrlC = false

        if currentMainWindowNode.currentColumn > 0:
          dec(currentMainWindowNode.currentColumn)
        currentMainWindowNode.expandedColumn = currentMainWindowNode.currentColumn
        status.changeMode(Mode.normal)

        return

    status.lastOperatingTime = now()

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.changeMode(Mode.normal)
    elif isRightKey(key):
      currentBufStatus.moveRight(currentMainWindowNode, isMoved, undoLastSuitId)
    elif isLeftKey(key):
      currentBufStatus.moveLeft(currentMainWindowNode, isMoved, undoLastSuitId)
    elif isUpKey(key):
      currentBufStatus.moveUp(currentMainWindowNode, isMoved, undoLastSuitId)
    elif isDownKey(key):
      currentBufStatus.moveDown(currentMainWindowNode, isMoved, undoLastSuitId)
    elif isEnterKey(key):
      currentBufStatus.keyEnter(currentMainWindowNode,
                                status.settings.autoIndent,
                                status.settings.tabStop)
    elif isBackspaceKey(key):
      currentBufStatus.undoOrMoveCursor(currentMainWindowNode,
                                        isMoved,
                                        undoLastSuitId)
    else:
      currentBufStatus.replaceCurrentCharacter(
        currentMainWindowNode,
        isMoved,
        key,
        status.settings)
