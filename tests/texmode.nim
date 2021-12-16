import std/[unittest, os]
import moepkg/[ui, editorstatus, gapbuffer, exmode, unicodeext, bufferstatus,
               settings]

suite "Ex mode: Edit command":
  test "Edit command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"e", ru"test"]
    status.exModeCommand(command, 100, 100)

  test "Edit command 2":
    var status = initEditorStatus()
    status.addNewBuffer("test")

    status.resize(100, 100)
    status.verticalSplitWindow
    status.resize(100, 100)

    status.changeMode(Mode.ex)
    const command = @[ru"e", ru"test2"]
    status.exModeCommand(command, 100, 100)

    check(status.bufStatus[0].mode == Mode.normal)
    check(status.bufStatus[1].mode == Mode.normal)

suite "Ex mode: Write command":
  test "Write command":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
    status.bufStatus[0].path = ru"test.txt"
    const command = @[ru"w"]
    status.exModeCommand(command, 100, 100)

    if fileExists("test.txt"):
      removeFile("test.txt")

suite "Ex mode: Change next buffer command":
 test "Change next buffer command":
   var status = initEditorStatus()
   for i in 0 ..< 2: status.addNewBuffer

   const command = @[ru"bnext"]
   for i in 0 ..< 3: status.exModeCommand(command, 100, 100)

suite "Ex mode: Change next buffer command":
  test "Change prev buffer command":
    var status = initEditorStatus()
    for i in 0 ..< 2: status.addNewBuffer

    currentMainWindowNode.bufferIndex = 1
    const command = @[ru"bprev"]
    for i in 0 ..< 3: status.exModeCommand(command, 100, 100)

suite "Ex mode: Open buffer by number command":
  test "Open buffer by number command":
    var status = initEditorStatus()
    for i in 0 ..< 3: status.addNewBuffer

    block:
      const command = @[ru"b", ru"1"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"b", ru"0"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"b", ru"2"]
      status.exModeCommand(command, 100, 100)

suite "Ex mode: Change to first buffer command":
  test "Change to first buffer command":
    var status = initEditorStatus()
    for i in 0 ..< 3: status.addNewBuffer

    currentMainWindowNode.bufferIndex = 2
    const command = @[ru"bfirst"]
    status.exModeCommand(command, 100, 100)

    check(currentMainWindowNode.bufferIndex == 0)

suite "Ex mode: Change to last buffer command":
  test "Change to last buffer command":
    var status = initEditorStatus()
    for i in 0 ..< 3: status.addNewBuffer

    currentMainWindowNode.bufferIndex = 0
    const command = @[ru"blast"]
    status.exModeCommand(command, 100, 100)
    check(currentMainWindowNode.bufferIndex == 2)

suite "Ex mode: Replace buffer command":
  test "Replace buffer command":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].buffer = initGapBuffer(@[ru"xyz",
                                                 ru"abcdefghijk",
                                                 ru"Hello"])
    const command = @[ru"%s/efg/zzzzzz"]
    status.exModeCommand(command, 100, 100)
    check(status.bufStatus[0].buffer[1] == ru"abcdzzzzzzhijk")

suite "Ex mode: Turn off highlighting command":
  test "Turn off highlighting command":
    var status = initEditorStatus()
    status.addNewBuffer
    const command = @[ru"noh"]
    status.exModeCommand(command, 100, 100)

suite "Ex mode: Tab line setting command":
  test "Tab line setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"tab", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.tabLine.enable == false)
    block:
      const command = @[ru"tab", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.tabLine.enable == true)

suite "Ex mode: StatusLine setting command":
  test "StatusLine setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"statusline", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.statusLine.enable == false)
    block:
      const command = @[ru"statusline", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.statusLine.enable == true)

suite "Ex mode: Line number setting command":
  test "Line number setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"linenum", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.view.lineNumber == false)
    block:
      const command = @[ru"linenum", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.view.lineNumber == true)

suite "Ex mode: Auto indent setting command":
  test "Auto indent setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"indent", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoIndent == false)
    block:
      const command = @[ru"indent", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoIndent == true)

suite "Ex mode: Auto close paren setting command":
  test "Auto close paren setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"paren", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoCloseParen == false)
    block:
      const command = @[ru"paren", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoCloseParen == true)

suite "Ex mode: Tab stop setting command":
  test "Tab stop setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"paren", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoCloseParen == false)
    block:
      const command = @[ru"paren", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.autoCloseParen == true)

suite "Ex mode: Syntax setting command":
  test "Syntax setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"syntax", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.syntax == false)
    block:
      const command = @[ru"syntax", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.syntax == true)

suite "Ex mode: Change cursor line command":
  test "Change cursor line command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"cursorLine", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.view.cursorLine == true)
    block:
      const command = @[ru"cursorLine", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.view.cursorLine == false)

suite "Ex mode: Split window command":
  test "Split window command":
    var status = initEditorStatus()
    status.addNewBuffer
    status.resize(100, 100)

    const command = @[ru"vs"]
    status.exModeCommand(command, 100, 100)
    check(status.mainWindow.numOfMainWindow == 2)

suite "Ex mode: Live reload of configuration file setting command":
  test "Live reload of configuration file setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"livereload", ru"on"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.liveReloadOfConf == true)
    block:
      const command = @[ru"livereload", ru"off"]
      status.exModeCommand(command, 100, 100)
    check(status.settings.liveReloadOfConf == false)

suite "Ex mode: Incremental search setting command":
  test "Incremental search setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"incrementalSearch", ru"off"]
      status.exModeCommand(command, 100, 100)
    check not status.settings.incrementalSearch
    block:
      const command = @[ru"incrementalSearch", ru"on"]
      status.exModeCommand(command, 100, 100)
    check status.settings.incrementalSearch

suite "Ex mode: Change theme command":
  test "Change theme command":
    var status = initEditorStatus()
    status.addNewBuffer
    startUi()

    block:
      const command = @[ru"theme", ru"vivid"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"theme", ru"dark"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"theme", ru"light"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"theme", ru"config"]
      status.exModeCommand(command, 100, 100)

suite "Ex mode: Open buffer manager":
  test "Open buffer manager":
    var status = initEditorStatus()
    status.addNewBuffer
    startUi()

    const command = @[ru"buf"]
    status.exModeCommand(command, 100, 100)

suite "Ex mode: Open log viewer":
  test "Open log viewer":
    var status = initEditorStatus()
    status.addNewBuffer
    startUi()

    const command = @[ru"log"]
    status.exModeCommand(command, 100, 100)

suite "Ex mode: Highlight pair of paren settig command":
  test "Highlight pair of paren settig command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"highlightparen", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.pairOfParen == false)
    block:
      const command = @[ru"highlightparen", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.pairOfParen == true)

suite "Ex mode: Auto delete paren setting command":
  test "Auto delete paren setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"deleteparen", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.autoDeleteParen == false)

    block:
      const command = @[ru"deleteparen", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.autoDeleteParen == true)

suite "Ex mode: Smooth scroll setting command":
  test "Smooth scroll setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"smoothscroll", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.smoothScroll == false)

    block:
      const command = @[ru"smoothscroll", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.smoothScroll == true)

suite "Ex mode: Smooth scroll speed setting command":
  test "Smooth scroll speed setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"scrollspeed", ru"1"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.smoothScrollSpeed == 1)

suite "Ex mode: Highlight current word setting command":
  test "Highlight current word setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"highlightcurrentword", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.currentWord == false)

    block:
      const command = @[ru"highlightcurrentword", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.currentWord == true)

suite "Ex mode: Clipboard setting command":
  test "Clipboard setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"clipboard", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.clipboard.enable == false)

    block:
      const command = @[ru"clipboard", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.clipboard.enable == true)

suite "Ex mode: Highlight full width space command":
  test "Highlight full width space command":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"highlightfullspace", ru"off"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.fullWidthSpace == false)

    block:
      const command = @[ru"highlightfullspace", ru"on"]
      status.exModeCommand(command, 100, 100)
      check(status.settings.highlightSettings.fullWidthSpace == true)

  test "Ex mode: Tab stop setting command 2":
    var status = initEditorStatus()
    status.addNewBuffer

    let defaultTabStop = status.settings.tabStop

    const command = @[ru"tabstop", ru"a"]
    status.exModeCommand(command, 100, 100)

    check(status.settings.tabStop == defaultTabStop)

suite "Ex mode: Smooth scroll speed setting command":
  test "Smooth scroll speed setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"scrollspeed", ru"1"]
    status.exModeCommand(command, 100, 100)

    check(status.settings.smoothScrollSpeed == 1)

  test "Smooth scroll speed setting command 2":
    var status = initEditorStatus()
    status.addNewBuffer

    let defaultSpeed = status.settings.smoothScrollSpeed

    const command = @[ru"scrollspeed", ru"a"]
    status.exModeCommand(command, 100, 100)

    check(status.settings.smoothScrollSpeed == defaultSpeed)

suite "Ex mode: Delete buffer status command":
  test "Delete buffer status command":
    var status = initEditorStatus()
    for i in 0 ..< 2: status.addNewBuffer

    const command = @[ru"bd", ru"0"]
    status.exModeCommand(command, 100, 100)

    check(status.bufStatus.len == 1)

  test "Delete buffer status command 2":
    var status = initEditorStatus()
    for i in 0 ..< 2: status.addNewBuffer

    const command = @[ru"bd", ru"a"]
    status.exModeCommand(command, 100, 100)

    check(status.bufStatus.len == 2)

suite "Ex mode: Open buffer by number command":
  test "Open buffer by number command":
    var status = initEditorStatus()
    for i in 0 ..< 2: status.addNewBuffer

    const command = @[ru"b", ru"0"]
    status.exModeCommand(command, 100, 100)

    check(status.bufferIndexInCurrentWindow == 0)

  test "Open buffer by number command 2":
    var status = initEditorStatus()
    for i in 0 ..< 2: status.addNewBuffer

    const command = @[ru"b", ru"a"]
    status.exModeCommand(command, 100, 100)

    check(status.bufferIndexInCurrentWindow == 1)

suite "Ex mode: Open help command":
  test "Open help command":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    const command = @[ru"help"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufferIndexInCurrentWindow == 1)

    check(status.bufStatus[1].mode == Mode.help)

suite "Ex mode: Open in horizontal split window":
  test "Open in horizontal split window":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    const command = @[ru"sp", ru"newfile"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 2)

  test "Open in horizontal split window 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    const command = @[ru"sp"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 1)

suite "Ex mode: Open in vertical split window":
  test "Open in vertical split window":
    var status = initEditorStatus()
    status.addNewBuffer

    status.resize(100, 100)
    status.update

    const command = @[ru"vs", ru"newfile"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check(status.mainWindow.numOfMainWindow == 2)
    check(status.bufStatus.len == 2)

suite "Ex mode: Create new empty buffer":
  test "Create new empty buffer":
    var status = initEditorStatus()
    status.addNewBuffer("a")

    status.resize(100, 100)
    status.update

    const command = @[ru"ene"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus.len == 2

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

  test "Create new empty buffer 2":
    var status = initEditorStatus()
    status.addNewBuffer

    status.bufStatus[0].countChange = 1

    status.resize(100, 100)
    status.update

    const command = @[ru"ene"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus.len == 1

    check status.bufferIndexInCurrentWindow == 0

suite "Ex mode: New empty buffer in split window horizontally":
  test "New empty buffer in split window horizontally":
    var status = initEditorStatus()
    status.addNewBuffer("a")

    status.resize(100, 100)
    status.update

    const command = @[ru"new"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus.len == 2

    check status.bufferIndexInCurrentWindow == 1

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

    check status.mainWindow.numOfMainWindow == 2

suite "Ex mode: New empty buffer in split window vertically":
  test "New empty buffer in split window vertically":
    var status = initEditorStatus()
    status.addNewBuffer("a")

    status.resize(100, 100)
    status.update

    const command = @[ru"vnew"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus.len == 2

    check status.bufferIndexInCurrentWindow == 1

    check status.bufStatus[0].path == ru"a"
    check status.bufStatus[1].path == ru""

    check status.mainWindow.numOfMainWindow == 2

suite "Ex mode: Filer icon setting command":
  test "Filer icon setting command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"icon", ru"on"]
    status.exModeCommand(command, 100, 100)

    check status.settings.filerSettings.showIcons

  test "Filer icon setting command 2":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"icon", ru"off"]
    status.exModeCommand(command, 100, 100)

    check status.settings.filerSettings.showIcons == false

suite "Ex mode: Put config file command":
  test "Put config file command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"putConfigFile"]
    status.exModeCommand(command, 100, 100)

    check fileExists(getHomeDir() / ".config" / "moe" / "moerc.toml")

suite "Ex mode: Show/Hide git branch name in status line when inactive window":
  test "Show/Hide git branch name in status line when inactive window":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"showGitInactive", ru"off"]
      status.exModeCommand(command, 100, 100)
      check not status.settings.statusLine.showGitInactive

    block:
      const command = @[ru"showGitInactive", ru"on"]
      status.exModeCommand(command, 100, 100)
      check status.settings.statusLine.showGitInactive

suite "Ex mode: Quick run command":
  test "Quick run command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"run"]
    status.exModeCommand(command, 100, 100)

suite "Ex mode: Workspace list command":
  test "Workspace list command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"lsw"]
    status.exModeCommand(command, 100, 100)

suite "Ex mode: Change ignorecase setting command":
  test "Enable ignorecase":
    var status = initEditorStatus()
    status.addNewBuffer
    status.settings.ignorecase = false

    const command = @[ru"ignorecase", ru"on"]
    status.exModeCommand(command, 100, 100)

    check status.settings.ignorecase

  test "Disale ignorecase":
    var status = initEditorStatus()
    status.addNewBuffer
    status.settings.ignorecase = true

    const command = @[ru"ignorecase", ru"off"]
    status.exModeCommand(command, 100, 100)

    check not status.settings.ignorecase

suite "Ex mode: Change smartcase setting command":
  test "Enable smartcase":
    var status = initEditorStatus()
    status.addNewBuffer
    status.settings.smartcase = false

    const command = @[ru"smartcase", ru"on"]
    status.exModeCommand(command, 100, 100)

    check status.settings.ignorecase

  test "Disale smartcase":
    var status = initEditorStatus()
    status.addNewBuffer
    status.settings.smartcase = true

    const command = @[ru"smartcase", ru"off"]
    status.exModeCommand(command, 100, 100)

    check not status.settings.smartcase

suite "Ex mode: e command":
  test "Open dicrecoty (#1042)":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"e", ru"./"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus[1].mode == Mode.filer
    check status.bufStatus[1].path == (ru getCurrentDir()) & ru"/"

suite "Ex mode: q command":
  test "Run q command when opening multiple windows (#1056)":
    var status = initEditorStatus()
    status.addNewBuffer
    status.resize(100, 100)

    status.verticalSplitWindow
    status.resize(100, 100)
    status.changeMode(Mode.ex)

    const command = @[ru"q"]
    status.exModeCommand(command, 100, 100)

    check status.bufStatus[0].mode == Mode.normal

suite "Ex mode: w! command":
  test "Run Force write command":
    const filename = "forceWriteTest.txt"
    writeFile(filename, "test")

    # Set readonly
    setFilePermissions(filename, {fpUserRead})

    var status = initEditorStatus()
    status.addNewBuffer(filename)
    status.resize(100, 100)

    status.bufStatus[0].buffer[0] = ru"abc"

    const command = @[ru"w!"]
    status.exModeCommand(command, 100, 100)

    let entireFile = readFile(filename)
    check entireFile == "abc"

    removeFile(filename)

suite "Ex mode: wq! command":
  test "Run Force write and close window":
    const filename = "forceWriteAndQuitTest.txt"
    writeFile(filename, "test")

    # Set readonly
    setFilePermissions(filename, {fpUserRead})

    var status = initEditorStatus()
    status.addNewBuffer(filename)
    status.resize(100, 100)

    status.verticalSplitWindow
    status.resize(100, 100)

    status.bufStatus[0].buffer[0] = ru"abc"

    const command = @[ru"wq!"]
    status.exModeCommand(command, 100, 100)
    check status.mainWindow.numOfMainWindow == 1

    let entireFile = readFile(filename)
    check entireFile == "abc"

    removeFile(filename)

suite "Ex mode: debug command":
  test "Start debug mode":
    var status = initEditorStatus()
    status.addNewBuffer
    status.changeMode(Mode.ex)

    status.resize(100, 100)
    status.update

    const command = @[ru"debug"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check status.mainWindow.numOfMainWindow == 2

    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[0].prevMode == Mode.ex

    check status.bufStatus[1].mode == Mode.debug
    check status.bufStatus[1].prevMode == Mode.normal

    check currentMainWindowNode.bufferIndex == 0

  test "Start debug mode (Disable all info)":
    var status = initEditorStatus()
    status.addNewBuffer
    status.changeMode(Mode.ex)

    status.settings.debugModeSettings.windowNode.enable = false
    status.settings.debugModeSettings.bufStatus.enable = false

    status.resize(100, 100)
    status.update

    const command = @[ru"debug"]
    status.exModeCommand(command, 100, 100)

    status.resize(100, 100)
    status.update

    check status.mainWindow.numOfMainWindow == 2

    check status.bufStatus[0].mode == Mode.normal
    check status.bufStatus[0].prevMode == Mode.ex

    check status.bufStatus[1].mode == Mode.debug
    check status.bufStatus[1].prevMode == Mode.normal

    check currentMainWindowNode.bufferIndex == 0

suite "Ex mode: highlight current line setting command":
  test "Enable current line highlighting":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"highlightCurrentLine", ru"off"]
    status.exModeCommand(command, 100, 100)
    check not status.settings.view.highlightCurrentLine

  test "Disable current line highlighting":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"highlightCurrentLine", ru"on"]
    status.exModeCommand(command, 100, 100)
    check status.settings.view.highlightCurrentLine

suite "Ex mode: Save Ex command history":
  test "Save \"noh\" command":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"noh"]
    status.exModeCommand(command, 100, 100)

    check status.exCommandHistory == @[ru "noh"]

  test "Save \"noh\" command 2":
    var status = initEditorStatus()
    status.addNewBuffer

    for i in 0 ..< 2:
      const command = @[ru"noh"]
      status.exModeCommand(command, 100, 100)

    check status.exCommandHistory == @[ru "noh"]

  test "Save 2 commands":
    var status = initEditorStatus()
    status.addNewBuffer

    block:
      const command = @[ru"noh"]
      status.exModeCommand(command, 100, 100)

    block:
      const command = @[ru"vs"]
      status.exModeCommand(command, 100, 100)

    check status.exCommandHistory == @[ru "noh", ru "vs"]

  test "Fix #1304":
    var status = initEditorStatus()
    status.addNewBuffer

    const command = @[ru"buildOnSave off"]
    status.exModeCommand(command, 100, 100)

    check status.exCommandHistory == @[ru "buildOnSave off"]
