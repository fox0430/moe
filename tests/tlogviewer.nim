import unittest, terminal
import moepkg/[editorstatus, logviewer]

test "Exit log viewer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[status.currentBuffer].mode = Mode.logViewer

  status.setMessageLog
  status.resize(terminalHeight(), terminalWidth())

  status.exitLogViewer

  status.resize(terminalHeight(), terminalWidth())
