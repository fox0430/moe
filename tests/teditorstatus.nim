import terminal, strutils, unittest
import moepkg/ui, moepkg/highlight, moepkg/editorstatus, moepkg/editorview, moepkg/gapbuffer, moepkg/unicodeext, moepkg/insertmode

test "Add new buffer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.addNewBuffer("")
  check(status.bufStatus.len == 2)

test "Split window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.splitWindow

test "Close window":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.splitWindow
  status.closeWindow(1)
  status.closeWindow(0)

test "Move window 1":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.splitWindow
  status.moveCurrentMainWindow(1)
  check(status.currentMainWindow == 1)

test "Move window 2":
  var status = initEditorStatus()
  status.addNewBuffer("")
  for i in 0 ..< 2: status.splitWindow
  for i in 0 ..< 3: status.moveNextWindow
  check(status.currentMainWindow == 2)

  for i in 0 ..< 3: status.movePrevWindow
  check(status.currentMainWindow == 0)

test "resize 1":
  var status = initEditorStatus()
  addNewBuffer(status, "")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.bufStatus[0].view = initEditorView(status.bufStatus[0].buffer, 1, 1)
  status.resize(0, 0)

test "resize 2":
  var status = initEditorStatus()
  addNewBuffer(status, "")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.bufStatus[0].view= initEditorView(status.bufStatus[0].buffer, 20, 4)
  status.resize(20, 4)
  status.bufStatus[0].currentColumn = 1
  status.changeMode(Mode.insert)
  for i in 0 ..< 10:
    keyEnter(status.bufStatus[0], status.settings.autoCloseParen)
    status.update
