import std/[strutils, sequtils, strformat, os, algorithm, options]
import ui, unicodeext, fileutils, color, commandline, popupwindow

type
  SuggestType* = enum
    exCommand
    exCommandOption
    filePath

# TODO: Auto inserts spaces in compile time.
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
  (command: "backup", description: "               | Open the Backup file manager"),
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
  (command: "multipleStatusLine", description: "   | Enable/Disable multiple status line"),
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
  (command: "statusLine", description: "           | Enable/Disable the status line"),
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

proc askCreateDirPrompt*(
  commndLine: var CommandLine,
  messageLog: var seq[Runes],
  path: string): bool =

    let mess = fmt"{path} does not exists. Create it now?: y/n"
    commndLine.write(mess.toRunes)
    messageLog.add(mess.toRunes)

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askBackupRestorePrompt*(
  commndLine: var CommandLine,
  messageLog: var seq[Runes],
  filename: seq[Rune]): bool =

    let mess = fmt"Restore {filename}?: y/n"
    commndLine.write(mess.toRunes)
    messageLog.add(mess.toRunes)

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askDeleteBackupPrompt*(
  commndLine: var CommandLine,
  messageLog: var seq[Runes],
  filename: seq[Rune]): bool =

    let mess = fmt"Delete {filename}?: y/n"
    commndLine.write(mess.toRunes)
    messageLog.add(mess.toRunes)

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askFileChangedSinceReading*(
  commndLine: var CommandLine,
  messageLog: var seq[Runes]): bool =

    block:
      const mess = "WARNING: The file has been changed since reading it!: Press any key"
      commndLine.write(mess.toRunes)
      messageLog.add(mess.toRunes)
      discard commndLine.getKey

    block:
      const mess = "Do you really want to write to it: y/n ?"
      commndLine.write(mess.toRunes)
      messageLog.add(mess.toRunes)
      let key = commndLine.getKey

      if key == ord('y'): result = true
      else: result = false

proc removeSuffix(r: seq[Runes], suffix: string): seq[Runes] =
  for i in 0 .. r.high:
    var string = $r[i]
    string.removeSuffix(suffix)
    if i == 0: result = @[string.toRunes]
    else: result.add(string.toRunes)

proc splitQout(s: string): seq[Runes]=
  result = @[ru""]
  var
    quotIn = false
    backSlash = false

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

proc splitCommand*(command: string): seq[Runes] =
  if (command).contains('"'):
    return splitQout(command)
  else:
    return strutils.splitWhitespace(command).mapIt(it.toRunes)

# Return a path in the `buffer`.
# Return an absolute path if path is `~`.
proc getInputPath*(buffer: Runes): Runes =
  let bufferSplited = strutils.splitWhitespace($buffer)
  if bufferSplited.len > 1:
    # Assume the last word as path.
    let path = bufferSplited[^1]

    if path == "~":
      return getHomeDir().toRunes
    else:
      return path.toRunes

# Return file paths for a suggestion from `buffer`.
# Return all file and dir in the current dir if inputPath is empty.
proc getCandidatesFilePath*(buffer: Runes): seq[string] =
  let inputPath = buffer.getInputPath

  var list: seq[Runes] = @[]

  # result[0] is input
  result.add $inputPath

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
    for kind, path in walkDir("./"):
      let normalizePath = path.toRunes.normalizePath
      if inputPath.len == 0 or normalizePath.startsWith(inputPath):
        let p = path.toRunes.normalizePath
        # If the path is a directory, add '/'
        if dirExists($p): list.add p & ru "/"
        else: list.add p

  for path in list: result.add($path)
  result.sort(proc (a, b: string): int = cmp(a, b))

proc isExCommand*(buffer: string): bool =
  let bufferSplited = strutils.splitWhitespace(buffer)
  if bufferSplited.len > 0:
    for c in exCommandList:
      if bufferSplited[0] == c.command:
        return true

proc getCandidatesExCommand*(commandLineBuffer: Runes): seq[Runes] =
  let buffer = toLowerAscii($commandLineBuffer)
  for list in exCommandList:
    let cmd = list.command
    if cmd.len >= buffer.len and cmd.startsWith(buffer):
      result.add(cmd.toRunes)

proc getSuggestType*(buffer: Runes): SuggestType =
  proc isECommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "e") == 0

  proc isVsCommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "vs") == 0

  proc isSvCommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "sv") == 0

  proc isSpCommand(command: seq[Runes]): bool {.inline.} =
    command.len > 0 and
    command.len < 3 and
    cmpIgnoreCase($command[0], "sp") == 0


  if buffer.len > 0 and isExCommand($buffer):
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

proc initSuggestBuffer*(
  suggestList: seq[Runes],
  suggestType: SuggestType): seq[Runes] =

    case suggestType:
      of filePath:
        for index, path in suggestList:
          # Remove '/' end of the path string
          let p =
            if path.len > 0: path[0 .. path.high - 1]
            else: "".toRunes
          if p.contains(ru '/'):
            result.add(path[p.rfind(ru'/') + 1 ..< path.len])
          else:
            result.add(path)
      of exCommand:
        # Add command description
        for list in exCommandList:
          for l in suggestList:
            if $l == list.command:
              result.add l & list.description.ru
      of exCommandOption:
        return suggestList

proc firstArg(buffer: Runes): Runes =
  let commandSplit = splitWhitespace(buffer)
  if commandSplit.len > 0:
    return commandSplit[0]
  else:
    return "".toRunes

proc getCandidatesExCommandOption*(commandLine: CommandLine): seq[Runes] =
  let
    buffer = commandLine.buffer
    command = $buffer.firstArg

  var argList: seq[string] = @[]
  case toLowerAscii(command):
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
       "smartcase":
         argList = @["on", "off"]
    of "theme":
      argList = @["vivid", "dark", "light", "config", "vscode"]
    of "e",
       "sp",
       "vs",
       "sv":
         argList = buffer.getCandidatesFilePath
    else:
      discard

  if argList.len > 0 and argList[0] != "":
    let arg =
      if splitWhitespace(buffer).len > 1:
        splitWhitespace(buffer)[1]
      else:
        ru""
    result = @[arg]

  for i in 0 ..< argList.len:
    result.add(argList[i].toRunes)

proc getsuggestList*(
  commandLine: CommandLine,
  suggestType: SuggestType): seq[Runes] =

    if isSuggestTypeExCommand(suggestType):
      result = getCandidatesExCommand(commandLine.buffer)
    elif isSuggestTypeExCommandOption(suggestType):
      result = commandLine.getCandidatesExCommandOption
    else:
      let pathList = commandLine.buffer.getCandidatesFilePath
      for path in pathList: result.add(path.ru)

proc calcXWhenSuggestPath*(buffer, inputPath: Runes): int =
  let
    # TODO: Refactor
    positionInInputPath =
      if inputPath.len > 0 and
         (inputPath.count('/'.toRune) > 1 or
         (not inputPath.startsWith("./".toRunes)) or
         (inputPath.count('/'.toRune) == 1 and $inputPath[^1] != "/")):
           inputPath.rfind(ru"/")
      else:
        0

  const promptAndSpaceWidth = 2
  let command = buffer.firstArg
  return command.len + promptAndSpaceWidth + positionInInputPath

proc calcPopUpWindowSize*(
  buffer: seq[Runes]): tuple[h: int, w: int] =

    var maxBufferLen = 0
    for runes in buffer:
      if maxBufferLen < runes.len: maxBufferLen = runes.len

    let
      height =
        if buffer.len > getTerminalHeight() - 2: getTerminalHeight() - 2
        else: buffer.len
      width =
        # 2 is side spaces
        if maxBufferLen + 2 > getTerminalWidth() - 1: getTerminalWidth() - 1
        else: maxBufferLen + 2

    return (h: height, w: width)

# TODO: Fix the return type to `SuggestionWindow`.
proc tryOpenSuggestWindow*(): Option[Window] =
  var
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = getTerminalHeight() - 1

  # Use EditorStatus.popUpWindow?
  var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  return some(popUpWindow)

proc updateSuggestWindow*(
  suggestWin: var Window,
  suggestType: SuggestType,
  suggestList: seq[Runes],
  suggestIndex: int,
  commandLine: var CommandLine) =

    let firstArg = commandLine.buffer.firstArg

    var
      # Pop up window initial size/position
      h = 1
      w = 1
      x = 0
      y = getTerminalHeight() - 2

    case suggestType:
      of exCommand:
        x = 0
      of exCommandOption:
        x = firstArg.len + 1
      of filePath:
        # suggestList[0] is the input path.
        let inputPath =
          if suggestList.len > 0: suggestList[0]
          else: "".toRunes
        x = calcXWhenSuggestPath(commandLine.buffer, inputPath)

    let
      currentLine = some(suggestIndex)
      displayBuffer = initSuggestBuffer(suggestList, suggestType)
      winSize = calcPopUpWindowSize(
        displayBuffer)

    h = winSize.h
    w = winSize.w

    suggestWin.erase
    suggestWin.writePopUpWindow(
      h, w,
      y, x,
      currentLine,
      displayBuffer)

    case suggestType:
      of exCommand:
        commandLine.buffer = suggestList[suggestIndex]
      else:
        commandLine.buffer = firstArg & ' '.toRune & suggestList[suggestIndex]


    commandLine.moveEnd
    commandLine.moveRight
