import unittest
import moepkg/editorstatus, moepkg/unicodeext, moepkg/exmode

test "Quit command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"q"]
  status.exModeCommand(command)
