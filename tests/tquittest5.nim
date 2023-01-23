import std/unittest
import moepkg/[editorstatus, unicodeext, exmode]

test "All buffer force quit command":
  var status = initEditorStatus()
  for i in 0 ..< 2:
    status.addNewBufferInCurrentWin
    status.bufStatus[i].countChange = 1
  status.verticalSplitWindow

  const command = @[ru"qa!"]
  status.exModeCommand(command)
