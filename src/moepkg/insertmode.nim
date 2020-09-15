import terminal, times
import ui, editorstatus, gapbuffer, unicodeext, undoredostack, window,
       movement, editor, bufferstatus

proc isInsertMode(status: EditorStatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex =
      status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
    mode = status.bufStatus[bufferIndex].mode
  return mode == Mode.insert

proc insertMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  while status.isInsertMode:
    let
      currentBufferIndex = status.bufferIndexInCurrentWindow
      workspaceIndex = status.currentWorkSpaceIndex

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key =
        getKey(status.workSpace[workspaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(windowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
      windowNode.expandedColumn = windowNode.currentColumn
      status.changeMode(Mode.normal)
    elif isControlU(key):
      status.bufStatus[currentBufferIndex].deleteBeforeCursorToFirstNonBlank(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isLeftKey(key):
      windowNode.keyLeft
    elif isRightkey(key):
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif isPageUpKey(key):
      pageUp(status)
    elif isPageDownKey(key):
      pageDown(status)
    elif isHomeKey(key):
      windowNode.moveToFirstOfLine
    elif isEndKey(key):
      status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif isDcKey(key):
      status.bufStatus[currentBufferIndex].deleteCurrentCharacter(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoDeleteParen)
    elif isBackspaceKey(key) or isControlH(key):
      status.bufStatus[currentBufferIndex].keyBackspace(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoDeleteParen,
        status.settings.tabStop)
    elif isEnterKey(key):
      keyEnter(status.bufStatus[currentBufferIndex],
               status.workSpace[workspaceIndex].currentMainWindowNode,
               status.settings.autoIndent,
               status.settings.tabStop)
    elif key == ord('\t') or isControlI(key):
      insertTab(status.bufStatus[currentBufferIndex],
                status.workSpace[workspaceIndex].currentMainWindowNode,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    elif isControlE(key):
      status.bufStatus[currentBufferIndex].insertCharacterBelowCursor(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isControlY(key):
      status.bufStatus[currentBufferIndex].insertCharacterAboveCursor(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isControlW(key):
      status.bufStatus[currentBufferIndex].deleteWordBeforeCursor(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.tabStop)
    elif isControlU(key):
      status.bufStatus[currentBufferIndex].deleteCharactersBeforeCursorInCurrentLine(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isControlT(key):
      status.bufStatus[currentBufferIndex].addIndentInCurrentLine(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.view.tabStop)
    elif isControlD(key):
      status.bufStatus[currentBufferIndex].deleteIndentInCurrentLine(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.view.tabStop)
    else:
      insertCharacter(status.bufStatus[currentBufferIndex],
                      status.workSpace[workspaceIndex].currentMainWindowNode,
                      status.settings.autoCloseParen, key)
