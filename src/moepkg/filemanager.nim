import os
import sequtils
import editorstatus
import ui

proc writeFillerView(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  for i in 0 ..< dirList.len:
    win.write(i, 0, dirList[i][1])
  win.write(currentLine, 0, dirList[currentLine][1], brightGreenDefault)
  win.refresh

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var viewUpdate = true
  var refreshDirList = true
  var dirList = newSeq[(PathComponent, string)]()
  var key: int 
  var currentDir = "./"
  var currentLine = 0

  while status.mode == Mode.filer:
    if refreshDirList == true:
      dirList = @[]
      for list in walkDir(currentDir):
        dirList.add list
      refreshDirList = false

    if viewUpdate == true:
      writeStatusBar(status)
      status.mainWindow.writeFillerView(dirList, currentLine)
      viewUpdate = false

    key = getKey(status.mainWindow)
    if key == ord(':'):
      status.mode = Mode.ex

    if key == ord('j') and currentLine < dirList.len - 1:
      inc(currentLine)
      viewUpdate = true
    elif key == ord('k') and 0 < currentLine:
      dec(currentLine)
      viewUpdate = true
