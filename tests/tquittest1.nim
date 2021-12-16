import std/unittest
import moepkg/[editorstatus, unicodeext, exmode]

test "Quit command":
  var status = initEditorStatus()
  status.addNewBuffer

  const command = @[ru"q"]
  status.exModeCommand(command, 100, 100)
