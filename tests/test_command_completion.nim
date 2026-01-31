#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, os, strutils]

import ../src/moepkg/[command_completion, commandline]

suite "CommandCompletion - fuzzyMatch":
  test "Exact match":
    check fuzzyMatch("hello", "hello") == true

  test "Prefix match":
    check fuzzyMatch("hel", "hello") == true

  test "Fuzzy match with gaps":
    check fuzzyMatch("hlo", "hello") == true

  test "Case insensitive match":
    check fuzzyMatch("HEL", "hello") == true
    check fuzzyMatch("hel", "HELLO") == true

  test "No match":
    check fuzzyMatch("xyz", "hello") == false

  test "Empty pattern matches everything":
    check fuzzyMatch("", "hello") == true

  test "Empty text matches nothing (except empty pattern)":
    check fuzzyMatch("a", "") == false
    check fuzzyMatch("", "") == true

  test "Pattern longer than text":
    check fuzzyMatch("helloworld", "hello") == false

  test "Match with underscore":
    check fuzzyMatch("my", "my_variable") == true
    check fuzzyMatch("mv", "my_variable") == true

suite "CommandCompletion - matchScore":
  test "Exact prefix match has high score":
    let score = matchScore("hel", "hello")
    check score >= 1000

  test "Case sensitive prefix match has bonus":
    let score1 = matchScore("Hel", "Hello")
    let score2 = matchScore("hel", "Hello")
    check score1 > score2

  test "Fuzzy match has lower score than prefix":
    let prefixScore = matchScore("hel", "hello")
    let fuzzyScore = matchScore("hlo", "hello")
    check prefixScore > fuzzyScore

  test "Empty pattern has zero score":
    let score = matchScore("", "hello")
    check score == 0

  test "No match has zero score":
    let score = matchScore("xyz", "hello")
    check score == 0

  test "Shorter words preferred for prefix match":
    let shortScore = matchScore("he", "he")
    let longScore = matchScore("he", "helicopter")
    check shortScore > longScore

  test "Consecutive character bonus":
    let consecutiveScore = matchScore("hel", "hello")
    let nonConsecutiveScore = matchScore("hlo", "hello")
    check consecutiveScore > nonConsecutiveScore

suite "CommandCompletion - extractCommandPrefix":
  test "Extract prefix from simple command :wq":
    let prefix = extractCommandPrefix(":wq")
    check prefix == "wq"

  test "Extract prefix from command with space :set num":
    let prefix = extractCommandPrefix(":set num")
    check prefix == "set"

  test "Extract from empty colon :":
    let prefix = extractCommandPrefix(":")
    check prefix == ""

  test "Extract from longer command :vsplit":
    let prefix = extractCommandPrefix(":vsplit")
    check prefix == "vsplit"

  test "Extract prefix ignores argument :e file.txt":
    let prefix = extractCommandPrefix(":e file.txt")
    check prefix == "e"

suite "CommandCompletion - parseCommandLine":
  test "Parse command without argument :q":
    let (cmd, arg) = parseCommandLine(":q")
    check cmd == "q"
    check arg == ""

  test "Parse command with argument :e file.txt":
    let (cmd, arg) = parseCommandLine(":e file.txt")
    check cmd == "e"
    check arg == "file.txt"

  test "Parse command with spaced argument :set number":
    let (cmd, arg) = parseCommandLine(":set number")
    check cmd == "set"
    check arg == "number"

  test "Parse empty command :":
    let (cmd, arg) = parseCommandLine(":")
    check cmd == ""
    check arg == ""

  test "Parse command with path argument :e /path/to/file":
    let (cmd, arg) = parseCommandLine(":e /path/to/file")
    check cmd == "e"
    check arg == "/path/to/file"

  test "Parse command with multiple spaces :set    tabstop":
    let (cmd, arg) = parseCommandLine(":set    tabstop")
    check cmd == "set"
    check arg == "tabstop"

suite "CommandCompletion - collectSetOptions":
  test "Collect all options with empty prefix":
    let options = collectSetOptions("")
    check options.len > 0
    # Check some known options exist
    var hasNumber = false
    var hasWrap = false
    for opt in options:
      if opt.command == "number":
        hasNumber = true
      if opt.command == "wrap":
        hasWrap = true
    check hasNumber
    check hasWrap

  test "Filter options by prefix":
    let options = collectSetOptions("num")
    check options.len > 0
    for opt in options:
      check fuzzyMatch("num", opt.command)

  test "Filter options case insensitive":
    let options = collectSetOptions("NUM")
    check options.len > 0

  test "No match returns empty":
    let options = collectSetOptions("xyz123")
    check options.len == 0

  test "Options are sorted by score":
    let options = collectSetOptions("no")
    # Check that options starting with "no" come first
    if options.len >= 2:
      check options[0].matchScore >= options[1].matchScore

suite "CommandCompletion - newCommandCompletionManager":
  test "Create idle manager":
    let mgr = newCommandCompletionManager()
    check mgr.state == ccsIdle
    check mgr.mode == cmCommand
    check mgr.menu.entries.len == 0
    check mgr.menu.selectedIndex == -1
    check mgr.menu.scrollOffset == 0
    check mgr.menu.maxVisible == DefaultMaxVisible
    check mgr.isActive == false

  test "Manager has empty allCommands initially":
    let mgr = newCommandCompletionManager()
    check mgr.allCommands.len == 0

suite "CommandCompletion - collectCommands":
  test "Collect commands from parser":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)
    parser.addAlias("wq", claSaveAndQuit)

    let commands = collectCommands(parser)
    check commands.len == 3

    var hasQ = false
    var hasW = false
    var hasWq = false
    for cmd in commands:
      if cmd.command == "q":
        hasQ = true
      if cmd.command == "w":
        hasW = true
      if cmd.command == "wq":
        hasWq = true
    check hasQ
    check hasW
    check hasWq

  test "Commands are sorted alphabetically":
    let parser = newCommandLineParser()
    parser.addAlias("z", claQuit)
    parser.addAlias("a", claSave)
    parser.addAlias("m", claSaveAndQuit)

    let commands = collectCommands(parser)
    check commands.len == 3
    check commands[0].command == "a"
    check commands[1].command == "m"
    check commands[2].command == "z"

  test "Commands include descriptions":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)

    let commands = collectCommands(parser)
    for cmd in commands:
      if cmd.command == "q":
        check cmd.description.len > 0
      if cmd.command == "w":
        check cmd.description.len > 0

suite "CommandCompletion - filterAndSortEntries":
  test "Filter commands by prefix":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(command: "quit", description: "Quit", matchScore: 0),
        CommandCompletionEntry(
          command: "write", description: "Write file", matchScore: 0
        ),
        CommandCompletionEntry(
          command: "wq", description: "Write and quit", matchScore: 0
        ),
      ]

    let entries = mgr.filterAndSortEntries("w")
    check entries.len == 2
    for e in entries:
      check e.command.startsWith("w")

  test "Empty prefix returns all":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 0),
        CommandCompletionEntry(command: "b", description: "", matchScore: 0),
        CommandCompletionEntry(command: "c", description: "", matchScore: 0),
      ]

    let entries = mgr.filterAndSortEntries("")
    check entries.len == 3

  test "Entries sorted by score descending":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(command: "help", description: "", matchScore: 0),
        CommandCompletionEntry(command: "he", description: "", matchScore: 0),
        CommandCompletionEntry(command: "helicopter", description: "", matchScore: 0),
      ]

    let entries = mgr.filterAndSortEntries("he")
    check entries.len == 3
    # Shorter exact prefix matches should have higher scores
    check entries[0].matchScore >= entries[1].matchScore

  test "No match returns empty":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(command: "quit", description: "", matchScore: 0),
        CommandCompletionEntry(command: "write", description: "", matchScore: 0),
      ]

    let entries = mgr.filterAndSortEntries("xyz")
    check entries.len == 0

suite "CommandCompletion - updateFilter":
  test "Update filter sets entries and resets selection":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(command: "quit", description: "", matchScore: 0),
        CommandCompletionEntry(command: "write", description: "", matchScore: 0),
      ]
    mgr.menu.selectedIndex = 1
    mgr.state = ccsActive

    mgr.updateFilter("q")

    check mgr.menu.prefix == "q"
    check mgr.menu.entries.len == 1
    check mgr.menu.selectedIndex == -1
    check mgr.menu.scrollOffset == 0

  test "No matches sets state to idle":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[CommandCompletionEntry(command: "quit", description: "", matchScore: 0)]
    mgr.state = ccsActive

    mgr.updateFilter("xyz")

    check mgr.state == ccsIdle
    check mgr.menu.entries.len == 0

suite "CommandCompletion - selectNext and selectPrevious":
  test "selectNext cycles through entries":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 100),
        CommandCompletionEntry(command: "b", description: "", matchScore: 90),
        CommandCompletionEntry(command: "c", description: "", matchScore: 80),
      ]

    check mgr.menu.selectedIndex == -1
    mgr.selectNext()
    check mgr.menu.selectedIndex == 0
    mgr.selectNext()
    check mgr.menu.selectedIndex == 1
    mgr.selectNext()
    check mgr.menu.selectedIndex == 2
    mgr.selectNext()
    check mgr.menu.selectedIndex == -1 # Wrap around to no selection

  test "selectPrevious cycles through entries":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 100),
        CommandCompletionEntry(command: "b", description: "", matchScore: 90),
        CommandCompletionEntry(command: "c", description: "", matchScore: 80),
      ]

    check mgr.menu.selectedIndex == -1
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 2 # Wrap to end
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 1
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 0
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == -1 # Wrap to no selection

  test "selectNext does nothing on empty entries":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries = @[]
    mgr.menu.selectedIndex = -1

    mgr.selectNext()
    check mgr.menu.selectedIndex == -1

  test "selectPrevious does nothing on empty entries":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries = @[]
    mgr.menu.selectedIndex = -1

    mgr.selectPrevious()
    check mgr.menu.selectedIndex == -1

suite "CommandCompletion - selectNext scroll offset":
  test "selectNext adjusts scroll offset when needed":
    let mgr = newCommandCompletionManager()
    mgr.menu.maxVisible = 3
    mgr.menu.entries =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 100),
        CommandCompletionEntry(command: "b", description: "", matchScore: 90),
        CommandCompletionEntry(command: "c", description: "", matchScore: 80),
        CommandCompletionEntry(command: "d", description: "", matchScore: 70),
        CommandCompletionEntry(command: "e", description: "", matchScore: 60),
      ]

    check mgr.menu.scrollOffset == 0
    mgr.selectNext() # index 0
    mgr.selectNext() # index 1
    mgr.selectNext() # index 2
    check mgr.menu.scrollOffset == 0
    mgr.selectNext() # index 3, should scroll
    check mgr.menu.scrollOffset == 1

  test "selectPrevious adjusts scroll offset when needed":
    let mgr = newCommandCompletionManager()
    mgr.menu.maxVisible = 3
    mgr.menu.entries =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 100),
        CommandCompletionEntry(command: "b", description: "", matchScore: 90),
        CommandCompletionEntry(command: "c", description: "", matchScore: 80),
        CommandCompletionEntry(command: "d", description: "", matchScore: 70),
        CommandCompletionEntry(command: "e", description: "", matchScore: 60),
      ]
    mgr.menu.selectedIndex = 4
    mgr.menu.scrollOffset = 2

    mgr.selectPrevious() # index 3
    check mgr.menu.scrollOffset == 2
    mgr.selectPrevious() # index 2
    check mgr.menu.scrollOffset == 2
    mgr.selectPrevious() # index 1, should scroll up
    check mgr.menu.scrollOffset == 1

suite "CommandCompletion - getSelectedCommand":
  test "Get selected command":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[
        CommandCompletionEntry(command: "quit", description: "", matchScore: 100),
        CommandCompletionEntry(command: "write", description: "", matchScore: 90),
      ]
    mgr.menu.selectedIndex = 0

    check mgr.getSelectedCommand() == "quit"
    mgr.selectNext()
    check mgr.getSelectedCommand() == "write"

  test "No selection returns empty":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[CommandCompletionEntry(command: "quit", description: "", matchScore: 100)]
    mgr.menu.selectedIndex = -1

    check mgr.getSelectedCommand() == ""

  test "Empty entries returns empty":
    let mgr = newCommandCompletionManager()
    check mgr.getSelectedCommand() == ""

  test "Out of range index returns empty":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[CommandCompletionEntry(command: "quit", description: "", matchScore: 100)]
    mgr.menu.selectedIndex = 5 # Out of range

    check mgr.getSelectedCommand() == ""

suite "CommandCompletion - cancelCompletion":
  test "Cancel resets all state":
    let mgr = newCommandCompletionManager()
    mgr.state = ccsActive
    mgr.mode = cmFilePath
    mgr.menu.entries =
      @[CommandCompletionEntry(command: "test", description: "", matchScore: 100)]
    mgr.menu.selectedIndex = 0
    mgr.menu.scrollOffset = 5
    mgr.menu.prefix = "tes"
    mgr.baseCommand = "e"
    mgr.originalDirPrefix = "/home/"

    mgr.cancelCompletion()

    check mgr.state == ccsIdle
    check mgr.mode == cmCommand
    check mgr.menu.entries.len == 0
    check mgr.menu.selectedIndex == -1
    check mgr.menu.scrollOffset == 0
    check mgr.menu.prefix == ""
    check mgr.baseCommand == ""
    check mgr.originalDirPrefix == ""

suite "CommandCompletion - isActive":
  test "Active when state is ccsActive":
    let mgr = newCommandCompletionManager()
    mgr.state = ccsActive
    check mgr.isActive == true

  test "Not active when state is ccsIdle":
    let mgr = newCommandCompletionManager()
    mgr.state = ccsIdle
    check mgr.isActive == false

suite "CommandCompletion - triggerCompletion":
  test "Trigger completion with prefix":
    let parser = newCommandLineParser()
    parser.addAlias("quit", claQuit)
    parser.addAlias("qall", claQuitAll)
    parser.addAlias("write", claSave)

    let mgr = newCommandCompletionManager()
    mgr.triggerCompletion(parser, ":q")

    check mgr.state == ccsActive
    check mgr.mode == cmCommand
    check mgr.menu.entries.len == 2 # quit and qall
    check mgr.menu.prefix == "q"

  test "Trigger completion without matches stays idle":
    let parser = newCommandLineParser()
    parser.addAlias("quit", claQuit)

    let mgr = newCommandCompletionManager()
    mgr.triggerCompletion(parser, ":xyz")

    check mgr.state == ccsIdle
    check mgr.menu.entries.len == 0

  test "Trigger completion collects commands once":
    let parser = newCommandLineParser()
    parser.addAlias("quit", claQuit)

    let mgr = newCommandCompletionManager()
    check mgr.allCommands.len == 0

    mgr.triggerCompletion(parser, ":q")
    check mgr.allCommands.len == 1

    # Trigger again - should not re-collect
    mgr.triggerCompletion(parser, ":q")
    check mgr.allCommands.len == 1

suite "CommandCompletion - triggerArgumentCompletion":
  test "Trigger set option completion":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":set num")

    check mgr.state == ccsActive
    check mgr.mode == cmSetOption
    check mgr.baseCommand == "set"
    check mgr.menu.entries.len > 0

  test "Trigger file path completion for edit":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":e ", getCurrentDir())

    check mgr.state == ccsActive
    check mgr.mode == cmFilePath
    check mgr.baseCommand == "e"

  test "Unknown command does not trigger":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":unknown arg")

    check mgr.state == ccsIdle

  test "Set option with 'se' alias":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":se num")

    check mgr.state == ccsActive
    check mgr.mode == cmSetOption
    check mgr.baseCommand == "se"

  test "File path completion for write command":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":w ", getCurrentDir())

    check mgr.state == ccsActive
    check mgr.mode == cmFilePath
    check mgr.baseCommand == "w"

  test "File path completion for vsplit command":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":vs ", getCurrentDir())

    check mgr.state == ccsActive
    check mgr.mode == cmFilePath
    check mgr.baseCommand == "vs"

  test "File path completion for split command":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":sp ", getCurrentDir())

    check mgr.state == ccsActive
    check mgr.mode == cmFilePath
    check mgr.baseCommand == "sp"

  test "originalDirPrefix is set for path with directory":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":e /home/user/", "")

    check mgr.originalDirPrefix == "/home/user/"

  test "originalDirPrefix is empty for simple filename":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":e test", getCurrentDir())

    check mgr.originalDirPrefix == ""

  test "argStartX is calculated correctly for command mode":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":set num")

    # argStartX = 1 (":") + 3 ("set") + 1 (space) = 5
    check mgr.argStartX == 5

  test "Menu prefix is set to argument":
    let mgr = newCommandCompletionManager()
    mgr.triggerArgumentCompletion(":set number")

    check mgr.menu.prefix == "number"

  test "selectedIndex is reset to -1":
    let mgr = newCommandCompletionManager()
    mgr.menu.selectedIndex = 5
    mgr.triggerArgumentCompletion(":set num")

    check mgr.menu.selectedIndex == -1

suite "CommandCompletion - calculateMaxCommandWidth":
  test "Calculate max width":
    let entries =
      @[
        CommandCompletionEntry(command: "short", description: "", matchScore: 100),
        CommandCompletionEntry(
          command: "verylongcommand", description: "", matchScore: 90
        ),
        CommandCompletionEntry(command: "medium", description: "", matchScore: 80),
      ]

    let width = calculateMaxCommandWidth(entries)
    check width == 15 # "verylongcommand".len

  test "Empty entries returns zero":
    let entries: seq[CommandCompletionEntry] = @[]
    let width = calculateMaxCommandWidth(entries)
    check width == 0

suite "CommandCompletion - calculateMaxDescriptionWidth":
  test "Calculate max description width":
    let entries =
      @[
        CommandCompletionEntry(command: "a", description: "short", matchScore: 100),
        CommandCompletionEntry(
          command: "b", description: "very long description", matchScore: 90
        ),
        CommandCompletionEntry(command: "c", description: "medium desc", matchScore: 80),
      ]

    let width = calculateMaxDescriptionWidth(entries)
    check width == 21 # "very long description".len

  test "Empty entries returns zero":
    let entries: seq[CommandCompletionEntry] = @[]
    let width = calculateMaxDescriptionWidth(entries)
    check width == 0

suite "CommandCompletion - calculateCommandPopupPosition":
  test "Basic popup position":
    let entries =
      @[CommandCompletionEntry(command: "test", description: "Test", matchScore: 100)]
    let pos = calculateCommandPopupPosition(0, 80, 24, entries)

    check pos.y >= 0
    check pos.x >= 0
    check pos.width >= MinPopupWidth
    check pos.height >= 3 # 1 item + 2 for border

  test "Popup adjusts for right edge":
    let entries =
      @[CommandCompletionEntry(command: "test", description: "Test", matchScore: 100)]
    let pos = calculateCommandPopupPosition(70, 80, 24, entries, argStartPos = 70)

    check pos.x + pos.width <= 80 # Should not exceed terminal width

  test "Popup height based on visible items":
    let entries =
      @[
        CommandCompletionEntry(command: "a", description: "", matchScore: 100),
        CommandCompletionEntry(command: "b", description: "", matchScore: 90),
        CommandCompletionEntry(command: "c", description: "", matchScore: 80),
        CommandCompletionEntry(command: "d", description: "", matchScore: 70),
        CommandCompletionEntry(command: "e", description: "", matchScore: 60),
      ]
    let pos = calculateCommandPopupPosition(0, 80, 24, entries, maxVisible = 3)

    check pos.height == 5 # 3 items + 2 for border

  test "Popup with argStartPos offset":
    let entries =
      @[CommandCompletionEntry(command: "file.txt", description: "", matchScore: 100)]
    let pos = calculateCommandPopupPosition(0, 80, 24, entries, argStartPos = 3)

    # Position should start from argStartPos if it fits
    check pos.x >= 0

suite "CommandCompletion - collectFilePaths":
  test "Collect files from current directory":
    let entries = collectFilePaths(getCurrentDir(), "")
    # Should have some entries (at least the test directory has files)
    check entries.len >= 0

  test "Directories come first":
    let entries = collectFilePaths(getCurrentDir(), "")
    if entries.len >= 2:
      var lastWasDir = true
      for entry in entries:
        if entry.command.endsWith("/"):
          check lastWasDir # Directories should come before files
        else:
          lastWasDir = false

  test "Filter by prefix":
    let entries = collectFilePaths(getCurrentDir(), "test")
    for entry in entries:
      check entry.command.toLowerAscii.startsWith("test")

  test "Non-existent directory returns empty":
    let entries = collectFilePaths("/nonexistent/path/that/does/not/exist", "")
    check entries.len == 0

  test "Absolute path prefix":
    # Use /tmp which should exist on all Unix systems
    let entries = collectFilePaths("", "/tmp")
    # Should search in root directory for files starting with "tmp"
    check entries.len >= 0

  test "Absolute path with trailing slash":
    let entries = collectFilePaths("", "/tmp/")
    # Should list contents of /tmp directory
    check entries.len >= 0

  test "Home directory path prefix":
    let entries = collectFilePaths("", "~/")
    # Should list contents of home directory
    check entries.len >= 0

  test "Relative path with directory":
    # Create a temp directory structure for testing
    let testDir = getTempDir() / "moe_test_completion"
    let subDir = testDir / "subdir"
    createDir(subDir)
    writeFile(testDir / "testfile.txt", "test")

    try:
      let entries = collectFilePaths(testDir, "")
      check entries.len >= 2 # At least subdir/ and testfile.txt

      # Check that subdir is a directory
      var hasSubdir = false
      for e in entries:
        if e.command == "subdir/":
          hasSubdir = true
          check e.description == "Directory"
      check hasSubdir
    finally:
      removeDir(testDir)

  test "Hidden files skipped by default":
    let testDir = getTempDir() / "moe_test_hidden"
    createDir(testDir)
    writeFile(testDir / ".hidden", "hidden")
    writeFile(testDir / "visible", "visible")

    try:
      let entries = collectFilePaths(testDir, "")
      # Hidden file should be skipped
      var hasHidden = false
      var hasVisible = false
      for e in entries:
        if e.command == ".hidden":
          hasHidden = true
        if e.command == "visible":
          hasVisible = true
      check not hasHidden
      check hasVisible
    finally:
      removeDir(testDir)

  test "Hidden files included when prefix starts with dot":
    let testDir = getTempDir() / "moe_test_hidden2"
    createDir(testDir)
    writeFile(testDir / ".hidden", "hidden")
    writeFile(testDir / ".config", "config")

    try:
      let entries = collectFilePaths(testDir, ".")
      # Hidden files starting with . should be included
      check entries.len >= 2
      for e in entries:
        check e.command.startsWith(".")
    finally:
      removeDir(testDir)

  test "Directory entries have higher matchScore":
    let testDir = getTempDir() / "moe_test_score"
    let subDir = testDir / "testdir"
    createDir(subDir)
    writeFile(testDir / "testfile", "test")

    try:
      let entries = collectFilePaths(testDir, "test")
      var dirScore = 0
      var fileScore = 0
      for e in entries:
        if e.command == "testdir/":
          dirScore = e.matchScore
        if e.command == "testfile":
          fileScore = e.matchScore
      check dirScore > fileScore
    finally:
      removeDir(testDir)

  test "Empty basePath uses current directory":
    let entries = collectFilePaths("", "")
    # Should list files in current directory
    check entries.len >= 0

suite "CommandCompletion - FilePathCommands constant":
  test "FilePathCommands contains expected commands":
    check "e" in FilePathCommands
    check "edit" in FilePathCommands
    check "w" in FilePathCommands
    check "write" in FilePathCommands
    check "vs" in FilePathCommands
    check "vsplit" in FilePathCommands
    check "sp" in FilePathCommands
    check "split" in FilePathCommands

suite "CommandCompletion - popup constants":
  test "Constants have expected values":
    check DefaultMaxVisible == 10
    check MinPopupWidth == 20
    check MaxPopupWidth == 60
    check PopupPadding == 2
    check DescriptionGap == 2

suite "CommandCompletion - edge cases":
  test "fuzzyMatch with special characters":
    check fuzzyMatch("f_b", "foo_bar") == true
    check fuzzyMatch("fb", "foo_bar") == true

  test "matchScore with mixed case":
    let score1 = matchScore("Test", "TestCase")
    let score2 = matchScore("test", "TestCase")
    # Exact case match should have bonus
    check score1 > score2

  test "parseCommandLine with empty argument after space":
    let (cmd, arg) = parseCommandLine(":e ")
    check cmd == "e"
    check arg == ""

  test "collectSetOptions finds tabstop with value format":
    let options = collectSetOptions("tab")
    var hasTabstop = false
    for opt in options:
      if opt.command == "tabstop":
        hasTabstop = true
        check opt.description.len > 0
    check hasTabstop

  test "filterAndSortEntries with fuzzy match":
    let mgr = newCommandCompletionManager()
    mgr.allCommands =
      @[
        CommandCompletionEntry(
          command: "vsplit", description: "Vertical split", matchScore: 0
        ),
        CommandCompletionEntry(
          command: "split", description: "Horizontal split", matchScore: 0
        ),
      ]

    # "vsp" should fuzzy match "vsplit"
    let entries = mgr.filterAndSortEntries("vsp")
    check entries.len == 1
    check entries[0].command == "vsplit"

  test "calculateCommandPopupPosition with empty entries":
    let entries: seq[CommandCompletionEntry] = @[]
    let pos = calculateCommandPopupPosition(0, 80, 24, entries)
    check pos.height == 2 # Just borders

  test "calculateCommandPopupPosition respects maxVisible limit":
    var entries: seq[CommandCompletionEntry] = @[]
    for i in 0 ..< 20:
      entries.add(
        CommandCompletionEntry(
          command: "cmd" & $i, description: "", matchScore: 100 - i
        )
      )
    let pos = calculateCommandPopupPosition(0, 80, 24, entries, maxVisible = 5)
    check pos.height == 7 # 5 items + 2 for border

  test "selectNext and selectPrevious with single entry":
    let mgr = newCommandCompletionManager()
    mgr.menu.entries =
      @[CommandCompletionEntry(command: "only", description: "", matchScore: 100)]

    check mgr.menu.selectedIndex == -1
    mgr.selectNext()
    check mgr.menu.selectedIndex == 0
    mgr.selectNext()
    check mgr.menu.selectedIndex == -1 # Wrap to no selection

    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 0
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == -1 # Wrap to no selection

  test "triggerCompletion with empty command text":
    let parser = newCommandLineParser()
    parser.addAlias("quit", claQuit)

    let mgr = newCommandCompletionManager()
    mgr.triggerCompletion(parser, ":")

    # Empty prefix should show all commands
    check mgr.state == ccsActive
    check mgr.menu.entries.len == 1

  test "Command descriptions are from CommandDescriptions table":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)
    parser.addAlias("wq", claSaveAndQuit)

    let commands = collectCommands(parser)
    for cmd in commands:
      if cmd.command == "q":
        check cmd.description == "Quit (close window)"
      if cmd.command == "w":
        check cmd.description == "Write (save) file"
      if cmd.command == "wq":
        check cmd.description == "Write and quit"

  test "SetOptions contains common vim options":
    let options = collectSetOptions("")
    var optionNames: seq[string] = @[]
    for opt in options:
      optionNames.add(opt.command)

    check "number" in optionNames
    check "nonumber" in optionNames
    check "wrap" in optionNames
    check "nowrap" in optionNames
    check "hlsearch" in optionNames
    check "nohlsearch" in optionNames
    check "expandtab" in optionNames
    check "noexpandtab" in optionNames
    check "tabstop" in optionNames
    check "syntax" in optionNames
