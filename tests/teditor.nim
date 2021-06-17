import unittest
import moepkg/register
include moepkg/[editor, editorstatus, ui, platform]

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

suite "Editor: Delete word":
  test "Fix #842":
    var status = initEditorStatus()
    status.addNewBuffer

    currentBufStatus.buffer = initGapBuffer(@[ru"block:", ru"  "])
    currentMainWindowNode.currentLine = 1

    let settings = initEditorSettings()
    const
      loop = 2
      registerName = ""
    currentBufStatus.deleteWord(
      currentMainWindowNode,
      loop,
      status.registers,
      registerName,
      settings)

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

    let settings = initEditorSettings()
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      registers,
      ru'"',
      settings)

    check currentBufStatus.buffer[0] == ru """abc "" "ghi""""

suite "Editor: Paste lines":
  test "Paste the single line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(ru "def", settings)

    currentBufStatus.pasteAfterCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru"adefbc"

  test "Paste lines when the last line is empty":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc"])

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(@[ru "def", ru ""], settings)

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

    var registers: Registers
    let settings = initEditorSettings()
    registers.addRegister(ru "def", settings)
    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, registers)

    check currentBufStatus.buffer[0] == ru "defabc"

suite "Editor: Yank characters":
  test "Yank a string with name in the empty line":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru ""])

    const
      length = 1
      name = "a"
      isDelete = false
    currentBufStatus.yankCharacters(
      status.registers,
      currentMainWindowNode,
      status.commandline,
      status.messageLog,
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

    const
      length = 1
      name = ""
      loop = 1
    currentBufStatus.yankWord(status.registers,
                              currentMainWindowNode,
                              loop,
                              status.settings)

    check status.registers.noNameRegister ==  register.Register(
      buffer: @[ru "abc "],
      isLine: false,
      name: "")

    let p = initPlatform()
    # Check clipboad
    if (p == Platforms.linux or
        p == Platforms.wsl):
      let
        cmd = if p == Platforms.linux:
                execCmdEx("xsel -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0

      const str = "abc "
      if p == Platforms.linux:
        check output[0 .. output.high - 1] == str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == str

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

suite "Editor: Delete from the previous blank line to the current line":
  test "Delete lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "", ru "def", ru "ghi"])
    currentMainWindowNode.currentLine = 3

    const registerName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "", ru "def", ru "ghi"])
    currentMainWindowNode.currentLine = 3
    currentMainWindowNode.currentColumn = 1

    const registerName = ""
    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "hi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "", ru "def", ru "g"],
      isLine: true)

suite "Editor: Delete from the current line to the next blank line":
  test "Delete lines":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "def", ru "", ru "ghi"])

    const registerName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "abc", ru "def"],
      isLine: true)

  test "Delete lines 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abc", ru "def", ru "", ru "ghi"])
    currentMainWindowNode.currentColumn = 1

    const registerName = ""
    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

    check currentBufStatus.buffer.len == 3
    check currentBufStatus.buffer[0] == ru "a"
    check currentBufStatus.buffer[1] == ru ""
    check currentBufStatus.buffer[2] == ru "ghi"

    check status.registers.noNameRegister == register.Register(
      buffer: @[ru "bc", ru "def"],
      isLine: true)

suite "Editor: Replace characters":
  test "Repace a character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 1
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zbcdef"
    check currentMainWindowNode.currentColumn == 1

  test "Repace characters":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 3
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zzzdef"
    check currentMainWindowNode.currentColumn == 3

  test "Repace characters 2":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 10
      character = ru 'z'

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer[0] == ru "zzzzzz"
    check currentMainWindowNode.currentColumn == 5

  test "Repace characters 3":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 1
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "bcdef"

  test "Repace characters 4":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const
      autoIndent = false
      autoDeleteParen = false
      tabStop = 2
      loop = 3
    let character = toRune(KEY_ENTER)

    currentBufStatus.replaceCharacters(
      currentMainWindowNode,
      autoIndent,
      autoDeleteParen,
      tabStop,
      loop,
      character)

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru ""
    check currentBufStatus.buffer[1] == ru "def"

suite "Editor: Toggle characters":
  test "Toggle a character":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru "Abcdef"
    check currentMainWindowNode.currentColumn == 1

  test "Toggle characters":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru "abcdef"])

    const loop = 3
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru "ABCdef"
    check currentMainWindowNode.currentColumn == 3

  test "Do nothing":
    var status = initEditorStatus()
    status.addNewBuffer
    currentBufStatus.buffer = initGapBuffer(@[ru " abcde"])

    const loop = 1
    currentBufStatus.toggleCharacters(currentMainWindowNode, loop)

    check currentBufStatus.buffer[0] == ru " abcde"
    check currentMainWindowNode.currentColumn == 0
