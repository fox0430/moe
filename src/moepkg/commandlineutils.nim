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
import pkg/results
import ui, unicodeext, fileutils, color, commandline, popupwindow, messagelog,
       theme, exmodeutils

type
  SuggestType* = enum
    exCommand
    exCommandOption

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

proc isPath(a: ArgsType): bool {.inline.} = a == ArgsType.path

proc isExCommand*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommand

proc isExCommandOption*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommandOption

proc isExCommand(list: SuggestList): bool {.inline.} =
  ## Return true if valid ex command text with space in the raw input.

  list.rawInput.contains(ru' ') and list.commandLineCmd.command.isExCommand

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
  ## Return candidates for ex command suggestion.
  ## Interpreting upper and lowercase letters as being the same.

  let lowerInput = toLower(input)
  for list in ExCommandInfoList:
    let lowerCmd = list.command.toLowerAscii.toRunes
    if lowerInput.len <= lowerCmd.len and lowerCmd.startsWith(lowerInput):
      result.add list.command.toRunes

proc getSuggestType*(command: Runes): SuggestType =
  if isExCommand(command):
    SuggestType.exCommandOption
  else:
    SuggestType.exCommand

proc getExCommandOptionCandidates*(
  command: Runes,
  args: seq[Runes],
  argsType: ArgsType): seq[Runes] =
    ## Return candidates for ex command option suggestion.
    ## Interpreting upper and lowercase letters as being the same.

    case argsType:
      of ArgsType.toggle:
        if args.len == 0:
          return @[ru"on", ru"off"]
        elif args.len == 1:
          let arg = args[0]
          for candidate in [ru"on", ru"off"]:
            if arg.len < candidate.len and candidate.startsWith(arg):
              result.add candidate
      of ArgsType.path:
        if args.len == 1:
          return getFilePathCandidates(args[0])
      of ArgsType.theme:
        if args.len == 0:
          return ColorTheme.mapIt(toRunes($it))
        elif args.len == 1:
          for theme in ColorTheme.mapIt(toRunes($it)):
            if args[0].len < theme.len and theme.startsWith(args[0]):
              result.add theme
      else:
        discard

proc currentSuggestion(list: SuggestList): Runes {.inline.} =
  ## Return the current suggestion.

  list.suggestions[list.currentIndex]

proc initCommandLineCommand(rawInput: Runes): CommandLineCommand =
  ## Return CommandLineCommand from a raw input.

  let commandSplit = splitExCommandBuffer(rawInput)
  if commandSplit.len > 0:
    result.command = commandSplit[0]

    if commandSplit.len > 1:
      result.args = commandSplit[1 .. ^1]

proc updateSuggestType(list: var SuggestList) =
  if list.isExCommand:
    list.suggestType = getSuggestType(list.commandLineCmd.command)

proc updateArgsType(list: var SuggestList) =
  if list.suggestType != SuggestType.exCommand:
    let argsType = getArgsType(list.commandLineCmd.command)
    if argsType.isOk:
      list.argsType = some(argsType.get)

proc updateSuggestions*(list: var SuggestList) =
  ## Update SuggestList.suggestions.

  var suggestions: seq[Runes]
  case list.suggestType:
    of SuggestType.exCommand:
      suggestions = getExCommandCandidates(list.rawInput)
    of SuggestType.exCommandOption:
      if isPath(list.argsType.get):
        let path =
          if list.commandLineCmd.args.len == 1: list.commandLineCmd.args[0]
          else: ru""
        suggestions = getFilePathCandidates(path)
      else:
        suggestions = getExCommandOptionCandidates(
          list.commandLineCmd.command,
          list.commandLineCmd.args,
          list.argsType.get)

  if suggestions.len == 1 and
     list.commandLineCmd.args.len > 0 and
     list.commandLineCmd.args[^1] == suggestions[0]:
       # Don't assign a new suggestion if it same as the end of the args.
       list.suggestions = @[]
  else:
    list.suggestions = suggestions

proc initSuggestList*(rawInput: Runes): SuggestList =
  result.rawInput = rawInput
  result.commandLineCmd = rawInput.initCommandLineCommand
  result.updateSuggestType
  result.updateArgsType
  result.updateSuggestions

proc initSuggestBuffer*(suggestList: SuggestList): seq[Runes] =
  case suggestList.suggestType:
    of SuggestType.exCommand:
      # Add formatted command descriptions.

      var maxCommandLen = 0
      for l in suggestList.suggestions:
        if l.len > maxCommandLen: maxCommandLen = l.len

      for l in suggestList.suggestions:
        for info in ExCommandInfoList:
          if l.toLower == info.command.toLowerAscii.toRunes:
            # Insert spaces and dividers to descriptions for
            # the ex command suggestion.
            let spaces = " ".repeat(maxCommandLen - l.len).toRunes
            result.add l & spaces & ru" | " & info.description.toRunes
    of SuggestType.exCommandOption:
      if isPath(suggestList.argsType.get):
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

proc updateSuggestWindow*(suggestWin: var Window, suggestList: SuggestList) =
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
      if isPath(suggestList.argsType.get):
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
