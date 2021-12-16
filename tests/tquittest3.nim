import std/unittest
import moepkg/[editorstatus, unicodeext, exmode]

test "Force quit command":
  var status = initEditorStatus()
  status.addNewBuffer

  status.bufStatus[0].countChange = 1
  const command = @[ru"q!"]
  status.exModeCommand(command, 100, 100)
