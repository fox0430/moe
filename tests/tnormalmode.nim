import unittest, osproc
import ncurses
import moepkg/[editorstatus, gapbuffer, normalmode, unicodeext, editor, bufferstatus]

include moepkg/normalmode

test "Delete current character":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn = 1
  status.bufStatus[0].deleteCurrentCharacter(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.autoDeleteParen)
  check(status.bufStatus[0].buffer[0] == ru"ac")

test "Add indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  const tabStop = 2
  status.bufStatus[0].addIndent(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, tabStop)
  check(status.bufStatus[0].buffer[0] == ru"  abc")

test "Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  const tabStop = 2
  status.bufStatus[0].deleteIndent(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, tabStop)
  check(status.bufStatus[0].buffer[0] == ru"abc")

test "Send to clipboard 1":
  const registers = Registers(yankedLines: @[], yankedStr: ru"Clipboard test")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "Clipboard test")

test "Send to clipboard 2":
  const registers = Registers(yankedLines: @[], yankedStr: ru"`Clipboard test`")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "`Clipboard test`")

test "Send to clipboard 3":
  const registers = Registers(yankedLines: @[], yankedStr: ru"`````")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "`````")

test "Send to clipboard 4":
  const registers = Registers(yankedLines: @[], yankedStr: ru"$Clipboard test")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "$Clipboard test")

test "Normal mode: Move right":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update


  status.bufStatus[0].cmdLoop = 2
  const key = @[ru'l']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 2)

test "Normal mode: Move left":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  block:
    const key = @[ru'l']
    status.normalCommand(key)
  status.update

  status.bufStatus[0].cmdLoop = 1
  block:
    const key = @[ru'h']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 1)

test "Normal mode: Move down":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  block:
    const key = @[ru'j']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == 1)

test "Normal mode: Move up":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  block:
    const key = @[ru'j']
    status.normalCommand(key)
  status.update

  status.bufStatus[0].cmdLoop = 1
  block:
    const key = @[ru'k']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == 1)

test "Normal mode: Delete current character":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  const key = @[ru'x']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer[0] == ru"c")

test "Normal mode: Move to last of line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update

  const key = @[ru'$']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 2)

test "Normal mode: Move to first of line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update

  block:
    const key = @[ru'$']
    status.normalCommand(key)
  status.update

  block:
    const key = @[ru'0']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

test "Normal mode: Move to first non blank of line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])

  status.resize(100, 100)
  status.update

  block:
    const key = @[ru'$']
    status.normalCommand(key)
  status.update

  block:
    const key = @[ru'^']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 2)

test "Normal mode: Move to first of previous line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"def", ru"ghi"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  block:
    const key = @[ru'j']
    status.normalCommand(key)
  status.update

  block:
    const key = @[ru'-']
    status.normalCommand(key)
    status.update
    check(status.workspace[0].currentMainWindowNode.currentLine == 1)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

    status.normalCommand(key)
    status.update
    check(status.workspace[0].currentMainWindowNode.currentLine == 0)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

test "Normal mode: Move to first of next line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

  status.resize(100, 100)
  status.update

  const key = @[ru'+']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == 1)
  check(status.workspace[0].currentMainWindowNode.currentColumn == 0)
  
test "Normal mode: Move to last line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

  status.resize(100, 100)
  status.update

  const key = @[ru'G']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == 2)

test "Normal mode: Page down":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

  status.settings.smoothScroll = false

  status.resize(100, 100)
  status.update

  const key = @[KEY_NPAGE.toRune]
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == status.workspace[0].currentMainWindowNode.view.height)

test "Normal mode: Page up":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  for i in 0 ..< 200: status.bufStatus[0].buffer.insert(ru"a", 0)

  status.settings.smoothScroll = false

  status.resize(100, 100)
  status.update

  block:
    const key = @[KEY_NPAGE.toRune]
    status.normalCommand(key)
  status.update

  block:
    const key = @[KEY_PPAGE.toRune]
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentLine == 0)

test "Normal mode: Move to forward word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  const key = @[ru'w']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 8)

test "Normal mode: Move to backward word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  block:
    const key = @[ru'w']
    status.normalCommand(key)
  status.update

  status.bufStatus[0].cmdLoop = 1
  block:
    const key = @[ru'b']
    status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 4)

test "Normal mode: Move to forward end of word":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])

  status.resize(100, 100)
  status.update

  status.bufStatus[0].cmdLoop = 2
  const key = @[ru'e']
  status.normalCommand(key)
  status.update

  check(status.workspace[0].currentMainWindowNode.currentColumn == 6)

test "Normal mode: Open blank line below":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'o']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer.len == 2)
  check(status.bufStatus[0].buffer[0] == ru"a")
  check(status.bufStatus[0].buffer[1] == ru"")

  check(status.workspace[0].currentMainWindowNode.currentLine == 1)

  check(status.bufStatus[0].mode == Mode.insert)

test "Normal mode: Open blank line below":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'O']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer.len == 2)
  check(status.bufStatus[0].buffer[0] == ru"")
  check(status.bufStatus[0].buffer[1] == ru"a")

  check(status.workspace[0].currentMainWindowNode.currentLine == 0)

  check(status.bufStatus[0].mode == Mode.insert)

test "Normal mode: Add indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'>']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer[0] == ru"  a")

test "Normal mode: Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'<']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer[0] == ru"a")

test "Normal mode: Join line":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

  status.resize(100, 100)
  status.update

  const key = @[ru'J']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].buffer[0] == ru"ab")

test "Normal mode: Replace mode":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'R']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].mode == Mode.replace)

test "Normal mode: Move right and enter insert mode":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

  status.resize(100, 100)
  status.update

  const key = @[ru'a']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].mode == Mode.insert)
  check(status.workspace[0].currentMainWindowNode.currentColumn == 1)

test "Normal mode: Move last of line and enter insert mode":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  status.resize(100, 100)
  status.update

  const key = @[ru'A']
  status.normalCommand(key)
  status.update

  check(status.bufStatus[0].mode == Mode.insert)
  check(status.workspace[0].currentMainWindowNode.currentColumn == 3)
