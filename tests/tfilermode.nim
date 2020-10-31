import unittest
import moepkg/[filermode, editorstatus, highlight, color, bufferstatus,
               unicodetext]

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
  status.addNewBuffer("./", Mode.filer)

  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList(ru path)
  status.updateFilerView(filerStatus, 100, 100)

  let node = status.workSpace[0].currentMainWindowNode
  check(node.highlight[0].color == EditorColorPair.currentFile)
