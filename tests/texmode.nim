import unittest
import moepkg/ui, moepkg/editorstatus, moepkg/gapbuffer, moepkg/exmode, moepkg/unicodeext

test "Edit command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"e", ru"test"]
  status.exModeCommand(command)

test "Wite command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.bufStatus[0].filename = ru"test.txt"
  const command = @[ru"w"]
  status.exModeCommand(command)

test "Quit command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"q"]
  status.exModeCommand(command)

test "Force quit command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.bufStatus[0].countChange = 1
  const command = @[ru"q!"]
  status.exModeCommand(command)

test "All buffer quit command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.splitWindow

  const command = @[ru"qa"]
  status.exModeCommand(command)
  check(status.mainWindowInfo.len == 0)

test "all buffer force quit command":
  var status = initEditorStatus()
  for i in 0 ..< 2:
    status.addNewBuffer("")
    status.bufStatus[i].countChange = 1
  status.splitWindow
  status.mainWindowInfo[1].bufferIndex = 1

  const command = @[ru"qa!"]
  status.exModeCommand(command)
  check(status.mainWindowInfo.len == 0)


test "Change next buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  const command = @[ru"bnext"]
  for i in 0 ..< 3: status.exModeCommand(command)

test "Change prev buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 2: status.addNewBuffer("")

  status.currentBuffer = 1
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

  status.currentBuffer = 2
  const command = @[ru"bfirst"]
  status.exModeCommand(command)
  check(status.currentBuffer == 0)

test "Change to last buffer command":
  var status = initEditorStatus()
  for i in 0 ..< 3: status.addNewBuffer("")

  status.currentBuffer = 0
  const command = @[ru"blast"]
  status.exModeCommand(command)
  check(status.currentBuffer == 2)

test "Replace buffer command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.bufStatus[0].buffer = initGapBuffer(@[ru"xyz", ru"abcdefghijk", ru"Hello"])
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
  check(status.settings.lineNumber == false)
  block:
    const command = @[ru"linenum", ru"on"]
    status.exModeCommand(command)
  check(status.settings.lineNumber == true)

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
  check(status.settings.cursorLine == true)
  block:
    const command = @[ru"cursorLine", ru"off"]
    status.exModeCommand(command)
  check(status.settings.cursorLine == false)

test "Split window command":
  var status = initEditorStatus()
  status.addNewBuffer("")

  const command = @[ru"vs"]
  status.exModeCommand(command)
  check(status.mainWindowInfo.len == 2)

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
