import std/[os, times]
import moepkg/[ui, editorstatus, normalmode, insertmode, visualmode,
               replacemode, filermode, exmode, buffermanager, logviewer,
               cmdlineoption, bufferstatus, help, recentfilemode, quickrun,
               historymanager, diffviewer, configmode, debugmode]

# Load persisted data (Ex command history, search history and cursor postion)
proc loadPersistData(status: var EditorStatus) =
  if status.settings.persist.exCommand:
    status.exCommandHistory = loadExCommandHistory()

  if status.settings.persist.search:
    status.searchHistory = loadSearchHistory()

  if status.settings.persist.cursorPosition:
    status.lastPosition = loadLastPosition()
    currentMainWindowNode.restoreCursorPostion(currentBufStatus,
                                               status.lastPosition)

proc addBufferStatus(status: var EditorStatus,
                     parsedList: CmdParsedList) =

  if parsedList.path.len > 0:
    for path in parsedList.path:
      if dirExists(path):
        status.addNewBuffer(path, Mode.filer)
      else:
        status.addNewBuffer(path)
  else:
    status.addNewBuffer

proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  startUi()

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()
  result.changeTheme

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit())

  if parsedList.isReadonly:
    result.isReadonly = true

  result.addBufferStatus(parsedList)

  result.loadPersistData

  disableControlC()

proc main() =
  var status = initEditor()

  while status.mainWindow.numOfMainWindow > 0:

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
