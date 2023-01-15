import std/unittest
import moepkg/[editorstatus, unicodeext, exmode, ui]

test "All buffer quit command":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin
  status.verticalSplitWindow

  updateTerminalSize(100, 100)
  status.resize

  const command = @[ru"qa"]
  status.exModeCommand(command)
