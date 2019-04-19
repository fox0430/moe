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
import independentutils
import highlight
import commandview

type
  PathInfo = tuple[kind: PathComponent, path: string, size: int64, lastWriteTime: times.Time]

type Sort = enum
  name = 0
  fileSize = 1
  time = 2

type FileRegister = object
  copy: bool
  cut: bool
  originPath: string
  filename: string

type FilerStatus = object
  register: FileRegister
  searchMode: bool
  viewUpdate: bool
  dirlistUpdate: bool
  dirList: seq[PathInfo]
  sortBy: Sort
  currentLine: int
  startIndex: int

proc tryExpandSymlink(symlinkPath: string): string =
  try:
    return expandSymlink(symlinkPath)
  except OSError:
    return ""

proc searchFiles(status: var EditorStatus, dirList: seq[PathInfo]): seq[PathInfo] =
  setCursor(true)
  let command = getCommand(status, "/")
  setCursor(false)

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return @[]

  let str = command[0].join("")
  result = @[]
  for index in 0 .. dirList.high:
    if dirList[index].path.contains(str):
      result.add dirList[index]

proc writeRemoveFileError(commandWindow: var Window, color: ColorPair) =
  commandWindow.erase
  commandWindow.write(0, 0, "Error: can not remove file", color)
  commandWindow.refresh

proc writeRemoveDirError(commandWindow: var Window, color: ColorPair) =
  commandWindow.erase
  commandWindow.write(0, 0, "Error: can not remove directory", color)
  commandWindow.refresh

proc writeCopyFileError(commandWindow: var Window, color: ColorPair) =
  commandWindow.erase
  commandWindow.write(0, 0, "Error: can not copy file", color)
  commandWindow.refresh

proc deleteFile(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let command = getCommand(status, "Delete file? 'y' or 'n': ")
  setCursor(false)

  let errorMessageColor = status.settings.editorColor.errorMessage

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return

  if (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    if filerStatus.dirList[filerStatus.currentLine].kind == pcDir:
      try:
        removeDir(filerStatus.dirList[filerStatus.currentLine].path)
      except OSError:
        writeRemoveDirError(status.commandWindow, errorMessageColor)
        return
    else:
      if tryRemoveFile(filerStatus.dirList[filerStatus.currentLine].path) == false:
        writeRemoveFileError(status.commandWindow, errorMessageColor)
        return
  else:
    return

  status.commandWindow.erase
  status.commandWindow.write(0, 0, "Deleted "&filerStatus.dirList[filerStatus.currentLine].path)
  status.commandWindow.refresh

proc sortDirList(dirList: seq[PathInfo], sortBy: Sort): seq[PathInfo] =
  case sortBy:
  of name:
    return dirList.sortedByIt(it.path)
  of fileSize:
    result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
    result.add dirList[1 .. dirList.high].sortedByIt(it.size).reversed
  of time:
    result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
    result.add dirList[1 .. dirList.high].sortedByIt(it.lastWriteTime)

proc refreshDirList(sortBy: Sort): seq[PathInfo] =
  result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
  for list in walkDir("./"):
    if list.kind == pcLinkToFile or list.kind == pcLinkToDir:
      if tryExpandSymlink(list.path) != "":
        result.add (list.kind, list.path, 0.int64, getLastModificationTime(getCurrentDir()))
    else:
      if list.kind == pcFile:
        try:
          result.add (list.kind, list.path, getFileSize(list.path), getLastModificationTime(list.path))
        except OSError, IOError:
          discard
      else:  result.add (list.kind, list.path, 0.int64, getLastModificationTime(list.path))
    result[result.high].path = $(result[result.high].path.toRunes.normalizePath)
  return sortDirList(result, sortBy)

proc writeFileNameCurrentLine(mainWindow: var Window, fileName: string , currentLine: int) =
  mainWindow.write(currentLine, 0, fileName, brightWhiteGreen)

proc writeDirNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, fileName, brightWhiteGreen)
  else:
    mainWindow.write(currentLine, 0, fileName & "/", brightWhiteGreen)

proc writePcLinkToDirNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, fileName & "@ -> " & expandsymLink(fileName) & "/", whiteCyan)

proc writePcLinkToFileNameCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, fileName & "@ -> " & expandsymLink(fileName), whiteCyan)

proc writeFileNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2), brightWhiteGreen)

proc writeDirNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  if currentLine == 0:    # "../"
    mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2), brightWhiteGreen)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2) & "/~", brightWhiteGreen)

proc writePcLinkToDirNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  let buffer = fileName & "@ -> " & expandsymLink(fileName) & "/"
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", whiteCyan)

proc writePcLinkToFileNameHalfwayCurrentLine(mainWindow: var Window, fileName: string, currentLine: int) =
  let buffer = fileName & "@ -> " & expandsymLink(fileName)
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", whiteCyan)

proc writeFileName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, fileName)

proc writeDirName(mainWindow: var Window, currentLine: int, fileName: string) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, fileName, brightGreenDefault)
  else:
    mainWindow.write(currentLine, 0, fileName & "/", brightGreenDefault)

proc writePcLinkToDirName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, fileName & "@ -> " & expandsymLink(fileName) & "/", cyanDefault)

proc writePcLinkToFileName(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, fileName & "@ -> " & expandsymLink(fileName), cyanDefault)

proc writeFileNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2) & "~")

proc writeDirNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  if fileName == "../":
    mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2) & "~", brightGreenDefault)
  else:
    mainWindow.write(currentLine, 0, substr(fileName, 0, terminalWidth() - 2) & "/~", brightGreenDefault)

proc writePcLinkToDirNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  let buffer = fileName & "@ -> " & expandsymLink(fileName) & "/"
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", cyanDefault)

proc writePcLinkToFileNameHalfway(mainWindow: var Window, currentLine: int, fileName: string) =
  let buffer = fileName & "@ -> " & expandsymLink(fileName)
  mainWindow.write(currentLine, 0, substr(buffer, 0, terminalWidth() - 4) & "~", cyanDefault)

proc writeFileDetailView(mainWindow: var Window, fileName: string) =
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

proc writeFillerView(mainWindow: var Window, dirList: seq[PathInfo], currentLine, startIndex: int) =

  for i in 0 ..< dirList.len - startIndex:
    let index = i
    let fileKind = dirList[index + startIndex].kind
    var fileName = dirList[index + startIndex].path

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
  let fileKind = dirList[currentLine + startIndex].kind
  let fileName= dirList[currentLine + startIndex].path

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

proc writeCreateDirErrorMessage*(commandWindow: var Window) =
  commandWindow.erase
  commandWindow.write(0, 0, "can not create direcotry")
  commandWindow.refresh

proc initFileRegister(): FileRegister =
  result.copy = false
  result.cut= false
  result.originPath = ""
  result.filename = ""

proc initFilerStatus(): FilerStatus =
  result.register = initFileRegister()
  result.viewUpdate = true
  result.dirlistUpdate = true
  result.dirList = newSeq[PathInfo]()
  result.sortBy = name
  result.currentLine = 0
  result.startIndex = 0
  result.searchMode = false

proc updateDirList(filerStatus: var FilerStatus): FilerStatus =
  filerStatus.currentLine = 0
  filerStatus.startIndex = 0
  filerStatus.dirList = @[]
  filerStatus.dirList.add refreshDirList(filerStatus.sortBy)
  filerStatus.viewUpdate = true
  filerStatus.dirlistUpdate = false
  return filerStatus

proc keyDown(filerStatus: var FilerStatus) =
  if filerStatus.currentLine == terminalHeight() - 3:
    inc(filerStatus.startIndex)
  else:
    inc(filerStatus.currentLine)
    filerStatus.viewUpdate = true

proc keyUp(filerStatus: var FilerStatus) =
  if 0 < filerStatus.startIndex and filerStatus.currentLine == 0:
    dec(filerStatus.startIndex)
  else:
    dec(filerStatus.currentLine)
    filerStatus.viewUpdate = true

proc moveToTopOfList(filerStatus: var FilerStatus) =
  filerStatus.currentLine = 0
  filerStatus.startIndex = 0
  filerStatus.viewUpdate = true

proc moveToLastOfList(status: EditorStatus, filerStatus: var FilerStatus) =
  if filerStatus.dirList.len < status.mainWindow[status.currentMainWindow].height:
    filerStatus.currentLine = filerStatus.dirList.high
  else:
    filerStatus.currentLine = status.mainWindow[status.currentMainWindow].height - 1
    filerStatus.startIndex = filerStatus.dirList.len - status.mainWindow[status.currentMainWindow].height
  filerStatus.viewUpdate = true

proc copyFile(filerStatus: var FilerStatus) =
  filerStatus.register.copy = true
  filerStatus.register.cut = false
  filerStatus.register.filename = filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].path

proc cutFile(filerStatus: var FilerStatus) =
  filerStatus.register.copy = false
  filerStatus.register.cut = true
  filerStatus.register.filename = filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].path

proc pasteFile(commandWindow: var Window, filerStatus: var FilerStatus, errorMessageColor: ColorPair) =
  try:
    copyFile(filerStatus.register.originPath, getCurrentDir() / filerStatus.register.filename)
    filerStatus.dirlistUpdate = true
    filerStatus.viewUpdate = true
  except OSError:
    writeCopyFileError(commandWindow, errorMessageColor)
    return

  if filerStatus.register.cut:
    if tryRemoveFile(filerStatus.register.originPath / filerStatus.register.filename):
      filerStatus.register.cut = false
    else:
      writeRemoveFileError(commandWindow, errorMessageColor)

proc createDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let dirname = getCommand(status, "New file name: ")
  setCursor(false)

  try:
    createDir($dirname[0])
    filerStatus.dirlistUpdate = true
  except OSError:
    writeCreateDirErrorMessage(status.commandWindow)
    return
   
proc openFileOrDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let
    kind = filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].kind
    path = filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex].path
  case kind
  of pcFile, pcLinkToFile:
    let filename = (if kind == pcFile: path else: expandsymLink(path)).toRunes
    status.bufStatus.add(BufferStatus(filename: filename))
    status.bufStatus[status.bufStatus.high].language = detectLanguage($filename)
    if existsFile($filename):
      try:
        let textAndEncoding = openFile(filename)
        status.bufStatus[status.bufStatus.high].buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        writeFileOpenErrorMessage(status.commandWindow, status.bufStatus[status.currentMainWindow].filename)
        status.bufStatus[status.bufStatus.high].buffer = newFile()
    else:
      status.bufStatus[status.bufStatus.high].buffer = newFile()

    changeCurrentBuffer(status, status.bufStatus.high)

    let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[status.currentBuffer].buffer.len) - 2 else: 0
    let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    status.updateHighlight
    status.bufStatus[status.currentBuffer].view = initEditorView(status.bufStatus[status.currentBuffer].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

    setCursor(true)

  of pcDir, pcLinkToDir:
    let directoryName = if kind == pcDir: path else: expandSymlink(path)
    try:
      setCurrentDir(path)
      filerStatus.dirlistUpdate = true
    except OSError:
      writeFileOpenErrorMessage(status.commandWindow, path.toRunes)

proc updateFilerView(status: var EditorStatus, filerStatus: var FilerStatus) =
  status.mainWindow[status.currentMainWindow].erase
  status.resize(terminalHeight(), terminalWidth())
  status.mainWindow[status.currentMainWindow].writeFillerView(filerStatus.dirList, filerStatus.currentLine, filerStatus.startIndex)
  filerStatus.viewUpdate = false

proc changeSortBy(filerStatus: var FilerStatus) =
  case filerStatus.sortBy:
  of name: filerStatus.sortBy = fileSize
  of fileSize: filerStatus.sortBy = time
  of time: filerStatus.sortBy = name

  filerStatus.dirlistUpdate = true

proc searchFileMode(status: var EditorStatus, filerStatus: var FilerStatus) =
  filerStatus.searchMode = true
  filerStatus.dirList = searchFiles(status, filerStatus.dirList)
  filerStatus.currentLine = 0
  filerStatus.startIndex = 0
  filerStatus.viewUpdate = true
  if filerStatus.dirList.len == 0:
    status.mainWindow[status.currentMainWindow].erase
    status.mainWindow[status.currentMainWindow].write(0, 0, "not found")
    status.mainWindow[status.currentMainWindow].refresh
    discard getKey(status.commandWindow)
    status.commandWindow.erase
    status.commandWindow.refresh
    filerStatus.dirlistUpdate = true

proc filerMode*(status: var EditorStatus) =
  setCursor(false)
  var filerStatus = initFilerStatus()

  while status.bufStatus[status.currentBuffer].mode == Mode.filer:
    if filerStatus.dirlistUpdate:
      filerStatus = updateDirList(filerStatus)

    if filerStatus.viewUpdate:
      updateFilerView(status, filerStatus)

    let key = getKey(status.mainWindow[status.currentMainWindow])

    if key == ord(':'):
      status.changeMode(Mode.ex)
    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      filerStatus.viewUpdate = true

    elif key == ord('/'):
      searchFileMode(status, filerStatus)

    elif isEscKey(key):
      if filerStatus.searchMode == true:
        filerStatus.dirlistUpdate = true
        filerStatus.searchMode = false

    elif key == ord('D'):
      deleteFile(status, filerStatus)
    elif key == ord('i'):
      writeFileDetailView(status.mainWindow[status.currentMainWindow], filerStatus.dirList[filerStatus.currentLine + filerStatus.startIndex][1])
      filerStatus.viewUpdate = true
    elif (key == 'j' or isDownKey(key)) and filerStatus.currentLine + filerStatus.startIndex < filerStatus.dirList.high:
      keyDown(filerStatus)
    elif (key == ord('k') or isUpKey(key)) and (0 < filerStatus.currentLine or 0 < filerStatus.startIndex):
      keyUp(filerStatus)
    elif key == ord('g'):
      moveToTopOfList(filerStatus)
    elif key == ord('G'):
      moveToLastOfList(status, filerStatus)
    elif key == ord('y'):
      copyFile(filerStatus)
    elif key == ord('C'):
      cutFile(filerStatus)
    elif key == ord('p'):
      pasteFile(status.commandWindow, filerStatus, status.settings.editorColor.errorMessage)
    elif key == ord('s'):
      changeSortBy(filerStatus)
    elif key == ord('N'):
      createDir(status, filerStatus)
    elif isEnterKey(key):
      openFileOrDir(status, filerStatus)
  setCursor(true)
