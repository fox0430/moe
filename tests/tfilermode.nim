import std/[unittest, strutils, algorithm, os]
import moepkg/[unicodeext, bufferstatus, gapbuffer, color, window, highlight]

import moepkg/filermodeutils {.all.}

proc getCurrentFiles(path: string): seq[string] =
  var
    dirs = @["../"]
    files: seq[string]
  for p in walkDir(path):
    if p.kind == PathComponent.pcDir:
      # Delete "./" or "../" and add "/" in the end of string
      if p.path.len > 2 and p.path.startsWith("../"):
        dirs.add p.path[3 .. ^1] & "/"
      else:
        dirs.add p.path[2 .. ^1] & "/"
    else:
      # Delete "./" or "../"
      if p.path.len > 2 and p.path.startsWith("../"):
        files.add p.path[3 .. ^1]

      files.add p.path[2 .. ^1]

  result = dirs.sortedByIt(it)
  result.add files.sortedByIt(it)

suite "Filer mode":
  test "Update directory list":
    const path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(path)

    check filerStatus.pathList.len > 0

  test "Check highlight in filer mode":
    const path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(path)

    var bufStatus = initBufferStatus($path, Mode.filer)

    const isShowIcons = false
    bufStatus.buffer = filerStatus.initFilerBuffer(isShowIcons).toGapBuffer

    const currentLine = 0
    let highlight = filerStatus.initFilerHighlight(bufStatus.buffer, currentLine)

    check highlight[0].color == EditorColorPair.currentFile

  test "Open current directory":
    const path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(path)

    var bufStatus = initBufferStatus($path, Mode.filer)
    const isShowIcons = false

    bufStatus.buffer = filerStatus.initFilerBuffer(isShowIcons).toGapBuffer

    let files = getCurrentFiles($path)
    for i in 0 ..< bufStatus.buffer.len:
      check files[i] == $bufStatus.buffer[i]

  test "Move directory":
    const path = "./".toRunes

    var filerStatus = initFilerStatus()
    filerStatus.updatePathList(path)

    var
      bufStatuses = @[initBufferStatus($path, Mode.filer)]
      mainWindow = initMainWindow()
    const isShowIcons = false

    bufStatuses[0].buffer = filerStatus.initFilerBuffer(isShowIcons).toGapBuffer

    bufStatuses.openFileOrDir(
      mainWindow.currentMainWindowNode,
      filerStatus)

    filerStatus.updatePathList(bufStatuses[0].path)
    bufStatuses[0].buffer = filerStatus.initFilerBuffer(isShowIcons).toGapBuffer

    let files = getCurrentFiles("../")
    for i in 0 ..< bufStatuses[0].buffer.len:
      check files[i] == $bufStatuses[0].buffer[i]
