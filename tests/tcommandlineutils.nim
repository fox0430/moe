import std/[unittest, os]
import moepkg/[commandline, unicodeext]
import moepkg/commandlineutils {.all.}

suite "commandlineutils: getCandidatesFilePath":
  test "Expect file and dir in current path":
    var files: seq[string] = @[]
    for pathComponent in walkDir("./"):
      # Delete "./" and if the path is directory, add '/' end of the path
      let path = pathComponent.path[2 .. ^1]
      let p = if dirExists(path): path & '/' else: path
      files.add(p)

    const buffer = "e ".toRunes
    let r = getCandidatesFilePath(buffer)

    # r[0] is the input path.
    for path in r[1 .. r.high]:
      check files.contains($path)

  test "Expect file and dir in \"/\"":
    var files: seq[string] = @[]
    for pathComponent in walkDir("/"):
      # if the path is directory, add '/' end of the path
      let
        path = pathComponent.path
        p = if dirExists(path): path & '/' else: path
      files.add(p)

    const buffer = "e /".toRunes
    let r = getCandidatesFilePath(buffer)

    # r[0] is the input path.
    for path in r[1 .. r.high]:
      check files.contains($path)

suite "commandlineutils: getCandidatesExCommandOption":
  test "Expect \"on\" and \"off\"":
    const commands = [
      "cursorline",
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
      "highlightcurrentword",
      "highlightfullspace",
      "multiplestatusline",
      "buildonsave",
      "indentationlines",
      "icon",
      "showgitinactive",
      "ignorecase",
      "smartcase"
    ]

    var commandLine = initCommandLine()

    for c in commands:
      commandLine.buffer = c.toRunes
      let r = commandLine.getCandidatesExCommandOption
      check r == @[ru"", ru"on", ru"off"]

  test "Expect \"vivid\", \"dark\", \"light\", \"config\", \"vscode\"":
    var commandLine = initCommandLine()

    const command = "theme".toRunes
    commandLine.buffer = command

    check commandLine.getCandidatesExCommandOption == @[
      ru"", ru"vivid", ru"dark", ru"light", ru"config", ru"vscode"]

suite "commandview: getCandidatesExCommand":
  test "Expect all ex command":
    let r = getCandidatesExCommand(ru"")

    for i in 0 ..< r.high:
      check exCommandList[i].command == $r[i]

  test "Expect ex commands starting with \"b\"":
    const candidates = [
      "b",
      "bd",
      "bfirst",
      "blast",
      "bnext",
      "bprev",
      "build",
      "buildOnSave",
      "buf",
      "backup"
    ]

    const command = "b".toRunes
    let r = getCandidatesExCommand(command)

    check candidates.len == r.len

    for i, c in candidates:
      check c == $r[i]

suite "commandview: getSuggestType":
  test "Expect to SuggestType.exCommand":
    const buffer = ru"h"
    check getSuggestType(buffer) == SuggestType.exCommand

  test "Expect to SuggestType.exCommandOption":
    const buffer = ru"cursorLine "
    check getSuggestType(buffer) == SuggestType.exCommandOption

  test "Expect to SuggestType.filePath":
    const buffer = ru"e "
    check getSuggestType(buffer) == SuggestType.filePath
