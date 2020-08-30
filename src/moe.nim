import os, unicode, times
import moepkg/ui
import moepkg/editorstatus
import moepkg/normalmode
import moepkg/insertmode
import moepkg/visualmode
import moepkg/replacemode
import moepkg/filermode
import moepkg/exmode
import moepkg/buffermanager
import moepkg/logviewer
import moepkg/cmdlineoption
import moepkg/bufferstatus
import moepkg/help
import moepkg/recentfilemode
import moepkg/messages
import moepkg/quickrun
import moepkg/historymanager
import moepkg/diffviewer
import moepkg/configmode

proc main() =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  var status = initEditorStatus()
  status.loadConfigurationFile
  status.timeConfFileLastReloaded = now()
  status.changeTheme

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit()
  )

  if parsedList.len > 0:
    for p in parsedList:
      if existsDir(p.filename):
        try: setCurrentDir(p.filename)
        except OSError:
          status.commandWindow.writeFileOpenError(p.filename, status.messageLog)
          status.addNewBuffer("")
        status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSavetime: now()))
      else: status.addNewBuffer(p.filename)
  else: status.addNewBuffer("")

  disableControlC()

  while status.workSpace.len > 0 and
        status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow > 0:

    let currentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    case status.bufStatus[currentBufferIndex].mode:
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

  status.settings.exitEditor

when isMainModule: main()
