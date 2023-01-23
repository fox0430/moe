import std/unittest
import moepkg/[editorstatus, unicodeext, exmode]

test "Quit command":
  var status = initEditorStatus()
  status.addNewBufferInCurrentWin

  const command = @[ru"q"]
  status.exModeCommand(command)
