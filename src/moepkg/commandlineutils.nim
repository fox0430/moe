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

import std/[strutils, sequtils, strformat, options]

import pkg/results

import lsp/documentsymbol
import unicodeext, commandline, messagelog, theme, exmodeutils, completion

type
  SuggestType* = enum
    exCommand
    exCommandOption

  CommandLineCommand* = object
    command*: Runes
    args*: seq[Runes]

proc askCreateDirPrompt*(
  commandLine: var CommandLine,
  path: string): bool =

    let mess = fmt"{path} does not exists. Create it now?: y/n"
    commandLine.write(mess.toRunes)
    addMessageLog mess.toRunes

    let key = commandLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askBackupRestorePrompt*(
  commandLine: var CommandLine,
  filename: Runes): bool =

    let mess = fmt"Restore {filename}?: y/n"
    commandLine.write(mess.toRunes)
    addMessageLog mess

    let key = commandLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askDeleteBackupPrompt*(
  commandLine: var CommandLine,
  filename: Runes): bool =

    let mess = fmt"Delete {filename}?: y/n"
    commandLine.write(mess.toRunes)
    addMessageLog mess

    let key = commandLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc askFileChangedSinceReading*(commandLine: var CommandLine): bool =
  block:
    const Mess = "WARNING: The file has been changed since reading it!: Press any key"
    commandLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes
    discard commandLine.getKeyBlocking

  block:
    const Mess = "Do you really want to write to it: y/n ?"
    commandLine.write(Mess.toRunes)
    addMessageLog Mess.toRunes

    let key = commandLine.getKeyBlocking
    if key == ord('y'): result = true
    else: result = false

proc getPathCompletionList*(inputPath: Runes): CompletionList =
  ## Return completion list for path suggestions.
  ## Return all files and dirs in the current dir if `inputPath` is empty.

  if inputPath.len == 0:
    return pathCompletionList(ru"./")
  else:
    return pathCompletionList(inputPath)

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

proc isPathArgs*(commandLine: CommandLine): bool =
  let commandSplit = splitExCommandBuffer(commandLine.buffer)
  if commandSplit.len > 0:
    return commandSplit[0].isPathArgsCommand

proc getExCommandOptionCompletionList*(
  rawInput: Runes,
  commandLineCmd: CommandLineCommand): CompletionList =
    ## Return completion list for ex command option suggestion.
    ## Interpreting upper and lowercase letters as being the same.

    result = CompletionList()

    let argsType = getArgsType(commandLineCmd.command)
    if argsType.isErr:
      # Invalid command
      return

    case argsType.get:
      of ArgsType.toggle:
        # "on" or "off"
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
        # File paths
        if commandLineCmd.args.len == 0:
          return getPathCompletionList(ru"")
        else:
          return getPathCompletionList(commandLineCmd.args[0])
      of ArgsType.theme:
        # Color themes
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
  ## Ex mode commands

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

proc toCompletionItem(s: DocumentSymbol): CompletionItem =
  var label = s.name

  label &= " " & $SymbolKind(s.kind)

  if s.detail.isSome:
    label &= " " & s.detail.get

  if s.range.isSome:
    label &= fmt" {s.range.get.start.line}, {$s.range.get.start.character}"

  return CompletionItem(label: label.toRunes, insertText: s.name.toRunes)

proc initDocSymbolCompletionList*(
  symbols: seq[DocumentSymbol],
  rawInput: Runes): CompletionList =
    ## LSP Docmument Symbol

    if rawInput.len == 0:
      # Return all
      return CompletionList(items: symbols.mapIt(it.toCompletionItem))

    result = CompletionList()
    let rawInputStr = $rawInput
    for s in symbols:
      if s.name.startsWith(rawInputStr):
        result.items.add s.toCompletionItem
