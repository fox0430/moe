import terminal, strutils, unittest
import moepkg/editorstatus, moepkg/editorview, moepkg/gapbuffer, moepkg/unicodeext, moepkg/insertmode

test "resize: 1":
  var status = initEditorStatus()
  status.buffer = initGapBuffer(@[ru"a"])
  status.view = initEditorView(status.buffer, 1, 1)
  status.resize(0, 0)

test "resize: 2":
  var status = initEditorStatus()
  status.buffer = initGapBuffer(@[ru"a"])
  status.view = initEditorView(status.buffer, 20, 4)
  status.resize(20, 4)
  status.currentColumn = 1
  status.changeMode(Mode.insert)
  for i in 0 ..< 10:
    keyEnter(status)
    status.update
