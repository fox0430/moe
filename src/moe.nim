import os, unicode, times
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
import moepkg/logviewer
import moepkg/cmdlineoption
import moepkg/settings
import moepkg/commandview
import moepkg/bufferstatus

proc main() =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  var status = initEditorStatus()
  status.settings.loadSettingFile
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

  while status.workSpace.len > 0 and status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow > 0:

    let currentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    case status.bufStatus[currentBufferIndex].mode:
    of Mode.normal: status.normalMode
    of Mode.insert: status.insertMode
    of Mode.visual, Mode.visualBlock: status.visualMode
    of Mode.replace: status.replaceMode
    of Mode.ex: status.exMode
    of Mode.filer: status.filerMode
    of Mode.search: status.searchMode
    of Mode.bufManager: status.bufferManager
    of Mode.logViewer: status.messageLogViewer

  status.settings.exitEditor

when isMainModule: main()
