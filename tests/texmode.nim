import unittest
import moepkg/[ui, editorstatus, gapbuffer, exmode, unicodeext, bufferstatus]

test "Edit command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"e", ru"test"]
  status.exModeCommand(command)

test "Edit command 2":
  var status = initEditorStatus()
  status.addNewBuffer("test")

  status.resize(100, 100)
  status.verticalSplitWindow
  status.resize(100, 100)

  status.changeMode(Mode.ex)
  const command = @[ru"e", ru"test2"]
  status.exModeCommand(command)

  check(status.bufStatus[0].mode == Mode.normal)
  check(status.bufStatus[1].mode == Mode.normal)

test "Write command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].filename = ru"test.txt"
  const command = @[ru"w"]
  status.exModeCommand(command)

test "Change next buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"bnext"]
  for i in 0 ..< 3: status.exModeCommand(command)

test "Change prev buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  status.workSpace[0].currentMainWindowNode.bufferIndex = 1
  const command = @[ru"bprev"]
  for i in 0 ..< 3: status.exModeCommand(command)

test "Open buffer by number command":
  var status = initEditorStatus()
  for i in 0 ..< 3: status.addNewBuffer("")

  block:
    const command = @[ru"b", ru"1"]
    status.exModeCommand(command)

  block:
    const command = @[ru"b", ru"0"]
    status.exModeCommand(command)

  block:
    const command = @[ru"b", ru"2"]
    status.exModeCommand(command)

test "Change to first buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 3: status.addNewBuffer("")

  status.workSpace[0].currentMainWindowNode.bufferIndex = 2
  const command = @[ru"bfirst"]
  status.exModeCommand(command)
  
  check(status.workSpace[0].currentMainWindowNode.bufferIndex == 0)

test "Change to last buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 3: status.addNewBuffer("")

  status.workSpace[0].currentMainWindowNode.bufferIndex = 0
  const command = @[ru"blast"]
  status.exModeCommand(command)
  check(status.workSpace[0].currentMainWindowNode.bufferIndex == 2)

test "Replace buffer command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.bufStatus[0].buffer = initGapBuffer(@[ru"xyz",
                                               ru"abcdefghijk",
                                               ru"Hello"])
  const command = @[ru"%s/efg/zzzzzz"]
  status.exModeCommand(command)
  check(status.bufStatus[0].buffer[1] == ru"abcdzzzzzzhijk")

test "Turn off highlighting command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  const command = @[ru"noh"]
  status.exModeCommand(command)

test "Tab line setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"tab", ru"off"]
    status.exModeCommand(command)
  check(status.settings.tabLine.useTab == false)
  block:
    const command = @[ru"tab", ru"on"]
    status.exModeCommand(command)
  check(status.settings.tabLine.useTab == true)

test "StatusBar setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"statusbar", ru"off"]
    status.exModeCommand(command)
  check(status.settings.statusBar.useBar == false)
  block:
    const command = @[ru"statusbar", ru"on"]
    status.exModeCommand(command)
  check(status.settings.statusBar.useBar == true)

test "Line number setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"linenum", ru"off"]
    status.exModeCommand(command)
  check(status.settings.view.lineNumber == false)
  block:
    const command = @[ru"linenum", ru"on"]
    status.exModeCommand(command)
  check(status.settings.view.lineNumber == true)

test "Auto indent setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"indent", ru"off"]
    status.exModeCommand(command)
  check(status.settings.autoIndent == false)
  block:
    const command = @[ru"indent", ru"on"]
    status.exModeCommand(command)
  check(status.settings.autoIndent == true)

test "Auto close paren setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"paren", ru"off"]
    status.exModeCommand(command)
  check(status.settings.autoCloseParen == false)
  block:
    const command = @[ru"paren", ru"on"]
    status.exModeCommand(command)
  check(status.settings.autoCloseParen == true)

test "Tab stop setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"paren", ru"off"]
    status.exModeCommand(command)
  check(status.settings.autoCloseParen == false)
  block:
    const command = @[ru"paren", ru"on"]
    status.exModeCommand(command)
  check(status.settings.autoCloseParen == true)

test "Syntax setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"syntax", ru"off"]
    status.exModeCommand(command)
  check(status.settings.syntax == false)
  block:
    const command = @[ru"syntax", ru"on"]
    status.exModeCommand(command)
  check(status.settings.syntax == true)

test "Change cursor line command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"cursorLine", ru"on"]
    status.exModeCommand(command)
  check(status.settings.view.cursorLine == true)
  block:
    const command = @[ru"cursorLine", ru"off"]
    status.exModeCommand(command)
  check(status.settings.view.cursorLine == false)

test "Split window command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.resize(100, 100)

  const command = @[ru"vs"]
  status.exModeCommand(command)
  check(status.workSpace[0].numOfMainWindow == 2)

test "Live reload of configuration file setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"livereload", ru"on"]
    status.exModeCommand(command)
  check(status.settings.liveReloadOfConf == true)
  block:
    const command = @[ru"livereload", ru"off"]
    status.exModeCommand(command)
  check(status.settings.liveReloadOfConf == false)

test "Real time search setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"realtimesearch", ru"off"]
    status.exModeCommand(command)
  check(status.settings.realtimeSearch == false)
  block:
    const command = @[ru"realtimesearch", ru"on"]
    status.exModeCommand(command)
  check(status.settings.realtimeSearch == true)

test "Change theme command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  startUi()

  block:
    const command = @[ru"theme", ru"vivid"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"dark"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"light"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"config"]
    status.exModeCommand(command)

test "Open buffer manager":
  var status = initEditorStatus()
  status.addNewBuffer("")
  startUi()

  const command = @[ru"buf"]
  status.exModeCommand(command)

test "Open log viewer":
  var status = initEditorStatus()
  status.addNewBuffer("")
  startUi()

  const command = @[ru"log"]
  status.exModeCommand(command)

test "Highlight pair of paren settig command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"highlightparen", ru"off"]
    status.exModeCommand(command)
    check(status.settings.highlightPairOfParen == false)
  block:
    const command = @[ru"highlightparen", ru"on"]
    status.exModeCommand(command)
    check(status.settings.highlightPairOfParen == true)

test "Auto delete paren setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"deleteparen", ru"off"]
    status.exModeCommand(command)
    check(status.settings.autoDeleteParen == false)

  block:
    const command = @[ru"deleteparen", ru"on"]
    status.exModeCommand(command)
    check(status.settings.autoDeleteParen == true)

test "Smooth scroll setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"smoothscroll", ru"off"]
    status.exModeCommand(command)
    check(status.settings.smoothScroll == false)

  block:
    const command = @[ru"smoothscroll", ru"on"]
    status.exModeCommand(command)
    check(status.settings.smoothScroll == true)

test "Smooth scroll speed setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"scrollspeed", ru"1"]
    status.exModeCommand(command)
    check(status.settings.smoothScrollSpeed == 1)

test "Highlight current word setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"highlightcurrentword", ru"off"]
    status.exModeCommand(command)
    check(status.settings.highlightOtherUsesCurrentWord == false)

  block:
    const command = @[ru"highlightcurrentword", ru"on"]
    status.exModeCommand(command)
    check(status.settings.highlightOtherUsesCurrentWord == true)

test "Clipboard setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"clipboard", ru"off"]
    status.exModeCommand(command)
    check(status.settings.systemClipboard == false)

  block:
    const command = @[ru"clipboard", ru"on"]
    status.exModeCommand(command)
    check(status.settings.systemClipboard == true)

test "Highlight full width space command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  block:
    const command = @[ru"highlightfullspace", ru"off"]
    status.exModeCommand(command)
    check(status.settings.highlightFullWidthSpace == false)

  block:
    const command = @[ru"highlightfullspace", ru"on"]
    status.exModeCommand(command)
    check(status.settings.highlightFullWidthSpace == true)

test "Create work space command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"cws"]
  status.exModeCommand(command)

  check(status.workspace.len == 2)

test "Change work space command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.createWrokSpace

  const command = @[ru"ws", ru"1"]
  status.exModeCommand(command)

  check(status.currentWorkSpaceIndex == 0)

test "Delete work space command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.createWrokSpace

  const command = @[ru"dws"]
  status.exModeCommand(command)

  check(status.workspace.len == 1)

test "Tab stop setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"tabstop", ru"4"]
  status.exModeCommand(command)

  check(status.settings.tabStop == 4)

test "Tab stop setting command 2":
  var status = initEditorStatus()
  status.addNewBuffer("")

  let defaultTabStop = status.settings.tabStop

  const command = @[ru"tabstop", ru"a"]
  status.exModeCommand(command)

  check(status.settings.tabStop == defaultTabStop)

test "Smooth scroll speed setting command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"scrollspeed", ru"1"]
  status.exModeCommand(command)

  check(status.settings.smoothScrollSpeed == 1)

test "Smooth scroll speed setting command 2":
  var status = initEditorStatus()
  status.addNewBuffer("")

  let defaultSpeed = status.settings.smoothScrollSpeed

  const command = @[ru"scrollspeed", ru"a"]
  status.exModeCommand(command)

  check(status.settings.smoothScrollSpeed == defaultSpeed)

test "Delete buffer status command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"bd", ru"0"]
  status.exModeCommand(command)

  check(status.bufStatus.len == 1)

test "Delete buffer status command 2":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"bd", ru"a"]
  status.exModeCommand(command)

  check(status.bufStatus.len == 2)

test "Open buffer by number command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"b", ru"0"]
  status.exModeCommand(command)

  check(status.bufferIndexInCurrentWindow == 0)

test "Open buffer by number command 2":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"b", ru"a"]
  status.exModeCommand(command)

  check(status.bufferIndexInCurrentWindow == 1)

test "Open help command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  const command = @[ru"help"]
  status.exModeCommand(command)

  status.resize(100, 100)
  status.update

  check(status.workSpace[0].numOfMainWindow == 2)
  check(status.bufferIndexInCurrentWindow == 1)

  check(status.bufStatus[1].mode == Mode.help)

test "Open in horizontal split window":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  const command = @[ru"sp", ru"newfile"]
  status.exModeCommand(command)

  status.resize(100, 100)
  status.update

  check(status.workSpace[0].numOfMainWindow == 2)
  check(status.bufStatus.len == 2)

test "Open in vertical split window":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  const command = @[ru"vs", ru"newfile"]
  status.exModeCommand(command)

  status.resize(100, 100)
  status.update

  check(status.workSpace[0].numOfMainWindow == 2)
  check(status.bufStatus.len == 2)
