import std/[unittest, strutils, algorithm]
import moepkg/settings
include moepkg/[filermodeutils, filermode]

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

    initFilerStatus()
    updateDirList(path)

    check filerStatus.get.pathList.len > 0

  test "Check highlight in filer mode":
    const path = "./".toRunes

    initFilerStatus()
    updateDirList(path)

    var bufStatus = initBufferStatus($path, Mode.filer)
    let settings = initEditorSettings()

    bufStatus.updateFierBuffer(filerStatus.get, settings)

    const currentLine = 0
    let highlight = bufStatus.buffer.initFilerHighlight(currentLine)

    check highlight[0].color == EditorColorPair.currentFile

  test "Open current directory":
    const path = "./".toRunes

    initFilerStatus()
    updateDirList(path)

    var
      bufStatus = initBufferStatus($path, Mode.filer)
      settings = initEditorSettings()

    settings.filer.showIcons = false

    bufStatus.updateFierBuffer(filerStatus.get, settings)

    let files = getCurrentFiles($path)
    for i in 0 ..< bufStatus.buffer.len:
      check files[i] == $bufStatus.buffer[i]

  test "Move directory":
    const path = "./".toRunes

    initFilerStatus()
    updateDirList(path)

    var
      bufStatuses = @[initBufferStatus($path, Mode.filer)]
      mainWindow = initMainWindow()
      settings = initEditorSettings()

    settings.filer.showIcons = false

    bufStatuses[0].updateFierBuffer(filerStatus.get, settings)

    bufStatuses.openFileOrDir(
      mainWindow.currentMainWindowNode,
      filerStatus.get)

    updateDirList(bufStatuses[0].path)
    bufStatuses[0].updateFierBuffer(filerStatus.get, settings)

    let files = getCurrentFiles("../")
    for i in 0 ..< bufStatuses[0].buffer.len:
      check files[i] == $bufStatuses[0].buffer[i]
