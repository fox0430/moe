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

suite "Editor: Delete word":
  test "Fix #842":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.workspace[0].currentMainWindowNode.currentLine = 1

    for i in 0 ..< 2:
      status.bufStatus[0].deleteWord(status.workspace[0].currentMainWindowNode)

suite "Editor: keyEnter":
  test "Delete all characters in the previous line if only whitespaces":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentLine = 1
    status.workspace[0].currentMainWindowNode.currentColumn = 2

    const isAutoIndent = true
    for i in 0 ..< 2:
      status.bufStatus[0].keyEnter(status.workspace[0].currentMainWindowNode,
                                   isAutoIndent,
                                   status.settings.tabStop)

    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru""
    check status.bufStatus[0].buffer[2] == ru""
    check status.bufStatus[0].buffer[3] == ru"  "

  test "Auto indent if finish a previous line with ':'":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 6

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(status.workspace[0].currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "New line":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test "])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 5

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(status.workspace[0].currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)

    check status.bufStatus[0].buffer[0] == ru"test "
    check status.bufStatus[0].buffer[1] == ru""

suite "Delete character before cursor":
  test "Delete one character":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"tes"

  test "Delete current Line":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test", ru""])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentLine = 1
    status.workspace[0].currentMainWindowNode.currentColumn = 0

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 2

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"   test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 3

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 3":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"    test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 4":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 1

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru" test"

  test "Delete tab 5":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    status.workspace[0].currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(status.workspace[0].currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  tst"
