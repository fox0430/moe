import unittest, terminal
import moepkg/[editorstatus, logviewer, bufferstatus, unicodetext]

test "Exit log viewer":
  var status = initEditorStatus()
  status.addNewBuffer("Log viewer", Mode.logViewer)

  status.resize(terminalHeight(), terminalWidth())
  status.update

  status.exitLogViewer

  status.resize(terminalHeight(), terminalWidth())
