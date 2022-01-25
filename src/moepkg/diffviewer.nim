import std/[times, terminal]
import editorstatus, unicodeext, bufferstatus, highlight, color, gapbuffer, ui,
       movement, window

proc isDiffViewerMode(status: Editorstatus): bool =
  let index = currentMainWindowNode.bufferIndex
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
    let bufferIndex = status.bufferIndexInCurrentWindow

    block:
      let
        bufferIndex = status.bufferIndexInCurrentWindow
        bufStatus = status.bufStatus[bufferIndex]
      currentMainWindowNode.highlight = initDiffHighlight(bufStatus)

    status.update

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
      status.bufStatus[bufferIndex].keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[bufferIndex].keyDown(currentMainWindowNode)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if  secondKey == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
      else:
        discard
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
    else:
      discard
