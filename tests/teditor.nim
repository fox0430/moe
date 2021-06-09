import unittest
include moepkg/[editor, editorstatus, register]

suite "Editor: Auto indent":
  test "Auto indent in current Line":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"  a")
    check(status.bufStatus[0].buffer[1] == ru"  b")

  test "Auto indent in current Line 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 3":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"  b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].autoIndentCurrentLine(
      currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"a")
    check(status.bufStatus[0].buffer[1] == ru"b")

  test "Auto indent in current Line 4":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    status.bufStatus[0].autoIndentCurrentLine(currentMainWindowNode)

    check(status.bufStatus[0].buffer[0] == ru"")

suite "Editor: Delete trailing spaces":
  test "Delete trailing spaces 1":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"d  ", ru"efg"])

    status.bufStatus[0].deleteTrailingSpaces

    check status.bufStatus[0].buffer.len == 3
    check status.bufStatus[0].buffer[0] == ru"abc"
    check status.bufStatus[0].buffer[1] == ru"d"
    check status.bufStatus[0].buffer[2] == ru"efg"

proc initRegister(buffer: seq[Rune]): register.Registers {.compiletime.} =
  result.addRegister(buffer)

proc initRegister(buffer: seq[seq[Rune]]): register.Registers {.compiletime.} =
  result.addRegister(buffer)

suite "Editor: Send to clipboad":
  test "Send string to clipboard 1 (xsel)":
    const
      str = ru"Clipboard test"
      tool = ClipboardToolOnLinux.xsel

    let registers = initRegister(str)

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 1 (xclip)":
    const
      str = ru"Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 2 (xsel)":
    const
      str = ru"`````"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xsel

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 2 (xclip)":
    const
      str = ru"`````"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 3 (xsel)":
    const
      str = ru"$Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xsel

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:

                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 3 (xclip)":
    const
      str = ru"$Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:

                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

suite "Editor: Delete word":
  test "Fix #842":
    var status = initEditorStatus()
    status.addNewBuffer

    currentBufStatus.buffer = initGapBuffer(@[ru"block:", ru"  "])
    currentMainWindowNode.currentLine = 1

    const loop = 2
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      loop,
      status.registers)

suite "Editor: keyEnter":
  test "Delete all characters in the previous line if only whitespaces":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:", ru"  "])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 2

    const isAutoIndent = true
    for i in 0 ..< 2:
      status.bufStatus[0].keyEnter(currentMainWindowNode,
                                   isAutoIndent,
                                   status.settings.tabStop)

    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru""
    check status.bufStatus[0].buffer[2] == ru""
    check status.bufStatus[0].buffer[3] == ru"  "

  test "Auto indent if finish a previous line with ':'":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"block:"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 6

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)


    check status.bufStatus[0].buffer[0] == ru"block:"
    check status.bufStatus[0].buffer[1] == ru"  "

  test "New line":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test "])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 5

    const isAutoIndent = true
    status.bufStatus[0].keyEnter(currentMainWindowNode,
                                 isAutoIndent,
                                 status.settings.tabStop)

    check status.bufStatus[0].buffer[0] == ru"test "
    check status.bufStatus[0].buffer[1] == ru""

suite "Delete character before cursor":
  test "Delete one character":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"tes"

  test "Delete one character 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test test2"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 7

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  testtest2"

  test "Delete current Line":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"test", ru""])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 0

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 2

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"test"

  test "Delete tab 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"   test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 3

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 3":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"    test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  test"

  test "Delete tab 4":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 1

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru" test"

  test "Delete tab 5":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"  test"])
    status.bufStatus[0].mode = Mode.insert
    currentMainWindowNode.currentColumn = 4

    const
      autoCloseParen = true
      tabStop = 2
    status.bufStatus[0].keyBackspace(currentMainWindowNode,
                                     autoCloseParen,
                                     tabStop)

    check status.bufStatus[0].buffer.len == 1
    check status.bufStatus[0].buffer[0] == ru"  tst"

suite "Editor: Delete inside paren":
  test "delete inside double quotes":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru """abc "def" "ghi""""])
    currentMainWindowNode.currentColumn = 6

    var registers: register.Registers

    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      registers,
      ru'"')

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

suite "Editor: Paste lines":
  test "Paste the single line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const registers = initRegister(@[ru "def"])

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"abc"
    check currentBufStatus.buffer[1] == ru"def"

  test "Paste lines when the last line is empty":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const registers = initRegister(@[ru "def", ru ""])

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru"abc"
    check currentBufStatus.buffer[1] == ru"def"
    check currentBufStatus.buffer[2] == ru""

suite "Editor: Paste a string":
  test "Paste a string before cursor":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const registers = initRegister(ru "def")
    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer[0] == ru "defabc"

suite "Editor: Yank a string":
  test "Yank a string with name in the empty line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru ""])

    let platform: editorstatus.Platform = editorstatus.initPlatform()
    const
      length = 1
      name = "a"
      isDelete = false
    currentBufStatus.yankString(status.registers,
                                currentMainWindowNode,
                                status.commandline,
                                status.messageLog,
                                platform,
                                status.settings,
                                length,
                                name,
                                isDelete)

    check status.registers.noNameRegister.buffer.len == 0

suite "Editor: Yank words":
  test "Yank a word":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc def"])

    let platform: editorstatus.Platform = editorstatus.initPlatform()
    const
      length = 1
      name = ""
      loop = 1
    currentBufStatus.yankWord(status.registers,
                              currentMainWindowNode,
                              platform,
                              status.settings.clipboard,
                              loop)

    check status.registers.noNameRegister ==  register.Register(
      buffer: @[ru "abc "],
      isLine: false,
      name: "")

    const str = "abc "
    # Check clipboad
    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

suite "Editor: Modify the number string under the cursor":
  test "Increment the number string":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "2"

  test "Increment the number string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru " 1 "])
    currentMainWindowNode.currentColumn = 1

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru " 2 "

  test "Increment the number string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "9"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "10"

  test "Decrement the number string":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "1"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "0"

  test "Decrement the number string 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "0"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "-1"

  test "Decrement the number string 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "10"])

    const amount = -1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "9"

  test "Do nothing":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    const amount = 1
    currentBufStatus.modifyNumberTextUnderCurosr(
      currentMainWindowNode,
      amount)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

