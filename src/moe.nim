import os
import moepkg/ui
import moepkg/gapbuffer
import moepkg/fileutils
import moepkg/editorstatus

when isMainModule:
  var status = initEditorStatus()

  startUi()
  exitUi()

  if paramCount() > 0: status.buffer = openFile(os.commandLineParams()[0])
