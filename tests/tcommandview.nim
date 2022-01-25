import std/[unittest, os, strutils]
import moepkg/unicodeext
include moepkg/[commandview, commandviewutils, editorstatus]

suite "commandview: getCandidatesFilePath":
  test "Expect file and dir in current path":
    var files: seq[string] = @[]
    for pathComponent in walkDir("./"):
      # Delete "./" and if the path is directory, add '/' end of the path
      let path = pathComponent.path[2 .. ^1]
      let p = if dirExists(path): path & '/' else: path
      files.add(p)

    let r = getCandidatesFilePath(ru"e ", "e")

    # r[0] is empty string
    for path in r[1 .. ^1]:
      check files.contains($path)

  test "Expect file and dir in \"/\"":
    var files: seq[string] = @[]
    for pathComponent in walkDir("/"):
      # if the path is directory, add '/' end of the path
      let
        path = pathComponent.path
        p = if dirExists(path): path & '/' else: path
      files.add(p)

    let r = getCandidatesFilePath(ru"e /", "e")

    # r[0] is empty string
    for path in r[1 .. ^1]:
      check files.contains($path)

suite "commandview: getCandidatesExCommandOption":
  test "Expect \"on\" and \"off\"":
    var status = initEditorStatus()
    status.addNewBuffer

    const prompt = ":"
    var exStatus = initExModeViewStatus(prompt)

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

    for c in commands:
      let r = exStatus.getCandidatesExCommandOption(c)
      check r == @[ru"", ru"on", ru"off"]

  test "Expect \"vivid\", \"dark\", \"light\", \"config\", \"vscode\"":
    var status = initEditorStatus()
    status.addNewBuffer

    const prompt = ":"
    var exStatus = initExModeViewStatus(prompt)

    const command = "theme"
    let r = exStatus.getCandidatesExCommandOption(command)
    check r == @[ru"", ru"vivid", ru"dark", ru"light", ru"config", ru"vscode"]

  test "Expect file and dir in current path":
    var status = initEditorStatus()
    status.addNewBuffer

    const prompt = ":"
    var exStatus = initExModeViewStatus(prompt)

    const commands = [
      "e",
      "sp",
      "vs",
      "sv"
    ]

    var files: seq[string] = @[]
    for pathComponent in walkDir("./"):
      # Delete "./" and if the path is directory, add '/' end of the path
      let path = pathComponent.path[2 .. ^1]
      let p = if dirExists(path): path & '/' else: path
      files.add(p)

    for c in commands:
      exStatus.buffer = c.ru & ru" "
      let r = exStatus.getCandidatesExCommandOption(c)

      # r[0] is empty string
      for i, path in r[1 .. ^1]:
        check files.contains($path)

suite "commandview: getCandidatesExCommand":
  test "Expect all ex command":
    let r = getCandidatesExCommand(ru"")

    for i in 0 ..< r.high:
      # r[0] is empty string
      check exCommandList[i].command == $r[i + 1]

  test "Expect ex commands starting with \"b\"":
    let r = getCandidatesExCommand(ru"b")

    const commands = [
      "b",
      "bd",
      "bfirst",
      "blast",
      "bnext",
      "bprev",
      "build",
      "buildOnSave",
      "buf"
    ]

    for i in 0 ..< r.high:
      # r[0] is empty string
      check commands[i] == $r[i + 1]

suite "commandview: initDisplayBuffer":
  test "Check display buffer":
    let
      list = getCandidatesExCommand(ru"")
      r = initDisplayBuffer(list, SuggestType.exCommand)

    for i in 0 ..< r.high:
      check exCommandList[i].command & exCommandList[i].description == $r[i]

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
