import unittest, terminal
import moepkg/[editorstatus, logviewer, bufferstatus]

test "Exit log viewer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].mode = Mode.logViewer

  status.setMessageLog
  status.resize(terminalHeight(), terminalWidth())

  status.exitLogViewer

  status.resize(terminalHeight(), terminalWidth())
