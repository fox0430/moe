import times, terminal
import editorstatus, unicodeext, bufferstatus, highlight, color, gapbuffer, ui,
       movement

proc isDiffViewerMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.diff

proc initDiffHighlight(bufStatus: BufferStatus): Highlight =
  for i in 0 ..< bufStatus.buffer.len:
    let
      line = bufStatus.buffer[i]
      color = if line.len > 0 and line[0] == ru'+':
                  EditorColorPair.addedLine
                elif line.len > 0 and line[0] == ru'-':
                  EditorColorPair.deletedLine
                else:
                  EditorColorPair.defaultChar

    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: line.high,
      color: color))

proc diffViewer*(status: var Editorstatus) =
  status.resize(terminalHeight(), terminalWidth())

  while status.isDiffViewerMode:
    let
      bufferIndex = status.bufferIndexInCurrentWindow
      workspaceIndex = status.currentWorkSpaceIndex

    block:
      let
        bufferIndex = status.bufferIndexInCurrentWindow
        bufStatus = status.bufStatus[bufferIndex]
        workspaceIndex = status.currentWorkSpaceIndex
      status.workspace[workspaceIndex].currentMainWindowNode.highlight = initDiffHighlight(bufStatus)

    status.update

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
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[bufferIndex].keyUp(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[bufferIndex].keyDown(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif key == ord('g'):
      let secondKey = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if  secondKey == ord('g'):
        status.moveToFirstLine
      else:
        discard
    elif key == ord('G'):
      status.moveToLastLine
    else:
      discard