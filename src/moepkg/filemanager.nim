import os
import sequtils
import terminal
import strformat
import strutils
import editorstatus
import ui
import fileutils
import editorview
import gapbuffer
import exmode
import unicodeext

proc deleteFile(status: var EditorStatus, dirList: seq[(PathComponent, string)], currentLine: int) =
  let command = getCommand(status.commandWindow, proc (window: var Window, command: seq[Rune]) =
    window.erase
    window.write(0, 0, fmt"Delete file? 'y' or 'n': {$command}")
    window.refresh
  )

  if (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    if dirList[currentLine][0] == pcDir:
      removeDir(dirList[currentLine][1])
    else:
      removeFile(dirList[currentLine][1])
  else:
    return

  status.commandWindow.erase
  status.commandWindow.write(0, 0, "Deleted "&dirList[currentLine][1])
  status.commandWindow.refresh

proc refreshDirList(): seq[(PathComponent, string)] =
  result = newSeq[(PathComponent, string)]()
  result = @[(pcDir, "../")]
  for list in walkDir("./"):
    result.add list

proc writeFileNameCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  win.write(currentLine, 0, substr(dirList[currentLine][1], 2), brightWhiteGreen)

proc writeDirNameCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  if currentLine == 0:    # "../"
    win.write(currentLine, 0, dirList[currentLine][1], brightWhiteGreen)
  else:
    win.write(currentLine, 0, substr(dirList[currentLine][1], 2) & "/", brightWhiteGreen)

proc writePcLinkToDirNameCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  win.write(currentLine, 0, substr(dirList[currentLine][1], 2) & "@", whiteCyan)

proc writeFileNameHalfwayCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  win.write(currentLine, 0, substr(dirList[currentLine][1], 2, terminalWidth() - 2), brightWhiteGreen)

proc writeDirNameHalfwayCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  if currentLine== 0:    # "../"
    win.write(currentLine, 0, substr(dirList[currentLine][1], 2, terminalWidth() - 2), brightWhiteGreen)
  else:
    win.write(currentLine, 0, substr(dirList[currentLine][1], 2, terminalWidth() - 2) & "/~", brightWhiteGreen)

proc writePcLinkToDirNameHalfwayCurrentLine(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =
  win.write(currentLine, 0, substr(dirList[currentLine][1], 2, terminalWidth() - 2) & "@~", whiteCyan)

proc writeFileName(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  win.write(index, 0, substr(dirList[index][1], 2))

proc writeDirName(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  if index == 0:    # "../"
    win.write(index, 0, dirList[index][1], brightGreenDefault)
  else:
    win.write(index, 0, substr(dirList[index][1], 2) & "/", brightGreenDefault)

proc writePcLinkToDirName(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  win.write(index, 0, substr(dirList[index][1], 2) & "@", cyanDefault)

proc writeFileNameHalfway(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  win.write(index, 0, substr(dirList[index][1], 2, terminalWidth() - 2) & "~")

proc writeDirNameHalfway(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  if index == 0:    # "../"
    win.write(index, 0, substr(dirList[index][1], 0, terminalWidth() - 2) & "~", brightGreenDefault)
  else:
    win.write(index, 0, substr(dirList[index][1], 2, terminalWidth() - 2) & "/~", brightGreenDefault)

proc writePcLinkToDirNameHalfway(win: var Window, index: int, dirList: seq[(PathComponent, string)]) =
  win.write(index, 0, substr(dirList[index][1], 2, terminalWidth() - 2) & "@~", cyanDefault)


proc writeFillerView(win: var Window, dirList: seq[(PathComponent, string)], currentLine: int) =

  for i in 0 ..< dirList.len:
    let index = i
    if dirList[i][1].len > terminalWidth():
      if dirList[i][0] == pcFile:
        writeFileNameHalfway(win, index, dirList)
      elif dirList[i][0] == pcDir:
        writeDirNameHalfway(win, index, dirList)
      elif dirList[i][0] == pcLinkToDir:
        writePcLinkToDirNameHalfway(win, index, dirList)
    else:
      if dirList[i][0] == pcFile:
        writeFileName(win, index, dirList)
      elif dirList[i][0] == pcDir:
        writeDirName(win, index, dirList)
      elif dirList[i][0] == pcLinkToDir:
        writePcLinkToDirName(win, index, dirList)

  # write current line
  if dirList[currentLine][1].len > terminalWidth():
    if dirList[currentLine][0] == pcFile:
      writeFileNameHalfwayCurrentLine(win, dirList, currentLine)
    elif dirList[currentLine][0] == pcDir:
      writeDirNameHalfwayCurrentLine(win, dirList, currentLine)
    elif dirList[currentLine][0] == pcLinkToDir:
      writePcLinkToDirNameHalfwayCurrentLine(win, dirList, currentLine)
  else:
    if dirList[currentLine][0] == pcFile:
      writeFileNameCurrentLine(win, dirList, currentLine)
    elif dirList[currentLine][0] == pcDir:
      writeDirNameCurrentLine(win, dirList, currentLine)
    elif dirList[currentLine][0] == pcLinkToDir:
      writePcLinkToDirNameCurrentLine(win, dirList, currentLine)
    
  win.refresh

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var viewUpdate = true
  var DirlistUpdate = true
  var dirList = newSeq[(PathComponent, string)]()
  var currentLine = 0

  while status.mode == Mode.filer:
    if DirlistUpdate == true:
      dirList = @[]
      dirList.add refreshDirList()
      viewUpdate = true
      DirlistUpdate = false

    if viewUpdate == true:
      status.mainWindow.erase
      writeStatusBar(status)
      status.mainWindow.writeFillerView(dirList, currentLine)
      viewUpdate = false

    let key = getKey(status.mainWindow)
    if key == ord(':'):
      status.changeMode(Mode.ex)
    elif isResizekey(key):
      status.resize
      viewUpdate = true

    elif key == 'D':
      deleteFile(status, dirList, currentLine)
      DirlistUpdate = true
      viewUpdate = true
    elif (key == 'j' or isDownKey(key)) and currentLine < dirList.len - 1:
      inc(currentLine)
      viewUpdate = true
    elif (key == ord('k') or isUpKey(key)) and 0 < currentLine:
      dec(currentLine)
      viewUpdate = true
    elif isEnterKey(key):
      if dirList[currentLine][0] == pcFile:
        status = initEditorStatus()
        status.filename = dirList[currentLine][1].toRunes
        status.buffer = openFile(status.filename)
        status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-status.buffer.len.intToStr.len-2)
        setCursor(true)
      elif dirList[currentLine][0] == pcDir:
        setCurrentDir(dirList[currentLine][1])
        currentLine = 0
        DirlistUpdate = true
  setCursor(true)
