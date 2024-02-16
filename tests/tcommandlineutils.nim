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

import std/[unittest, os, sequtils, strutils, sugar, algorithm]

import moepkg/[unicodeext, theme, exmodeutils, completion]

import moepkg/commandlineutils {.all.}

suite "commandlineutils: initCommandLineCommand":
  test "\"vs\"":
    const Input = ru"vs"
    check CommandLineCommand(command: ru"vs", args: @[]) ==
      initCommandLineCommand(Input)

  test "\"e file.txt\"":
    const Input = ru"e file.txt"
    check CommandLineCommand(command: ru"e", args: @[ru"file.txt"]) ==
      initCommandLineCommand(Input)

  test "\"! \"echo test\"\"":
    const Input = toRunes("! \"echo test\"")
    check CommandLineCommand(
      command: ru"!",
      args: @[ru"echo test"]) == initCommandLineCommand(Input)

suite "commandlineutils: getSuggestType":
  test "SuggestType.exCommand":
    const RawInput = ru"h"
    check getSuggestType(RawInput) == SuggestType.exCommand

  test "SuggestType.exCommand 2":
    const RawInput = ru"e"
    check getSuggestType(RawInput) == SuggestType.exCommand

  test "SuggestType.exCommandOption":
    const RawInput = ru"cursorLine "
    check getSuggestType(RawInput) == SuggestType.exCommandOption

  test "SuggestType.exCommandOption with arg":
    const RawInput = ru"cursorLine o"
    check getSuggestType(RawInput) == SuggestType.exCommandOption

  test "SuggestType.exCommandOption lower case":
    const RawInput = ru"cursorline "
    check getSuggestType(RawInput) == SuggestType.exCommandOption

suite "commandlineutils: getPathCompletionList":
  test "Expect file and dir in current path":
    var files: seq[string] = @[]
    for pathComponent in walkDir("./"):
      # Delete "./" and if the path is directory, add '/' end of the path
      let path = pathComponent.path[2 .. ^1]
      let p = if dirExists(path): path & '/' else: path
      files.add(p)

    let buffer = "e ".toRunes
    for path in getPathCompletionList(buffer).items:
      check files.contains($path)

  test "Expect file and dir in \"/\"":
    var files: seq[string] = @[]
    for pathComponent in walkDir("/"):
      # if the path is directory, add '/' end of the path
      let
        path = pathComponent.path
        p = if dirExists(path): path & '/' else: path
      files.add(p)

    let buffer = "e /".toRunes
    for path in getPathCompletionList(buffer).items:
      check files.contains($path)

  test "Expect files and dirs in the home dir":
    const Input = ru"~/"
    let expectList = collect:
      for k in walkDir(getHomeDir()):
        if k.kind == pcDir:
          k.path.replace(getHomeDir(), "") & '/'
        else:
          k.path.replace(getHomeDir(), "")

    check expectList.sorted == getPathCompletionList(Input)
      .items
      .mapIt($it.insertText)
      .sorted

suite "commandlineutils: getExCommandOptionCompletionList":
  test "Expect \"on\" and \"off\"":
    let commands = ExCommandInfoList.filterIt(it.argsType == ArgsType.toggle)

    for c in commands:
      let
        rawInput = c.command.toRunes
        commandLineCmd = initCommandLineCommand(rawInput)
      check @[
        initCompletionItem(ru"on"),
        initCompletionItem(ru"off")] == getExCommandOptionCompletionList(
          rawInput,
          commandLineCmd).items

  test "Expect ColorTheme values":
    const RawInput = "theme".toRunes
    let commandLineCmd = initCommandLineCommand(RawInput)
    check ColorTheme
      .mapIt(initCompletionItem(toRunes($it))) == getExCommandOptionCompletionList(
        RawInput,
        commandLineCmd).items

suite "commandlineutils: getExCommandCompletionList":
  test "Expect all ex command":
    # TODO: Check labels
    check ExCommandInfoList
      .mapIt(initCompletionItem(
        it.command.toRunes).insertText) == getExCommandCompletionList(
          ru"").items.mapIt(it.insertText)

  test "Expect ex commands starting with \"b\"":
    const Input = ru"b"
    let commands = ExCommandInfoList
      .filterIt(it.command.startsWith("b"))
      .mapIt(initCompletionItem(it.command.toRunes).insertText)

    # TODO: Check labels
    check commands == getExCommandCompletionList(Input)
      .items
      .mapIt(it.insertText)

  test "Expect \"cursorLine\"":
    const Input = ru"cursorl"
    let commands = ExCommandInfoList
      .filterIt(it.command == "cursorLine")
      .mapIt(initCompletionItem(it.command.toRunes).insertText)

    # TODO: Check labels
    check commands == getExCommandCompletionList(Input)
      .items
      .mapIt(it.insertText)

  test "Expect \"cursorLine\" 2":
    const Input = ru"cursorL"
    let commands = ExCommandInfoList
      .filterIt(it.command == "cursorLine")
      .mapIt(initCompletionItem(it.command.toRunes).insertText)

    # TODO: Check labels
    check commands == getExCommandCompletionList(Input)
      .items
      .mapIt(it.insertText)

suite "commandlineutils: initExmodeCompletionList":
  test "Ex commands":
    const RawInput = ru"h"
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(
        label: ru"help                 | Open the help",
        insertText: ru"help"),
      CompletionItem(
        label: ru"highlightCurrentLine | Change setting to the highlightCurrentLine",
        insertText: ru"highlightCurrentLine"),
      CompletionItem(
        label: ru"highlightCurrentWord | Change setting to the highlightCurrentWord",
        insertText: ru"highlightCurrentWord"),
      CompletionItem(
        label: ru"highlightFullSpace   | Change setting to the highlightFullSpace",
        insertText: ru"highlightFullSpace"),
      CompletionItem(
        label: ru"highlightParen       | Change setting to the highlightParen",
        insertText: ru"highlightParen")
    ]

  test "Ex commands 2":
    const RawInput = ru"e"
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(label: ru"e   | Open file", insertText: ru"e"),
      CompletionItem(label: ru"ene | Create the empty buffer", insertText: ru"ene")
    ]

  test "Toggle options":
    const RawInput = ru"cursorline "
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(label: ru"on", insertText: ru"on"),
      CompletionItem(label: ru"off", insertText: ru"off"),
    ]

  test "Toggle options 2":
    const RawInput = ru"cursorline of"
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(label: ru"off", insertText: ru"off")
    ]

  test "Suggest toggle themes":
    const RawInput = ru"theme "
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(label: ru"dark", insertText: ru"dark"),
      CompletionItem(label: ru"light", insertText: ru"light"),
      CompletionItem(label: ru"vivid", insertText: ru"vivid"),
      CompletionItem(label: ru"config", insertText: ru"config"),
      CompletionItem(label: ru"vscode", insertText: ru"vscode")
    ]

  test "Suggest toggle themes 2":
    const RawInput = ru"theme d"
    # TODO: Check labels
    check initExmodeCompletionList(RawInput).items == @[
      CompletionItem(label: ru"dark", insertText: ru"dark")
    ]

  test "Suggest paths":
    let expectList = collect:
      for k in walkDir("./"):
        if k.kind == pcDir: initCompletionItem(toRunes(k.path.replace("./", "") & "/"))
        else: initCompletionItem(k.path.replace("./", "").toRunes)

    const RawInput = ru"e ./"
    check initExmodeCompletionList(RawInput).items == expectList

  test "Suggest paths 2":
    let expectList = collect:
      for k in walkDir("./src/"):
        let tail = k.path.splitPath.tail
        if tail.startsWith('m'):
          if k.kind == pcDir: initCompletionItem(toRunes(tail & "/"))
          else: initCompletionItem(tail.toRunes)

    const RawInput = ru"e src/m"
    check initExmodeCompletionList(RawInput).items == expectList
