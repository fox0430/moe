import std/[terminal, strutils, sequtils, strformat, os, algorithm]
import ui, unicodeext, fileutils, color, commandline

type ExModeViewStatus* = object
    buffer*: seq[Rune]
    prompt*: string
    cursorY*: int
    cursorX*: int
    currentPosition*: int
    startPosition*: int

type SuggestType* = enum
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

proc writeExModeView*(commandLine: var CommandLine,
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

proc initExModeViewStatus*(prompt: string): ExModeViewStatus =
  result.buffer = ru""
  result.prompt = prompt
  result.cursorY = 0
  result.cursorX = 1

proc moveLeft*(commandWindow: Window, exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition > 0:
    dec(exStatus.currentPosition)
    if exStatus.cursorX > exStatus.prompt.len: dec(exStatus.cursorX)
    else: dec(exStatus.startPosition)

proc moveRight*(exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition < exStatus.buffer.len:
    inc(exStatus.currentPosition)
    if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
    else: inc(exStatus.startPosition)

proc moveTop*(exStatus: var ExModeViewStatus) =
  exStatus.cursorX = exStatus.prompt.len
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc moveEnd*(exStatus: var ExModeViewStatus) =
  exStatus.currentPosition = exStatus.buffer.len - 1
  if exStatus.buffer.len > terminalWidth():
    exStatus.startPosition = exStatus.buffer.len - terminalWidth()
    exStatus.cursorX = terminalWidth()
  else:
    exStatus.startPosition = 0
    exStatus.cursorX = exStatus.prompt.len + exStatus.buffer.len - 1

proc clearCommandBuffer*(exStatus: var ExModeViewStatus) =
  exStatus.buffer = ru""
  exStatus.cursorY = 0
  exStatus.cursorX = 1
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc deleteCommandBuffer*(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0:
    if exStatus.buffer.len < terminalWidth(): dec(exStatus.cursorX)
    exStatus.buffer.delete(exStatus.currentPosition - 1)
    dec(exStatus.currentPosition)

proc deleteCommandBufferCurrentPosition*(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0 and exStatus.currentPosition < exStatus.buffer.len:
    exStatus.buffer.delete(exStatus.cursorX - 1)
    if exStatus.currentPosition > exStatus.buffer.len:
      dec(exStatus.currentPosition)

proc insertCommandBuffer*(exStatus: var ExModeViewStatus, r: Rune) =
  exStatus.buffer.insert(r, exStatus.currentPosition)
  inc(exStatus.currentPosition)
  if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
  else: inc(exStatus.startPosition)

proc insertCommandBuffer*(exStatus: var ExModeViewStatus,
                          runes: seq[Rune]) {.inline.} =

  for r in runes:
    exStatus.insertCommandBuffer(r)

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

proc getCandidatesExCommandOption*(exStatus: var ExModeViewStatus,
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
       "sv": argList = getCandidatesFilePath(exStatus.buffer, command)
    else: discard

  if argList[0] != "":
    let arg = if (splitWhitespace(exStatus.buffer)).len > 1:
                (splitWhitespace(exStatus.buffer))[1]
              else: ru""
    result = @[arg]

  for i in 0 ..< argList.len:
    result.add(argList[i].toRunes)

proc getSuggestList*(exStatus: var ExModeViewStatus,
                     suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeExCommand(suggestType):
    result = getCandidatesExCommand(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    let cmd = $(splitWhitespace(exStatus.buffer))[0]
    result = exStatus.getCandidatesExCommandOption(cmd)
  else:
    let
      cmd = (splitWhitespace(exStatus.buffer))[0]
      pathList = getCandidatesFilePath(exStatus.buffer, $cmd)
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
