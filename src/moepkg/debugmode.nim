import terminal, times, strformat, options
import gapbuffer, ui, unicodeext, highlight, color, window, bufferstatus,
       movement, workspace

template currentBufStatus: var BufferStatus =
  mixin status
  status.bufStatus[status.bufferIndexInCurrentWindow]

template currentMainWindowNode: var WindowNode =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

template currentWorkSpace: var WorkSpace =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex]

proc getDebugModeBufferIndex*(bufStatuses: seq[BufferStatus]): int =
  result = -1
  for index, bufStatus in bufStatuses:
    if isDebugMode(bufStatus.mode, bufStatus.prevMode): return index

proc initDebugModeHighlight*[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: buffer[i].len,
      color: EditorColorPair.defaultChar))

import editorstatus

proc initDebugModeBuffer*(bufStatuses: var seq[BufferStatus],
                          root: WindowNode,
                          currentWindowIndex: int) =

  template debugModeBuffer: var GapBuffer[seq[Rune]] =
    bufStatuses[debugModeBufferIndex].buffer

  let debugModeBufferIndex = bufStatuses.getDebugModeBufferIndex

  bufStatuses[debugModeBufferIndex].path = ru"Debug mode"
  bufStatuses[debugModeBufferIndex].buffer = initGapBuffer[seq[Rune]]()

  # Add WindowNode info
  let windowNodes = root.getAllWindowNode
  debugModeBuffer.add(ru fmt"-- WindowNode --")
  for n in windowNodes:
    let
      haveCursesWin = if n.window.isSome: true else: false
      isCurrentWindow = if n.windowIndex == currentWindowIndex: true else: false
    debugModeBuffer.add(ru fmt"  currentWindow    : {isCurrentWindow}")
    debugModeBuffer.add(ru fmt"  index            : {n.index}")
    debugModeBuffer.add(ru fmt"  windowIndex      : {n.windowIndex}")
    debugModeBuffer.add(ru fmt"  bufferIndex      : {n.bufferIndex}")
    debugModeBuffer.add(ru fmt"  parentIndex      : {n.parent.index}")
    debugModeBuffer.add(ru fmt"  child length     : {n.child.len}")
    debugModeBuffer.add(ru fmt"  splitType        : {n.splitType}")
    debugModeBuffer.add(ru fmt"  HaveCursesWindow : {haveCursesWin}")
    debugModeBuffer.add(ru fmt"  y                : {n.y}")
    debugModeBuffer.add(ru fmt"  x                : {n.x}")
    debugModeBuffer.add(ru fmt"  h                : {n.h}")
    debugModeBuffer.add(ru fmt"  w                : {n.w}")
    debugModeBuffer.add(ru fmt"  currentLine      : {n.currentLine}")
    debugModeBuffer.add(ru fmt"  currentColumn    : {n.currentColumn}")
    debugModeBuffer.add(ru fmt"  expandedColumn   : {n.expandedColumn}")
    debugModeBuffer.add(ru fmt"  cursor           : {n.cursor}")
    debugModeBuffer.add(ru "")

  # Add BufferStatus info
  debugModeBuffer.add(ru fmt"-- bufStatus --")
  for i in 0 ..< bufStatuses.len:
    let bufStatus = bufStatuses[i]
    debugModeBuffer.add(ru fmt"buffer Index: {i}")
    debugModeBuffer.add(ru fmt"  path             : {bufStatus.path}")
    debugModeBuffer.add(ru fmt"  openDir          : {bufStatus.openDir}")
    debugModeBuffer.add(ru fmt"  currentMode      : {bufStatus.mode}")
    debugModeBuffer.add(ru fmt"  prevMode         : {bufStatus.prevMode}")
    debugModeBuffer.add(ru fmt"  language         : {bufStatus.language}")
    debugModeBuffer.add(ru fmt"  encoding         : {bufStatus.characterEncoding}")
    debugModeBuffer.add(ru fmt"  countChange      : {bufStatus.countChange}")
    debugModeBuffer.add(ru fmt"  cmdLoop          : {bufStatus.cmdLoop}")
    debugModeBuffer.add(ru fmt"  lastSaveTime     : {$bufStatus.lastSaveTime}")
    debugModeBuffer.add(ru fmt"  buffer length    : {bufStatus.buffer.len}")
    debugModeBuffer.add(ru "")

proc debugMode*(status: var Editorstatus) =
  let
    currentBufferIndex = currentMainWindowNode.bufferIndex
    currentWorkSpace = status.currentWorkSpaceIndex

  status.resize(terminalHeight(), terminalWidth())

  while currentBufStatus.mode == Mode.debug and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    status.update
    setCursor(false)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)

    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == ord('g'): status.moveToFirstLine
      else: discard
    elif key == ord('G'):
      status.moveToLastLine

    else:
      discard
