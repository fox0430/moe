import std/[unittest, os, strformat, times]
import moepkg/[editorstatus, bufferstatus, gapbuffer, unicodeext]
import moepkg/debugmode {.all.}

suite "Init debug mode buffer":
  test "Init buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    status.addNewBufferInCurrentWin(Mode.debug)

    status.bufStatus.initDebugModeBuffer(
      mainWindow.mainWindowNode,
      currentMainWindowNode.windowIndex,
      status.settings.debugMode)

    status.resize(100, 100)
    status.update

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
      ru"  y                       : 1",
      ru"  x                       : 0",
      ru"  h                       : 98",
      ru"  w                       : 100",
      ru"  currentLine             : 0",
      ru"  currentColumn           : 0",
      ru"  expandedColumn          : 0",
      ru"  cursor                  : (y: 0, x: 0)",
      ru"",
      ru"-- editorview --",
      ru"  widthOfLineNum          : 2",
      ru"  height                  : 97",
      ru"  width                   : 98",
      ru"",
      ru"-- bufStatus --",
      ru"buffer Index: 0",
      ru"  path                    : ",
      ru fmt"  openDir                 : {getCurrentDir()}",
      ru"  currentMode             : normal",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {status.bufStatus[0].lastSaveTime}",
      ru"  buffer length           : 1",
      ru"",
      ru"buffer Index: 1",
      ru"  path                    : Debug mode",
      ru fmt"  openDir                 : {getCurrentDir()}",
      ru"  currentMode             : debug",
      ru"  prevMode                : normal",
      ru"  language                : langNone",
      ru"  encoding                : UTF-8",
      ru"  countChange             : 0",
      ru"  cmdLoop                 : 0",
      ru fmt"  lastSaveTime            : {status.bufStatus[1].lastSaveTime}",
      ru"  buffer length           : 47",
      ru""])

    for i in 0 ..< status.bufStatus[1].buffer.len:
      check status.bufStatus[1].buffer[i] == correctBuf[i]
