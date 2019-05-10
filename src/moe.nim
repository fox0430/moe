import os, terminal, strutils, strformat, unicode
import packages/docutils/highlite
import moepkg/ui
import moepkg/editorstatus
import moepkg/normalmode
import moepkg/insertmode
import moepkg/visualmode
import moepkg/replacemode
import moepkg/filermode
import moepkg/exmode
import moepkg/searchmode
import moepkg/buffermanager
import moepkg/editorview
import moepkg/cmdoption
import moepkg/settings
import moepkg/commandview

proc main() =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  var status = initEditorStatus()
  status.settings = parseSettingsFile(getConfigDir() / "moe" / "moerc.toml")
  changeTheme(status)

  if existsDir(parsedList.filename):
    try: setCurrentDir(parsedList.filename)
    except OSError:
      status.commandWindow.writeFileOpenError(parsedList.filename, status.settings.editorColor.errorMessage)
      addNewBuffer(status, "")
    status.bufStatus.add(BufferStatus(mode: Mode.filer))
  else: addNewBuffer(status, parsedList.filename)

  while status.mainWindowInfo.len > 0:

    case status.bufStatus[status.currentBuffer].mode:
    of Mode.normal: normalMode(status)
    of Mode.insert: insertMode(status)
    of Mode.visual: visualMode(status)
    of Mode.replace: replaceMode(status)
    of Mode.ex: exMode(status)
    of Mode.filer: filerMode(status)
    of Mode.search: searchMode(status)
    of Mode.bufManager: bufferManager(status)

  exitEditor(status.settings)

when isMainModule: main()
