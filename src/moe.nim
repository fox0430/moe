import os, terminal, strutils
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode
import moepkg/editorview
import moepkg/gapbuffer

when isMainModule:
  startUi()
  
  var status = initEditorStatus()
  if commandLineParams().len >= 1:
    let filename = commandLineParams()[0]
    status.buffer = openFile(filename)
    status.filename = filename
  else:
    status.buffer = newFile()

  status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)

  normalMode(status)

  exitUi()
