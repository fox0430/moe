import os, terminal, strutils, strformat
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode
import moepkg/insertmode
import moepkg/exmode
import moepkg/filemanager
import moepkg/editorview
import moepkg/gapbuffer

when isMainModule:
  startUi()

  var status = initEditorStatus()
  if commandLineParams().len >= 1:
    status.filename = commandLineParams()[0]
    if existsFile(status.filename):
      try:
        status.buffer = openFile(status.filename)
      except IOError:
        echo(fmt"Failed to open: {status.filename}")
        exitUi()
        quit()
    elif existsDir(status.filename):
      setCurrentDir(status.filename)
      status.mode = filer
    else: status.buffer = newFile()
  else:
    status.buffer = newFile()

  status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)

  while true:
    case status.mode:
    of Mode.normal:
      normalMode(status)
    of Mode.insert:
      insertMode(status)
    of Mode.ex:
      exMode(status)
    of Mode.filer:
      filerMode(status)
    of Mode.quit:
      break
    else:
      doAssert(false, "Invalid Mode")

  exitUi()
