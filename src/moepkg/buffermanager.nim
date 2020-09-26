import terminal, os, heapqueue, times
import gapbuffer, ui, editorstatus, unicodeext, highlight, window, movement,
       color, bufferstatus

proc initFilelistHighlight[T](buffer: T,
                              currentLine: int): Highlight =

  for i in 0 ..< buffer.len:

    let color =
      if i == currentLine: EditorColorPair.currentLineNum
      else: EditorColorPair.defaultChar

    let colorSegment = ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: buffer[i].len,
      color: color)

    result.colorSegments.add(colorSegment)

proc setBufferList(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.bufStatus[currentBufferIndex].path = ru"Buffer manager"
  status.bufStatus[currentBufferIndex].buffer = initGapBuffer[seq[Rune]]()

  for i in 0 ..< status.bufStatus.len:
    let currentMode = status.bufStatus[i].mode
    if currentMode != Mode.bufManager:
      let
        prevMode = status.bufStatus[i].prevMode
        line =
          if (currentMode == Mode.filer) or
            (prevMode == Mode.filer and
            currentMode == Mode.ex): getCurrentDir().toRunes
          else: status.bufStatus[i].path

      status.bufStatus[currentBufferIndex].buffer.add(line)

proc updateBufferManagerHighlight(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentLine =
      status.workSpace[workspaceIndex].currentMainWindowNode.currentLine

  let filelistHighlight =
    initFilelistHighlight(status.bufStatus[currentBufferIndex].buffer,
                          currentLine)
  status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
    filelistHighlight

proc deleteSelectedBuffer(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex
    deleteIndex =
      status.workSpace[workspaceIndex].currentMainWindowNode.currentLine

  var qeue = initHeapQueue[WindowNode]()
  for node in status.workSpace[workspaceIndex].mainWindowNode.child:
    qeue.push(node)
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.bufferIndex == deleteIndex: status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  if status.workSpace[workspaceIndex].numOfMainWindow > 0:
    status.bufStatus.delete(deleteIndex)

    var qeue = initHeapQueue[WindowNode]()
    for node in status.workSpace[workspaceIndex].mainWindowNode.child:
      qeue.push(node)
    while qeue.len > 0:
      for i in 0 ..< qeue.len:
        var node = qeue.pop
        if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

        if node.child.len > 0:
          for node in node.child: qeue.push(node)

    if currentBufferIndex > deleteIndex:
      dec(status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex)
    if status.workSpace[workspaceIndex].currentMainWindowNode.currentLine > 0:
      dec(status.workSpace[workspaceIndex].currentMainWindowNode.currentLine)

    let
      index= status.workSpace[workspaceIndex].numOfMainWindow - 1
      node = status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(index)
    status.workSpace[workspaceIndex].currentMainWindowNode = node
    status.setBufferList

    status.resize(terminalHeight(), terminalWidth())

proc openSelectedBuffer(status: var Editorstatus, isNewWindow: bool) =
  let workspaceIndex = status.currentWorkSpaceIndex
  if isNewWindow:
    status.verticalSplitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(status.workSpace[workspaceIndex].currentMainWindowNode.currentLine)
  else:
    status.changeCurrentBuffer(status.workSpace[workspaceIndex].currentMainWindowNode.currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc isBufferManagerMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.bufManager

proc bufferManager*(status: var Editorstatus) =
  status.setBufferList
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isBufferManagerMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.updateBufferManagerHighlight
    status.update
    setCursor(false)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif isEnterKey(key): status.openSelectedBuffer(false)
    elif key == ord('o'): status.openSelectedBuffer(true)
    elif key == ord('D'): status.deleteSelectedBuffer

    if status.bufStatus.len < 2: exitEditor(status.settings)
