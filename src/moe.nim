import std/[os, times]

import moepkg/[ui, bufferstatus, editorstatus, cmdlineoption, mainloop]

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

proc addBufferStatus(status: var EditorStatus, parsedList: CmdParsedList) =
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

  status.editorMainLoop

  status.exitEditor

when isMainModule: main()

