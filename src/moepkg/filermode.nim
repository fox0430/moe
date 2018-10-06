import os
import sequtils
import terminal
import strformat
import strutils
import unicodeext
import times
import algorithm

import editorstatus
import ui
import fileutils
import editorview
import gapbuffer
import exmode
import independentutils

type
  List = tuple[kind: PathComponent, path: string]

proc searchFiles(status: var EditorStatus, dirList: seq[List]): seq[List] =
  let command = getCommand(status.commandWindow, proc (window: var Window, command: seq[Rune]) =
    window.erase
    window.write(0, 0, fmt"/{$command}")
    window.refresh
  )
  let str = command[0].join("")

  result = @[]
  for index in 0 .. dirList.high:
    if dirList[index].path.contains(str):
      result.add dirList[index]

proc deleteFile(status: var EditorStatus, dirList: List, currentLine: int) =
  let command = getCommand(status.commandWindow, proc (window: var Window, command: seq[Rune]) =
    window.erase
    window.write(0, 0, fmt"Delete file? 'y' or 'n': {$command}")
    window.refresh
  )

  if (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    if dirList.kind == pcDir:
      removeDir(dirList.path)
    else:
      removeFile(dirList.path)
  else:
    return

  status.commandWindow.erase
  status.commandWindow.write(0, 0, "Deleted "&dirList.path)
  status.commandWindow.refresh

proc refreshDirList(): seq[List] =
  result = @[(pcDir, "../")]
  for list in walkDir("./"):
    result.add list
  return result.sortedByIt(it.path)

proc writeFileNameCurrentLine(mainWindow: var Window, fileName: string , currentLine: int) =
  mainWindow.write(currentLine, 0, substr(fileName, 2), brightWhiteGreen)

proc writeDirNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, fileName, brightWhiteGreen)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 2) & "/", brightWhiteGreen)

proc writePcLinkToDirNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, substr(fileName, 2) & "@ -> " & expandsymLink(fileName) & "/", whiteCyan)

proc writePcLinkToFileNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, substr(fileName, 2) & "@ -> " & expandsymLink(fileName), whiteCyan)

proc writeFileNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, substr(fileName, 2, terminalWidth() - 2), brightWhiteGreen)

proc writeDirNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  if currentLine== 0:    # "../"
    mainWindow.write(currentLine, 0, substr(fileName, 2, terminalWidth() - 2), brightWhiteGreen)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 2, terminalWidth() - 2) & "/~", brightWhiteGreen)

proc writePcLinkToDirNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  let buffer = substr(fileName, 2) & "@ -> " & expandsymLink(fileName) & "/"
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", whiteCyan)

proc writePcLinkToFileNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  let buffer = substr(fileName, 2) & "@ -> " & expandsymLink(fileName)
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", whiteCyan)

proc writeFileName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, substr(fileName, 2))

proc writeDirName(mainWindow: var Window, currentLine: int, fileName: string) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, fileName, brightGreenDefault)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 2) & "/", brightGreenDefault)

proc writePcLinkToDirName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, substr(fileName, 2) & "@ -> " & expandsymLink(fileName) & "/", cyanDefault)

proc writePcLinkToFileName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, substr(fileName, 2) & "@ -> " & expandsymLink(fileName), cyanDefault)

proc writeFileNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, substr(fileName, 2, terminalWidth() - 2) & "~")

proc writeDirNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2) & "~", brightGreenDefault)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 2, terminalWidth() - 2) & "/~", brightGreenDefault)

proc writePcLinkToDirNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  let buffer = substr(fileName, 2) & "@ -> " & expandsymLink(fileName) & "/"
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", cyanDefault)

proc writePcLinkToFileNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  let buffer = substr(fileName, 2) & "@ -> " & expandsymLink(fileName)
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", cyanDefault)

proc writeFileDitailView(mainWindow: var Window, fileName: string) =
  mainWindow.erase

  let fileInfo = getFileInfo(fileName, false)
  var buffer = @[
                  "name        : " & $substr(fileName, 2),
                  "permissions : " & substr($fileInfo.permissions, 1, ($fileInfo.permissions).high - 1),
                  "last access : " & $fileInfo.lastAccessTime,
                  "last write  : " & $fileInfo.lastWriteTime,
                ]
  if fileInfo.kind == pcFile:
    buffer.insert("kind        : " & "File", 1)
  elif fileInfo.kind == pcDir:
    buffer.insert("kind        : " & "Directory", 1)
  elif fileInfo.kind == pcLinkToFile:
    buffer.insert("kind        : " & "Symbolic link to file", 1)
  elif fileInfo.kind == pcLinkToDir:
    buffer.insert("kind        : " & "Symbolic link to directory", 1)
    
  if fileInfo.kind == pcFile or fileInfo.kind == pcLinkToFile:
    buffer.insert("size        : " & $fileInfo.size & " bytes", 2)

  if fileInfo.kind == pcLinkToDir or fileInfo.kind == pcLinkToFile:
    buffer.insert("link        : " & expandsymLink(fileName), 3)

  if fileName == "../":
    mainWindow.write(0, 0, substr( "name        : ../", 0, terminalWidth()), brightWhiteDefault)
    for currentLine in 1 .. min(buffer.high, terminalHeight()):
      mainWindow.write(currentLine, 0,  substr(buffer[currentLine], 0, terminalWidth()), brightWhiteDefault)
  else:
    for currentLine in 0 .. min(buffer.high, terminalHeight()):
      mainWindow.write(currentLine, 0,  substr(buffer[currentLine], 0, terminalWidth()), brightWhiteDefault)

  discard getKey(mainWindow)

proc writeFillerView(mainWindow: var Window, dirList: seq[(PathComponent, string)], currentLine, startIndex: int) =

  for i in 0 ..< dirList.len - startIndex:
    let index = i
    let fileKind = dirList[index + startIndex][0]
    let fileName = dirList[index + startIndex][1]

    if fileKind == pcLinkToDir:
      if (fileName.len + expandsymLink(fileName).len + 5) > terminalWidth():
        writePcLinkToDirNameHalfway(mainWindow, index, fileName)
      else:
        writePcLinkToDirName(mainWindow, index, fileName)
    elif fileKind == pcLinkToFile:
      if (fileName.len + expandsymLink(fileName).len + 4) > terminalWidth():
        writePcLinkToFileNameHalfway(mainWindow, index, fileName)
      else:
        writePcLinkToFileName(mainWindow, index, fileName)
    elif fileName.len > terminalWidth():
      if fileKind == pcFile:
        writeFileNameHalfway(mainWindow, index, fileName)
      elif fileKind == pcDir:
        writeDirNameHalfway(mainWindow, index, fileName)
    else:
      if fileKind == pcFile:
        writeFileName(mainWindow, index, fileName)
      elif fileKind == pcDir:
        writeDirName(mainWindow, index, filename)

  # write current line
  let fileKind = dirList[currentLine + startIndex][0]
  let fileName= dirList[currentLine + startIndex][1]

  if fileKind == pcLinkToDir:
    if (fileName.len + expandsymLink(fileName).len + 5) > terminalWidth():
      writePcLinkToDirNameHalfwayCurrentLine(mainWindow, filename, currentLine)
    else:
      writePcLinkToDirNameCurrentLine(mainWindow, fileName, currentLine)
  elif fileKind == pcLinkToFile:
    if (fileName.len + expandsymLink(fileName).len + 4) > terminalWidth():
      writePcLinkToFileNameHalfwayCurrentLine(mainWindow, fileName, currentLine)
    else:
      writePcLinkToFileNameCurrentLine(mainWindow, fileName, currentLine)
  elif fileName.len > terminalWidth():
    if fileKind == pcFile:
      writeFileNameHalfwayCurrentLine(mainWindow, fileName, currentLine)
    elif fileKind == pcDir:
        writeDirNameHalfwayCurrentLine(mainWindow, fileName, currentLine)
  else:
    if fileKind == pcFile:
      writeFileNameCurrentLine(mainWindow, fileName, currentLine)
    elif fileKind == pcDir:
      writeDirNameCurrentLine(mainWindow, fileName, currentLine)
   
  mainWindow.refresh

proc writeFileOpenErrorMessage*(commandWindow: var Window, fileName: seq[Rune]) =
  commandWindow.erase
  commandWindow.write(0, 0, "can not open: ".toRunes & fileName)
  commandWindow.refresh

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var viewUpdate = true
  var DirlistUpdate = true
  var dirList = newSeq[List]()
  var currentLine = 0
  var startIndex = 0

  while status.mode == Mode.filer:
    if DirlistUpdate:
      currentLine = 0
      startIndex = 0
      dirList = @[]
      dirList.add refreshDirList()
      viewUpdate = true
      DirlistUpdate = false

    if viewUpdate:
      status.mainWindow.erase
      writeStatusBar(status)
      status.mainWindow.writeFillerView(dirList, currentLine, startIndex)
      viewUpdate = false

    let key = getKey(status.mainWindow)
    if key == ord(':'):
      status.changeMode(Mode.ex)
    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      viewUpdate = true
    elif key == ord('/'):
      dirList = searchFiles(status, dirList)
      viewUpdate = true
      if dirList.len < 1:
        DirlistUpdate = true

    elif key == ord('D'):
      deleteFile(status, dirList[currentLine], currentLine)
      DirlistUpdate = true
      viewUpdate = true
    elif key == ord('i'):
      writeFileDitailView(status.mainWindow, dirList[currentLine + startIndex][1])
      viewUpdate = true
    elif (key == 'j' or isDownKey(key)) and currentLine + startIndex < dirList.high:
      if currentLine == terminalHeight() - 3:
        inc(startIndex)
      else:
        inc(currentLine)
      viewUpdate = true
    elif (key == ord('k') or isUpKey(key)) and (0 < currentLine or 0 < startIndex):
      if 0 < startIndex and currentLine == 0:
        dec(startIndex)
      else:
        dec(currentLine)
      viewUpdate = true
    elif key == ord('g'):
      currentLine = 0
      startIndex = 0
      viewUpdate = true
    elif key == ord('G'):
      if dirList.len < status.mainWindow.height:
        currentLine = dirList.high
      else:
        currentLine = status.mainWindow.height - 1
        startIndex = dirList.len - status.mainWindow.height
      viewUpdate = true
    elif isEnterKey(key):
      let
        kind = dirList[currentLine + startIndex][0]
        path = dirList[currentLine + startIndex][1]
      case kind
      of pcFile, pcLinkToFile:
        let
          filename = (if kind == pcFile: substr(path, 2) else: expandsymLink(path)).toRunes
          textAndEncoding = openFile(filename)
        status = initEditorStatus()
        status.filename = filename
        status.buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
        status.view = initEditorView(status.buffer, terminalHeight()-2, terminalWidth()-numberOfDigits(status.buffer.len)-2)
        setCursor(true)
      of pcDir:
        try:
          setCurrentDir(dirList[currentLine + startIndex][1])
          DirlistUpdate = true
        except OSError:
          writeFileOpenErrorMessage(status.commandWindow, (substr(dirList[currentLine][1])).toRunes)
      of pcLinkToDir:
        try:
          setCurrentDir(expandsymLink(dirList[currentLine + startIndex][1]))
          DirlistUpdate = true
        except OSError:
          writeFileOpenErrorMessage(status.commandWindow, (substr(dirList[currentLine][1])).toRunes)
  setCursor(true)
