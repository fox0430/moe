import unittest
include moepkg/[editor, editorstatus]

suite "Editor: Auto indent":
  test "Auto indent in current Line":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a", ru"b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"  a")
    check(status.bufStatus[0].buffer[1] == ru"  b")

  test "Auto indent in current Line 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 3":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"  b"])

    status.workSpace[0].currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 4":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.bufStatus[0].autoIndentCurrentLine(
      status.workspace[0].currentMainWindowNode
    )

    check(status.bufStatus[0].buffer[0] == ru"")

suite "Editor: Delete trailing spaces":
  test "Delete trailing spaces 1":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d  ", ru"efg"])

    status.bufStatus[0].deleteTrailingSpaces

    check status.bufStatus[0].buffer.len == 3
    check status.bufStatus[0].buffer[0] == ru"abc"
    check status.bufStatus[0].buffer[1] == ru"d"
    check status.bufStatus[0].buffer[2] == ru"efg"

suite "Editor: Send to clipboad":
  test "Send string to clipboard 1":
    const str = ru"Clipboard test"
    const registers = editorstatus.Registers(yankedLines: @[], yankedStr: str)

    const platform = editorstatus.Platform.linux
    sendToClipboad(registers, platform)

    let (output, exitCode) = execCmdEx("xclip -o")

    check exitCode == 0 and output[0 .. output.high - 1] == "Clipboard test"

  test "Send string to clipboard 2":
    const str = ru"`````"
    const registers = editorstatus.Registers(yankedLines: @[], yankedStr: str)

    const platform = editorstatus.Platform.linux
    registers.sendToClipboad(platform)

    let (output, exitCode) = execCmdEx("xclip -o")

    check exitCode == 0 and output[0 .. output.high - 1] == "`````"

  test "Send string to clipboard 3":
    const str = ru"$Clipboard test"
    const registers = editorstatus.Registers(yankedLines: @[], yankedStr: str)

    const platform = editorstatus.Platform.linux
    registers.sendToClipboad(platform)

    let (output, exitCode) = execCmdEx("xclip -o")

    check exitCode == 0 and output[0 .. output.high - 1] == "$Clipboard test"

suite "Delete word":
  test "Fix #842":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.workspace[0].currentMainWindowNode.currentLine = 1

    for i in 0 ..< 2:
      status.bufStatus[0].deleteWord(status.workspace[0].currentMainWindowNode)
