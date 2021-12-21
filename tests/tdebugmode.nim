import std/[unittest, strformat]
import moepkg/[editorstatus, unicodeext, bufferstatus]

include moepkg/debugmode

suite "Init debug mode buffer":
  test "Init buffer":
    var status = initEditorStatus()
    status.addNewBuffer
    status.addNewBuffer(Mode.debug)

    status.bufStatus.initDebugModeBuffer(
      mainWindow.mainWindowNode,
      currentMainWindowNode.windowIndex,
      status.settings.debugModeSettings)

    let correctBuf = initGapBuffer[seq[Rune]](@[
      ru "",
      ru"-- WindowNode --",
      ru"  currentWindow           : true",
      ru"  index                   : 0",
      ru"  windowIndex             : 0",
      ru"  bufferIndex             : 1",
      ru"  parentIndex             : 0",
      ru"  child length            : 0",
      ru"  splitType               : vertical",
      ru"  HaveCursesWindow        : true",
      ru"  y                       : 0",
      ru"  x                       : 0",
      ru"  h                       : 1",
      ru"  w                       : 1",
      ru"  currentLine             : 0",
      ru"  currentColumn           : 0",
      ru"  expandedColumn          : 0",
      ru"  cursor                  : (y: 0, x: 0)",
      ru"",
      ru"-- editorview --",
      ru"  widthOfLineNum          : 2",
      ru"  height                  : 1",
      ru"  width                   : 1",
      ru"",
      ru"-- bufStatus --",
      ru"buffer Index: 0",
      ru"  path                    : ",
      ru"  openDir                 : ",
      ru"  currentMode             : normal",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {$status.bufStatus[0].lastSaveTime}",
      ru"  buffer length           : 1",
      ru"",
      ru"buffer Index: 1",
      ru"  path                    : Debug mode",
      ru"  openDir                 : ",
      ru"  currentMode             : debug",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {$status.bufStatus[1].lastSaveTime}",
      ru"  buffer length           : 47",
      ru""])

    for i in 0 ..< status.bufStatus[1].buffer.len:
      if status.bufStatus[1].buffer[i] != correctBuf[i]: echo status.bufStatus[1].buffer[i]
      check status.bufStatus[1].buffer[i] == correctBuf[i]

  test "Init highlight":
    var status = initEditorStatus()
    status.addNewBuffer
    status.addNewBuffer(Mode.debug)

    status.bufStatus.initDebugModeBuffer(
      mainWindow.mainWindowNode,
      currentMainWindowNode.windowIndex,
      status.settings.debugModeSettings)

    let
      buffer = status.bufStatus[1].buffer
      highlight = buffer.initDebugModeHighlight

    for i in 0 ..< buffer.len:
      check highlight[i].firstRow == i
      check highlight[i].lastRow == i
      check highlight[i].firstColumn == 0
      check highlight[i].lastColumn == buffer[i].len
