import os
import sequtils
import editorstatus
import ui

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var viewUpdate = true
  var refreshDirList = true
  var dirList = newSeq[(PathComponent, string)]()
  var key: int
  var currentDir = "./"
  var y = 0

  while status.mode == Mode.filer:
    if refreshDirList == true:
      dirList = @[]
      for list in walkDir(currentDir):
        dirList.add list
      refreshDirList = false

    if viewUpdate == true:
      writeStatusBar(status)
      for i in 0 ..< dirList.len:
        status.mainWindow.write(i, 0, dirList[i][1])
      status.mainWindow.write(y, 0, dirList[y][1], brightGreenDefault)
      status.mainWindow.refresh
      viewUpdate = false

    key = getKey(status.mainWindow)
    if key == ord(':'):
      status.mode = Mode.ex
