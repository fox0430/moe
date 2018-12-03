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
import moepkg/highlight

proc main() =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer:
    exitUi()
    discard execShellCmd("printf '\\033[2 q'")

  startUi()

  var status = initEditorStatus()
  status.settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")

  if parsedList.filename != "":
    status.filename = parsedList.filename.toRunes
    status.language = initLanguage(parsedList.filename)
    if existsFile($(status.filename)):
      try:
        let textAndEncoding = openFile(status.filename)
        status.buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        writeFileOpenErrorMessage(status.commandWindow, status.filename)
        return
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

  status.highlightInfo = initHighlightInfo(status.buffer, status.language, status.settings.syntax)
  status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-numberOfDigits(status.buffer.len)-2)
    
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

when isMainModule: main()
