import unittest, terminal
import moepkg/highlight, moepkg/editorstatus, moepkg/editorview, moepkg/gapbuffer, moepkg/unicodeext, moepkg/insertmode

test "Add new buffer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.addNewBuffer("")
  status.resize(100, 100)
  check(status.bufStatus.len == 2)

test "Vertical split window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.verticalSplitWindow
  
test "Horizontal splitsplit window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.horizontalSplitWindow

test "Close window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.verticalSplitWindow
  status.closeWindow(status.currentMainWindowNode)
  status.closeWindow(status.currentMainWindowNode)

test "Move window 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  status.verticalSplitWindow
  status.moveCurrentMainWindow(1)

test "Move window 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)
  for i in 0 ..< 2: status.verticalSplitWindow
  for i in 0 ..< 3: status.moveNextWindow

  for i in 0 ..< 3: status.movePrevWindow

test "resize 1":
  var status = initEditorStatus()
  addNewBuffer(status, "")
  status.resize(100, 100)
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.currentMainWindowNode.view = initEditorView(status.bufStatus[0].buffer, 1, 1)
  status.resize(0, 0)

test "resize 2":
  var status = initEditorStatus()
  addNewBuffer(status, "")
  status.resize(100, 100)
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.currentMainWindowNode.view= initEditorView(status.bufStatus[0].buffer, 20, 4)
  status.resize(20, 4)
  status.bufStatus[0].currentColumn = 1
  status.changeMode(Mode.insert)
  for i in 0 ..< 10:
    status.bufStatus[0].keyEnter(status.currentMainWindowNode, status.settings.autoCloseParen)
    status.update
