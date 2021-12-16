import std/unittest
import moepkg/[editorstatus, unicodeext, exmode, ui]

test "Open buffer manager":
  var status = initEditorStatus()
  status.addNewBuffer
  startUi()

  const command = @[ru"buf"]
  status.exModeCommand(command, 100, 100)
