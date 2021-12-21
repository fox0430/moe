import std/unittest
import moepkg/[editorstatus, unicodeext, exmode]

test "All buffer quit command":
  var status = initEditorStatus()
  status.addNewBuffer
  status.verticalSplitWindow
  status.resize(100, 100)

  const command = @[ru"qa"]
  status.exModeCommand(command, 100, 100)
