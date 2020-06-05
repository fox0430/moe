import unittest
import moepkg/[filermode, editorstatus, highlight, color, bufferstatus]

test "Update directory list":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].mode = Mode.filer
  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList
  status.updateFilerView(filerStatus)

test "Check highlight in filer mode":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].mode = Mode.filer
  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList
  status.updateFilerView(filerStatus)

  let node = status.workSpace[0].currentMainWindowNode
  check(node.highlight[0].color == EditorColorPair.currentFile)
