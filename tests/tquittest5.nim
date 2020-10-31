import unittest
import moepkg/[editorstatus, unicodetext, exmode]

test "All buffer force quit command":
  var status = initEditorStatus()
  for i in 0 ..< 2:
    status.addNewBuffer
    status.bufStatus[i].countChange = 1
  status.verticalSplitWindow

  const command = @[ru"qa!"]
  status.exModeCommand(command, 100, 100)
