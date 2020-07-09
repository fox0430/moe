import unittest, osproc
import ncurses
import moepkg/[editorstatus, gapbuffer, normalmode, unicodeext, editor, bufferstatus]

include moepkg/normalmode

suite "Normal mode: Move to the right":
  test "Move tow to the right":
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

suite "Normal mode: Move to the left":
  test "Move one to the left":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    status.workspace[0].currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    const key = @[ru'h']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentColumn == 1)

suite "Normal mode: Move to the down":
  test "Move two to the down":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const key = @[ru'j']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentLine == 2)

suite "Normal mode: Move to the up":
  test "Move two to the up":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])
    status.workspace[0].currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 2
    const key = @[ru'k']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentLine == 0)

suite "Normal mode: Delete current character":
  test "Delete two current character":
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

suite "Normal mode: Move to last of line":
  test "Move to last of line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    const key = @[ru'$']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentColumn == 2)

suite "Normal mode: Move to first of line":
  test "Move to first of line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    status.workspace[0].currentMainWindowNode.currentColumn = 2

    status.resize(100, 100)
    status.update

    const key = @[ru'0']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

suite "Normal mode: Move to first non blank of line":
  test "Move to first non blank of line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
    status.workspace[0].currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    const key = @[ru'^']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentColumn == 2)

suite "Normal mode: Move to first of previous line":
  test "Move to first of previous line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"def", ru"ghi"])
    status.workspace[0].currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    const key = @[ru'-']
    status.normalCommand(key)
    status.update
    check(status.workspace[0].currentMainWindowNode.currentLine == 1)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

    status.normalCommand(key)
    status.update
    check(status.workspace[0].currentMainWindowNode.currentLine == 0)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

suite "Normal mode: Move to first of next line":
  test "Move to first of next line":
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

suite "Normal mode: Move to last line":
  test "Move to last line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    const key = @[ru'G']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentLine == 2)

suite "Normal mode: Page down":
  test "Page down":
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

    let
      currentLine = status.workspace[0].currentMainWindowNode.currentLine
      viewHeight = status.workspace[0].currentMainWindowNode.view.height

    check currentLine == viewHeight

suite "Normal mode: Page up":
  test "Page up":
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

suite "Normal mode: Move to forward word":
  test "Move to forward word":
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

suite "Normal mode: Move to backward word":
  test "Move to backward word":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc def ghi"])
    status.workspace[0].currentMainWindowNode.currentColumn = 8

    status.resize(100, 100)
    status.update

    status.bufStatus[0].cmdLoop = 1
    const key = @[ru'b']
    status.normalCommand(key)
    status.update

    check(status.workspace[0].currentMainWindowNode.currentColumn == 4)

suite "Normal mode: Move to forward end of word":
  test "Move to forward end of word":
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

suite "Normal mode: Open blank line below":
  test "Open blank line below":
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

suite "Normal mode: Open blank line below":
  test "Open blank line below":
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

suite "Normal mode: Add indent":
  test "Add indent":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const key = @[ru'>']
    status.normalCommand(key)
    status.update

    check(status.bufStatus[0].buffer[0] == ru"  a")

suite "Normal mode: Delete indent":
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

suite "Normal mode: Join line":
  test "Join line":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.resize(100, 100)
    status.update

    const key = @[ru'J']
    status.normalCommand(key)
    status.update

    check(status.bufStatus[0].buffer[0] == ru"ab")

suite "Normal mode: Replace mode":
  test "Replace mode":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.resize(100, 100)
    status.update

    const key = @[ru'R']
    status.normalCommand(key)
    status.update

    check(status.bufStatus[0].mode == Mode.replace)

suite "Normal mode: Move right and enter insert mode":
  test "Move right and enter insert mode":
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

suite "Normal mode: Move last of line and enter insert mode":
  test "Move last of line and enter insert mode":
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

suite "Normal mode: Repeat last command":
  test "Repeat last command":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    block:
      const key = ru'x'
      let commands = status.isNormalModeCommand(key)
      status.normalCommand(commands)
      status.update

    block:
      const key = @[ru'.']
      status.normalCommand(key)
      status.update

    check(status.bufStatus[0].buffer.len == 1)
    check(status.bufStatus[0].buffer[0].len == 1)

  test "Repeat last command 2":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.resize(100, 100)
    status.update

    block:
      const key = ru'>'
      let commands = status.isNormalModeCommand(key)
      status.normalCommand(commands)
      status.update

    status.workspace[0].currentMainWindowNode.currentColumn = 0

    block:
      const key = ru'x'
      let commands = status.isNormalModeCommand(key)
      status.normalCommand(commands)
      status.update

    block:
      const key = @[ru'.']
      status.normalCommand(key)
      status.update

    check(status.bufStatus[0].buffer.len == 1)
    check(status.bufStatus[0].buffer[0] == ru"abc")

  test "Repeat last command 3":
    var status = initEditorStatus()
    status.addNewBuffer("")
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    status.resize(100, 100)
    status.update

    block:
      const key = ru'j'
      let commands = status.isNormalModeCommand(key)
      status.normalCommand(commands)
      status.update

    block:
      const key = @[ru'.']
      status.normalCommand(key)
      status.update

    check(status.workspace[0].currentMainWindowNode.currentLine == 1)
