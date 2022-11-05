import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       window, color, settings, statusline, bufferstatus, cursor, tabline,
       backup, messages, commandline, register, platform, searchutils,
       movement, autocomplete, editorstatus, normalmode, insertmode,
       visualmode, replacemode, exmode, filermode, buffermanager, logviewer,
       help, recentfilemode, quickrun, historymanager, diffviewer, configmode,
       debugmode

proc editorMainLoop*(status: var EditorStatus) =
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
