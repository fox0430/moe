import unittest
import moepkg/ui, moepkg/editorstatus, moepkg/exmode, moepkg/unicodeext

test "Change theme command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  startUi()
  
  block:
    const command = @[ru"theme", ru"vivid"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"dark"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"light"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"config"]
    status.exModeCommand(command)
