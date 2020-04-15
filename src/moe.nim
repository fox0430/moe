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
  changeTheme(status)

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
          addNewBuffer(status, "")
        status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSavetime: now()))
      else: addNewBuffer(status, p.filename)
  else: addNewBuffer(status, "")

  disableControlC()

  while status.workSpace.len > 0 and status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow > 0:

    let currentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    case status.bufStatus[currentBufferIndex].mode:
    of Mode.normal: normalMode(status)
    of Mode.insert: insertMode(status)
    of Mode.visual, Mode.visualBlock: visualMode(status)
    of Mode.replace: replaceMode(status)
    of Mode.ex: exMode(status)
    of Mode.filer: filerMode(status)
    of Mode.search: searchMode(status)
    of Mode.bufManager: bufferManager(status)
    of Mode.logViewer: messageLogViewer(status)

  exitEditor(status.settings)

when isMainModule: main()
