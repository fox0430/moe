import os, terminal, strutils, strformat, unicode, packages/docutils/highlite
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
  changeTheme(status)

  if parsedList.filename != "":
    let filename = parsedList.filename
    if existsFile(filename):
      status.bufStatus.add(BufferStatus(filename: parsedList.filename.toRunes))
      status.bufStatus[0].language = detectLanguage(filename)
      try:
        let textAndEncoding = openFile(filename.toRunes)
        status.bufStatus[0].buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        writeFileOpenErrorMessage(status.commandWindow, status.bufStatus[0].filename)
        return
    elif existsDir(filename):
      try:
        setCurrentDir(filename)
        status.bufStatus[0].mode = filer
      except OSError:
        writeFileOpenErrorMessage(status.commandWindow, filename.toRunes)
        status.bufStatus.add(BufferStatus(filename: "".toRunes))
        status.bufStatus[0].buffer = newFile()
    else:
      status.bufStatus.add(BufferStatus(filename: "".toRunes))
      status.bufStatus[0].buffer = newFile()
  else:
    status.bufStatus.add(BufferStatus(filename: "".toRunes))
    status.bufStatus[0].buffer = newFile()

  if status.bufStatus[0].mode != filer:
    status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, if status.settings.syntax: status.bufStatus[0].language else: SourceLanguage.langNone, status.settings.editorColor.editor)
    let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
    let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    status.bufStatus[0].view= initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)
    changeCurrentBuffer(status, 0)

  while true:
    case status.bufStatus[0].mode:
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
