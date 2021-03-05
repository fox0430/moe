import os, times
import moepkg/[ui, editorstatus, normalmode, insertmode, visualmode,
               replacemode, filermode, exmode, buffermanager, logviewer,
               cmdlineoption, bufferstatus, help, recentfilemode, quickrun,
               historymanager, diffviewer, configmode, debugmode]

proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()
  result.changeTheme

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit())

  if parsedList.len > 0:
    for p in parsedList:
      if dirExists(p.filename):
        result.addNewBuffer(p.filename, Mode.filer)
      else:
        result.addNewBuffer(p.filename)
  else:
    result.addNewBuffer

  disableControlC()

  # Load persisted data (Ex command history and search history)
  if result.settings.persist.exCommand:
    result.exCommandHistory = loadExCommandHistory()
  if result.settings.persist.search:
    result.searchHistory = loadSearchHistory()

proc main() =
  var status = initEditor()

  while status.workSpace.len > 0 and
        currentWorkSpace.numOfMainWindow > 0:

    case currentBufStatus.mode:
    of Mode.normal: status.normalMode
    of Mode.insert: status.insertMode
    of Mode.visual, Mode.visualBlock: status.visualMode
    of Mode.replace: status.replaceMode
    of Mode.ex: status.exMode
    of Mode.filer: status.filerMode
    of Mode.bufManager: status.bufferManager
    of Mode.logViewer: status.messageLogViewer
    of Mode.help: status.helpMode
    of Mode.recentFile: status.recentFileMode
    of Mode.quickRun: status.quickRunMode
    of Mode.history: status.historyManager
    of Mode.diff: status.diffViewer
    of Mode.config: status.configMode
    of Mode.debug: status.debugMode

  status.exitEditor

when isMainModule: main()
