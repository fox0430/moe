import terminal, os, heapqueue, times
import gapbuffer, ui, editorstatus, unicodetext, highlight, window, movement,
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
  currentBufStatus.path = ru"Buffer manager"
  currentBufStatus.buffer = initGapBuffer[seq[Rune]]()

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

      currentBufStatus.buffer.add(line)

proc updateBufferManagerHighlight[T](node: var WindowNode,
                                     buffer: T,
                                     currentLine: int) {.inline.} =

  node.highlight = initFilelistHighlight(buffer, currentLine)

proc deleteSelectedBuffer(status: var Editorstatus, height, width: int) =
  let deleteIndex = currentMainWindowNode.currentLine

  var qeue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    qeue.push(node)
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.bufferIndex == deleteIndex:
        status.closeWindow(node, height, width)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  if currentWorkSpace.numOfMainWindow > 0:
    status.bufStatus.delete(deleteIndex)

    var qeue = initHeapQueue[WindowNode]()
    for node in mainWindowNode.child:
      qeue.push(node)
    while qeue.len > 0:
      for i in 0 ..< qeue.len:
        var node = qeue.pop
        if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

        if node.child.len > 0:
          for node in node.child: qeue.push(node)

    if status.bufferIndexInCurrentWindow > deleteIndex:
      dec(currentMainWindowNode.bufferIndex)
    if currentMainWindowNode.currentLine > 0:
      dec(currentMainWindowNode.currentLine)

    let index = currentWorkSpace.numOfMainWindow - 1
    currentMainWindowNode = mainWindowNode.searchByWindowIndex(index)
    status.setBufferList

    status.resize(terminalHeight(), terminalWidth())

proc openSelectedBuffer(status: var Editorstatus, isNewWindow: bool) =
  if isNewWindow:
    status.verticalSplitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
  else:
    status.changeCurrentBuffer(currentMainWindowNode.currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc bufferManager*(status: var Editorstatus) =
  status.setBufferList
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while isBufferManagerMode(currentBufStatus.mode) and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    block:
      let
        buffer = currentBufStatus.buffer
        currentLine = currentMainWindowNode.currentLine
      currentMainWindowNode.updateBufferManagerHighlight(buffer, currentLine)

    status.update
    setCursor(false)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif isEnterKey(key):
      status.openSelectedBuffer(false)
    elif key == ord('o'):
      status.openSelectedBuffer(true)
    elif key == ord('D'):
      status.deleteSelectedBuffer(terminalHeight(), terminalWidth())

    if status.bufStatus.len < 2: exitEditor(status.settings)
