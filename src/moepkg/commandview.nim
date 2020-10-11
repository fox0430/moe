import terminal, strutils, sequtils, strformat, os, algorithm
import ui, unicodeext, fileutils, color, commandline

type
  ExModeViewStatus = tuple[
    buffer: seq[Rune],
    prompt: string,
    cursorY, cursorX, currentPosition, startPosition: int
  ]

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
    return strutils.splitWhitespace(command).map(proc(s: string): seq[Rune] = toRunes(s))

proc writeExModeView(commandLine: var CommandLine,
                     exStatus: ExModeViewStatus,
                     color: EditorColorPair) =

  let buffer = ($exStatus.buffer).substr(exStatus.startPosition, exStatus.buffer.len)

  commandLine.erase
  commandLine.window.write(exStatus.cursorY, 0, fmt"{exStatus.prompt}{buffer}", color)
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
    exStatus.buffer.delete(exStatus.currentPosition - 1, exStatus.currentPosition - 1)
    dec(exStatus.currentPosition)

proc deleteCommandBufferCurrentPosition(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0 and exStatus.currentPosition < exStatus.buffer.len:
    exStatus.buffer.delete(exStatus.cursorX - 1, exStatus.cursorX - 1)
    if exStatus.currentPosition > exStatus.buffer.len: dec(exStatus.currentPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus, r: Rune) =
  exStatus.buffer.insert(r, exStatus.currentPosition)
  inc(exStatus.currentPosition)
  if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
  else: inc(exStatus.startPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus, runes: seq[Rune]) {.inline.} =
  for r in runes:
    exStatus.insertCommandBuffer(r)

import editorstatus
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

proc suggestFilePath(status: var Editorstatus,
                     exStatus: var ExModeViewStatus,
                     command: string,
                     key: var Rune) =

  let inputPath = if (exStatus.buffer.substr(command.len + 1)) == ru"~":
                    getHomeDir().toRunes
                  else:
                    exStatus.buffer.substr(command.len + 1)
  var suggestlist = @[inputPath]
  if inputPath.len == 0 or not inputPath.contains(ru'/'):
    for kind, path in walkDir("./"):
      if path.toRunes.normalizePath.startsWith(inputPath):
        suggestlist.add(path.toRunes.normalizePath)
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
          suggestlist.add(addPath)
        else:
          suggestlist.add(path.toRunes)

  suggestlist.sort(proc (a, b: seq[Rune]): int = cmp($a, $b))

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    # Pop up window position
    positionInInputPath = if inputPath.rfind(ru"/") > 0: inputPath.rfind(ru"/")
                          else: 0
    # +2 is pronpt and space
    x = command.len + 2 + positionInInputPath
    y = terminalHeight() - 1
    popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  # TODO: I don't know why yet, but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    exStatus.buffer = (command & " ").toRunes
    exStatus.currentPosition = command.len + 1
    exStatus.cursorX = command.len + 2

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1

      var displayBuffer: seq[seq[Rune]] = @[]
      if suggestlist[1].contains(ru'/'):
        for i in 1 ..< suggestlist.len:
          let path = suggestlist[i]
          displayBuffer.add(path[path.rfind(ru'/') + 1 ..< path.len])
      else: displayBuffer = suggestlist[1 ..< suggestlist.len]

      var (h, w) = displayBuffer.calcPopUpWindowSize
      popUpWindow.writePopUpWindow(h, w, y, x, currentLine, displayBuffer)

    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)
    if suggestlist.len == 1:
      status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
      return

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = status.commandLine.getKey

proc isExCommand(exBuffer: seq[Rune]): bool =
  if ($exBuffer).contains(" ") == false: return false

  let buffer = ($exBuffer).splitWhitespace(-1)
  for i in 0 ..< exCommandList.len:
    if buffer[0] == $exCommandList[i]:
      result = true
      break

proc suggestExCommandOption(status: var Editorstatus,
                            exStatus: var ExModeViewStatus,
                            key: var Rune) =

  var argList: seq[string] = @[]
  let command = (splitWhitespace(exStatus.buffer))[0]

  case toLowerAscii($command):
    of "cursorLine",
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
       "smartcase":
      argList = @["on", "off"]
    of "theme":
      argList= @["vivid", "dark", "light", "config", "vscode"]
    of "e",
       "sp",
       "vs",
       "sv":
      status.suggestFilePath(exStatus, $command, key)
    else: discard

  let  arg = if (splitWhitespace(exStatus.buffer)).len > 1:
               (splitWhitespace(exStatus.buffer))[1]
             else: ru""
  var suggestlist: seq[seq[Rune]] = @[arg]

  for i in 0 ..< argList.len:
    if argList[i].startsWith($arg): suggestlist.add(argList[i].toRunes)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    # +1 is space
    x = command.len + 1
    y = terminalHeight() - 1

    popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    exStatus.currentPosition = 0
    exStatus.cursorX = 1
    exStatus.buffer = ru""

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let
        currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
        displayBuffer = suggestlist[1 ..< suggestlist.len]
      # Pop up window size
      var (h, w) = displayBuffer.calcPopUpWindowSize

      popUpWindow.writePopUpWindow(h, w, y, x, currentLine, displayBuffer)

    for rune in command & ru' ': exStatus.insertCommandBuffer(rune)
    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = status.commandLine.getKey

proc suggestExCommand(status: var Editorstatus,
                      exStatus: var ExModeViewStatus,
                      key: var Rune) =

  var suggestlist: seq[seq[Rune]] = @[exStatus.buffer]
  let buffer = toLowerAscii($exStatus.buffer)
  for str in exCommandList:
    if str.len >= buffer.len and
       str.startsWith(buffer): suggestlist.add(str.toRunes)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

    popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    exStatus.buffer = ru""
    exStatus.currentPosition = 0
    exStatus.cursorX = 1

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let
        currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
        displayBuffer = suggestlist[1 ..< suggestlist.len]
      # Pop up window size
      var (h, w) = displayBuffer.calcPopUpWindowSize

      popUpWindow.writePopUpWindow(h, w, y, x, currentLine, displayBuffer)

    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = status.commandLine.getKey

proc suggestMode(status: var Editorstatus,
                 exStatus: var ExModeViewStatus,
                 key: var Rune) =

  if exStatus.buffer.len > 0 and exStatus.buffer.isExCommand:
    status.suggestExCommandOption(exStatus, key)
  else: suggestExCommand(status, exStatus, key)
  status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
  if status.settings.popUpWindowInExmode: status.deletePopUpWindow

  while isTabKey(key) or isShiftTab(key):
    key = status.commandLine.getKey

proc getKeyOnceAndWriteCommandView*(status: var Editorstatus,
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


