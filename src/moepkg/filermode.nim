import os, terminal, strutils, unicodeext, times, algorithm
import editorstatus, ui, fileutils, editorview, gapbuffer, highlight,
       commandview, highlight, window, color, bufferstatus, settings

type PathInfo = tuple[kind: PathComponent,
                      path: string,
                      size: int64,
                      lastWriteTime: times.Time]

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
  for dir in dirList:
    if dir.path.contains(str): result.add dir

proc deleteFile(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let command = getCommand(status, "Delete file? 'y' or 'n': ")

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
  elif (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    let workspaceIndex = status.currentWorkSpaceIndex
    var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode
    if filerStatus.dirList[windowNode.currentLine].kind == pcDir:
      try:
        removeDir(filerStatus.dirList[windowNode.currentLine].path)
        status.commandWindow.writeMessageDeletedFile(
          filerStatus.dirList[windowNode.currentLine].path,
          status.messageLog)
      except OSError:
        status.commandWindow.writeRemoveDirError(status.messageLog)
    else:
      if tryRemoveFile(filerStatus.dirList[windowNode.currentLine].path):
        status.commandWindow.writeMessageDeletedFile(
          filerStatus.dirList[windowNode.currentLine].path,
          status.messageLog)
      else:
        status.commandWindow.writeRemoveFileError(status.messageLog)

proc sortDirList(dirList: seq[PathInfo], sortBy: Sort): seq[PathInfo] =
  case sortBy:
  of name:
    return dirList.sortedByIt(it.path)
  of fileSize:
    result.add dirList.sortedByIt(it.size).reversed
  of time:
    result.add dirList.sortedByIt(it.lastWriteTime)

proc refreshDirList(sortBy: Sort): seq[PathInfo] =
  var dirList  : seq[PathInfo]
  var fileList : seq[PathInfo]
  var item     : PathInfo
  for list in walkDir("./"):
    if list.kind == pcLinkToFile or list.kind == pcLinkToDir:
      if tryExpandSymlink(list.path) != "":
        item = (list.kind,
                list.path,
                0.int64,
                getLastModificationTime(getCurrentDir()))
    else:
      if list.kind == pcFile:
        try:
          item = (list.kind,
                  list.path,
                  getFileSize(list.path),
                  getLastModificationTime(list.path))
        except OSError, IOError: discard
      else:
        item = (list.kind,
                list.path,
                0.int64,
                getLastModificationTime(list.path))
    item.path = $(item.path.toRunes.normalizePath)
    if list.kind in {pcLinkToDir, pcDir}:
      dirList.add item
    else:
      fileList.add item
  return @[(pcDir,
            "../",
            0.int64,
            getLastModificationTime(getCurrentDir()))] &
    sortDirList(dirList, sortBy) & sortDirList(fileList, sortBy)

proc initFileRegister(): FileRegister =
  result.copy = false
  result.cut= false
  result.originPath = ""
  result.filename = ""

proc initFilerStatus*(): FilerStatus =
  result.register = initFileRegister()
  result.viewUpdate = true
  result.dirlistUpdate = true
  result.dirList = newSeq[PathInfo]()
  result.sortBy = name
  result.searchMode = false

proc updateDirList*(filerStatus: var FilerStatus): FilerStatus =
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
  let path = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = getCurrentDir() / path

proc cutFile(filerStatus: var FilerStatus, currentLine: int) =
  filerStatus.register.copy = false
  filerStatus.register.cut = true
  let path = filerStatus.dirList[currentLine].path
  filerStatus.register.filename = path
  filerStatus.register.originPath = getCurrentDir() / path

proc pasteFile(commandWindow: var Window,
               filerStatus: var FilerStatus,
               messageLog: var seq[seq[Rune]]) =

  try:
    let filename = filerStatus.register.filename
    copyFile(filerStatus.register.originPath, getCurrentDir() / filename)
    filerStatus.dirlistUpdate = true
    filerStatus.viewUpdate = true
  except OSError:
    commandWindow.writeCopyFileError(messageLog)
    return

  if filerStatus.register.cut:
    let filename = filerStatus.register.filename
    if tryRemoveFile(filerStatus.register.originPath / filename):
      filerStatus.register.cut = false
    else: commandWindow.writeRemoveFileError(messageLog)

proc createDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let dirname = getCommand(status, "New file name: ")

  try:
    createDir($dirname[0])
    filerStatus.dirlistUpdate = true
  except OSError: status.commandWindow.writeCreateDirError(status.messageLog)
   
proc openFileOrDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode
  let
    kind = filerStatus.dirList[windowNode.currentLine].kind
    path = filerStatus.dirList[windowNode.currentLine].path

  case kind
  of pcFile, pcLinkToFile:
    addNewBuffer(status, path)
  of pcDir, pcLinkToDir:
    try:
      setCurrentDir(path)
      filerStatus.dirlistUpdate = true
    except OSError: status.commandWindow.writeFileOpenError(path, status.messageLog)

proc setDirListColor(kind: PathComponent, isCurrentLine: bool): EditorColorPair =
  if isCurrentLine: result = EditorColorPair.currentFile
  else:
    case kind
    of pcFile: result = EditorColorPair.file
    of pcDir: result = EditorColorPair.dir
    of pcLinkToDir, pcLinkToFile: result = EditorColorPair.pcLink

proc initFilelistHighlight[T](dirList: seq[PathInfo], buffer: T, currentLine: int): Highlight =
  for index, dir in dirList:
    let color = setDirListColor(dir.kind, index == currentLine)
    result.colorSegments.add(ColorSegment(firstRow: index,
                                          firstColumn: 0,
                                          lastRow: index,
                                          lastColumn: buffer[index].len,
                                          color: color))

proc pathToIcon(path: string): seq[Rune] =
  if existsDir(path):
    return ru"📁"

  # Not sure if this is a perfect solution,
  # it should detect if the current user can execute
  # the file or not:
  try:
    let permissions = getFilePermissions(path)
    if fpUserExec  in permissions or
      fpGroupExec in permissions:
      return ru"🏃"
  except:
    discard

  # The symbols were selected for their looks,
  # they don't always have to make perfect sense,
  # there's simply not a symbol for every possible
  # file extension in unicode.
  let ext = path.split(".")[^1]
  case ext.toLower():
  of "nim":
    return ru"👑"
  of "nimble", "rpm", "deb":
    return ru"📦"
  of "py":
    return ru"🐍"
  of "ui", "glade":
    return ru"🏠"
  of "txt", "md", "rst":
    return ru"📝"
  of "cpp", "cxx", "hpp":
    return ru"⧺"
  of "c", "h":
    return ru"🅒"
  of "java":
    return ru"🍵"
  of "php":
    return ru"🙈"
  of "js", "json":
    return ru"🙉"
  of "html", "xhtml":
    return ru"🏄"
  of "css":
    return ru"👚"
  of "xml":
    return ru"༕"
  of "cfg", "ini":
    return ru"🍳"
  of "sh":
    return ru"🐚"
  of "pdf", "doc", "odf", "ods", "odt":
    return ru"🍞"
  of "wav", "mp3", "ogg":
    return ru"🎼"
  of "zip", "bz2", "xz", "gz", "tgz", "zstd":
    return ru"🚢"
  of "exe", "bin":
    return ru"🏃"
  of "mp4", "webm", "avi", "mpeg":
    return ru"🎞"
  of "patch":
    return ru"💊"
  of "lock":
    return ru"🔒"
  of "pem", "crt":
    return ru"🔏"
  of "png", "jpeg", "jpg", "bmp", "gif":
    return ru"🎨"
  else:
    return ru"🍕"

  # useful unicode symbols: that aren't used here yet:
  # open book        : 📖
  # penguin          : 🐧
  # open file folder : 📂
  #
proc fileNameToGapBuffer(bufStatus: var BufferStatus,
                         windowNode: WindowNode,
                         settings: EditorSettings,
                         filerStatus: FilerStatus) =

  bufStatus.buffer = initGapBuffer[seq[Rune]]()

  for index, dir in filerStatus.dirList:
    let
      filename = dir.path
      kind = dir.kind
    bufStatus.buffer.add(filename.toRunes)

    let oldLine =  bufStatus.buffer[index]
    var newLine =  bufStatus.buffer[index]
    if kind == pcDir and 0 < index:
      newLine.add(ru"/")
    elif kind == pcLinkToFile:
      newLine.add(ru"@ -> " & expandsymLink(filename).toRunes)
    elif kind == pcLinkToDir:
      newLine.add(ru"@ -> " & expandsymLink(filename).toRunes & ru"/")
    newLine = pathToIcon(filename)
    newLine.add oldLine
    bufStatus.buffer[index] = newLine
  
  let useStatusBar = if settings.statusBar.useBar: 1 else: 0
  let numOfFile = filerStatus.dirList.len
  windowNode.highlight = initFilelistHighlight(filerStatus.dirList, bufStatus.buffer, windowNode.currentLine)
  windowNode.view = initEditorView(bufStatus.buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numOfFile)

proc updateFilerView*(status: var EditorStatus, filerStatus: var FilerStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  fileNameToGapBuffer(status.bufStatus[currentBufferIndex],
                      status.workSpace[workspaceIndex].currentMainWindowNode,
                      status.settings,
                      filerStatus)
  status.resize(terminalHeight(), terminalWidth())
  status.update
  filerStatus.viewUpdate = false

proc initFileDeitalHighlight[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(firstRow: i,
                                          firstColumn: 0,
                                          lastRow: i,
                                          lastColumn: buffer[i].len,
                                          color: EditorColorPair.defaultChar))

proc writefileDetail(status: var Editorstatus, numOfFile: int, fileName: string) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].buffer = initGapBuffer[seq[Rune]]()

  let fileInfo = getFileInfo(fileName, false)
  status.bufStatus[currentBufferIndex].buffer.add(ru"name        : " & fileName.toRunes)

  if fileInfo.kind == pcFile:
    status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"File")
  elif fileInfo.kind == pcDir:
    status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Directory")
  elif fileInfo.kind == pcLinkToFile:
    status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Symbolic link to file")
  elif fileInfo.kind == pcLinkToDir:
    status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Symbolic link to directory")

  status.bufStatus[currentBufferIndex].buffer.add(("size        : " & $fileInfo.size & " bytes").toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("permissions : " & substr($fileInfo.permissions,
                                                                             1,
                                                                             ($fileInfo.permissions).high - 1)).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("create time : " & $fileInfo.creationTime).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("last write  : " & $fileInfo.lastWriteTime).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("last access : " & $fileInfo.lastAccessTime).toRunes)

  let buffer = status.bufStatus[currentBufferIndex].buffer
  status.workSpace[workspaceIndex].currentMainWindowNode.highlight = initFileDeitalHighlight(buffer)

  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    tmpCurrentLine = windowNode.currentLine

  windowNode.view = initEditorView(
                                   status.bufStatus[currentBufferIndex].buffer,
                                   terminalHeight() - useStatusBar - 1,
                                   terminalWidth() - numOfFile)
  windowNode.currentLine = 0

  status.update
  setCursor(false)
  while isResizekey(status.workSpace[workspaceIndex].currentMainWindowNode.window.getKey):
    status.resize(terminalHeight(), terminalWidth())
    status.update
    setCursor(false)

  windowNode.currentLine = tmpCurrentLine

proc changeSortBy(filerStatus: var FilerStatus) =
  case filerStatus.sortBy:
  of name: filerStatus.sortBy = fileSize
  of fileSize: filerStatus.sortBy = time
  of time: filerStatus.sortBy = name

  filerStatus.dirlistUpdate = true

proc searchFileMode(status: var EditorStatus, filerStatus: var FilerStatus) =
  filerStatus.searchMode = true
  filerStatus.dirList = searchFiles(status, filerStatus.dirList)
  filerStatus.viewUpdate = true

  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  windowNode.currentLine = 0

  if filerStatus.dirList.len == 0:
    windowNode.window.erase
    windowNode.window.write(0, 0, "not found", EditorColorPair.commandBar)
    windowNode.window.refresh
    discard getKey(status.commandWindow)
    status.commandWindow.erase
    status.commandWindow.refresh
    filerStatus.dirlistUpdate = true

proc isFilerMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].mode == Mode.filer

proc filerMode*(status: var EditorStatus) =
  var filerStatus = initFilerStatus()

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isFilerMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let currentBufferIndex = status.bufferIndexInCurrentWindow

    var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

    if filerStatus.dirlistUpdate:
      filerStatus = updateDirList(filerStatus)
      windowNode.currentLine = 0

    if filerStatus.viewUpdate: updateFilerView(status, filerStatus)

    setCursor(false)
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(windowNode)
    
    if key == ord(':'): status.changeMode(Mode.ex)

    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
      filerStatus.viewUpdate = true

    elif key == ord('/'): searchFileMode(status, filerStatus)

    elif isEscKey(key):
      if filerStatus.searchMode == true:
        filerStatus.dirlistUpdate = true
        filerStatus.searchMode = false
    elif key == ord('D'):
      deleteFile(status, filerStatus)
    elif key == ord('i'):
      writeFileDetail(status,
                      filerStatus.dirList.len,
                      filerStatus.dirList[windowNode.currentLine][1])
      filerStatus.viewUpdate = true
    elif key == 'j' or isDownKey(key):
      filerStatus.keyDown(windowNode.currentLine)
    elif key == ord('k') or isUpKey(key):
      filerStatus.keyUp(windowNode.currentLine)
    elif key == ord('g'):
      filerStatus.moveToTopOfList(windowNode.currentLine)
    elif key == ord('G'):
      filerStatus.moveToLastOfList(windowNode.currentLine)
    elif key == ord('y'):
      filerStatus.copyFile(windowNode.currentLine)
    elif key == ord('C'):
      filerStatus.cutFile(windowNode.currentLine)
    elif key == ord('p'):
      status.commandWindow.pasteFile(filerStatus, status.messageLog)
    elif key == ord('s'):
      filerStatus.changeSortBy
    elif key == ord('N'):
      status.createDir(filerStatus)
    elif isControlJ(key):
      status.movePrevWindow
    elif isControlK(key):
      status.moveNextWindow
    elif isEnterKey(key):
      status.openFileOrDir(filerStatus)
