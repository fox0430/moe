import std/[terminal, strutils, sequtils, strformat, os, algorithm]
import ui, unicodeext, fileutils, color, term

type
  CommandLine* = object
    buffer*: seq[Rune]
    prompt*: string
    cursorY*: int
    cursorX*: int
    currentPosition*: int
    startPosition*: int
    color*: EditorColorPair

  SuggestType* = enum
    exCommand
    exCommandOption
    filePath

const exCommandList: array[65, tuple[command, description: string]] = [
  (command: "!", description: "                    | Shell command execution"),
  (command: "deleteParen", description: "          | Enable/Disable auto delete paren"),
  (command: "b", description: "                    | Change the buffer with the given number"),
  (command: "bd", description: "                   | Delete the current buffer"),
  (command: "bfirst", description: "               | Change the first buffer"),
  (command: "blast", description: "                | Change the last buffer"),
  (command: "bnext", description: "                | Change the next buffer"),
  (command: "bprev", description: "                | Change the previous buffer"),
  (command: "build", description: "                | Build the current buffer"),
  (command: "buildOnSave", description: "          | Enable/Disable build on save"),
  (command: "buf", description: "                  | Open the buffer manager"),
  (command: "clipboard", description: "            | Enable/Disable accessing the system clipboard"),
  (command: "conf", description: "                 | Open the configuration mode"),
  (command: "cursorLine", description: "           | Change setting to the cursorLine"),
  (command: "cws", description: "                  | Create the work space"),
  (command: "debug", description: "                | Open the debug mode"),
  (command: "deleteTrailingSpaces", description: " | Delete the trailing spaces in the current buffer"),
  (command: "dws", description: "                  | Delete the current workspace"),
  (command: "e", description: "                    | Open file"),
  (command: "ene", description: "                  | Create the empty buffer"),
  (command: "help", description: "                 | Open the help"),
  (command: "highlightCurrentLine", description: " | Change setting to the highlightCurrentLine"),
  (command: "highlightCurrentWord", description: " | Change setting to the highlightCurrentWord"),
  (command: "highlightFullSpace", description: "   | Change setting to the highlightFullSpace"),
  (command: "highlightParen", description: "       | Change setting to the highlightParen"),
  (command: "history", description: "              | Open the history mode (Backup file manager)"),
  (command: "icon", description: "                 | Show/Hidden icons in filer mode"),
  (command: "ignorecase", description: "           | Change setting to ignore case in search"),
  (command: "incrementalSearch", description: "    | Enable/Disable incremental search"),
  (command: "indent", description: "               | Enable/Disable auto indent"),
  (command: "indentationLines", description: "     | Enable/Disable auto indentation lines"),
  (command: "linenum", description: "              | Enable/Disable the line number"),
  (command: "liveReload", description: "           | Enable/Disable the live reload of the config file"),
  (command: "log", description: "                  | Open the log viewer"),
  (command: "ls", description: "                   | Show the all buffer"),
  (command: "lsw", description: "                  | Show the all workspace"),
  (command: "multipleStatusLine", description: "    | Enable/Disable multiple status line"),
  (command: "new", description: "                  | Create the new buffer in split window horizontally"),
  (command: "noh", description: "                  | Turn off highlights"),
  (command: "paren", description: "                | Enable/Disable auto close paren"),
  (command: "putConfigFile", description: "        | Put the sample configuration file in ~/.config/moe"),
  (command: "q", description: "                    | Close the current window"),
  (command: "Q", description: "                    | Run Quickrun"),
  (command: "q!", description: "                   | Force close the current window"),
  (command: "qa", description: "                   | Close the all window in current workspace"),
  (command: "qa!", description: "                  | Force close the all window in current workspace"),
  (command: "recent", description: "               | Open the recent file selection mode"),
  (command: "run", description: "                  | run Quickrun"),
  (command: "scrollSpeed", description: "          | Change setting to the scroll speed"),
  (command: "showGitInactive", description: "      | Change status line setting to show/hide git branch name in inactive window"),
  (command: "smartcase", description: "            | Change setting to smart case in search"),
  (command: "smoothScroll", description: "         | Enable/Disable the smooth scroll"),
  (command: "sp", description: "                   | Open the file in horizontal split window"),
  (command: "statusLine", description: "            | Enable/Disable the status line"),
  (command: "syntax", description: "               | Enable/Disable the syntax highlighting"),
  (command: "tab", description: "                  | Enable/Disable the tab line"),
  (command: "tabstop", description: "              | Change setting to the tabstop"),
  (command: "theme", description: "                | Change the color theme"),
  (command: "vs", description: "                   | Vertical split window"),
  (command: "w", description: "                    | Write file"),
  (command: "w!", description: "                   | Force write file"),
  (command: "ws", description: "                   | Change the current workspace"),
  (command: "wq", description: "                   | Write file and close window"),
  (command: "wq!", description: "                  | Force write file and close window"),
  (command: "wqa", description: "                  | Write all file in current workspace")
]

# Clear the buffer
proc clear*(commndLine: var CommandLine) =
  commndLine.buffer = @[]

proc writeExModeView*(commandLine: CommandLine,
                      color: EditorColorPair) =

  let buffer = ($commandLine.buffer).substr(
    commandLine.startPosition,
    commandLine.buffer.len)

  # TODO: Enable color
  #commandLine.write(
  #  commandLine.cursorY,
  #  0,
  #  fmt"{commandLine.prompt}{buffer}",
  #  color)

  const x = 0
  let y = terminalHeight() - 1
  write(x, y, fmt"{commandLine.prompt}{buffer}")

  # TODO: Enable cursor
  #commandLine.window.moveCursor(0, commandLine.cursorX)

proc askCreateDirPrompt*(commndLine: var CommandLine,
                         messageLog: var seq[seq[Rune]],
                         path: string): bool =

  let mess = fmt"{path} does not exists. Create it now?: y/n"
  commndLine.buffer = mess.toRunes
  commndLine.writeExModeView(EditorColorPair.defaultChar)
  messageLog.add(mess.toRunes)

  var key = NONE_KEY
  while key == NONE_KEY:
    key = getKey()
    sleep 100

  if key == ord('y'): result = true
  else: result = false

proc askBackupRestorePrompt*(commndLine: var CommandLine,
                             messageLog: var seq[seq[Rune]],
                             filename: seq[Rune]): bool =

  let mess = fmt"Restore {filename}?: y/n"
  commndLine.buffer = mess.toRunes
  commndLine.writeExModeView(EditorColorPair.defaultChar)
  messageLog.add(mess.toRunes)

  var key = NONE_KEY
  while key == NONE_KEY:
    key = getKey()
    sleep 100

  if key == ord('y'): result = true
  else: result = false

proc askDeleteBackupPrompt*(commndLine: var CommandLine,
                            messageLog: var seq[seq[Rune]],
                            filename: seq[Rune]): bool =

  let mess = fmt"Delete {filename}?: y/n"
  commndLine.buffer = mess.toRunes
  commndLine.writeExModeView(EditorColorPair.defaultChar)
  messageLog.add(mess.toRunes)

  var key = NONE_KEY
  while key == NONE_KEY:
    key = getKey()
    sleep 100

  if key == ord('y'): result = true
  else: result = false

proc askFileChangedSinceReading*(commndLine: var CommandLine,
                                 messageLog: var seq[seq[Rune]]): bool =

  block:
    const warnMess = "WARNING: The file has been changed since reading it!: Press any key".toRunes
    commndLine.buffer = warnMess
    commndLine.writeExModeView(EditorColorPair.defaultChar)
    messageLog.add(warnMess)

  var key = NONE_KEY
  while key == NONE_KEY:
    key = getKey()
    sleep 100

  block:
    const askMess = "Do you really want to write to it: y/n ?".toRunes
    commndLine.buffer = askMess
    commndLine.writeExModeView(EditorColorPair.defaultChar)
    messageLog.add(askMess)

    var key = NONE_KEY
    while key == NONE_KEY:
      key = getKey()
      sleep 100

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

proc initExModeViewStatus*(prompt: string):CommandLine =
  result.buffer = ru""
  result.prompt = prompt
  result.cursorY = 0
  result.cursorX = 1

proc moveLeft*(commandWindow: Window, commandLine: var CommandLine) =
  if commandLine.currentPosition > 0:
    dec(commandLine.currentPosition)
    if commandLine.cursorX > commandLine.prompt.len: dec(commandLine.cursorX)
    else: dec(commandLine.startPosition)

proc moveRight*(commandLine: var CommandLine) =
  if commandLine.currentPosition < commandLine.buffer.len:
    inc(commandLine.currentPosition)
    if commandLine.cursorX < terminalWidth() - 1: inc(commandLine.cursorX)
    else: inc(commandLine.startPosition)

proc moveTop*(commandLine: var CommandLine) =
  commandLine.cursorX = commandLine.prompt.len
  commandLine.currentPosition = 0
  commandLine.startPosition = 0

proc moveEnd*(commandLine: var CommandLine) =
  commandLine.currentPosition = commandLine.buffer.len - 1
  if commandLine.buffer.len > terminalWidth():
    commandLine.startPosition = commandLine.buffer.len - terminalWidth()
    commandLine.cursorX = terminalWidth()
  else:
    commandLine.startPosition = 0
    commandLine.cursorX = commandLine.prompt.len + commandLine.buffer.len - 1

proc clearCommandBuffer*(commandLine: var CommandLine) =
  commandLine.buffer = ru""
  commandLine.cursorY = 0
  commandLine.cursorX = 1
  commandLine.currentPosition = 0
  commandLine.startPosition = 0

proc deleteCommandBuffer*(commandLine: var CommandLine) =
  if commandLine.buffer.len > 0:
    if commandLine.buffer.len < terminalWidth(): dec(commandLine.cursorX)
    commandLine.buffer.delete(commandLine.currentPosition - 1)
    dec(commandLine.currentPosition)

proc deleteCommandBufferCurrentPosition*(commandLine: var CommandLine) =
  if commandLine.buffer.len > 0 and commandLine.currentPosition < commandLine.buffer.len:
    commandLine.buffer.delete(commandLine.cursorX - 1)
    if commandLine.currentPosition > commandLine.buffer.len:
      dec(commandLine.currentPosition)

proc insertCommandBuffer*(commandLine: var CommandLine, r: Rune) =
  commandLine.buffer.insert(r, commandLine.currentPosition)
  inc(commandLine.currentPosition)
  if commandLine.cursorX < terminalWidth() - 1: inc(commandLine.cursorX)
  else: inc(commandLine.startPosition)

proc insertCommandBuffer*(commandLine: var CommandLine,
                          runes: seq[Rune]) {.inline.} =

  for r in runes:
    commandLine.insertCommandBuffer(r)

proc calcPopUpWindowSize*(buffer: seq[seq[Rune]]): (int, int) =
  var maxBufferLen = 0
  for runes in buffer:
    if maxBufferLen < runes.len: maxBufferLen = runes.len
  let
    height = if buffer.len > terminalHeight() - 1: terminalHeight() - 1
        else: buffer.len
    width = maxBufferLen + 2

  return (height, width)

proc getInputPath*(buffer, cmd: seq[Rune]): seq[Rune] =
  if (buffer.substr(cmd.len + 1)) == ru"~":
    getHomeDir().toRunes
  else:
    buffer.substr(cmd.len + 1)

proc getCandidatesFilePath*(buffer: seq[Rune],
                           command: string): seq[string] =

  let inputPath = getInputPath(buffer, command.ru)

  var list: seq[seq[Rune]] = @[]
  if inputPath.len > 0: list.add(inputPath)

  if inputPath.contains(ru'/'):
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
            # If the path is a directory, add '/'
            p = if dirExists($addPath): addPath & ru "/" else: addPath
          list.add(p)
        else:
          # If the path is a directory, add '/'
          let p = if dirExists(path): path & "/" else: path
          list.add(p.toRunes)
  else:
    if inputPath.len == 0:
      list.add ru ""

    for kind, path in walkDir("./"):
      if path.toRunes.normalizePath.startsWith(inputPath):
        let p = path.toRunes.normalizePath
        # If the path is a directory, add '/'
        if dirExists($p): list.add p & ru "/"
        else: list.add p

  for path in list: result.add($path)
  result.sort(proc (a, b: string): int = cmp(a, b))

proc isExCommand*(exBuffer: seq[Rune]): bool =
  if ($exBuffer).contains(" ") == false: return false

  let buffer = ($exBuffer).splitWhitespace(-1)
  for i in 0 ..< exCommandList.len:
    if buffer[0] == exCommandList[i].command: return true

proc getCandidatesExCommand*(commandLineBuffer: seq[Rune]): seq[seq[Rune]] =
  result = @[commandLineBuffer]
  let buffer = toLowerAscii($commandLineBuffer)
  for list in exCommandList:
    let cmd = list.command
    if cmd.len >= buffer.len and cmd.startsWith(buffer):
      result.add(cmd.toRunes)

proc getSuggestType*(buffer: seq[Rune]): SuggestType =
  template isECommand(command: seq[seq[Rune]]): bool =
    cmpIgnoreCase($command[0], "e") == 0

  template isVsCommand(command: seq[seq[Rune]]): bool =
    cmpIgnoreCase($command[0], "vs") == 0

  template isSvCommand(command: seq[seq[Rune]]): bool =
    cmpIgnoreCase($command[0], "sv") == 0

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

proc isSuggestTypeExCommand*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommand

proc isSuggestTypeExCommandOption*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommandOption

proc isSuggestTypeFilePath*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.filePath

proc initDisplayBuffer*(suggestlist: seq[seq[Rune]],
                       suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeFilePath(suggestType):
    for index, path in suggestlist:
      # suggestlist[0] is input text
      if index > 0:
        # Remove '/' end of the path string
        let p = path[0 .. path.high - 1]
        if p.contains(ru '/'):
          result.add(path[p.rfind(ru'/') + 1 ..< path.len])
        else:
          result.add(path)
  elif isSuggestTypeExCommand(suggestType):
    # Add command description
    for list in exCommandList:
      for i in 1 ..< suggestlist.len:
        if $suggestlist[i] == list.command:
          result.add suggestlist[i] & list.description.ru
  else:
    result = suggestlist[1 ..< suggestlist.len]

proc getCandidatesExCommandOption*(commandLine: var CommandLine,
                                   command: string): seq[seq[Rune]] =

  var argList: seq[string] = @[]
  case toLowerAscii($command):
    of "cursorline",
       "highlightparen",
       "indent",
       "linenum",
       "livereload",
       "realtimesearch",
       "statusline",
       "syntax",
       "tabstop",
       "smoothscroll",
       "clipboard",
       "highlightCurrentLine",
       "highlightcurrentword",
       "highlightfullspace",
       "multiplestatusline",
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
       "sv": argList = getCandidatesFilePath(commandLine.buffer, command)
    else: discard

  if argList[0] != "":
    let arg = if (splitWhitespace(commandLine.buffer)).len > 1:
                (splitWhitespace(commandLine.buffer))[1]
              else: ru""
    result = @[arg]

  for i in 0 ..< argList.len:
    result.add(argList[i].toRunes)

proc getSuggestList*(commandLine: var CommandLine,
                     suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeExCommand(suggestType):
    result = getCandidatesExCommand(commandLine.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    let cmd = $(splitWhitespace(commandLine.buffer))[0]
    result = commandLine.getCandidatesExCommandOption(cmd)
  else:
    let
      cmd = (splitWhitespace(commandLine.buffer))[0]
      pathList = getCandidatesFilePath(commandLine.buffer, $cmd)
    for path in pathList: result.add(path.ru)

proc calcXWhenSuggestPath*(buffer: seq[Rune]): int =
  let
    cmd = (splitWhitespace(buffer))[0]
    inputPath = getInputPath(buffer, cmd)
    positionInInputPath = if inputPath.rfind(ru"/") > 0:
                            inputPath.rfind(ru"/")
                          else:
                            0
  # +2 is pronpt and space
  return cmd.len + 2 + positionInInputPath

proc suggestCommandLine*(commandLine: var CommandLine,
                        key: var Rune) =

  let
    suggestType = getSuggestType(commandLine.buffer)
    suggestlist = commandLine.getSuggestList(suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if commandLine.buffer.len > 0:
                  (splitWhitespace(commandLine.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(commandLine.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  # TODO: Enable popUpWindow
  #var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      commandLine.buffer = command & ru" "
      commandLine.currentPosition = command.len + commandLine.prompt.len
      commandLine.cursorX = commandLine.currentPosition
    else:
      commandLine.buffer = ru""
      commandLine.currentPosition = 0
      commandLine.cursorX = 0

  # TODO: I don't know why yet,
  #       but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    # TODO: Enable popupwindow
    #if status.settings.popUpWindowInExmode:
    #  let
    #    currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
    #    displayBuffer = initDisplayBuffer(suggestlist, suggestType)
    #  # Pop up window size
    #  var (h, w) = displayBuffer.calcPopUpWindowSize

    #  popUpWindow.writePopUpWindow(h, w, y, x,
    #                               terminalHeight(), terminalWidth(),
    #                               currentLine,
    #                               displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      commandLine.insertCommandBuffer(command & ru' ')

    commandLine.insertCommandBuffer(suggestlist[suggestIndex])
    commandLine.cursorX.inc

    commandLine.writeExModeView(EditorColorPair.commandBar)

    key = NONE_KEY
    while key == NONE_KEY:
      key = getKey()

    commandLine.cursorX = commandLine.currentPosition + 1

  # TODO: Enable cursor
  #status.commandLine.window.moveCursor(commandLine.cursorY, commandLine.cursorX)
  # TODO: Enable popUpWindow
  #if status.settings.popUpWindowInExmode: status.deletePopUpWindow
