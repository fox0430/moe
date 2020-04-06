import unittest
import moepkg/editorstatus, moepkg/gapbuffer, moepkg/unicodeext, moepkg/highlight, moepkg/insertmode

test "Issue #474":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru""])
  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  status.resize(10, 10)

  for i in 0..<100: insertCharacter(status.bufStatus[0], status.currentWorkSpace.currentMainWindowNode, status.settings.autoCloseParen, ru'a')
  status.update
