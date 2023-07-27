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

  ArgsType* = enum
    none
    toggle  # "on" or "off"
    number
    text
    path    # File path
    theme   # color.ColorTheme

  CommandLineCommand* = object
    command*: Runes
    args*: seq[Runes]

  SuggestList* = object
    rawInput*: Runes
    commandLineCmd*: CommandLineCommand
    suggestType*: SuggestType
    argsType*: Option[ArgsType]
    currentIndex*: int
    suggestions*: seq[Runes]

# TODO: Auto inserts spaces in compile time.
const ExCommandList: array[64, tuple[command, description: string, argsType: ArgsType]] = [
  (command: "!", description: "                    | Shell command execution", argsType: ArgsType.text),
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
  (command: "e", description: "                    | Open file", argsType: ArgsType.path),
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
  (command: "sp", description: "                   | Open the file in horizontal split window", argsType: ArgsType.path),
  (command: "statusLine", description: "           | Enable/Disable the status line", argsType: ArgsType.toggle),
  (command: "syntax", description: "               | Enable/Disable the syntax highlighting", argsType: ArgsType.toggle),
  (command: "sv", description: "                   | Horizontal split window", argsType: ArgsType.path),
  (command: "tab", description: "                  | Enable/Disable the tab line", argsType: ArgsType.toggle),
  (command: "tabstop", description: "              | Change setting to the tabstop", argsType: ArgsType.number),
  (command: "theme", description: "                | Change the color theme", argsType: ArgsType.theme),
  (command: "vs", description: "                   | Vertical split window", argsType: ArgsType.path),
  (command: "w", description: "                    | Write file", argsType: ArgsType.none),
  (command: "w!", description: "                   | Force write file", argsType: ArgsType.none),
  (command: "wq", description: "                   | Write file and close window", argsType: ArgsType.none),
  (command: "wq!", description: "                  | Force write file and close window", argsType: ArgsType.none),
  (command: "wqa", description: "                  | Write all files", argsType: ArgsType.none)
]

when (NimMajor, NimMinor) >= (1, 9):
  # These codes can't compile in Nim 1.6. Maybe compiler bug.

  proc noArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.none)
      .mapIt(it.command.toRunes)

  proc toggleArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.toggle)
      .mapIt(it.command.toRunes)

  proc numberArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.number)
      .mapIt(it.command.toRunes)

  proc textArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.text)
      .mapIt(it.command.toRunes)

  proc pathArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.path)
      .mapIt(it.command.toRunes)

  proc themeArgsCommands(): seq[Runes] {.compileTime.} =
    ExCommandList
      .filterIt(it.argsType == ArgsType.theme)
      .mapIt(it.command.toRunes)

  proc isExCommand(c: Runes, isCaseSensitive: bool = false): bool =
    if isCaseSensitive:
      const Commands = ExCommandList.mapIt(it.command.toRunes)
      Commands.contains(c)
    else:
      const Commands = ExCommandList.mapIt(it.command.toLowerAscii.toRunes)
      Commands.contains(c.toLowerAscii)
else:
  proc noArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.none)
      .mapIt(it.command.toRunes)

  proc toggleArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.toggle)
      .mapIt(it.command.toRunes)

  proc numberArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.number)
      .mapIt(it.command.toRunes)

  proc textArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.text)
      .mapIt(it.command.toRunes)

  proc pathArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.path)
      .mapIt(it.command.toRunes)

  proc themeArgsCommands(): seq[Runes] =
    ExCommandList
      .filterIt(it.argsType == ArgsType.theme)
      .mapIt(it.command.toRunes)

  proc isExCommand(c: Runes, isCaseSensitive: bool = false): bool =
    if isCaseSensitive:
      let commands = ExCommandList.mapIt(it.command.toRunes)
      commands.contains(c)
    else:
      let commands = ExCommandList.mapIt(it.command.toLowerAscii.toRunes)
      commands.contains(c.toLowerAscii)

proc isNoArgsCommand(c: Runes, isCaseSensitive: bool = false): bool {.used.} =
  # NOTE: Remove the used pragma if you use this.

  if isCaseSensitive:
    noArgsCommands().contains(c)
  else:
    noArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isToggleArgsCommand(c: Runes, isCaseSensitive: bool = false): bool =
  if isCaseSensitive:
    toggleArgsCommands().contains(c)
  else:
    toggleArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isNumberArgsCommand(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      numberArgsCommands().contains(c)
    else:
      numberArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isTextArgsCommand(c: Runes, isCaseSensitive: bool = false): bool {.used.} =
  # NOTE: Remove the used pragma if you use this.

  if isCaseSensitive:
    textArgsCommands().contains(c)
  else:
    textArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isPathArgsCommand(c: Runes, isCaseSensitive: bool = false): bool =
  if isCaseSensitive:
    pathArgsCommands().contains(c)
  else:
    pathArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isThemeArgsCommand(c: Runes, isCaseSensitive: bool = false): bool =
  if isCaseSensitive:
    themeArgsCommands().contains(c)
  else:
    themeArgsCommands().toLowerAscii.contains(c.toLowerAscii)

proc isPath(a: Option[ArgsType]): bool {.inline.} =
  a.isSome and a.get == ArgsType.path

proc isExCommand*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommand

proc isExCommandOption*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommandOption

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
  filename: Runes): bool =

    let mess = fmt"Restore {filename}?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess

    let key = commndLine.getKey

    if key == ord('y'): result = true
    else: result = false

proc askDeleteBackupPrompt*(
  commndLine: var CommandLine,
  filename: Runes): bool =

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

proc removeSuffix(lines: seq[Runes], suffix: Runes): seq[Runes] =
  for i, runes in lines:
    var withoutSuffix = runes
    withoutSuffix.removeSuffix(suffix)
    if i == 0: result = @[withoutSuffix]
    else: result.add withoutSuffix

proc splitQout(runes: Runes): seq[Runes]=
  # TODO: Rewrite
  result = @[ru""]
  var
    InQuot = false
    backSlash = false

  for i, r in runes:
    if r == ru'\\':
      backSlash = true
    elif backSlash:
      backSlash = false
      result[^1].add r
    elif i > 0 and runes[i - 1] == ru'\\':
      result[^1].add r
    elif not InQuot and r == ru'"':
      InQuot = true
      result.add ru""
    elif InQuot and r == ru'"':
      InQuot = false
      if i != runes.high:  result.add ru""
    else:
      result[^1].add r

  return result.removeSuffix(ru" ")

proc getFilePathCandidates*(inputPath: Runes): seq[Runes] =
  ## Return paths for suggestions from `inputPath`.
  ## Return all files and dirs in the current dir if `inputPath` is empty.

  if inputPath == ru"~":
    # Return an absolute path of the home dir.
    return @[getHomeDir().toRunes]
  elif inputPath.contains(ru'/'):
    let (inputPathHead, inputPathTail) = splitAndNormalizedPath(inputPath)
    for kind, path in walkDir($inputPathHead):
      if path.splitPath.tail.startsWith($inputPathTail):
        if inputPath[0] == ru'~':
          let
            pathHigh = path.toRunes.high
            homeDirHigh = high(getHomeDir())
            addPath = ru"~" & path.toRunes[homeDirHigh .. pathHigh]
          # If the path is a directory, add '/'
          if dirExists($addPath): result.add addPath & ru"/"
          else: result.add addPath
        else:
          # If the path is a directory, add '/'
          if dirExists(path): result.add toRunes(path & "/")
          else: result.add path.toRunes
  else:
    for kind, path in walkDir("./"):
      let normalizePath = normalizedPath(path.toRunes)
      if inputPath.len == 0 or normalizePath.startsWith(inputPath):
        let p = normalizedPath(path.toRunes)
        # If the path is a directory, add '/'
        if dirExists($p): result.add p & ru"/"
        else: result.add p

  result.sort(proc (a, b: Runes): int = cmp($a, $b))

proc getExCommandCandidates*(input: Runes): seq[Runes] =
  let lowerInput = toLowerAscii(input)
  for list in ExCommandList:
    let cmd = list.command.toRunes
    if cmd.len >= lowerInput.len and cmd.startsWith(lowerInput):
      result.add cmd

proc getSuggestType*(command: Runes): SuggestType =
  if command.len > 0 and isExCommand(command):
    SuggestType.exCommandOption
  else:
    SuggestType.exCommand

proc getArgsType(command: Runes): Option[ArgsType] =
  ## Return ArgsType if valid ex command.

  let lowerCommand = command.toLowerAscii
  for cmd in ExCommandList:
    if cmd.command.toLowerAscii.toRunes == lowerCommand:
      return some(cmd.argsType)

proc getExCommandOptionCandidates*(
  command: Runes,
  args: seq[Runes]): seq[Runes] =
    ## Return candidates for ex command option suggestion.
    ## Interpreting upper and lowercase letters as being the same.

    if isToggleArgsCommand(command):
      if args.len == 0:
        return @[ru"on", ru"off"]
      elif args.len == 1:
        let arg = args[0]
        for candidate in [ru"on", ru"off"]:
          if arg.len < candidate.len and candidate.startsWith(arg):
            result.add candidate
    elif isPathArgsCommand(command):
      if args.len == 1:
        return getFilePathCandidates(args[0])
    elif isThemeArgsCommand(command):
      if args.len == 0:
        return ColorTheme.mapIt(toRunes($it))
      elif args.len == 1:
        for theme in ColorTheme.mapIt(toRunes($it)):
          if args[0].len < theme.len and theme.startsWith(args[0]):
            result.add theme

proc currentSuggestion(list: SuggestList): Runes {.inline.} =
  ## Return the current suggestion.

  list.suggestions[list.currentIndex]

proc updateSuggestions*(list: var SuggestList) =
  ## Update SuggestList.suggestions.

  case list.suggestType:
    of SuggestType.exCommand:
      list.suggestions = getExCommandCandidates(list.rawInput)
    of SuggestType.exCommandOption:
      if isPath(list.argsType):
        let path =
          if list.commandLineCmd.args.len == 1: list.commandLineCmd.args[0]
          else: ru""
        list.suggestions = getFilePathCandidates(path)
      else:
        list.suggestions = getExCommandOptionCandidates(
          list.commandLineCmd.command,
          list.commandLineCmd.args)

proc splitCommand*(rawInput: Runes): seq[Runes] =
  if rawInput.contains(ru'"'):
    # `splitQout` is incomplete.
    return rawInput.splitQout
  else:
    return rawInput.splitWhitespace

proc initCommandLineCommand(rawInput: Runes): CommandLineCommand =
  ## Return CommandLineCommand from a raw input.

  let commandSplit = splitCommand(rawInput)
  if commandSplit.len > 0:
    result.command = commandSplit[0]

    if commandSplit.len > 1:
      result.args = commandSplit[1 .. ^1]

proc initSuggestList*(rawInput: Runes): SuggestList =
  result.rawInput = rawInput
  result.commandLineCmd = rawInput.initCommandLineCommand
  result.suggestType = getSuggestType(result.commandLineCmd.command)
  result.argsType = getArgsType(result.commandLineCmd.command)
  result.updateSuggestions

proc initSuggestBuffer*(suggestList: SuggestList): seq[Runes] =
  case suggestList.suggestType:
    of SuggestType.exCommand:
      # Add command description
      for list in ExCommandList:
        for l in suggestList.suggestions:
          if $l == list.command:
            result.add l & list.description.ru
    of SuggestType.exCommandOption:
      if isPath(suggestList.argsType):
        for index, path in suggestList.suggestions:
          # Remove '/' end of the path string
          let p =
            if path.len > 0: path[0 .. path.high - 1]
            else: "".toRunes
          if p.contains(ru '/'):
            result.add(path[p.rfind(ru'/') + 1 ..< path.len])
          else:
            result.add(path)
      else:
        return suggestList.suggestions

proc calcXWhenSuggestPath*(commandLineCmd: CommandLineCommand): int =
  const PromptAndSpaceWidth = 2

  if commandLineCmd.args.len == 0:
    return commandLineCmd.command.high + PromptAndSpaceWidth

  let
    inputPath = commandLineCmd.args[0]
    # TODO: Refactor
    positionInInputPath =
      if inputPath.len > 0 and
         (inputPath.count('/'.toRune) > 1 or
         (not inputPath.startsWith(ru"./")) or
         (inputPath.count(ru'/') == 1 and inputPath[^1] != ru'/')):
           inputPath.rfind(ru'/')
      else:
        0

  return commandLineCmd.command.len + PromptAndSpaceWidth + positionInInputPath

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
    h, w, y, x,
    EditorColorPairIndex.popUpWindow.int16)

  return some(popUpWindow)

proc insertSuggestion*(commandLine: var CommandLine, suggestList: SuggestList) =
  ## Insert the current suggestion to the command line buffer and
  ## move the cursor position to the end + 1.

  case suggestList.suggestType:
    of exCommand:
      if suggestList.currentIndex > -1:
        commandLine.buffer = suggestList.currentSuggestion
      else:
        commandLine.buffer = suggestList.rawInput
    else:
      if suggestList.currentIndex > -1:
        commandLine.buffer =
          suggestList.commandLineCmd.command &
          ru" " &
          suggestList.currentSuggestion
      else:
        commandLine.buffer = suggestList.rawInput

  commandLine.moveEnd
  commandLine.moveRight

proc updateSuggestWindow*(
  suggestWin: var Window,
  commandLine: var CommandLine,
  suggestList: SuggestList) =

    var
      # Pop up window initial size/position
      h = 1
      w = 1
      x = 0
      y = getTerminalHeight() - 2

    case suggestList.suggestType:
      of SuggestType.exCommand:
        x = 0
      of SuggestType.exCommandOption:
        if isPath(suggestList.argsType):
          x = calcXWhenSuggestPath(suggestList.commandLineCmd)
        else:
          x = suggestList.commandLineCmd.command.len + 1

    let
      currentLine =
        if suggestList.currentIndex > -1: some(suggestList.currentIndex)
        else: none(int)
      displayBuffer = suggestList.initSuggestBuffer
      winSize = calcPopUpWindowSize(
        displayBuffer)

    h = winSize.h
    w = winSize.w

    suggestWin.erase
    suggestWin.writePopUpWindow(
      h, w, y, x,
      currentLine,
      displayBuffer)

    commandLine.insertSuggestion(suggestList)
