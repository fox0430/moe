import std/[terminal, times, strformat, options]
import gapbuffer, ui, unicodeext, highlight, color, window, bufferstatus,
       movement, settings

proc getDebugModeBufferIndex*(bufStatus: seq[BufferStatus]): int =
  result = -1
  for index, bufStatus in bufStatus:
    if isDebugMode(bufStatus.mode, bufStatus.prevMode): result = index

proc initDebugModeHighlight*[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: buffer[i].len,
      color: EditorColorPair.defaultChar))

proc updateDebugModeBuffer*(
  bufStatus: var seq[BufferStatus],
  root: WindowNode,
  currentWindowIndex: int,
  debugModeSettings: DebugModeSettings) =

  template debugModeBuffer: var GapBuffer[seq[Rune]] =
    bufStatus[bufStatus.getDebugModeBufferIndex].buffer

  debugModeBuffer = initGapBuffer[seq[Rune]](@[ru""])

  # Add WindowNode info
  if debugModeSettings.windowNode.enable:
    let windowNodes = root.getAllWindowNode
    for n in windowNodes:
      debugModeBuffer.add(ru fmt"-- WindowNode --")

      let
        haveCursesWin = if n.window.isSome: true else: false
        isCurrentWindow = if n.windowIndex == currentWindowIndex: true else: false
      if debugModeSettings.windowNode.currentWindow:
        debugModeBuffer.add(ru fmt"  currentWindow           : {isCurrentWindow}")
      if debugModeSettings.windowNode.index:
        debugModeBuffer.add(ru fmt"  index                   : {n.index}")
      if debugModeSettings.windowNode.windowIndex:
        debugModeBuffer.add(ru fmt"  windowIndex             : {n.windowIndex}")
      if debugModeSettings.windowNode.bufferIndex:
        debugModeBuffer.add(ru fmt"  bufferIndex             : {n.bufferIndex}")
      if debugModeSettings.windowNode.parentIndex:
        debugModeBuffer.add(ru fmt"  parentIndex             : {n.parent.index}")
      if debugModeSettings.windowNode.childLen:
        debugModeBuffer.add(ru fmt"  child length            : {n.child.len}")
      if debugModeSettings.windowNode.splitType:
        debugModeBuffer.add(ru fmt"  splitType               : {n.splitType}")
      if debugModeSettings.windowNode.haveCursesWin:
        debugModeBuffer.add(ru fmt"  HaveCursesWindow        : {haveCursesWin}")
      if debugModeSettings.windowNode.y:
        debugModeBuffer.add(ru fmt"  y                       : {n.y}")
      if debugModeSettings.windowNode.x:
        debugModeBuffer.add(ru fmt"  x                       : {n.x}")
      if debugModeSettings.windowNode.h:
        debugModeBuffer.add(ru fmt"  h                       : {n.h}")
      if debugModeSettings.windowNode.w:
        debugModeBuffer.add(ru fmt"  w                       : {n.w}")
      if debugModeSettings.windowNode.currentLine:
        debugModeBuffer.add(ru fmt"  currentLine             : {n.currentLine}")
      if debugModeSettings.windowNode.currentColumn:
        debugModeBuffer.add(ru fmt"  currentColumn           : {n.currentColumn}")
      if debugModeSettings.windowNode.expandedColumn:
        debugModeBuffer.add(ru fmt"  expandedColumn          : {n.expandedColumn}")
      if debugModeSettings.windowNode.cursor:
        debugModeBuffer.add(ru fmt"  cursor                  : {n.cursor}")

      debugModeBuffer.add(ru "")

      # Add Editorview info
      if debugModeSettings.editorview.enable:
        debugModeBuffer.add(ru fmt"-- editorview --")
      if debugModeSettings.editorview.widthOfLineNum:
        debugModeBuffer.add(ru fmt"  widthOfLineNum          : {n.view.widthOfLineNum}")
      if debugModeSettings.editorview.height:
        debugModeBuffer.add(ru fmt"  height                  : {n.view.height}")
      if debugModeSettings.editorview.width:
        debugModeBuffer.add(ru fmt"  width                   : {n.view.width}")
      if debugModeSettings.editorview.originalLine:
        debugModeBuffer.add(ru fmt"  originalLine            : {n.view.originalLine}")
      if debugModeSettings.editorview.start:
        debugModeBuffer.add(ru fmt"  start                   : {n.view.start}")
      if debugModeSettings.editorview.length:
        debugModeBuffer.add(ru fmt"  length                  : {n.view.length}")

      debugModeBuffer.add(ru "")

  # Add BufferStatus info
  if debugModeSettings.bufStatus.enable:
    debugModeBuffer.add(ru fmt"-- bufStatus --")
    for i in 0 ..< bufStatus.len:
      if debugModeSettings.bufStatus.bufferIndex:
        debugModeBuffer.add(ru fmt"buffer Index: {i}")
      if debugModeSettings.bufStatus.path:
        debugModeBuffer.add(ru fmt"  path                    : {bufStatus[i].path}")
      if debugModeSettings.bufStatus.openDir:
        debugModeBuffer.add(ru fmt"  openDir                 : {bufStatus[i].openDir}")
      if debugModeSettings.bufStatus.currentMode:
        debugModeBuffer.add(ru fmt"  currentMode             : {bufStatus[i].mode}")
      if debugModeSettings.bufStatus.prevMode:
        debugModeBuffer.add(ru fmt"  prevMode                : {bufStatus[i].prevMode}")
      if debugModeSettings.bufStatus.language:
        debugModeBuffer.add(ru fmt"  language                : {bufStatus[i].language}")
      if debugModeSettings.bufStatus.encoding:
        debugModeBuffer.add(ru fmt"  encoding                : {bufStatus[i].characterEncoding}")
      if debugModeSettings.bufStatus.countChange:
        debugModeBuffer.add(ru fmt"  countChange             : {bufStatus[i].countChange}")
      if debugModeSettings.bufStatus.cmdLoop:
        debugModeBuffer.add(ru fmt"  cmdLoop                 : {bufStatus[i].cmdLoop}")
      if debugModeSettings.bufStatus.lastSaveTime:
        debugModeBuffer.add(ru fmt"  lastSaveTime            : {$bufStatus[i].lastSaveTime}")
      if debugModeSettings.bufStatus.bufferLen:
        debugModeBuffer.add(ru fmt"  buffer length           : {bufStatus[i].buffer.len}")

      debugModeBuffer.add(ru "")

proc initDebugModeBuffer*(
  bufStatus: var seq[BufferStatus],
  root: WindowNode,
  currentWindowIndex: int,
  debugModeSettings: DebugModeSettings) =

  bufStatus[bufStatus.getDebugModeBufferIndex].path = ru"Debug mode"
  bufStatus.updateDebugModeBuffer(
    root,
    currentWindowIndex,
    debugModeSettings)

import editorstatus

proc debugMode*(status: var Editorstatus) =
  let currentBufferIndex = currentMainWindowNode.bufferIndex

  status.resize(terminalHeight(), terminalWidth())

  while currentBufStatus.mode == Mode.debug and
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
