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

import std/[strutils, sequtils, strformat, os, algorithm, options]
import ui, unicodeext, fileutils, color, commandline, popupwindow, messagelog

type
  SuggestType* = enum
    exCommand
    exCommandOption
    filePath

  ArgsType* = enum
    none
    toggle  # "on" or "off"
    number
    text
    theme   # color.colorTheme

# TODO: Auto inserts spaces in compile time.
const ExCommandList: array[63, tuple[command, description: string, argsType: ArgsType]] = [
  (command: "!", description: "                    | Shell command execution", argsType: ArgsType.none),
  (command: "deleteParen", description: "          | Enable/Disable auto delete paren", argsType: ArgsType.toggle),
  (command: "b", description: "                    | Change the buffer with the given number", argsType: ArgsType.number),
  (command: "bd", description: "                   | Delete the current buffer", argsType: ArgsType.none),
  (command: "bg", description: "                   | Pause the editor and show the recent terminal output", argsType: ArgsType.none),
  (command: "bfirst", description: "               | Change the first buffer", argsType: ArgsType.none),
  (command: "blast", description: "                | Change the last buffer", argsType: ArgsType.none),
  (command: "bnext", description: "                | Change the next buffer", argsType: ArgsType.none),
  (command: "bprev", description: "                | Change the previous buffer", argsType: ArgsType.none),
  (command: "build", description: "                | Build the current buffer", argsType: ArgsType.none),
  (command: "buildOnSave", description: "          | Enable/Disable build on save", argsType: ArgsType.toggle),
  (command: "buf", description: "                  | Open the buffer manager", argsType: ArgsType.none),
  (command: "clipboard", description: "            | Enable/Disable accessing the system clipboard", argsType: ArgsType.toggle),
  (command: "conf", description: "                 | Open the configuration mode", argsType: ArgsType.none),
  (command: "cursorLine", description: "           | Change setting to the cursorLine", argsType: ArgsType.toggle),
  (command: "debug", description: "                | Open the debug mode", argsType: ArgsType.none),
  (command: "deleteTrailingSpaces", description: " | Delete the trailing spaces in the current buffer", argsType: ArgsType.none),
  (command: "e", description: "                    | Open file", argsType: ArgsType.text),
  (command: "ene", description: "                  | Create the empty buffer", argsType: ArgsType.none),
  (command: "help", description: "                 | Open the help", argsType: ArgsType.none),
  (command: "highlightCurrentLine", description: " | Change setting to the highlightCurrentLine", argsType: ArgsType.toggle),
  (command: "highlightCurrentWord", description: " | Change setting to the highlightCurrentWord", argsType: ArgsType.toggle),
  (command: "highlightFullSpace", description: "   | Change setting to the highlightFullSpace", argsType: ArgsType.toggle),
  (command: "highlightParen", description: "       | Change setting to the highlightParen", argsType: ArgsType.toggle),
  (command: "backup", description: "               | Open the Backup file manager", argsType: ArgsType.none),
  (command: "icon", description: "                 | Show/Hidden icons in filer mode", argsType: ArgsType.toggle),
  (command: "ignorecase", description: "           | Change setting to ignore case in search", argsType: ArgsType.toggle),
  (command: "incrementalSearch", description: "    | Enable/Disable incremental search", argsType: ArgsType.toggle),
  (command: "indent", description: "               | Enable/Disable auto indent", argsType: ArgsType.toggle),
  (command: "indentationLines", description: "     | Enable/Disable auto indentation lines", argsType: ArgsType.toggle),
  (command: "linenum", description: "              | Enable/Disable the line number", argsType: ArgsType.toggle),
  (command: "liveReload", description: "           | Enable/Disable the live reload of the config file", argsType: ArgsType.toggle),
  (command: "log", description: "                  | Open the log viewer", argsType: ArgsType.none),
  (command: "ls", description: "                   | Show the all buffer", argsType: ArgsType.none),
  (command: "man", description: "                  | Show the given UNIX manual page, if available", argsType: ArgsType.toggle),
  (command: "multipleStatusLine", description: "   | Enable/Disable multiple status line", argsType: ArgsType.toggle),
  (command: "new", description: "                  | Create the new buffer in split window horizontally", argsType: ArgsType.none),
  (command: "noh", description: "                  | Turn off highlights", argsType: ArgsType.none),
  (command: "paren", description: "                | Enable/Disable auto close paren", argsType: ArgsType.toggle),
  (command: "putConfigFile", description: "        | Put the sample configuration file in ~/.config/moe", argsType: ArgsType.none),
  (command: "q", description: "                    | Close the current window", argsType: ArgsType.none),
  (command: "Q", description: "                    | Run Quickrun", argsType: ArgsType.none),
  (command: "q!", description: "                   | Force close the current window", argsType: ArgsType.none),
  (command: "qa", description: "                   | Close the all windows", argsType: ArgsType.none),
  (command: "qa!", description: "                  | Force close the all windows", argsType: ArgsType.none),
  (command: "recent", description: "               | Open the recent file selection mode", argsType: ArgsType.none),
  (command: "run", description: "                  | run Quickrun", argsType: ArgsType.none),
  (command: "scrollSpeed", description: "          | Change setting to the scroll speed", argsType: ArgsType.number),
  (command: "showGitInactive", description: "      | Change status line setting to show/hide git branch name in inactive window", argsType: ArgsType.toggle),
  (command: "smartcase", description: "            | Change setting to smart case in search", argsType: ArgsType.toggle),
  (command: "smoothScroll", description: "         | Enable/Disable the smooth scroll", argsType: ArgsType.toggle),
  (command: "sp", description: "                   | Open the file in horizontal split window", argsType: ArgsType.none),
  (command: "statusLine", description: "           | Enable/Disable the status line", argsType: ArgsType.toggle),
  (command: "syntax", description: "               | Enable/Disable the syntax highlighting", argsType: ArgsType.toggle),
  (command: "tab", description: "                  | Enable/Disable the tab line", argsType: ArgsType.toggle),
  (command: "tabstop", description: "              | Change setting to the tabstop", argsType: ArgsType.number),
  (command: "theme", description: "                | Change the color theme", argsType: ArgsType.theme),
  (command: "vs", description: "                   | Vertical split window", argsType: ArgsType.none),
  (command: "w", description: "                    | Write file", argsType: ArgsType.none),
  (command: "w!", description: "                   | Force write file", argsType: ArgsType.none),
  (command: "wq", description: "                   | Write file and close window", argsType: ArgsType.none),
  (command: "wq!", description: "                  | Force write file and close window", argsType: ArgsType.none),
  (command: "wqa", description: "                  | Write all files", argsType: ArgsType.none)
]

proc askCreateDirPrompt*(
  commndLine: var CommandLine,
  path: string): bool =

    let mess = fmt"{path} does not exists. Create it now?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess.toRunes

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askBackupRestorePrompt*(
  commndLine: var CommandLine,
  filename: seq[Rune]): bool =

    let mess = fmt"Restore {filename}?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askDeleteBackupPrompt*(
  commndLine: var CommandLine,
  filename: seq[Rune]): bool =

    let mess = fmt"Delete {filename}?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askFileChangedSinceReading*(commndLine: var CommandLine): bool =
  block:
    const Mess = "WARNING: The file has been changed since reading it!: Press any key"
    commndLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes
    discard commndLine.getKey

  block:
    const Mess = "Do you really want to write to it: y/n ?"
    commndLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes
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
    for c in ExCommandList:
      if bufferSplited[0] == c.command:
        return true

proc getCandidatesExCommand*(commandLineBuffer: Runes): seq[Runes] =
  let buffer = toLowerAscii($commandLineBuffer)
  for list in ExCommandList:
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
        for list in ExCommandList:
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

proc getSuggestList*(
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

  const PromptAndSpaceWidth = 2
  let command = buffer.firstArg
  return command.len + PromptAndSpaceWidth + positionInInputPath

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
  var popUpWindow = initWindow(
    h,
    w,
    y,
    x,
    EditorColorPairIndex.popUpWindow.int16)

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
