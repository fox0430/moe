import os, terminal, strutils, strformat, unicode
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode
import moepkg/insertmode
import moepkg/filermode
import moepkg/exmode
import moepkg/editorview
import moepkg/gapbuffer
import moepkg/independentutils
import moepkg/unicodeext

when isMainModule:
  startUi()

  var status = initEditorStatus()
  if commandLineParams().len >= 1:
    status.filename = commandLineParams()[0].toRunes
    if existsFile($(status.filename)):
      try:
        let textAndEncoding = openFile(status.filename)
        status.buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        echo(fmt"Failed to open: {status.filename}")
        exitUi()
        quit()
    elif existsDir($(status.filename)):
      try:
        setCurrentDir($(status.filename))
        status.mode = filer
      except OSError:
        writeFileOpenErrorMessage(status.commandWindow, status.filename)
        status.filename = "".toRunes
        status.buffer = newFile()
    else: status.buffer = newFile()
  else:
    status.buffer = newFile()

  status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)

  defer:
    exitUi()
    discard execShellCmd("printf '\\033[2 q'")
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

