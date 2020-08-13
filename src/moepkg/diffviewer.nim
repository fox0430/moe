import times, terminal
import editorstatus, unicodeext, bufferstatus, highlight, color, gapbuffer, ui,
       movement

proc isDiffViewerMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.diff

proc updateDiffHighlight(bufStatus: BufferStatus, highlight: var Highlight) =
  for i in 0 ..< bufStatus.buffer.len:
    let color = if bufStatus.buffer[i].len > 0 and bufStatus.buffer[i][0] == ru'+':
                  EditorColorPair.errorMessage
                else:
                  EditorColorPair.defaultChar

    highlight.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: bufStatus.buffer[i].high,
      color: color))

proc diffViewer*(status: var Editorstatus) =
  while status.isDiffViewerMode:

    let
      bufferIndex = status.bufferIndexInCurrentWindow
      workspaceIndex = status.currentWorkSpaceIndex

    status.update
    status.bufStatus[bufferIndex].updateDiffHighlight(status.workspace[workspaceIndex].currentMainWindowNode.highlight)

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(status.workSpace[workspaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      exitUi()
      for bufStatus in status.bufStatus:
        echo bufStatus.mode
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[bufferIndex].keyUp(status.workSpace[workspaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[bufferIndex].keyDown(status.workSpace[workspaceIndex].currentMainWindowNode)
