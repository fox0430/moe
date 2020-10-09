import unittest, strformat
import moepkg/[editorstatus, unicodeext, bufferstatus]

include moepkg/debugmode

suite "Init debug mode buffer":
  test "Init buffer":
    var status = initEditorStatus()
    status.addNewBuffer
    status.addNewBuffer(Mode.debug)

    status.bufStatus.initDebugModeBuffer(
      status.workspace[0].mainWindowNode,
      status.workspace[0].currentMainWindowNode.windowIndex)

    let correctBuf = initGapBuffer[seq[Rune]](@[
      ru"-- WindowNode --",
      ru"  currentWindow    : true",
      ru"  index            : 0",
      ru"  windowIndex      : 0",
      ru"  bufferIndex      : 1",
      ru"  parentIndex      : 0",
      ru"  child length     : 0",
      ru"  splitType        : vertical",
      ru"  HaveCursesWindow : true",
      ru"  y                : 0",
      ru"  x                : 0",
      ru"  h                : 1",
      ru"  w                : 1",
      ru"  currentLine      : 0",
      ru"  currentColumn    : 0",
      ru"  expandedColumn   : 0",
      ru"  cursor           : (y: 0, x: 0)",
      ru"",
      ru"-- bufStatus --",
      ru"buffer Index: 0",
      ru"  path             : ",
      ru"  openDir          : ",
      ru"  currentMode      : normal",
      ru"  prevMode         : normal",
      ru"  language         : langNone",
      ru"  encoding         : UTF-8",
      ru"  countChange      : 0",
      ru"  cmdLoop          : 0",
      ru fmt"  lastSaveTime     : {$status.bufStatus[0].lastSaveTime}",
      ru"  buffer length    : 1",
      ru"",
      ru"buffer Index: 1",
      ru"  path             : Debug mode",
      ru"  openDir          : ",
      ru"  currentMode      : debug",
      ru"  prevMode         : normal",
      ru"  language         : langNone",
      ru"  encoding         : UTF-8",
      ru"  countChange      : 0",
      ru"  cmdLoop          : 0",
      ru fmt"  lastSaveTime     : {$status.bufStatus[1].lastSaveTime}",
      ru"  buffer length    : 31",
      ru""])

    for i in 0 ..< status.bufStatus[1].buffer.len:
      check status.bufStatus[1].buffer[i] == correctBuf[i]
