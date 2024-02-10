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

import std/[unittest, os, sequtils, strutils, sugar]

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

  test "Expect the absolute path of the home dir":
    const Input = ru"~"
    check @[initCompletionItem(getHomeDir().toRunes)] == getPathCompletionList(
      Input).items

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
    let expectList = ExCommandInfoList
      .filterIt(it.command.toRunes.startsWith(RawInput))
      .mapIt(initCompletionItem(it.command.toRunes).insertText)

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Ex commands 2":
    const RawInput = ru"e"
    let expectList = ExCommandInfoList
      .filterIt(it.command.toRunes.startsWith(RawInput))
      .mapIt(initCompletionItem(it.command.toRunes).insertText)

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Toggle options":
    const RawInput = ru"cursorline "
    let expectList = @[ru"on", ru"off"]

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Toggle options 2":
    const RawInput = ru"cursorline of"
    let expectList = @[ru"off"]

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Suggest toggle themes":
    const RawInput = ru"theme "
    let expectList = ColorTheme.mapIt(toRunes($it))

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Suggest toggle themes 2":
    const RawInput = ru"theme d"
    let expectList = @[ru"dark"]

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Suggest paths":
    const RawInput = ru"e ./"

    var expectList = collect:
      for k in walkDir("./"):
        if k.kind == pcDir:
          toRunes(k.path & "/")
        else:
          k.path.toRunes

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)

  test "Suggest paths 2":
    const RawInput = ru"e src/m"

    var expectList = collect:
      for k in walkDir("src/"):
        if k.path.splitPath.tail.startsWith("m"):
          if k.kind == pcDir:
            toRunes(k.path & "/")
          else:
            k.path.toRunes

    # TODO: Check labels
    check expectList == initExmodeCompletionList(RawInput)
      .items
      .mapIt(it.insertText)
