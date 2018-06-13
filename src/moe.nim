import os
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode

when isMainModule:
  startUi()
  
  var status = initEditorStatus()
  if commandLineParams().len >= 1:
    let filename = commandLineParams()[0]
    status.buffer = openFile(filename)
    status.filename = filename
  else: status.buffer = newFile()

  normalMode(status)

  exitUi()
