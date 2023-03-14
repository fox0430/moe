#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[os, strutils, times, algorithm, sequtils,
            options, strformat]
import ui, fileutils, editorview, gapbuffer, highlight, window,
       color, bufferstatus, settings, messages, commandline, unicodeext

type
  PathInfo* = tuple[
    kind: PathComponent,
    path: string,
    size: int64,
    lastWriteTime: times.Time]

  Sort = enum
    name = 0
    fileSize = 1
    time = 2

  FileRegister* = object
    copy: bool
    cut: bool
    originPath: string
    filename: string

  FilerStatus* = object
    register: FileRegister
    searchMode*: bool
    isUpdateView*: bool
    isUpdatePathList*: bool
    pathList*: seq[PathInfo]
    sortBy: Sort

proc initFileRegister(): FileRegister {.inline.} =
  result.copy = false
  result.cut = false
  result.originPath = ""
  result.filename = ""

proc initFilerStatus*(): FilerStatus {.inline.} =
  FilerStatus(
    register: initFileRegister(),
    isUpdateView: true,
    isUpdatePathList: true,
    pathList: newSeq[PathInfo](),
    sortBy: name,
    searchMode: false)

proc searchFiles(
  pathList: seq[PathInfo],
  keyword: string): seq[PathInfo] =

  for dir in pathList:
    if dir.path.contains(keyword): result.add dir

## Return a message.
## TODO: Return `Result` type.
proc deleteFile*(pathInfo: PathInfo): tuple[ok: bool, mess: Runes] =
  if pathInfo.kind == pcDir:
    try:
      removeDir(pathInfo.path)
    except OSError:
      let errMess = fmt"Failed to remove directory: {getCurrentExceptionMsg()}"
      return (false, errMess.toRunes)
  else:
    try:
      removeFile(pathInfo.path)
    except CatchableError:
      let errMess = fmt"Failed to remove file: {getCurrentExceptionMsg()}"
      return (false, errMess.toRunes)

  let mess = "Deleted: " & pathInfo.path
  return (true, mess.toRunes)

proc sortDirList(pathList: seq[PathInfo], sortBy: Sort): seq[PathInfo] =
  case sortBy:
  of name:
    return pathList.sortedByIt(it.path)
  of fileSize:
    result.add pathList.sortedByIt(it.size).reversed
  of time:
    result.add pathList.sortedByIt(it.lastWriteTime)

when defined(posix):
  from std/posix import nil
  from std/posix_utils import nil

  proc isFifo(file: string): bool {.inline.} =
    posix.S_ISFIFO(posix_utils.stat(file).st_mode)
else:
  proc isFifo(file: string): bool {.inline.} = false

proc refreshDirList(path: seq[Rune], sortBy: Sort): seq[PathInfo] =
  var
    pathList  : seq[PathInfo]
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
      pathList.add item
    else:
      fileList.add item

  return @[(pcDir,
            ParDir,
            0.int64,
            getLastModificationTime($path))] &
            sortDirList(pathList, sortBy) & sortDirList(fileList, sortBy)

proc updatePathList*(
  filerStatus: var FilerStatus,
  path: Runes) =
    filerStatus.pathList = refreshDirList(path, filerStatus.sortBy)
    filerStatus.isUpdateView = true
    filerStatus.isUpdatePathList = false

proc keyDown*(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine < filerStatus.pathList.high:
    inc(currentLine)
    filerStatus.isUpdateView = true

proc keyUp*(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine > 0:
    dec(currentLine)
    filerStatus.isUpdateView = true

proc moveToTopOfList*(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = 0
  filerStatus.isUpdateView = true

proc moveToLastOfList*(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = filerStatus.pathList.high
  filerStatus.isUpdateView = true

proc copyFile*(
  filerStatus: var FilerStatus,
  currentLine: int,
  currentPath: seq[Rune]) =
    filerStatus.register.copy = true
    filerStatus.register.cut = false
    filerStatus.register.filename = filerStatus.pathList[currentLine].path
    let path = filerStatus.pathList[currentLine].path
    filerStatus.register.originPath = $currentPath / path

proc cutFile*(
  filerStatus: var FilerStatus,
  currentLine: int,
  currentPath: seq[Rune]) =
    filerStatus.register.copy = false
    filerStatus.register.cut = true
    let path = filerStatus.pathList[currentLine].path
    filerStatus.register.filename = path
    filerStatus.register.originPath = $currentPath / path

proc pasteFile*(
  commandLine: var CommandLine,
  filerStatus: var FilerStatus,
  currentPath: seq[Rune]) =
    try:
      let filename = filerStatus.register.filename
      copyFile(filerStatus.register.originPath, $currentPath / filename)
      filerStatus.isUpdatePathList = true
      filerStatus.isUpdateView = true
    except OSError:
      commandLine.writeCopyFileError
      return

    if filerStatus.register.cut:
      let filename = filerStatus.register.filename
      if tryRemoveFile(filerStatus.register.originPath / filename):
        filerStatus.register.cut = false
      else: commandLine.writeRemoveFileError

## Get keys for a dir name and create a dir.
## Return error message if it failed.
## TODO: Return `Result` type
proc createDir*(
  filerStatus: var FilerStatus,
  commandLine: var CommandLine): Runes =

    const prompt = "Dir name: "
    if commandLine.getKeys(prompt):
      let dirName = $commandLine.buffer
      try:
        createDir(dirName)
      except OSError:
        let errMess = fmt"Failed to create directory: {getCurrentExceptionMsg()}"
        return errMess.toRunes

      filerStatus.isUpdatePathList = true

proc openFileOrDir*(
  bufStatuses: var seq[BufferStatus],
  windowNode: var WindowNode,
  filerStatus: var FilerStatus) =

    let
      kind = filerStatus.pathList[windowNode.currentLine].kind
      path = filerStatus.pathList[windowNode.currentLine].path
      bufferIndex = windowNode.bufferIndex

    case kind
      of pcFile, pcLinkToFile:
        try:
          bufStatuses.add initBufferStatus(path, Mode.filer)
        except CatchableError:
          # TODO: Show error message.
          discard
      of pcDir, pcLinkToDir:
        let currentPath = bufStatuses[bufferIndex].path
        if path == "..":
          if not isRootDir($currentPath):
            let parentDir = parentDir($currentPath).toRunes
            bufStatuses[bufferIndex].path = parentDir
        else:
          bufStatuses[bufferIndex].path = path.toRunes

        windowNode.currentLine = 0
        filerStatus.isUpdatePathList = true

proc setDirListColor(
  kind: PathComponent,
  isCurrentLine: bool): EditorColorPair =

    if isCurrentLine: result = EditorColorPair.currentFile
    else:
      case kind
      of pcFile: result = EditorColorPair.file
      of pcDir: result = EditorColorPair.dir
      of pcLinkToDir, pcLinkToFile: result = EditorColorPair.pcLink

proc initFilerHighlight*[T](
  filerStatus: FilerStatus,
  buffer: T,
  currentLine: int): Highlight =

    for index, dir in filerStatus.pathList:
      let color = setDirListColor(dir.kind, index == currentLine)
      result.colorSegments.add(ColorSegment(
        firstRow: index,
        firstColumn: 0,
        lastRow: index,
        lastColumn: buffer[index].len,
        color: color))

## Return true if Dockerfile or docker compose file.
proc isDockerFile(filename: string): bool {.inline.} =
 filename == "Dockerfile" or
 filename == "docker-compose.yml" or
 filename == "docker-compose.yaml" or
 filename == "compose.yaml" or
 filename == "compose.yml"

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
  except CatchableError:
    discard

  # The symbols were selected for their looks,
  # they don't always have to make perfect sense,
  # there's simply not a symbol for every possible
  # file extension in unicode.

  let filename = path.split("/")[^1]
  if filename.isDockerFile:
    return ru"🐳 "
  else:
    let ext = filename.split(".")[^1]
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
      of "rs":
        return ru"🦀 "
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

proc expandSymLinkOrFilename(filename: string): string {.inline.} =
  try:
    expandSymlink(filename)
  except OSError:
    filename

proc initFilerBuffer*(
  filerStatus: var FilerStatus,
  isShowIcons: bool): seq[Runes] =

    for index, dir in filerStatus.pathList:
      let
        filename = dir.path
        kind = dir.kind

      var newLine =
        if kind == pcLinkToFile or kind == pcLinkToDir:
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
      if isShowIcons:
        # Add an icon
        newLine.insert(pathToIcon(filename), 0)

      result.add(newLine)

proc initFileDeitalHighlight[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: buffer[i].len,
      color: EditorColorPair.defaultChar))

# TODO: Separate updating buffer and updating view.
proc writeFileDetail*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  settings: EditorSettings,
  numOfFile: int,
  fileName: string) =

    bufStatus.buffer = initGapBuffer[seq[Rune]]()

    let fileInfo = getFileInfo(fileName, false)

    # TODO: Insert indent automatically

    bufStatus.buffer.add(ru"name        : " & fileName.toRunes)

    if fileInfo.kind == pcFile:
      bufStatus.buffer.add(ru"kind        : " & ru"File")
    elif fileInfo.kind == pcDir:
      bufStatus.buffer.add(ru"kind        : " & ru"Directory")
    elif fileInfo.kind == pcLinkToFile:
      bufStatus.buffer.add(ru"kind        : " & ru"Symbolic link to file")
    elif fileInfo.kind == pcLinkToDir:
      bufStatus.buffer.add(ru"kind        : " & ru"Symbolic link to directory")

    bufStatus.buffer.add(("size        : " & $fileInfo.size & " bytes").toRunes)
    bufStatus.buffer.add(("permissions : " & substr($fileInfo.permissions,
                                                    1,
                                                    ($fileInfo.permissions).high - 1)).toRunes)
    bufStatus.buffer.add(("create time : " & $fileInfo.creationTime).toRunes)
    bufStatus.buffer.add(("last write  : " & $fileInfo.lastWriteTime).toRunes)
    bufStatus.buffer.add(("last access : " & $fileInfo.lastAccessTime).toRunes)

    windowNode.highlight = initFileDeitalHighlight(bufStatus.buffer)

    let
      useStatusBar = if settings.statusLine.enable: 1 else: 0
      tmpCurrentLine = windowNode.currentLine

    # TODO: Move
    windowNode.view = initEditorView(
      bufStatus.buffer,
      getTerminalHeight() - useStatusBar - 1,
      getTerminalWidth() - numOfFile)

    windowNode.currentLine = tmpCurrentLine

proc changeSortBy*(filerStatus: var FilerStatus) =
  case filerStatus.sortBy:
    of name: filerStatus.sortBy = fileSize
    of fileSize: filerStatus.sortBy = time
    of time: filerStatus.sortBy = name

  filerStatus.isUpdatePathList = true

proc searchFileMode*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  filerStatus: var FilerStatus,
  keyword: Runes) =

    filerStatus.searchMode = true
    filerStatus.pathList = filerStatus.pathList.searchFiles($keyword)
    filerStatus.isUpdateView = true

    windowNode.currentLine = 0

    if filerStatus.pathList.len == 0:
      # TODO: Fix
      windowNode.eraseWindow
      windowNode.window.get.write(0, 0, "Not found", EditorColorPair.commandBar)
      windowNode.refreshWindow
      filerStatus.isUpdatePathList = true

proc isFilerModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if key == ord(':') or
       key == ord('/') or
       key == ord('D') or
       key == ord('i') or
       key == 'j' or isDownKey(key) or
       key == ord('k') or isUpKey(key) or
       key == ord('g') or
       key == ord('G') or
       key == ord('y') or
       key == ord('C') or
       key == ord('p') or
       key == ord('s') or
       key == ord('N') or
       key == ord('v') or
       isEscKey(key) or
       isControlJ(key) or
       isControlK(key) or
       isEnterKey(key):
         return InputState.Valid
