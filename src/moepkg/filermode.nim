import std/[os, terminal, strutils, times, algorithm, sequtils,
            options]
import editorstatus, ui, fileutils, editorview, gapbuffer, highlight,
       commandview, window, color, bufferstatus, settings, messages,
       commandline, unicodeext

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

proc searchFiles(status: var EditorStatus,
                 dirList: seq[PathInfo]): seq[PathInfo] =

  setCursor(true)
  let command = status.getCommand("/")

  if command.len == 0:
    status.commandLine.erase
    return @[]

  let str = command[0].join("")
  result = @[]
  for dir in dirList:
    if dir.path.contains(str): result.add dir

proc deleteFile(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let command = getCommand(status, "Delete file? 'y' or 'n': ")

  if command.len == 0:
    status.commandLine.erase
  elif (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    if filerStatus.dirList[currentMainWindowNode.currentLine].kind == pcDir:
      try:
        removeDir(filerStatus.dirList[currentMainWindowNode.currentLine].path)
        status.commandLine.writeMessageDeletedFile(
          filerStatus.dirList[currentMainWindowNode.currentLine].path,
          status.settings.notificationSettings,
          status.messageLog)
      except OSError:
        status.commandLine.writeRemoveDirError(status.messageLog)
    else:
      if tryRemoveFile(filerStatus.dirList[currentMainWindowNode.currentLine].path):
        status.commandLine.writeMessageDeletedFile(
          filerStatus.dirList[currentMainWindowNode.currentLine].path,
          status.settings.notificationSettings,
          status.messageLog)
      else:
        status.commandLine.writeRemoveFileError(status.messageLog)

proc sortDirList(dirList: seq[PathInfo], sortBy: Sort): seq[PathInfo] =
  case sortBy:
  of name:
    return dirList.sortedByIt(it.path)
  of fileSize:
    result.add dirList.sortedByIt(it.size).reversed
  of time:
    result.add dirList.sortedByIt(it.lastWriteTime)

when defined(posix):
  from std/posix import nil
  from std/posix_utils import nil

  proc isFifo(file: string): bool {.inline.} =
    posix.S_ISFIFO(posix_utils.stat(file).st_mode)
else:
  proc isFifo(file: string): bool {.inline.} = false

proc refreshDirList(path: seq[Rune], sortBy: Sort): seq[PathInfo] =
  var
    dirList  : seq[PathInfo]
    fileList : seq[PathInfo]

  for list in walkDir($path):
    proc getLastModificationTimeOrDefault(file: string): times.Time =
      try: getLastModificationTime(file)
      except OSError: initTime(0,0)

    proc getFileSizeOrDefault(file: string): int64 =
      try:
        # `getFileSize` opens files internally. So if `file` is a named pipe,
        # we don't call `getFileSize` to avoid opening named pipes.
        if isFifo(file): return 0.int64

        getFileSize(file)
      except IOError, OSError: 0.int64

    var item: PathInfo

    case list.kind
    of pcLinkToFile, pcLinkToDir:
      item = (list.kind,
              list.path,
              0.int64,
              getLastModificationTimeOrDefault(list.path))
    of pcFile:
      item = (list.kind,
              list.path,
              getFileSizeOrDefault(list.path),
              getLastModificationTimeOrDefault(list.path))
    else:
      item = (list.kind,
              list.path,
              0.int64,
              getLastModificationTimeOrDefault(list.path))

    if item.path.len > 0:
      item.path = $(item.path.toRunes.normalizePath)

    if list.kind in {pcLinkToDir, pcDir}:
      dirList.add item
    else:
      fileList.add item

  return @[(pcDir,
            ParDir,
            0.int64,
            getLastModificationTime($path))] &
            sortDirList(dirList, sortBy) & sortDirList(fileList, sortBy)

proc initFileRegister(): FileRegister {.inline.} =
  result.copy = false
  result.cut= false
  result.originPath = ""
  result.filename = ""

proc initFilerStatus*(): FilerStatus =
  result.register = initFileRegister()
  #result.currentPath = getCurrentDir().toRunes
  result.viewUpdate = true
  result.dirlistUpdate = true
  result.dirList = newSeq[PathInfo]()
  result.sortBy = name
  result.searchMode = false

proc updateDirList*(filerStatus: var FilerStatus,
                    path: seq[Rune]): FilerStatus =

  filerStatus.dirList = @[]
  filerStatus.dirList.add(refreshDirList(path, filerStatus.sortBy))

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

proc copyFile(filerStatus: var FilerStatus,
              currentLine: int,
              currentPath: seq[Rune]) =

  filerStatus.register.copy = true
  filerStatus.register.cut = false
  filerStatus.register.filename = filerStatus.dirList[currentLine].path
  let path = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = $currentPath / path

proc cutFile(filerStatus: var FilerStatus,
             currentLine: int,
             currentPath: seq[Rune]) =

  filerStatus.register.copy = false
  filerStatus.register.cut = true
  let path = filerStatus.dirList[currentLine].path
  filerStatus.register.filename = path
  filerStatus.register.originPath = $currentPath / path

proc pasteFile(commandLine: var CommandLine,
               filerStatus: var FilerStatus,
               currentPath: seq[Rune],
               messageLog: var seq[seq[Rune]]) =

  try:
    let filename = filerStatus.register.filename
    copyFile(filerStatus.register.originPath, $currentPath / filename)
    filerStatus.dirlistUpdate = true
    filerStatus.viewUpdate = true
  except OSError:
    commandLine.writeCopyFileError(messageLog)
    return

  if filerStatus.register.cut:
    let filename = filerStatus.register.filename
    if tryRemoveFile(filerStatus.register.originPath / filename):
      filerStatus.register.cut = false
    else: commandLine.writeRemoveFileError(messageLog)

proc createDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let dirname = getCommand(status, "New file name: ")

  try:
    createDir($dirname[0])
    filerStatus.dirlistUpdate = true
  except OSError: status.commandLine.writeCreateDirError(status.messageLog)

proc openFileOrDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let
    kind = filerStatus.dirList[currentMainWindowNode.currentLine].kind
    path = filerStatus.dirList[currentMainWindowNode.currentLine].path

  case kind
    of pcFile, pcLinkToFile:
      status.addNewBuffer(path)
    of pcDir, pcLinkToDir:
      let currentPath = currentBufStatus.path
      if path == "..":
        if not isRootDir($currentPath):
          let parentDir = parentDir($currentPath).toRunes
          currentBufStatus.path = parentDir
      else:
        currentBufStatus.path = path.toRunes

      filerStatus.dirlistUpdate = true

proc openNewWinAndOpenFilerOrDir(status: var EditorStatus,
                                 filerStatus: var FilerStatus,
                                 terminalHeight, terminalWidth: int) =

  let path = filerStatus.dirList[currentMainWindowNode.currentLine].path

  status.verticalSplitWindow
  status.resize(terminalHeight, terminalWidth)
  status.moveNextWindow

  if dirExists($path):
    try:
      setCurrentDir($path)
    except OSError:
      status.commandLine.writeFileOpenError($path, status.messageLog)
      status.addNewBuffer("")
    status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSaveTime: now()))
  else:
    status.addNewBuffer($path)

    status.changeCurrentBuffer(status.bufStatus.high)

proc setDirListColor(kind: PathComponent,
                     isCurrentLine: bool): EditorColorPair =

  if isCurrentLine: result = EditorColorPair.currentFile
  else:
    case kind
    of pcFile: result = EditorColorPair.file
    of pcDir: result = EditorColorPair.dir
    of pcLinkToDir, pcLinkToFile: result = EditorColorPair.pcLink

proc initFilelistHighlight[T](dirList: seq[PathInfo],
                              buffer: T,
                              currentLine: int): Highlight =

  for index, dir in dirList:
    let color = setDirListColor(dir.kind, index == currentLine)
    result.colorSegments.add(ColorSegment(firstRow: index,
                                          firstColumn: 0,
                                          lastRow: index,
                                          lastColumn: buffer[index].len,
                                          color: color))

proc pathToIcon(path: string): seq[Rune] =
  if dirExists(path):
    return ru"📁 "

  # Not sure if this is a perfect solution,
  # it should detect if the current user can execute
  # the file or not:
  try:
    let permissions = getFilePermissions(path)
    if fpUserExec  in permissions or
      fpGroupExec in permissions:
      return ru"🏃 "
  except:
    discard

  # The symbols were selected for their looks,
  # they don't always have to make perfect sense,
  # there's simply not a symbol for every possible
  # file extension in unicode.
  let ext = path.split(".")[^1]
  case ext.toLower():
  of "nim":
    return ru"👑 "
  of "nimble", "rpm", "deb":
    return ru"📦 "
  of "py":
    return ru"🐍 "
  of "ui", "glade":
    return ru"🏠 "
  of "txt", "md", "rst":
    return ru"📝 "
  of "cpp", "cxx", "hpp":
    return ru"⧺ "
  of "c", "h":
    return ru"🅒 "
  of "java":
    return ru"🍵 "
  of "php":
    return ru"🙈 "
  of "js", "json":
    return ru"🙉 "
  of "html", "xhtml":
    return ru"🏄 "
  of "css":
    return ru"👚 "
  of "xml":
    return ru"༕ "
  of "cfg", "ini":
    return ru"🍳 "
  of "sh":
    return ru"🐚 "
  of "pdf", "doc", "odf", "ods", "odt":
    return ru"🍞 "
  of "wav", "mp3", "ogg":
    return ru"🎼 "
  of "zip", "bz2", "xz", "gz", "tgz", "zstd":
    return ru"🚢 "
  of "exe", "bin":
    return ru"🏃 "
  of "mp4", "webm", "avi", "mpeg":
    return ru"🎞 "
  of "patch":
    return ru"💊 "
  of "lock":
    return ru"🔒 "
  of "pem", "crt":
    return ru"🔏 "
  of "png", "jpeg", "jpg", "bmp", "gif":
    return ru"🎨 "
  else:
    return ru"🍕 "

  # useful unicode symbols: that aren't used here yet:
  # open book        : 📖
  # penguin          : 🐧
  # open file folder : 📂
  #
proc fileNameToGapBuffer(bufStatus: var BufferStatus,
                         windowNode: WindowNode,
                         settings: EditorSettings,
                         filerStatus: FilerStatus,
                         terminalHeight, terminalWidth: int) =

  bufStatus.buffer = initGapBuffer[seq[Rune]]()

  for index, dir in filerStatus.dirList:
    proc expandSymLinkOrFilename(filename: string): string =
      try: expandSymLink(filename)
      except OSError: filename

    let
      filename = dir.path
      kind = dir.kind

    var newLine = if kind == pcLinkToFile or kind == pcLinkToDir:
                    filename.toRunes
                  else:
                    toRunes(splitPath(filename).tail)
    case kind
    of pcFile:
      try:
        if isFifo(filename): newLine.add(ru '|')
      except OSError:
        discard
    of pcDir:
      newLine.add(ru DirSep)
    of pcLinkToFile:
      newLine.add(ru"@ -> " & expandSymLinkOrFilename(filename).toRunes)
    of pcLinkToDir:
      newLine.add(ru"@ -> " & toRunes(expandSymLinkOrFilename(filename) / $DirSep))

    # Set icons
    if settings.filerSettings.showIcons: newLine.insert(pathToIcon(filename), 0)

    bufStatus.buffer.add(newLine)

  let useStatusBar = if settings.statusLine.enable: 1 else: 0
  let numOfFile = filerStatus.dirList.len
  windowNode.highlight = initFilelistHighlight(filerStatus.dirList,
                                               bufStatus.buffer,
                                               windowNode.currentLine)
  windowNode.view = initEditorView(bufStatus.buffer,
                                   terminalHeight - useStatusBar - 1,
                                   terminalWidth - numOfFile)

proc updateFilerView*(status: var EditorStatus,
                      filerStatus: var FilerStatus,
                      terminalHeight, terminalWidth: int) =

  fileNameToGapBuffer(currentBufStatus,
                      currentMainWindowNode,
                      status.settings,
                      filerStatus,
                      terminalHeight,
                      terminalWidth)
  status.resize(terminalHeight, terminalWidth)
  status.update
  filerStatus.viewUpdate = false

proc initFileDeitalHighlight[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(firstRow: i,
                                          firstColumn: 0,
                                          lastRow: i,
                                          lastColumn: buffer[i].len,
                                          color: EditorColorPair.defaultChar))

proc writefileDetail(status: var Editorstatus,
                     numOfFile: int,
                     fileName: string,
                     terminalHeight, terminalWidth: int) =

  currentBufStatus.buffer = initGapBuffer[seq[Rune]]()

  let fileInfo = getFileInfo(fileName, false)
  currentBufStatus.buffer.add(ru"name        : " & fileName.toRunes)

  if fileInfo.kind == pcFile:
    currentBufStatus.buffer.add(ru"kind        : " & ru"File")
  elif fileInfo.kind == pcDir:
    currentBufStatus.buffer.add(ru"kind        : " & ru"Directory")
  elif fileInfo.kind == pcLinkToFile:
    currentBufStatus.buffer.add(ru"kind        : " & ru"Symbolic link to file")
  elif fileInfo.kind == pcLinkToDir:
    currentBufStatus.buffer.add(ru"kind        : " & ru"Symbolic link to directory")

  currentBufStatus.buffer.add(("size        : " & $fileInfo.size & " bytes").toRunes)
  currentBufStatus.buffer.add(("permissions : " & substr($fileInfo.permissions,
                                                         1,
                                                         ($fileInfo.permissions).high - 1)).toRunes)
  currentBufStatus.buffer.add(("create time : " & $fileInfo.creationTime).toRunes)
  currentBufStatus.buffer.add(("last write  : " & $fileInfo.lastWriteTime).toRunes)
  currentBufStatus.buffer.add(("last access : " & $fileInfo.lastAccessTime).toRunes)

  let buffer = currentBufStatus.buffer
  currentMainWindowNode.highlight = initFileDeitalHighlight(buffer)

  var windowNode = currentMainWindowNode
  let
    useStatusBar = if status.settings.statusLine.enable: 1 else: 0
    tmpCurrentLine = windowNode.currentLine

  windowNode.view = initEditorView(currentBufStatus.buffer,
                                   terminalHeight - useStatusBar - 1,
                                   terminalWidth - numOfFile)
  windowNode.currentLine = 0

  status.update
  setCursor(false)
  while isResizekey(currentMainWindowNode.getKey):
    status.resize(terminalHeight, terminalWidth)
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
  filerStatus.dirList = status.searchFiles(filerStatus.dirList)
  filerStatus.viewUpdate = true

  currentMainWindowNode.currentLine = 0

  if filerStatus.dirList.len == 0:
    currentMainWindowNode.eraseWindow
    currentMainWindowNode.window.get.write(0, 0, "not found", EditorColorPair.commandBar)
    currentMainWindowNode.refreshWindow
    discard status.commandLine.getKey
    status.commandLine.erase
    filerStatus.dirlistUpdate = true

proc filerMode*(status: var EditorStatus) =
  var filerStatus = initFilerStatus()

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  block:
    filerStatus = filerStatus.updateDirList(currentBufStatus.path)
    filerStatus.dirlistUpdate = false

    status.updateFilerView(filerStatus, terminalHeight(), terminalWidth())

    currentMainWindowNode.restoreCursorPostion(
      currentBufStatus,
      status.lastPosition)

    status.updateFilerView(filerStatus, terminalHeight(), terminalWidth())
    filerStatus.viewUpdate = false

  while isFilerMode(currentBufStatus.mode) and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    if filerStatus.dirlistUpdate:
      let path = currentBufStatus.path

      filerStatus = filerStatus.updateDirList(path)

      if currentMainWindowNode.currentLine > filerStatus.dirList.high:
        currentMainWindowNode.currentLine = filerStatus.dirList.high

    if filerStatus.viewUpdate:
      status.updateFilerView(filerStatus, terminalHeight(), terminalWidth())

    setCursor(false)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    if key == ord(':'): status.changeMode(Mode.ex)

    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      filerStatus.viewUpdate = true

    elif key == ord('/'): status.searchFileMode(filerStatus)

    elif isEscKey(key):
      if filerStatus.searchMode == true:
        filerStatus.dirlistUpdate = true
        filerStatus.searchMode = false
    elif key == ord('D'):
      deleteFile(status, filerStatus)
    elif key == ord('i'):
      status.writeFileDetail(
        filerStatus.dirList.len,
        filerStatus.dirList[currentMainWindowNode.currentLine][1],
        terminalHeight(),
        terminalWidth())
      filerStatus.viewUpdate = true
    elif key == 'j' or isDownKey(key):
      filerStatus.keyDown(currentMainWindowNode.currentLine)
    elif key == ord('k') or isUpKey(key):
      filerStatus.keyUp(currentMainWindowNode.currentLine)
    elif key == ord('g'):
      filerStatus.moveToTopOfList(currentMainWindowNode.currentLine)
    elif key == ord('G'):
      filerStatus.moveToLastOfList(currentMainWindowNode.currentLine)
    elif key == ord('y'):
      filerStatus.copyFile(currentMainWindowNode.currentLine,
                           currentBufStatus.path)
    elif key == ord('C'):
      filerStatus.cutFile(currentMainWindowNode.currentLine,
                          currentBufStatus.path)
    elif key == ord('p'):
      status.commandLine.pasteFile(
        filerStatus,
        currentBufStatus.path,
        status.messageLog)
    elif key == ord('s'):
      filerStatus.changeSortBy
    elif key == ord('N'):
      status.createDir(filerStatus)
    elif key == ord('v'):
      status.openNewWinAndOpenFilerOrDir(
        filerStatus,
        terminalHeight(),
        terminalWidth())
    elif isControlJ(key):
      status.movePrevWindow
    elif isControlK(key):
      status.moveNextWindow
    elif isEnterKey(key):
      status.openFileOrDir(filerStatus)
