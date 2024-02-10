#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[strutils, sequtils, strformat, options, os]

import pkg/results

import unicodeext, commandline, messagelog, theme, exmodeutils, completion

type
  SuggestType* = enum
    exCommand
    exCommandOption

  CommandLineCommand* = object
    command*: Runes
    args*: seq[Runes]

proc askCreateDirPrompt*(
  commndLine: var CommandLine,
  path: string): bool =

    let mess = fmt"{path} does not exists. Create it now?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess.toRunes

    let key = commndLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askBackupRestorePrompt*(
  commndLine: var CommandLine,
  filename: Runes): bool =

    let mess = fmt"Restore {filename}?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess

    let key = commndLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askDeleteBackupPrompt*(
  commndLine: var CommandLine,
  filename: Runes): bool =

    let mess = fmt"Delete {filename}?: y/n"
    commndLine.write(mess.toRunes)
    addMessageLog mess

    let key = commndLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askFileChangedSinceReading*(commndLine: var CommandLine): bool =
  block:
    const Mess = "WARNING: The file has been changed since reading it!: Press any key"
    commndLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes
    discard commndLine.getKeyBlocking

  block:
    const Mess = "Do you really want to write to it: y/n ?"
    commndLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes

    let key = commndLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc getPathCompletionList*(inputPath: Runes): CompletionList =
  ## Return completion list for path suggestions.
  ## Return all files and dirs in the current dir if `inputPath` is empty.

  if inputPath.len == 0:
    return pathCompletionList(ru"./")
  else:
    result = pathCompletionList(inputPath)
    if result.len > 0:
      let pathSplit = splitPath($inputPath)
      if pathSplit.head.len > 0:
        let pathHead = pathSplit.head.toRunes
        for i in 0 .. result.items.high:
          result.items[i].insertText = pathHead / result.items[i].insertText

proc getExCommandCompletionList*(input: Runes): CompletionList =
  ## Return completion list for ex command suggestion.
  ## Interpreting upper and lowercase letters as being the same.

  result = CompletionList()

  let lowerInput = toLower(input)
  var
    suggestions: seq[ExCommandInfo]
    maxCommandLen = 0
  for info in ExCommandInfoList:
    let lowerCmd = info.command.toLowerAscii.toRunes
    if lowerInput.len <= lowerCmd.len and lowerCmd.startsWith(lowerInput):
      suggestions.add info
      if info.command.len > maxCommandLen: maxCommandLen = info.command.len

  for s in suggestions:
    # Insert spaces and dividers to descriptions for the ex command suggestion.
    let spaces = " ".repeat(maxCommandLen - s.command.len)
    result.add CompletionItem(
      label: toRunes(fmt"{s.command}{spaces} | {s.description}"),
      insertText: s.command.toRunes)

proc getSuggestType*(rawInput: Runes): SuggestType =
  let commandSplit = splitExCommandBuffer(rawInput)
  if commandSplit.len == 0 or (commandSplit.len == 1 and rawInput[^1] != ru' '):
    return SuggestType.exCommand
  else:
    return SuggestType.exCommandOption

proc initCommandLineCommand(rawInput: Runes): CommandLineCommand =
  ## Return CommandLineCommand from a raw input.

  let commandSplit = splitExCommandBuffer(rawInput)
  if commandSplit.len > 0:
    result.command = commandSplit[0]

    if commandSplit.len > 1:
      result.args = commandSplit[1 .. ^1]

proc getExCommandOptionCompletionList*(
  rawInput: Runes,
  commandLineCmd: CommandLineCommand): CompletionList =
    ## Return completion list for ex command option suggestion.
    ## Interpreting upper and lowercase letters as being the same.

    result = CompletionList()

    let argsType = getArgsType(commandLineCmd.command).get

    case argsType:
      of ArgsType.toggle:
        if commandLineCmd.args.len == 0:
          return CompletionList(items: @[
            initCompletionItem(ru"on"),
            initCompletionItem(ru"off")
          ])
        elif commandLineCmd.args.len == 1:
          for s in [ru"on", ru"off"]:
            if s.startsWith(commandLineCmd.args[0]):
              result.add initCompletionItem(s)
      of ArgsType.path:
        if commandLineCmd.args.len == 0:
          return getPathCompletionList(ru"")
        else:
          return getPathCompletionList(commandLineCmd.args[0])
      of ArgsType.theme:
        if commandLineCmd.args.len == 0:
          return CompletionList(items:
            ColorTheme.mapIt(initCompletionItem(toRunes($it))))
        elif commandLineCmd.args.len == 1:
          for theme in ColorTheme.mapIt(toRunes($it)):
            if commandLineCmd.args[0].len < theme.len and
               theme.startsWith(commandLineCmd.args[0]):
                 result.add CompletionItem(label: theme, insertText: theme)
      else:
        discard

proc initExmodeCompletionList*(rawInput: Runes): CompletionList =
  let
    commandLineCmd = initCommandLineCommand(rawInput)
    suggestType = getSuggestType(rawInput)

  case suggestType:
    of SuggestType.exCommand:
      return getExCommandCompletionList(rawInput)
    of SuggestType.exCommandOption:
      let list = getExCommandOptionCompletionList(rawInput, commandLineCmd)
      if list.items.len == 1 and
         commandLineCmd.args.len > 0 and
         commandLineCmd.args[^1] == list.items[0].label:
           # Don't assign a new suggestion if it same as the end of the args.
           return CompletionList()
      else:
        return list
