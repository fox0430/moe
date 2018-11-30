import os, terminal, strutils, strformat, unicode
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode
import moepkg/insertmode
import moepkg/filermode
import moepkg/exmode
import moepkg/searchmode
import moepkg/editorview
import moepkg/gapbuffer
import moepkg/independentutils
import moepkg/unicodeext
import moepkg/cmdoption
import moepkg/settings

when isMainModule:
  let parsedList = parseCommandLineOption(commandLineParams())

  startUi()

  var status = initEditorStatus()
  status.settings = parseConfigFile(status.settings)
  if parsedList.filename != "":
    status.filename = parsedList.filename.toRunes
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

  status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-numberOfDigits(status.buffer.len)-2)

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
    of Mode.search:
      searchMode(status)
    of Mode.quit:
      break

