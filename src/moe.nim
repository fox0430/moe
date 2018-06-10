import os
import moepkg/ui
import moepkg/view
import moepkg/gapbuffer
import moepkg/fileutils
import moepkg/editorstatus

when isMainModule:
  var status = initEditorStatus()

  startUi()
  
  var win = initWindow(10, 10, 0, 0)
  win.write(0, 0, "hoge", ColorPair.lightBlueDefault)
  win.refresh

  while true: discard

  if paramCount() == 0:
    var buffer = initGapBuffer[string]()
    status = newFile()
  else:
    status.filename = os.commandLineParams()[0]
    var buffer = openFile(status.filename)

  exitUi()
