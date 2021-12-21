import std/[unittest, os, algorithm, strutils]
import moepkg/[filermode, editorstatus, highlight, color, bufferstatus,
               unicodeext, gapbuffer]

include moepkg/filermode

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

template updateDirListAndView() =
  if filerStatus.dirlistUpdate:
    let path = currentBufStatus.path

    filerStatus = filerStatus.updateDirList(path)

    if currentMainWindowNode.currentLine > filerStatus.dirList.high:
      currentMainWindowNode.currentLine = filerStatus.dirList.high

  if filerStatus.viewUpdate:
    status.updateFilerView(filerStatus, 100, 100)

suite "Filer mode":
  test "Update directory list":
    var status = initEditorStatus()

    const path = "./"
    status.addNewBuffer(path, Mode.filer)

    var filerStatus = initFilerStatus()
    filerStatus = filerStatus.updateDirList(ru path)
    status.updateFilerView(filerStatus, 100, 100)

  test "Check highlight in filer mode":
    var status = initEditorStatus()

    const path = "./"
    status.addNewBuffer(path, Mode.filer)

    var filerStatus = initFilerStatus()
    filerStatus = filerStatus.updateDirList(ru path)
    status.updateFilerView(filerStatus, 100, 100)

    let node = currentMainWindowNode
    check(node.highlight[0].color == EditorColorPair.currentFile)

  test "Open current directory":
    var status = initEditorStatus()
    status.settings.filerSettings.showIcons = false

    const path = "./"
    status.addNewBuffer(path, Mode.filer)

    var filerStatus = initFilerStatus()
    filerStatus = filerStatus.updateDirList(ru path)
    status.updateFilerView(filerStatus, 100, 100)

    let files = getCurrentFiles(path)
    for i in 0 ..< currentBufStatus.buffer.len:
      check files[i] == $currentBufStatus.buffer[i]

  test "Move directory":
    var status = initEditorStatus()
    status.settings.filerSettings.showIcons = false

    const path = "./"
    status.addNewBuffer(path, Mode.filer)

    var filerStatus = initFilerStatus()
    filerStatus = filerStatus.updateDirList(ru path)
    status.updateFilerView(filerStatus, 100, 100)

    status.openFileOrDir(filerStatus)

    updateDirListAndView()

    let files = getCurrentFiles("../")
    for i in 0 ..< currentBufStatus.buffer.len:
      check files[i] == $currentBufStatus.buffer[i]
