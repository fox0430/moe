import unittest
import moepkg/[editorstatus, unicodetext, exmode, ui]

test "Open buffer manager":
  var status = initEditorStatus()
  status.addNewBuffer("")
  startUi()

  const command = @[ru"buf"]
  status.exModeCommand(command)
