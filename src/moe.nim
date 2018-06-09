import os
import moepkg/ui
import moepkg/view
import moepkg/gapbuffer
import moepkg/filestream
import moepkg/editorstatus

if isMainModule:
  var status = initEditorStatus()

  startUi()
  exitUi()

  if paramCount() == 0:
    var gb = initGapBuffer[string]()
    status = newFile()
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    var gb = openFile(status.filename)
    quit()
