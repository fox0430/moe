import unittest
import moepkg/[filermode, editorstatus, highlight, color, bufferstatus,
               unicodeext]

test "Update directory list":
  var status = initEditorStatus()

  const path = "./"
  status.addNewBuffer(path, Mode.filer)

  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList(ru path)
  status.updateFilerView(filerStatus)

test "Check highlight in filer mode":
  var status = initEditorStatus()

  const path = "./"
  status.addNewBuffer("./", Mode.filer)

  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList(ru path)
  status.updateFilerView(filerStatus)

  let node = status.workSpace[0].currentMainWindowNode
  check(node.highlight[0].color == EditorColorPair.currentFile)
