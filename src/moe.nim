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
  status.bufStatus.add(BufferStatus(filename: parsedList.filename.toRunes))
  status.settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")

  if parsedList.filename != "":
    let filename = parsedList.filename
    status.bufStatus[0].language = detectLanguage(filename)
    if existsFile(filename):
      try:
        let textAndEncoding = openFile(filename.toRunes)
        status.bufStatus[0].buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        writeFileOpenErrorMessage(status.commandWindow, status.filename)
        return
    elif existsDir(filename):
      try:
        setCurrentDir(filename)
        status.mode = filer
      except OSError:
        writeFileOpenErrorMessage(status.commandWindow, filename.toRunes)
        status.bufStatus[0].filename = "".toRunes
        status.bufStatus[0].buffer = newFile()
    else: status.bufStatus[0].buffer = newFile()
  else:
    status.bufStatus[0].buffer = newFile()

  status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.bufStatus[0].view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  changeCurrentBuffer(status, 0)

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
