import terminal, os, heapqueue
import gapbuffer, ui, editorstatus, unicodeext, highlight, window, movement, color

proc initFilelistHighlight[T](buffer: T, currentLine: int): Highlight =
  for i in 0 ..< buffer.len:
    let color = if i == currentLine: EditorColorPair.currentLineNum else: EditorColorPair.defaultChar
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: color))

proc setBufferList(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.bufStatus[currentBufferIndex].filename = ru"Buffer manager"
  status.bufStatus[currentBufferIndex].buffer = initGapBuffer[seq[Rune]]()

  for i in 0 ..< status.bufStatus.len:
    let currentMode = status.bufStatus[i].mode
    if currentMode != Mode.bufManager:
      let
        prevMode = status.bufStatus[i].prevMode
        line = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir().toRunes else: status.bufStatus[i].filename
      status.bufStatus[currentBufferIndex].buffer.add(line)

proc updateBufferManagerHighlight(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].highlight = initFilelistHighlight(status.bufStatus[currentBufferIndex].buffer, status.bufStatus[currentBufferIndex].currentLine)

proc deleteSelectedBuffer(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    deleteIndex = status.bufStatus[currentBufferIndex].currentLine

  var qeue = initHeapQueue[WindowNode]()
  for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: qeue.push(node)
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.bufferIndex == deleteIndex: status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  if status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow > 0:
    status.bufStatus.delete(deleteIndex)

    var qeue = initHeapQueue[WindowNode]()
    for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: qeue.push(node)
    while qeue.len > 0:
      for i in 0 ..< qeue.len:
        var node = qeue.pop
        if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

        if node.child.len > 0:
          for node in node.child: qeue.push(node)

    if currentBufferIndex > deleteIndex: dec(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex)
    if status.bufStatus[currentBufferIndex].currentLine > 0: dec(status.bufStatus[currentBufferIndex].currentLine)
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1)
    status.setBufferList

    status.resize(terminalHeight(), terminalWidth())
  
proc openSelectedBuffer(status: var Editorstatus, isNewWindow: bool) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if isNewWindow:
    status.verticalSplitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(status.bufStatus[currentBufferIndex].currentLine)
  else:
    status.changeCurrentBuffer(status.bufStatus[currentBufferIndex].currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc bufferManager*(status: var Editorstatus) =
  status.setBufferList
  status.resize(terminalHeight(), terminalWidth())

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  while status.bufStatus[currentBufferIndex].mode == Mode.bufManager:
    status.updateBufferManagerHighlight
    status.update
    setCursor(false)
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown
    elif isEnterKey(key): status.openSelectedBuffer(false)
    elif key == ord('o'): status.openSelectedBuffer(true)
    elif key == ord('D'): status.deleteSelectedBuffer

    if status.bufStatus.len < 2: exitEditor(status.settings)
