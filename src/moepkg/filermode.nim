import os, sequtils, terminal, strformat, strutils, unicodeext, times, algorithm
import packages/docutils/highlite
import editorstatus, ui, fileutils, editorview, gapbuffer, independentutils, highlight, commandview, highlight

type PathInfo = tuple[kind: PathComponent, path: string, size: int64, lastWriteTime: times.Time]

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

proc tryExpandSymlink(symlinkPath: string): string =
  try: return expandSymlink(symlinkPath)
  except OSError: return ""

proc searchFiles(status: var EditorStatus, dirList: seq[PathInfo]): seq[PathInfo] =
  setCursor(true)
  let command = getCommand(status, "/")

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return @[]

  let str = command[0].join("")
  result = @[]
  for index in 0 .. dirList.high:
    if dirList[index].path.contains(str): result.add dirList[index]

proc deleteFile(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let command = getCommand(status, "Delete file? 'y' or 'n': ")

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
  elif (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    if filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].kind == pcDir:
      try:
        removeDir(filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].path)
        status.commandWindow.writeMessageDeletedFile(filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].path)
      except OSError:
        status.commandWindow.writeRemoveDirError
    else:
      if tryRemoveFile(filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].path):
        status.commandWindow.writeMessageDeletedFile(filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].path)
      else:
        status.commandWindow.writeRemoveFileError

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
      if tryExpandSymlink(list.path) != "": result.add (list.kind, list.path, 0.int64, getLastModificationTime(getCurrentDir()))
    else:
      if list.kind == pcFile:
        try: result.add (list.kind, list.path, getFileSize(list.path), getLastModificationTime(list.path))
        except OSError, IOError: discard
      else: result.add (list.kind, list.path, 0.int64, getLastModificationTime(list.path))
    result[result.high].path = $(result[result.high].path.toRunes.normalizePath)
  return sortDirList(result, sortBy)

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
  result.searchMode = false

proc updateDirList(filerStatus: var FilerStatus): FilerStatus =
  filerStatus.dirList = @[]
  filerStatus.dirList.add refreshDirList(filerStatus.sortBy)
  filerStatus.viewUpdate = true
  filerStatus.dirlistUpdate = false
  return filerStatus

proc keyDown(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine < filerStatus.dirList.high:
    inc(currentLine)
    filerStatus.viewUpdate = true

proc keyUp(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine > 0:
    dec(currentLine)
    filerStatus.viewUpdate = true

proc moveToTopOfList(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = 0
  filerStatus.viewUpdate = true

proc moveToLastOfList(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = filerStatus.dirList.high
  filerStatus.viewUpdate = true

proc copyFile(filerStatus: var FilerStatus, currentLine: int) =
  filerStatus.register.copy = true
  filerStatus.register.cut = false
  filerStatus.register.filename = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[currentLine].path

proc cutFile(filerStatus: var FilerStatus, currentLine: int) =
  filerStatus.register.copy = false
  filerStatus.register.cut = true
  filerStatus.register.filename = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[currentLine].path

proc pasteFile(commandWindow: var Window, filerStatus: var FilerStatus) =
  try:
    copyFile(filerStatus.register.originPath, getCurrentDir() / filerStatus.register.filename)
    filerStatus.dirlistUpdate = true
    filerStatus.viewUpdate = true
  except OSError:
    commandWindow.writeCopyFileError
    return

  if filerStatus.register.cut:
    if tryRemoveFile(filerStatus.register.originPath / filerStatus.register.filename): filerStatus.register.cut = false
    else: commandWindow.writeRemoveFileError

proc createDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let dirname = getCommand(status, "New file name: ")

  try:
    createDir($dirname[0])
    filerStatus.dirlistUpdate = true
  except OSError: status.commandWindow.writeCreateDirError
   
proc openFileOrDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let
    kind = filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].kind
    path = filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine].path

  case kind
  of pcFile, pcLinkToFile:
    addNewBuffer(status, path)
  of pcDir, pcLinkToDir:
    let directoryName = if kind == pcDir: path else: expandSymlink(path)
    try:
      setCurrentDir(path)
      filerStatus.dirlistUpdate = true
    except OSError: status.commandWindow.writeFileOpenError(path)

proc setDirListColor(kind: PathComponent, isCurrentLine: bool): EditorColorPair =
  if isCurrentLine: result = EditorColorPair.currentFile
  else:
    case kind
    of pcFile: result = EditorColorPair.file
    of pcDir: result = EditorColorPair.dir
    of pcLinkToDir, pcLinkToFile: result = EditorColorPair.pcLink

proc initFilelistHighlight[T](dirList: seq[PathInfo], buffer: T, currentLine: int): Highlight =
  for i in 0 ..< dirList.len:
    let color = setDirListColor(dirList[i].kind, i == currentLine)
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: color))

proc fileNameToGapBuffer(bufStatus: var BufferStatus, settings: EditorSettings, filerStatus: FilerStatus) =
  bufStatus.buffer = initGapBuffer[seq[Rune]]()

  for i in 0 ..< filerStatus.dirList.len:
    let
      filename = filerStatus.dirList[i].path
      kind = filerStatus.dirList[i].kind
    bufStatus.buffer.add(filename.toRunes)

    let oldLine =  bufStatus.buffer[i]
    var newLine =  bufStatus.buffer[i]
    if kind == pcDir and 0 < i: newLine.add(ru"/")
    elif kind == pcLinkToFile: newLine.add(ru"@ -> " & expandsymLink(filename).toRunes)
    elif kind == pcLinkToDir: newLine.add(ru"@ -> " & expandsymLink(filename).toRunes & ru"/")
    if oldLine != newLine: bufStatus.buffer[i] = newLine
  
  let useStatusBar = if settings.statusBar.useBar: 1 else: 0
  let numOfFile = filerStatus.dirList.len
  bufStatus.highlight = initFilelistHighlight(filerStatus.dirList, bufStatus.buffer, bufStatus.currentLine)
  bufStatus.view = initEditorView(bufStatus.buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numOfFile)

proc updateFilerView(status: var EditorStatus, filerStatus: var FilerStatus) =
  fileNameToGapBuffer(status.bufStatus[status.currentBuffer], status.settings, filerStatus)
  status.resize(terminalHeight(), terminalWidth())
  status.update
  filerStatus.viewUpdate = false

proc initFileDeitalHighlight[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: EditorColorPair.defaultChar))

proc writefileDetail(status: var Editorstatus, numOfFile: int, fileName: string) =
  status.bufStatus[status.currentBuffer].buffer = initGapBuffer[seq[Rune]]()

  let fileInfo = getFileInfo(fileName, false)
  status.bufStatus[status.currentBuffer].buffer.add(ru"name        : " & fileName.toRunes)

  if fileInfo.kind == pcFile: status.bufStatus[status.currentBuffer].buffer.add(ru"kind        : " & ru"File")
  elif fileInfo.kind == pcDir: status.bufStatus[status.currentBuffer].buffer.add(ru"kind        : " & ru"Directory")
  elif fileInfo.kind == pcLinkToFile: status.bufStatus[status.currentBuffer].buffer.add(ru"kind        : " & ru"Symbolic link to file")
  elif fileInfo.kind == pcLinkToDir: status.bufStatus[status.currentBuffer].buffer.add(ru"kind        : " & ru"Symbolic link to directory")

  status.bufStatus[status.currentBuffer].buffer.add(("size        : " & $fileInfo.size & " bytes").toRunes)
  status.bufStatus[status.currentBuffer].buffer.add(("permissions : " & substr($fileInfo.permissions, 1, ($fileInfo.permissions).high - 1)).toRunes)
  status.bufStatus[status.currentBuffer].buffer.add(("create time : " & $fileInfo.creationTime).toRunes)
  status.bufStatus[status.currentBuffer].buffer.add(("last write  : " & $fileInfo.lastWriteTime).toRunes)
  status.bufStatus[status.currentBuffer].buffer.add(("last access : " & $fileInfo.lastAccessTime).toRunes)

  status.bufStatus[status.currentBuffer].highlight = initFileDeitalHighlight(status.bufStatus[status.currentBuffer].buffer)

  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    tmpCurrentLine = status.bufStatus[status.currentBuffer].currentLine

  status.bufStatus[status.currentBuffer].view = initEditorView(status.bufStatus[status.currentBuffer].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numOfFile)
  status.bufStatus[status.currentBuffer].currentLine = 0

  status.update
  setCursor(false)
  while isResizekey(status.mainWindowInfo[status.currentMainWindow].window.getKey):
    status.resize(terminalHeight(), terminalWidth())
    status.update
    setCursor(false)

  status.bufStatus[status.currentBuffer].currentLine = tmpCurrentLine

proc changeSortBy(filerStatus: var FilerStatus) =
  case filerStatus.sortBy:
  of name: filerStatus.sortBy = fileSize
  of fileSize: filerStatus.sortBy = time
  of time: filerStatus.sortBy = name

  filerStatus.dirlistUpdate = true

proc searchFileMode(status: var EditorStatus, filerStatus: var FilerStatus) =
  filerStatus.searchMode = true
  filerStatus.dirList = searchFiles(status, filerStatus.dirList)
  status.bufStatus[status.currentBuffer].currentLine = 0
  filerStatus.viewUpdate = true
  if filerStatus.dirList.len == 0:
    status.mainWindowInfo[status.currentMainWindow].window.erase
    status.mainWindowInfo[status.currentMainWindow].window.write(0, 0, "not found", EditorColorPair.commandBar)
    status.mainWindowInfo[status.currentMainWindow].window.refresh
    discard getKey(status.commandWindow)
    status.commandWindow.erase
    status.commandWindow.refresh
    filerStatus.dirlistUpdate = true

proc filerMode*(status: var EditorStatus) =
  var filerStatus = initFilerStatus()

  while status.bufStatus[status.currentBuffer].mode == Mode.filer:
    if filerStatus.dirlistUpdate:
      filerStatus = updateDirList(filerStatus)
      status.bufStatus[status.currentBuffer].currentLine = 0

    if filerStatus.viewUpdate: updateFilerView(status, filerStatus)

    setCursor(false)
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    
    if key == ord(':'): status.changeMode(Mode.ex)

    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      filerStatus.viewUpdate = true

    elif key == ord('/'): searchFileMode(status, filerStatus)

    elif isEscKey(key):
      if filerStatus.searchMode == true:
        filerStatus.dirlistUpdate = true
        filerStatus.searchMode = false
    elif key == ord('D'):
      deleteFile(status, filerStatus)
    elif key == ord('i'):
      writeFileDetail(status, filerStatus.dirList.len, filerStatus.dirList[status.bufStatus[status.currentBuffer].currentLine][1])
      filerStatus.viewUpdate = true
    elif key == 'j' or isDownKey(key):
      keyDown(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('k') or isUpKey(key):
      keyUp(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('g'):
      moveToTopOfList(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('G'):
      moveToLastOfList(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('y'):
      copyFile(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('C'):
      cutFile(filerStatus, status.bufStatus[status.currentBuffer].currentLine)
    elif key == ord('p'):
      pasteFile(status.commandWindow, filerStatus)
    elif key == ord('s'):
      changeSortBy(filerStatus)
    elif key == ord('N'):
      createDir(status, filerStatus)
    elif isControlJ(key):
      movePrevWindow(status)
    elif isControlK(key):
      moveNextWindow(status)
    elif isEnterKey(key):
      openFileOrDir(status, filerStatus)
