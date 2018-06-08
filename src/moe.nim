import os
import moepkg/ui
import moepkg/view
import moepkg/gapbuffer
import moepkg/fileutils
import moepkg/editorstatus

when isMainModule:
  var status = initEditorStatus()

  startUi()
  exitUi()

  if paramCount() == 0:
    var buffer = initGapBuffer[string]()
    status = newFile()
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    var buffer = openFile(status.filename)
    quit()
