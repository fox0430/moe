import os, terminal, strutils, strformat, unicode
import moepkg/ui
import moepkg/editorstatus
import moepkg/fileutils
import moepkg/normalmode
import moepkg/insertmode
import moepkg/visualmode
import moepkg/replacemode
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

  startUi()

  var status = initEditorStatus()
  status.settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")

  if parsedList.filename != "":
    status.filename = parsedList.filename.toRunes
    status.language = detectLanguage(parsedList.filename)
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

  status.highlight = initHighlight($status.buffer, status.language)
  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.view = initEditorView(status.buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)
    
  while true:
    case status.mode:
    of Mode.normal:
      normalMode(status)
    of Mode.insert:
      insertMode(status)
    of Mode.visual:
      visualMode(status)
    of Mode.replace:
      replaceMode(status)
    of Mode.ex:
      exMode(status)
    of Mode.filer:
      filerMode(status)
    of Mode.search:
      searchMode(status)
    of Mode.quit:
      executeOnExit(status.settings)
      break

when isMainModule: main()
