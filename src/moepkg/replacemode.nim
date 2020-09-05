import terminal, times
import editorstatus, ui, unicodeext, movement, editor, bufferstatus, gapbuffer,
       undoredostack, window, settings

proc isReplaceMode(status: EditorStatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  result = status.bufStatus[bufferIndex].mode == Mode.replace

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

proc replaceCurrentCharacter(bufStatus: var BufferStatus,
                             windowNode: var WindowNode,
                             isMoved: var bool,
                             key: Rune,
                             settings: EditorSettings) =

  if windowNode.currentColumn < bufStatus.buffer[windowNode.currentLine].len:
    bufStatus.replaceCurrentCharacter(windowNode,
                                      settings.autoIndent,
                                      settings.autoDeleteParen,
                                      settings.tabStop,
                                      key)
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
    undoLastSuitId =
      status.bufStatus[status.bufferIndexInCurrentWindow].buffer.lastSuitId
    windowNode =
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  while status.isReplaceMode:
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(windowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.changeMode(Mode.normal)
    elif isRightKey(key):
      status.bufStatus[currentBufferIndex].moveRight(windowNode,
                                                     isMoved,
                                                     undoLastSuitId)
    elif isLeftKey(key):
      status.bufStatus[currentBufferIndex].moveLeft(windowNode, isMoved, undoLastSuitId)
    elif isUpKey(key):
      status.bufStatus[currentBufferIndex].moveUp(windowNode, isMoved, undoLastSuitId)
    elif isDownKey(key):
      status.bufStatus[currentBufferIndex].moveDown(windowNode,
                                                    isMoved,
                                                    undoLastSuitId)
    elif isEnterKey(key):
      status.bufStatus[currentBufferIndex].keyEnter(windowNode,
                                                    status.settings.autoIndent,
                                                    status.settings.tabStop)
    elif isBackspaceKey(key):
      status.bufStatus[currentBufferIndex].undoOrMoveCursor(windowNode,
                                                            isMoved,
                                                            undoLastSuitId)
    else:
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(
        windowNode,
        isMoved,
        key,
        status.settings)
