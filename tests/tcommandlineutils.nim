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

import std/[unittest, os, sequtils, strutils, options, sugar, algorithm]
import moepkg/[unicodeext, color]

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
    const Command = ru"h"
    check getSuggestType(Command) == SuggestType.exCommand

  test "SuggestType.exCommandOption":
    const Command = ru"cursorLine"
    check getSuggestType(Command) == SuggestType.exCommandOption

  test "SuggestType.exCommandOption lower case":
    const Command = ru"cursorline"
    check getSuggestType(Command) == SuggestType.exCommandOption

suite "commandlineutils: getArgsType":
  test "none(ArgsType)":
    const InvalidCommand = ru"aaaaa"
    check getArgsType(InvalidCommand).isNone

  # Generate test code
  template genGetArgsTypeTest(argsType: ArgsType) =
    let testTitle = $`argsType`
    test testTitle:
      let commands = ExCommandList
        .filterIt(it.argsType == `argsType`)
        .mapIt(it.command.toRunes)
      check commands.len > 0

      for c in commands:
        check getArgsType(c).get == `argsType`

  for argsType in ArgsType:
    # Run tests for all ArgsType.
    genGetArgsTypeTest(argsType)

suite "commandlineutils: isNoArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.none)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isNoArgsCommand(c)

  test "Expect to false":
    const Command = ru"!"
    check not isNoArgsCommand(Command)

suite "commandlineutils: isToggleArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.toggle)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isToggleArgsCommand(c)

  test "Expect to false":
    const Command = ru"!"
    check not isToggleArgsCommand(Command)

suite "commandlineutils: isNumberArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.number)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isNumberArgsCommand(c)

  test "Expect to false":
    const Command = ru"!"
    check not isNumberArgsCommand(Command)

suite "commandlineutils: isTextArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.text)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isTextArgsCommand(c)

  test "Expect to false":
    const Command = ru"deleteParen"
    check not isTextArgsCommand(Command)

suite "commandlineutils: isPathArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.path)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isPathArgsCommand(c)

  test "Expect to false":
    const Command = ru"!"
    check not isPathArgsCommand(Command)

suite "commandlineutils: isThemeArgsCommand":
  test "Expect to ture":
    let commands = ExCommandList
      .filterIt(it.argsType == ArgsType.theme)
      .mapIt(it.command.toRunes)
    check commands.len > 0

    for c in commands:
      check isThemeArgsCommand(c)

  test "Expect to false":
    const Command = ru"!"
    check not isThemeArgsCommand(Command)

suite "commandlineutils: getFilePathCandidates":
  test "Expect file and dir in current path":
    var files: seq[string] = @[]
    for pathComponent in walkDir("./"):
      # Delete "./" and if the path is directory, add '/' end of the path
      let path = pathComponent.path[2 .. ^1]
      let p = if dirExists(path): path & '/' else: path
      files.add(p)

    let buffer = "e ".toRunes
    for path in getFilePathCandidates(buffer):
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
    for path in getFilePathCandidates(buffer):
      check files.contains($path)

  test "Expect the absolute path of the home dir":
    const Input = ru"~"
    check @[getHomeDir().toRunes] == getFilePathCandidates(Input)

suite "commandlineutils: getExCommandOptionCandidates":
  test "Expect \"on\" and \"off\"":
    let commands = ExCommandList.filterIt(it.argsType == ArgsType.toggle)

    for c in commands:
      const Args: seq[Runes] = @[]
      check @[ru"on", ru"off"] == getExCommandOptionCandidates(
        c.command.toRunes,
        Args,
        ArgsType.toggle)

  test "Expect ColorTheme values":
    const
      Command = "theme".toRunes
      Args: seq[Runes] = @[]
    check ColorTheme.mapIt(toRunes($it)) == getExCommandOptionCandidates(
      Command,
      Args,
        ArgsType.theme)

suite "commandlineutils: getExCommandCandidates":
  test "Expect all ex command":
    check ExCommandList.mapIt(it.command.toRunes) == getExCommandCandidates(
      ru"")

  test "Expect ex commands starting with \"b\"":
    const Input = ru"b"
    let commands = ExCommandList
      .filterIt(it.command.startsWith("b"))
      .mapIt(it.command.toRunes)

    check commands == getExCommandCandidates(Input)

  test "Expect \"cursorLine\"":
    const Input = ru"cursorl"
    let commands = ExCommandList
      .filterIt(it.command == "cursorLine")
      .mapIt(it.command.toRunes)

    check commands == getExCommandCandidates(Input)

  test "Expect \"cursorLine\" 2":
    const Input = ru"cursorL"
    let commands = ExCommandList
      .filterIt(it.command == "cursorLine")
      .mapIt(it.command.toRunes)

    check commands == getExCommandCandidates(Input)

suite "commandlineutils: initSuggestList":
  test "Suggest ex commands":
    const RawInput = ru"h"
    let expectSuggestions = ExCommandList
      .filterIt(it.command.toRunes.startsWith(RawInput))
      .mapIt(it.command.toRunes)
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"h",
      commandLineCmd: CommandLineCommand(command: ru"h", args: @[]),
      suggestType: SuggestType.exCommand,
      argsType: none(ArgsType),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest ex commands 2":
    const RawInput = ru"e"
    let expectSuggestions = ExCommandList
      .filterIt(it.command.toRunes.startsWith(RawInput))
      .mapIt(it.command.toRunes)
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"e",
      commandLineCmd: CommandLineCommand(command: ru"e", args: @[]),
      suggestType: SuggestType.exCommand,
      argsType: none(ArgsType),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest toggle options":
    const RawInput = ru"cursorline "
    let expectSuggestions = @[ru"on", ru"off"]
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"cursorline ",
      commandLineCmd: CommandLineCommand(command: ru"cursorline", args: @[]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.toggle),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest toggle options 2":
    const RawInput = ru"cursorline of"
    let expectSuggestions = @[ru"off"]
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"cursorline of",
      commandLineCmd: CommandLineCommand(command: ru"cursorline", args: @[ru"of"]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.toggle),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest toggle themes":
    const RawInput = ru"theme "
    let expectSuggestions = ColorTheme.mapIt(toRunes($it))
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"theme ",
      commandLineCmd: CommandLineCommand(command: ru"theme", args: @[]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.theme),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest toggle themes 2":
    const RawInput = ru"theme d"
    let expectSuggestions = @[ru"dark"]
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"theme d",
      commandLineCmd: CommandLineCommand(command: ru"theme", args: @[ru"d"]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.theme),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest paths":
    const RawInput = ru"e ./"

    var expectSuggestions = collect:
      for k in walkDir("./"):
        if k.kind == pcDir:
          toRunes(k.path & "/")
        else:
          k.path.toRunes
    expectSuggestions.sort(proc (a, b: Runes): int = cmp($a, $b))
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"e ./",
      commandLineCmd: CommandLineCommand(command: ru"e", args: @[ru"./"]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.path),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)

  test "Suggest paths 2":
    const RawInput = ru"e src/m"

    var expectSuggestions = collect:
      for k in walkDir("src/"):
        if k.path.splitPath.tail.startsWith("m"):
          if k.kind == pcDir:
            toRunes(k.path & "/")
          else:
            k.path.toRunes
    expectSuggestions.sort(proc (a, b: Runes): int = cmp($a, $b))
    check expectSuggestions.len > 0

    check SuggestList(
      rawInput: ru"e src/m",
      commandLineCmd: CommandLineCommand(command: ru"e", args: @[ru"src/m"]),
      suggestType: SuggestType.exCommandOption,
      argsType: some(ArgsType.path),
      currentIndex: 0,
      suggestions: expectSuggestions) == initSuggestList(RawInput)
