import terminal, times
import editorstatus, ui, unicodeext, movement, editor, bufferstatus, gapbuffer,
       undoredostack, window

proc isReplaceMode(status: EditorStatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  result = status.bufStatus[bufferIndex].mode == Mode.replace

proc replaceMode*(status: var EditorStatus) =
  var
    bufferChanged = false
    windowNode =
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  template replaceCurrentCharacter() =
    let
      workspaceIndex = status.currentWorkSpaceIndex
      windowNode = status.workSpace[workSpaceIndex].currentMainWindowNode
      buffer = status.bufStatus[currentBufferIndex].buffer

    if windowNode.currentColumn < buffer[windowNode.currentLine].len:
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoIndent, status.settings.autoDeleteParen,
        status.settings.tabStop, key)
    else:
      insertCharacter(status.bufStatus[currentBufferIndex],
                      status.workSpace[workspaceIndex].currentMainWindowNode,
                      status.settings.autoCloseParen, key)

  template undoOrMoveCursor() =
    let
      workspaceIndex = status.currentWorkSpaceIndex

    # Can undo until you enter Replace mode
    # Do not undo if the cursor is moved and re-enable undo if the character is replaced
    if not isMoved and
       status.bufStatus[currentBufferIndex].buffer.lastSuitId > undoLastSuitId:
      undo(status.bufStatus[currentBufferIndex],
           status.workSpace[workSpaceIndex].currentMainWindowNode)
    else:
      if windowNode.currentColumn == 0 and
         windowNode.currentLine > 0:
        # Jump to the end of the above line
        status.bufStatus[currentBufferIndex].keyUp(windowNode)
        status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
      else:
        # Move to left once
        windowNode.keyLeft

  var isMoved = false
  let
    bufferIndex = status.bufferIndexInCurrentWindow
    undoLastSuitId = status.bufStatus[bufferIndex].buffer.lastSuitId

  while status.isReplaceMode:
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    if bufferChanged:
      status.updatehighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)
      bufferChanged = false

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.changeMode(Mode.normal)
      isMoved = true
    elif isRightKey(key):
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
      isMoved = true
    elif isLeftKey(key):
      windowNode.keyLeft
      isMoved = true
    elif isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
      isMoved = true
    elif isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
      isMoved = true
    elif isEnterKey(key):
      status.bufStatus[currentBufferIndex].keyEnter(windowNode,
                                                    status.settings.autoIndent,
                                                    status.settings.tabStop)
    elif isBackspaceKey(key):
      undoOrMoveCursor()
    else:
      replaceCurrentCharacter()

      status.bufStatus[currentBufferIndex].keyRight(windowNode)
      bufferChanged = true
      isMoved = false
