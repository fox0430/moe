import os
import sequtils
import terminal
import strutils
import editorstatus
import ui
import fileutils
import editorview
import gapbuffer

proc writeFillerView(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  const topSpace = 2
  const border = 20
  win.write(0, 0, getCurrentDir())
  for i in 0 .. border:
    win.write(1, i, "-")
  for i in 0 ..< dirList.len:
    win.write(i + topSpace, 0, dirList[i][1])
  win.write(currentLine + topSpace, 0, dirList[currentLine][1], brightGreenDefault)
  win.refresh

proc refreshDirList(): seq[(PathComponent, string)] =
  result = newSeq[(PathComponent, string)]()
  result = @[(pcDir, "../")]
  for list in walkDir("./"):
    result.add list

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var viewUpdate = true
  var updateDirList = true
  var dirList = newSeq[(PathComponent, string)]()
  var key: int 
  var currentLine = 0

  while status.mode == Mode.filer:
    if updateDirList == true:
      dirList = @[]
      dirList.add refreshDirList()
      updateDirList = false

    if viewUpdate == true:
      status.mainWindow.erase
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
    elif isEnterKey(key):
      if dirList[currentLine][0] == pcFile:
        status = initEditorStatus()
        status.filename = dirList[currentLine][1]
        status.buffer = openFile(status.filename)
        status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)
        setCursor(true)
      elif dirList[currentLine][0] == pcDir:
        setCurrentDir(dirList[currentLine][1])
        currentLine = 0
        viewUpdate = true
        updateDirList = true
