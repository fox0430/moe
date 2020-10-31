import terminal, strutils, sequtils, strformat, os, algorithm
import ui, unicodetext, fileutils, color, commandline

type ExModeViewStatus = object
    buffer: seq[Rune]
    prompt: string
    cursorY: int
    cursorX: int
    currentPosition: int
    startPosition: int

type SuggestType = enum
  exCommand
  exCommandOption
  filePath

const exCommandList = [
  "!",
  "deleteParen",
  "b",
  "bd",
  "bfirst",
  "blast",
  "bnext",
  "bprev",
  "buildOnSave",
  "buf",
  "clipboard",
  "conf",
  "cursorLine",
  "cws",
  "debug",
  "deleteTrailingSpaces",
  "dws",
  "e",
  "ene",
  "help",
  "highlightCurrentWord",
  "highlightFullSpace",
  "highlightParen",
  "history",
  "icon",
  "ignorecase",
  "incrementalSearch",
  "indent",
  "indentationLines",
  "linenum",
  "liveReload",
  "log",
  "ls",
  "lsw",
  "multipleStatusbar",
  "new",
  "noh",
  "paren",
  "putConfigFile",
  "q",
  "Q",
  "q!",
  "qa",
  "qa!",
  "recent",
  "run",
  "scrollSpeed",
  "showGitInactive",
  "smartcase",
  "smoothScroll",
  "sp",
  "statusbar",
  "syntax",
  "tab",
  "tabstop",
  "theme",
  "vs",
  "w",
  "w!",
  "ws",
  "wq",
  "wq!",
  "wqa",
]

proc askCreateDirPrompt*(commndLine: var CommandLine,
                         messageLog: var seq[seq[Rune]],
                         path: string): bool =

  let mess = fmt"{path} does not exists. Create it now?: y/n"
  commndLine.updateCommandLineBuffer(mess)
  commndLine.updateCommandLineView
  messageLog.add(mess.toRunes)

  let key = commndLine.getKey

  if key == ord('y'): result = true
  else: result = false

proc askBackupRestorePrompt*(commndLine: var CommandLine,
                             messageLog: var seq[seq[Rune]],
                             filename: seq[Rune]): bool =

  let mess = fmt"Restore {filename}?: y/n"
  commndLine.updateCommandLineBuffer(mess)
  commndLine.updateCommandLineView
  messageLog.add(mess.toRunes)

  let key = commndLine.getKey

  if key == ord('y'): result = true
  else: result = false

proc askDeleteBackupPrompt*(commndLine: var CommandLine,
                            messageLog: var seq[seq[Rune]],
                            filename: seq[Rune]): bool =

  let mess = fmt"Delete {filename}?: y/n"
  commndLine.updateCommandLineBuffer(mess)
  commndLine.updateCommandLineView
  messageLog.add(mess.toRunes)

  let key = commndLine.getKey

  if key == ord('y'): result = true
  else: result = false

proc askFileChangedSinceReading*(commndLine: var CommandLine,
                                 messageLog: var seq[seq[Rune]]): bool =

  block:
    const warnMess = "WARNING: The file has been changed since reading it!: Press any key"
    commndLine.updateCommandLineBuffer(warnMess)
    commndLine.updateCommandLineView
    messageLog.add(warnMess.toRunes)
    discard commndLine.getKey

  block:
    const askMess = "Do you really want to write to it: y/n ?"
    commndLine.updateCommandLineBuffer(askMess)
    commndLine.updateCommandLineView
    messageLog.add(askMess.toRunes)
    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc removeSuffix(r: seq[seq[Rune]], suffix: string): seq[seq[Rune]] =
  for i in 0 .. r.high:
    var string = $r[i]
    string.removeSuffix(suffix)
    if i == 0: result = @[string.toRunes]
    else: result.add(string.toRunes)

proc splitQout(s: string): seq[seq[Rune]]=
  result = @[ru""]
  var quotIn = false
  var backSlash = false

  for i in 0 .. s.high:
    if s[i] == '\\':
      backSlash = true
    elif backSlash:
      backSlash = false
      result[result.high].add(($s[i]).toRunes)
    elif i > 0 and s[i - 1] == '\\':
      result[result.high].add(($s[i]).toRunes)
    elif not quotIn and s[i] == '"':
      quotIn = true
      result.add(ru"")
    elif quotIn and s[i] == '"':
      quotIn = false
      if i != s.high:  result.add(ru"")
    else:
      result[result.high].add(($s[i]).toRunes)

  return result.removeSuffix(" ")

proc splitCommand*(command: string): seq[seq[Rune]] =
  if (command).contains('"'):
    return splitQout(command)
  else:
    return strutils.splitWhitespace(command)
                    .map(proc(s: string): seq[Rune] = toRunes(s))

proc writeExModeView(commandLine: var CommandLine,
                     exStatus: ExModeViewStatus,
                     color: EditorColorPair) =

  let buffer = ($exStatus.buffer).substr(exStatus.startPosition,
                                         exStatus.buffer.len)

  commandLine.erase
  commandLine.window.write(exStatus.cursorY,
                           0,
                           fmt"{exStatus.prompt}{buffer}",
                           color)
  commandLine.window.moveCursor(0, exStatus.cursorX)
  commandLine.window.refresh

proc initExModeViewStatus(prompt: string): ExModeViewStatus =
  result.buffer = ru""
  result.prompt = prompt
  result.cursorY = 0
  result.cursorX = 1

proc moveLeft(commandWindow: Window, exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition > 0:
    dec(exStatus.currentPosition)
    if exStatus.cursorX > exStatus.prompt.len: dec(exStatus.cursorX)
    else: dec(exStatus.startPosition)

proc moveRight(exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition < exStatus.buffer.len:
    inc(exStatus.currentPosition)
    if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
    else: inc(exStatus.startPosition)

proc moveTop(exStatus: var ExModeViewStatus) =
  exStatus.cursorX = exStatus.prompt.len
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc moveEnd(exStatus: var ExModeViewStatus) =
  exStatus.currentPosition = exStatus.buffer.len - 1
  if exStatus.buffer.len > terminalWidth():
    exStatus.startPosition = exStatus.buffer.len - terminalWidth()
    exStatus.cursorX = terminalWidth()
  else:
    exStatus.startPosition = 0
    exStatus.cursorX = exStatus.prompt.len + exStatus.buffer.len - 1

proc clearCommandBuffer(exStatus: var ExModeViewStatus) =
  exStatus.buffer = ru""
  exStatus.cursorY = 0
  exStatus.cursorX = 1
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc deleteCommandBuffer(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0:
    if exStatus.buffer.len < terminalWidth(): dec(exStatus.cursorX)
    exStatus.buffer.delete(exStatus.currentPosition - 1,
                           exStatus.currentPosition - 1)
    dec(exStatus.currentPosition)

proc deleteCommandBufferCurrentPosition(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0 and exStatus.currentPosition < exStatus.buffer.len:
    exStatus.buffer.delete(exStatus.cursorX - 1, exStatus.cursorX - 1)
    if exStatus.currentPosition > exStatus.buffer.len:
      dec(exStatus.currentPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus, r: Rune) =
  exStatus.buffer.insert(r, exStatus.currentPosition)
  inc(exStatus.currentPosition)
  if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
  else: inc(exStatus.startPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus,
                         runes: seq[Rune]) {.inline.} =

  for r in runes:
    exStatus.insertCommandBuffer(r)

import editorstatus
# Search text in buffer
proc getKeyword*(status: var EditorStatus,
                 prompt: string,
                 isSearch: bool): (seq[Rune], bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      exStatus.clearCommandBuffer
      inc searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): exStatus.moveRight
    elif isUpKey(key) and isSearch: setPrevSearchHistory()
    elif isDownKey(key) and isSearch: setNextSearchHistory()
    elif isHomeKey(key): exStatus.moveTop
    elif isEndKey(key): exStatus.moveEnd
    elif isBackspaceKey(key): exStatus.deleteCommandBuffer
    elif isDcKey(key): exStatus.deleteCommandBufferCurrentPosition
    else: exStatus.insertCommandBuffer(key)

  return (exStatus.buffer, cancelSearch)

proc calcPopUpWindowSize(buffer: seq[seq[Rune]]): (int, int) =
  var maxBufferLen = 0
  for runes in buffer:
    if maxBufferLen < runes.len: maxBufferLen = runes.len
  let
    height = if buffer.len > terminalHeight() - 1: terminalHeight() - 1
        else: buffer.len
    width = maxBufferLen + 2

  return (height, width)

proc getInputPath(buffer, cmd: seq[Rune]): seq[Rune] =
  if (buffer.substr(cmd.len + 1)) == ru"~":
    getHomeDir().toRunes
  else:
    buffer.substr(cmd.len + 1)

proc getCandidatesFilePath(buffer: seq[Rune],
                           command: string): seq[string] =

  let inputPath = getInputPath(buffer, command.ru)

  var list: seq[seq[Rune]] = @[]
  if inputPath.len > 0: list.add(inputPath)

  if inputPath.len == 0 or not inputPath.contains(ru'/'):
    for kind, path in walkDir("./"):
      if path.toRunes.normalizePath.startsWith(inputPath):
        list.add(path.toRunes.normalizePath)
  elif inputPath.contains(ru'/'):
    let
      normalizedInput = normalizePath(inputPath)
      normalizedPath = normalizePath(inputPath.substr(0, inputPath.rfind(ru'/')))
    for kind, path in walkDir($normalizedPath):
      if path.toRunes.len > normalizedInput.len and
            path.toRunes.startsWith(normalizedInput):
        if inputPath[0] == ru'~':
          let
            pathLen = path.toRunes.high
            hoemeDirLen = (getHomeDir()).high
            addPath = ru"~" & path.toRunes.substr(hoemeDirLen, pathLen)
          list.add(addPath)
        else:
          list.add(path.toRunes)

  for path in list: result.add($path)
  result.sort(proc (a, b: string): int = cmp(a, b))

proc isExCommand(exBuffer: seq[Rune]): bool =
  if ($exBuffer).contains(" ") == false: return false

  let buffer = ($exBuffer).splitWhitespace(-1)
  for i in 0 ..< exCommandList.len:
    if buffer[0] == $exCommandList[i]: return true

proc getCandidatesExCommandOption(status: var Editorstatus,
                                  exStatus: var ExModeViewStatus,
                                  command: string): seq[seq[Rune]] =

  var argList: seq[string] = @[]
  case toLowerAscii($command):
    of "cursorline",
       "highlightparen",
       "indent",
       "linenum",
       "livereload",
       "realtimesearch",
       "statusbar",
       "syntax",
       "tabstop",
       "smoothscroll",
       "clipboard",
       "highlightcurrentword",
       "highlightfullspace",
       "multiplestatusbar",
       "buildonsave",
       "indentationlines",
       "icon",
       "showgitinactive",
       "ignorecase",
       "smartcase": argList = @["on", "off"]
    of "theme": argList= @["vivid", "dark", "light", "config", "vscode"]
    of "e",
       "sp",
       "vs",
       "sv": argList = getCandidatesFilePath(exStatus.buffer, command)
    else: discard

  let  arg = if (splitWhitespace(exStatus.buffer)).len > 1:
               (splitWhitespace(exStatus.buffer))[1]
             else: ru""
  result = @[arg]

  for i in 0 ..< argList.len:
    if argList[i].startsWith($arg): result.add(argList[i].toRunes)

proc getCandidatesExCommand(commandLineBuffer: seq[Rune]): seq[seq[Rune]] =
  result = @[commandLineBuffer]
  let buffer = toLowerAscii($commandLineBuffer)
  for str in exCommandList:
    if str.len >= buffer.len and str.startsWith(buffer):
      result.add(str.toRunes)

proc getSuggestType(buffer: seq[Rune]): SuggestType =
  template isECommand(command: seq[seq[Rune]]): bool =
    command.len == 2 and cmpIgnoreCase($command[0], "e") == 0

  template isVsCommand(command: seq[seq[Rune]]): bool =
    command.len == 2 and cmpIgnoreCase($command[0], "vs") == 0

  template isSvCommand(command: seq[seq[Rune]]): bool =
    command.len == 1 and cmpIgnoreCase($command[0], "sv") == 0

  template isSpCommand(command: seq[seq[Rune]]): bool =
    command.len > 0 and
    command.len < 3 and
    cmpIgnoreCase($command[0], "sp") == 0

  if buffer.len > 0 and buffer.isExCommand:
    let cmd = splitCommand($buffer)
    if isECommand(cmd) or
       isVsCommand(cmd) or
       isSvCommand(cmd) or
       isSpCommand(cmd): SuggestType.filePath
    else:
      SuggestType.exCommandOption
  else:
    SuggestType.exCommand

proc isSuggestTypeExCommand(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommand

proc isSuggestTypeExCommandOption(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommandOption

proc isSuggestTypeFilePath(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.filePath

proc getSuggestList(status: var Editorstatus,
                    exStatus: var ExModeViewStatus,
                    suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeExCommand(suggestType):
    result = getCandidatesExCommand(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    let cmd = $(splitWhitespace(exStatus.buffer))[0]
    result = status.getCandidatesExCommandOption(exStatus, cmd)
  else:
    let
      cmd = (splitWhitespace(exStatus.buffer))[0]
      pathList = getCandidatesFilePath(exStatus.buffer, $cmd)
    for path in pathList: result.add(path.ru)

proc calcXWhenSuggestPath(buffer: seq[Rune]): int =
  let
    cmd = (splitWhitespace(buffer))[0]
    inputPath = getInputPath(buffer, cmd)
    positionInInputPath = if inputPath.rfind(ru"/") > 0:
                            inputPath.rfind(ru"/")
                          else:
                            0
  # +2 is pronpt and space
  return cmd.len + 2 + positionInInputPath

proc initDisplayBuffer(suggestlist: seq[seq[Rune]],
                       suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeFilePath(suggestType):
    if suggestlist[1].contains(ru'/'):
      for i in 1 ..< suggestlist.len:
        let path = suggestlist[i]
        result.add(path[path.rfind(ru'/') + 1 ..< path.len])
    else: result = suggestlist[1 ..< suggestlist.len]
  else:
    result = suggestlist[1 ..< suggestlist.len]

proc suggestCommandLine(status: var Editorstatus,
                        exStatus: var ExModeViewStatus,
                        key: var Rune) =

  let
    suggestType = getSuggestType(exStatus.buffer)
    suggestlist = status.getSuggestList(exStatus, suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if exStatus.buffer.len > 0:
                  (splitWhitespace(exStatus.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      exStatus.buffer = command & ru" "
      exStatus.currentPosition = command.len + exStatus.prompt.len
      exStatus.cursorX = exStatus.currentPosition
    else:
      exStatus.buffer = ru""
      exStatus.currentPosition = 0
      exStatus.cursorX = 0

  # TODO: I don't know why yet, but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let
        currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
        displayBuffer = initDisplayBuffer(suggestlist, suggestType)
      # Pop up window size
      var (h, w) = displayBuffer.calcPopUpWindowSize

      popUpWindow.writePopUpWindow(h, w, y, x,
                                   terminalHeight(), terminalWidth(),
                                   currentLine,
                                   displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      exStatus.insertCommandBuffer(command & ru' ')

    exStatus.insertCommandBuffer(suggestlist[suggestIndex])
    exStatus.cursorX.inc

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = status.commandLine.getKey
    exStatus.cursorX = exStatus.currentPosition + 1

  status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
  if status.settings.popUpWindowInExmode: status.deletePopUpWindow

proc suggestMode(status: var Editorstatus,
                 exStatus: var ExModeViewStatus,
                 key: var Rune) =

  status.suggestCommandLine(exStatus, key)

  while isTabKey(key) or isShiftTab(key):
    key = status.commandLine.getKey

proc getKeyOnceAndWriteCommandView*(
  status: var Editorstatus,
  prompt: string,
  buffer: seq[Rune],
  isSuggest, isSearch : bool): (seq[Rune], bool, bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    exitSearch = false
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high
    commandHistoryIndex = status.exCommandHistory.high
  for rune in buffer: exStatus.insertCommandBuffer(rune)

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      exStatus.clearCommandBuffer
      inc searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextCommandHistory() =
    if commandHistoryIndex < status.exCommandHistory.high:
      exStatus.clearCommandBuffer
      inc commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  template setPrevCommandHistory() =
    if commandHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestMode(exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
        status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)

    if isEnterKey(key):
      exitSearch = true
      break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key):
      status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key):
      exStatus.moveRight
    elif isUpKey(key):
      if isSearch: setPrevSearchHistory()
      else: setPrevCommandHistory()
    elif isDownKey(key):
      if isSearch: setNextSearchHistory()
      else: setNextCommandHistory()
    elif isHomeKey(key):
      exStatus.moveTop
    elif isEndKey(key):
      exStatus.moveEnd
    elif isBackspaceKey(key):
      exStatus.deleteCommandBuffer
      break
    elif isDcKey(key):
      exStatus.deleteCommandBufferCurrentPosition
      break
    else:
      exStatus.insertCommandBuffer(key)
      break

  status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
  return (exStatus.buffer, exitSearch, cancelSearch)

proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var exStatus = initExModeViewStatus(prompt)
  status.resize(terminalHeight(), terminalWidth())

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      suggestMode(status, exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
          status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
          key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandLine.erase
      return @[ru""]
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return splitCommand($exStatus.buffer)
