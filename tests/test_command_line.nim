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

import std/[unittest, options, tables, strutils]

import ../src/moepkg/command_line

suite "CommandLine - processEscapeSequences":
  test "Convert \\n to newline":
    check processEscapeSequences("hello\\nworld") == "hello\nworld"

  test "Convert \\t to tab":
    check processEscapeSequences("hello\\tworld") == "hello\tworld"

  test "Convert \\\\ to backslash":
    check processEscapeSequences("hello\\\\world") == "hello\\world"

  test "Convert \\/ to slash":
    check processEscapeSequences("hello\\/world") == "hello/world"

  test "Multiple escape sequences":
    check processEscapeSequences("a\\nb\\tc\\\\d\\/e") == "a\nb\tc\\d/e"

  test "Unknown escape sequence keeps backslash":
    check processEscapeSequences("hello\\xworld") == "hello\\xworld"

  test "Trailing backslash":
    check processEscapeSequences("hello\\") == "hello\\"

  test "Empty string":
    check processEscapeSequences("") == ""

  test "No escape sequences":
    check processEscapeSequences("hello world") == "hello world"

suite "CommandLine - parseSubstituteCommand basic":
  test "Simple substitute command :s/foo/bar/":
    let result = parseSubstituteCommand(":s/foo/bar/")
    check result.isValid == true
    check result.isGlobal == false
    check result.hasRange == false
    check result.pattern == "foo"
    check result.replacement == "bar"
    check result.flags == ""
    check result.hasReplacement == true

  test "Global substitute command :%s/foo/bar/":
    let result = parseSubstituteCommand(":%s/foo/bar/")
    check result.isValid == true
    check result.isGlobal == true
    check result.hasRange == false
    check result.pattern == "foo"
    check result.replacement == "bar"

  test "Substitute with flags :%s/foo/bar/g":
    let result = parseSubstituteCommand(":%s/foo/bar/g")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == "bar"
    check result.flags == "g"

  test "Substitute with multiple flags :%s/foo/bar/gi":
    let result = parseSubstituteCommand(":%s/foo/bar/gi")
    check result.isValid == true
    check result.flags == "gi"

  test "Substitute without trailing slash :s/foo/bar":
    let result = parseSubstituteCommand(":s/foo/bar")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == "bar"
    check result.hasReplacement == true

  test "Empty replacement :s/foo//":
    let result = parseSubstituteCommand(":s/foo//")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == ""
    check result.hasReplacement == true

  test "Pattern only :s/foo/":
    let result = parseSubstituteCommand(":s/foo/")
    check result.isValid == true
    check result.pattern == "foo"
    check result.hasReplacement == true
    check result.replacement == ""

  test "Without leading colon s/foo/bar/":
    let result = parseSubstituteCommand("s/foo/bar/")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == "bar"

suite "CommandLine - parseSubstituteCommand with escapes":
  test "Escaped slash in pattern :s/foo\\/bar/baz/":
    let result = parseSubstituteCommand(":s/foo\\/bar/baz/")
    check result.isValid == true
    check result.pattern == "foo\\/bar"
    check result.replacement == "baz"

  test "Escaped slash in replacement :s/foo/bar\\/baz/":
    let result = parseSubstituteCommand(":s/foo/bar\\/baz/")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == "bar\\/baz"

  test "Escaped backslash before slash :s/foo\\\\/bar/":
    let result = parseSubstituteCommand(":s/foo\\\\/bar/")
    check result.isValid == true
    check result.pattern == "foo\\\\"
    check result.replacement == "bar"

  test "Escaped slash in pattern parses correctly :s/foo\\/bar/":
    # In :s/foo\/bar/, the \/ is an escaped slash, so pattern is "foo\/bar"
    let result = parseSubstituteCommand(":s/foo\\/bar/")
    check result.isValid == true
    check result.pattern == "foo\\/bar"
    check result.replacement == ""

suite "CommandLine - parseSubstituteCommand with ranges":
  test "Line range :1,10s/foo/bar/":
    let result = parseSubstituteCommand(":1,10s/foo/bar/")
    check result.isValid == true
    check result.hasRange == true
    check result.isGlobal == false
    check result.startLine == 1
    check result.endLine == 10
    check result.pattern == "foo"
    check result.replacement == "bar"

  test "Single line :5s/foo/bar/":
    let result = parseSubstituteCommand(":5s/foo/bar/")
    check result.isValid == true
    check result.hasRange == true
    check result.startLine == 5
    check result.endLine == 5

  test "Current line to line N :.,10s/foo/bar/":
    let result = parseSubstituteCommand(":.,10s/foo/bar/")
    check result.isValid == true
    check result.hasRange == true
    check result.startLine == 0 # 0 means current line
    check result.endLine == 10

  test "Line N to current line :1,.s/foo/bar/":
    let result = parseSubstituteCommand(":1,.s/foo/bar/")
    check result.isValid == true
    check result.hasRange == true
    check result.startLine == 1
    check result.endLine == 0 # 0 means current line

  test "Current line only :.s/foo/bar/":
    let result = parseSubstituteCommand(":.s/foo/bar/")
    check result.isValid == true
    check result.hasRange == true
    check result.startLine == 0
    check result.endLine == 0

suite "CommandLine - parseSubstituteCommand invalid":
  test "Empty command":
    let result = parseSubstituteCommand("")
    check result.isValid == false

  test "Too short command :s":
    let result = parseSubstituteCommand(":s")
    check result.isValid == false

  test "Missing slash :sfoo":
    let result = parseSubstituteCommand(":sfoo")
    check result.isValid == false

  test "Not a substitute command :q":
    let result = parseSubstituteCommand(":q")
    check result.isValid == false

suite "CommandLine - extractSubstitutePattern":
  test "Extract pattern from :%s/foo/bar/g":
    check extractSubstitutePattern(":%s/foo/bar/g") == "foo"

  test "Extract pattern from :s/hello world/bye/":
    check extractSubstitutePattern(":s/hello world/bye/") == "hello world"

  test "Returns empty for invalid command":
    check extractSubstitutePattern(":q") == ""

suite "CommandLine - extractSubstituteReplacement":
  test "Extract replacement from :%s/foo/bar/g":
    let (replacement, hasReplacement) = extractSubstituteReplacement(":%s/foo/bar/g")
    check hasReplacement == true
    check replacement == "bar"

  test "Empty replacement from :s/foo//":
    let (replacement, hasReplacement) = extractSubstituteReplacement(":s/foo//")
    check hasReplacement == true
    check replacement == ""

  test "No replacement yet from :s/foo":
    let (replacement, hasReplacement) = extractSubstituteReplacement(":s/foo")
    check hasReplacement == false
    check replacement == ""

  test "Invalid command returns no replacement":
    let (replacement, hasReplacement) = extractSubstituteReplacement(":q")
    check hasReplacement == false
    check replacement == ""

suite "CommandLine - extractSubstituteFlags":
  test "Extract flags from :%s/foo/bar/gi":
    check extractSubstituteFlags(":%s/foo/bar/gi") == "gi"

  test "No flags returns empty":
    check extractSubstituteFlags(":s/foo/bar/") == ""

  test "Invalid command returns empty":
    check extractSubstituteFlags(":q") == ""

suite "CommandLine - CommandLineParser creation and aliases":
  test "Create new parser":
    let parser = newCommandLineParser()
    check parser.aliases.len == 0

  test "Add alias":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    check parser.aliases["q"] == claQuit

  test "Remove alias":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.removeAlias("q")
    check "q" notin parser.aliases

  test "Clear aliases":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)
    parser.clearAliases()
    check parser.aliases.len == 0

suite "CommandLine - parseCommandLine":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("qa", claQuitAll)
    parser.addAlias("w", claSave)
    parser.addAlias("wa", claSaveAll)
    parser.addAlias("wq", claSaveAndQuit)
    parser.addAlias("x", claSaveAndQuit)
    parser.addAlias("wqa", claSaveAllAndQuit)
    parser.addAlias("e", claEdit)
    parser.addAlias("ene", claEnew)
    parser.addAlias("enew", claEnew)
    parser.addAlias("set", claSet)
    parser.addAlias("help", claHelp)
    parser.addAlias("h", claHelp)
    parser.addAlias("vs", claVSplit)
    parser.addAlias("sp", claHSplit)
    parser.addAlias("new", claNew)
    parser.addAlias("vnew", claVnew)
    parser.addAlias("bn", claBufferNext)
    parser.addAlias("bnext", claBufferNext)
    parser.addAlias("bp", claBufferPrev)
    parser.addAlias("bprev", claBufferPrev)
    parser.addAlias("bf", claBufferFirst)
    parser.addAlias("bfirst", claBufferFirst)
    parser.addAlias("bl", claBufferLast)
    parser.addAlias("blast", claBufferLast)
    parser.addAlias("bd", claBufferDelete)
    parser.addAlias("bdelete", claBufferDelete)
    parser.addAlias("b", claBuffer)
    parser.addAlias("noh", claClearSearchHighlight)
    parser.addAlias("nohlsearch", claClearSearchHighlight)
    parser.addAlias("man", claMan)
    parser.addAlias("theme", claTheme)

  test "Parse :q":
    let cmd = parser.parseCommandLine(":q")
    check cmd.action == claQuit
    check cmd.rawText == ":q"

  test "Parse :q!":
    let cmd = parser.parseCommandLine(":q!")
    check cmd.action == claQuit
    check "force" in cmd.flags

  test "Parse :w with filename":
    let cmd = parser.parseCommandLine(":w myfile.txt")
    check cmd.action == claSave
    check cmd.args == @["myfile.txt"]

  test "Parse :e with filename":
    let cmd = parser.parseCommandLine(":e /path/to/file.nim")
    check cmd.action == claEdit
    check cmd.args == @["/path/to/file.nim"]

  test "Parse line number :123":
    let cmd = parser.parseCommandLine(":123")
    check cmd.action == claGoto
    check cmd.args == @["123"]

  test "Parse shell command :!ls -la":
    let cmd = parser.parseCommandLine(":!ls -la")
    check cmd.action == claShellCommand
    check cmd.args == @["ls -la"]

  test "Parse substitute :s/foo/bar/":
    let cmd = parser.parseCommandLine(":s/foo/bar/")
    check cmd.action == claSubstitute
    check cmd.args == @["s/foo/bar/"]

  test "Parse global substitute :%s/foo/bar/g":
    let cmd = parser.parseCommandLine(":%s/foo/bar/g")
    check cmd.action == claSubstitute
    check cmd.args == @["%s/foo/bar/g"]

  test "Parse range substitute :1,10s/foo/bar/":
    let cmd = parser.parseCommandLine(":1,10s/foo/bar/")
    check cmd.action == claSubstitute
    check cmd.args == @["1,10s/foo/bar/"]

  test "Parse unknown command":
    let cmd = parser.parseCommandLine(":unknowncmd")
    check cmd.action == claUnknown

  test "Parse empty input":
    let cmd = parser.parseCommandLine(":")
    check cmd.action == claUnknown

  test "Parse command without colon":
    let cmd = parser.parseCommandLine("q")
    check cmd.action == claQuit

  test "Parse :set with option":
    let cmd = parser.parseCommandLine(":set number")
    check cmd.action == claSet
    check cmd.args == @["number"]

  test "Parse :set with option and value":
    let cmd = parser.parseCommandLine(":set tabstop=4")
    check cmd.action == claSet
    check cmd.args == @["tabstop=4"]

suite "CommandLine - execute":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("qa", claQuitAll)
    parser.addAlias("w", claSave)
    parser.addAlias("wq", claSaveAndQuit)
    parser.addAlias("e", claEdit)
    parser.addAlias("enew", claEnew)
    parser.addAlias("set", claSet)
    parser.addAlias("help", claHelp)
    parser.addAlias("vs", claVSplit)
    parser.addAlias("sp", claHSplit)
    parser.addAlias("bn", claBufferNext)
    parser.addAlias("bd", claBufferDelete)
    parser.addAlias("b", claBuffer)
    parser.addAlias("noh", claClearSearchHighlight)
    parser.addAlias("man", claMan)
    parser.addAlias("theme", claTheme)

  test "Execute :q":
    let result = parser.parseAndExecute(":q")
    check result.kind == claQuit
    check result.forceQuit == false

  test "Execute :q!":
    let result = parser.parseAndExecute(":q!")
    check result.kind == claQuit
    check result.forceQuit == true

  test "Execute :w":
    let result = parser.parseAndExecute(":w")
    check result.kind == claSave
    check result.filename.isNone
    check result.forceSave == false

  test "Execute :w!":
    let result = parser.parseAndExecute(":w!")
    check result.kind == claSave
    check result.forceSave == true

  test "Execute :w filename":
    let result = parser.parseAndExecute(":w myfile.txt")
    check result.kind == claSave
    check result.filename.isSome
    check result.filename.get() == "myfile.txt"

  test "Execute :wq":
    let result = parser.parseAndExecute(":wq")
    check result.kind == claSaveAndQuit
    check result.forceSaveAndQuit == false

  test "Execute :e with filename":
    let result = parser.parseAndExecute(":e test.nim")
    check result.kind == claEdit
    check result.editFilename == some("test.nim")
    check result.forceEdit == false

  test "Execute :e without filename":
    let result = parser.parseAndExecute(":e")
    check result.kind == claEdit
    check result.editFilename.isNone
    check result.forceEdit == false

  test "Execute :e! without filename":
    let result = parser.parseAndExecute(":e!")
    check result.kind == claEdit
    check result.editFilename.isNone
    check result.forceEdit == true

  test "Execute :e! with filename":
    let result = parser.parseAndExecute(":e! test.nim")
    check result.kind == claEdit
    check result.editFilename == some("test.nim")
    check result.forceEdit == true

  test "Execute :enew":
    let result = parser.parseAndExecute(":enew")
    check result.kind == claEnew

  test "Execute goto line :123":
    let result = parser.parseAndExecute(":123")
    check result.kind == claGoto
    check result.lineNumber == 123

  test "Execute :set number":
    let result = parser.parseAndExecute(":set number")
    check result.kind == claSet
    check result.option == "number"
    check result.value.isNone

  test "Execute :set tabstop=4":
    let result = parser.parseAndExecute(":set tabstop=4")
    check result.kind == claSet
    check result.option == "tabstop"
    check result.value.isSome
    check result.value.get() == "4"

  test "Execute :set without option returns error":
    let result = parser.parseAndExecute(":set")
    check result.kind == claUnknown

  test "Execute substitute :s/foo/bar/":
    let result = parser.parseAndExecute(":s/foo/bar/")
    check result.kind == claSubstitute
    check result.pattern == "foo"
    check result.replacement == "bar"
    check result.substituteFlags == ""
    check result.isGlobal == false

  test "Execute global substitute :%s/foo/bar/g":
    let result = parser.parseAndExecute(":%s/foo/bar/g")
    check result.kind == claSubstitute
    check result.pattern == "foo"
    check result.replacement == "bar"
    check result.substituteFlags == "g"
    check result.isGlobal == true

  test "Execute range substitute :1,10s/foo/bar/":
    let result = parser.parseAndExecute(":1,10s/foo/bar/")
    check result.kind == claSubstitute
    check result.hasRange == true
    check result.startLine == 1
    check result.endLine == 10

  test "Execute substitute with empty pattern returns error":
    let result = parser.parseAndExecute(":s//bar/")
    check result.kind == claUnknown

  test "Execute :help":
    let result = parser.parseAndExecute(":help")
    check result.kind == claHelp
    check result.topic.isNone

  test "Execute :help topic":
    let result = parser.parseAndExecute(":help buffers")
    check result.kind == claHelp
    check result.topic.isSome
    check result.topic.get() == "buffers"

  test "Execute :vs":
    let result = parser.parseAndExecute(":vs")
    check result.kind == claVSplit
    check result.vsplitFilename.isNone

  test "Execute :vs filename":
    let result = parser.parseAndExecute(":vs test.nim")
    check result.kind == claVSplit
    check result.vsplitFilename.isSome
    check result.vsplitFilename.get() == "test.nim"

  test "Execute :sp":
    let result = parser.parseAndExecute(":sp")
    check result.kind == claHSplit
    check result.hsplitFilename.isNone

  test "Execute :bn":
    let result = parser.parseAndExecute(":bn")
    check result.kind == claBufferNext

  test "Execute :bd":
    let result = parser.parseAndExecute(":bd")
    check result.kind == claBufferDelete
    check result.forceBufferDelete == false

  test "Execute :bd!":
    let result = parser.parseAndExecute(":bd!")
    check result.kind == claBufferDelete
    check result.forceBufferDelete == true

  test "Execute :b with buffer number":
    let result = parser.parseAndExecute(":b 3")
    check result.kind == claBuffer
    check result.bufferArg == "3"

  test "Execute :b without argument returns error":
    let result = parser.parseAndExecute(":b")
    check result.kind == claUnknown

  test "Execute :noh":
    let result = parser.parseAndExecute(":noh")
    check result.kind == claClearSearchHighlight

  test "Execute :man with page":
    let result = parser.parseAndExecute(":man ls")
    check result.kind == claMan
    check result.manPage == "ls"

  test "Execute :man without page returns error":
    let result = parser.parseAndExecute(":man")
    check result.kind == claUnknown

  test "Execute :theme with name":
    let result = parser.parseAndExecute(":theme dark")
    check result.kind == claTheme
    check result.themeName == "dark"

  test "Execute :theme without name returns error":
    let result = parser.parseAndExecute(":theme")
    check result.kind == claUnknown

  test "Execute shell command :!ls":
    let result = parser.parseAndExecute(":!ls")
    check result.kind == claShellCommand
    check result.shellCommand == "ls"

  test "Execute empty shell command returns error":
    let result = parser.parseAndExecute(":!")
    check result.kind == claUnknown

suite "CommandLine - isQuitCommand and isSaveCommand":
  test "isQuitCommand returns true for quit commands":
    check isQuitCommand(CommandLineResult(kind: claQuit)) == true
    check isQuitCommand(CommandLineResult(kind: claQuitAll)) == true
    check isQuitCommand(CommandLineResult(kind: claSaveAndQuit)) == true
    check isQuitCommand(CommandLineResult(kind: claSaveAllAndQuit)) == true

  test "isQuitCommand returns false for non-quit commands":
    check isQuitCommand(CommandLineResult(kind: claSave)) == false
    check isQuitCommand(CommandLineResult(kind: claEdit, editFilename: some("test"))) ==
      false

  test "isSaveCommand returns true for save commands":
    check isSaveCommand(CommandLineResult(kind: claSave)) == true
    check isSaveCommand(CommandLineResult(kind: claSaveAll)) == true
    check isSaveCommand(CommandLineResult(kind: claSaveAndQuit)) == true
    check isSaveCommand(CommandLineResult(kind: claSaveAllAndQuit)) == true

  test "isSaveCommand returns false for non-save commands":
    check isSaveCommand(CommandLineResult(kind: claQuit)) == false
    check isSaveCommand(CommandLineResult(kind: claEdit, editFilename: some("test"))) ==
      false

suite "CommandLine - isNoArgumentAction":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)
    parser.addAlias("e", claEdit)
    parser.addAlias("bn", claBufferNext)
    parser.addAlias("set", claSet)
    parser.addAlias("man", claMan)

  test "Quit is a no-argument action":
    check parser.isNoArgumentAction("q") == true

  test "Save is a no-argument action":
    check parser.isNoArgumentAction("w") == true

  test "BufferNext is a no-argument action":
    check parser.isNoArgumentAction("bn") == true

  test "Edit requires argument":
    check parser.isNoArgumentAction("e") == false

  test "Set requires argument":
    check parser.isNoArgumentAction("set") == false

  test "Man requires argument":
    check parser.isNoArgumentAction("man") == false

  test "Unknown command returns false":
    check parser.isNoArgumentAction("unknown") == false

suite "CommandLine - execute additional commands":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("qa", claQuitAll)
    parser.addAlias("w", claSave)
    parser.addAlias("wa", claSaveAll)
    parser.addAlias("wq", claSaveAndQuit)
    parser.addAlias("wqa", claSaveAllAndQuit)
    parser.addAlias("new", claNew)
    parser.addAlias("vnew", claVnew)
    parser.addAlias("bp", claBufferPrev)
    parser.addAlias("bf", claBufferFirst)
    parser.addAlias("bl", claBufferLast)
    parser.addAlias("sp", claHSplit)
    parser.addAlias("filer", claFiler)
    parser.addAlias("log", claLogViewer)
    parser.addAlias("run", claQuickRun)
    parser.addAlias("buffers", claBufferManager)
    parser.addAlias("ls", claBufferManager)
    parser.addAlias("backup", claBackupManager)
    parser.addAlias("recent", claRecentFile)
    parser.addAlias("bg", claBackground)
    parser.addAlias("ju", claJumpList)
    parser.addAlias("jump", claJumpList)
    parser.addAlias("build", claBuild)
    parser.addAlias("debug", claDebug)
    parser.addAlias("conf", claConfig)
    parser.addAlias("putconfigfile", claPutConfigFile)
    parser.addAlias("stripws", claStripWhitespace)
    parser.addAlias("lsplog", claLspLog)
    parser.addAlias("lspformat", claLspFormat)
    parser.addAlias("lsprestart", claLspRestart)
    parser.addAlias("lspfold", claLspFold)
    parser.addAlias("lspexecommand", claLspExecuteCommand)
    parser.addAlias("lspcallhierarchyincoming", claLspCallHierarchyIncoming)
    parser.addAlias("lspcallhierarchyoutgoing", claLspCallHierarchyOutgoing)

  test "Execute :qa":
    let result = parser.parseAndExecute(":qa")
    check result.kind == claQuitAll
    check result.forceQuitAll == false

  test "Execute :qa!":
    let result = parser.parseAndExecute(":qa!")
    check result.kind == claQuitAll
    check result.forceQuitAll == true

  test "Execute :wa":
    let result = parser.parseAndExecute(":wa")
    check result.kind == claSaveAll
    check result.forceSaveAll == false

  test "Execute :wa!":
    let result = parser.parseAndExecute(":wa!")
    check result.kind == claSaveAll
    check result.forceSaveAll == true

  test "Execute :wqa":
    let result = parser.parseAndExecute(":wqa")
    check result.kind == claSaveAllAndQuit
    check result.forceSaveAllAndQuit == false

  test "Execute :wqa!":
    let result = parser.parseAndExecute(":wqa!")
    check result.kind == claSaveAllAndQuit
    check result.forceSaveAllAndQuit == true

  test "Execute :wq with filename":
    let result = parser.parseAndExecute(":wq output.txt")
    check result.kind == claSaveAndQuit
    check result.saveFilename.isSome
    check result.saveFilename.get() == "output.txt"

  test "Execute :wq!":
    let result = parser.parseAndExecute(":wq!")
    check result.kind == claSaveAndQuit
    check result.forceSaveAndQuit == true

  test "Execute :new":
    let result = parser.parseAndExecute(":new")
    check result.kind == claNew

  test "Execute :vnew":
    let result = parser.parseAndExecute(":vnew")
    check result.kind == claVnew

  test "Execute :bp":
    let result = parser.parseAndExecute(":bp")
    check result.kind == claBufferPrev

  test "Execute :bf":
    let result = parser.parseAndExecute(":bf")
    check result.kind == claBufferFirst

  test "Execute :bl":
    let result = parser.parseAndExecute(":bl")
    check result.kind == claBufferLast

  test "Execute :sp with filename":
    let result = parser.parseAndExecute(":sp test.nim")
    check result.kind == claHSplit
    check result.hsplitFilename.isSome
    check result.hsplitFilename.get() == "test.nim"

  test "Execute :Filer":
    let result = parser.parseAndExecute(":filer")
    check result.kind == claFiler
    check result.filerPath.isNone

  test "Execute :Filer with path":
    let result = parser.parseAndExecute(":filer /home/user")
    check result.kind == claFiler
    check result.filerPath.isSome
    check result.filerPath.get() == "/home/user"

  test "Execute :log":
    let result = parser.parseAndExecute(":log")
    check result.kind == claLogViewer

  test "Execute :run":
    let result = parser.parseAndExecute(":run")
    check result.kind == claQuickRun

  test "Execute :buffers":
    let result = parser.parseAndExecute(":buffers")
    check result.kind == claBufferManager

  test "Execute :ls":
    let result = parser.parseAndExecute(":ls")
    check result.kind == claBufferManager

  test "Execute :backup":
    let result = parser.parseAndExecute(":backup")
    check result.kind == claBackupManager

  test "Execute :recent":
    let result = parser.parseAndExecute(":recent")
    check result.kind == claRecentFile

  test "Execute :bg":
    let result = parser.parseAndExecute(":bg")
    check result.kind == claBackground

  test "Execute :ju":
    let result = parser.parseAndExecute(":ju")
    check result.kind == claJumpList

  test "Execute :jump":
    let result = parser.parseAndExecute(":jump")
    check result.kind == claJumpList

  test "Execute :build":
    let result = parser.parseAndExecute(":build")
    check result.kind == claBuild

  test "Execute :debug":
    let result = parser.parseAndExecute(":debug")
    check result.kind == claDebug

  test "Execute :conf":
    let result = parser.parseAndExecute(":conf")
    check result.kind == claConfig

  test "Execute :putConfigFile":
    let result = parser.parseAndExecute(":putconfigfile")
    check result.kind == claPutConfigFile

  test "Execute :stripws":
    let result = parser.parseAndExecute(":stripws")
    check result.kind == claStripWhitespace

  test "Execute :lspLog":
    let result = parser.parseAndExecute(":lsplog")
    check result.kind == claLspLog

  test "Execute :lspFormat":
    let result = parser.parseAndExecute(":lspformat")
    check result.kind == claLspFormat

  test "Execute :lspRestart":
    let result = parser.parseAndExecute(":lsprestart")
    check result.kind == claLspRestart

  test "Execute :lspFold":
    let result = parser.parseAndExecute(":lspfold")
    check result.kind == claLspFold

  test "Execute :lspExeCommand with command":
    let result = parser.parseAndExecute(":lspexecommand someCommand")
    check result.kind == claLspExecuteCommand
    check result.lspCommand == "someCommand"
    check result.lspCommandArgs.len == 0

  test "Execute :lspExeCommand with command and args":
    let result = parser.parseAndExecute(":lspexecommand someCommand arg1 arg2")
    check result.kind == claLspExecuteCommand
    check result.lspCommand == "someCommand"
    check result.lspCommandArgs == @["arg1", "arg2"]

  test "Execute :lspExeCommand without command returns error":
    let result = parser.parseAndExecute(":lspexecommand")
    check result.kind == claUnknown

  test "Execute :lspCallHierarchyIncoming":
    let result = parser.parseAndExecute(":lspcallhierarchyincoming")
    check result.kind == claLspCallHierarchyIncoming

  test "Execute :lspCallHierarchyOutgoing":
    let result = parser.parseAndExecute(":lspcallhierarchyoutgoing")
    check result.kind == claLspCallHierarchyOutgoing

suite "CommandLine - parseCommandLine edge cases":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.addAlias("w", claSave)

  test "Case insensitive command parsing :Q":
    let cmd = parser.parseCommandLine(":Q")
    check cmd.action == claQuit

  test "Case insensitive command parsing :W":
    let cmd = parser.parseCommandLine(":W")
    check cmd.action == claSave

  test "Multiple arguments":
    let cmd = parser.parseCommandLine(":w file1.txt file2.txt")
    check cmd.action == claSave
    check cmd.args == @["file1.txt", "file2.txt"]

  test "Parse current line substitute :.,.s/foo/bar/":
    let cmd = parser.parseCommandLine(":.,. s/foo/bar/")
    # This is not a valid substitute pattern (space before s/)
    check cmd.action == claUnknown

  test "Parse :.s/foo/bar/":
    let cmd = parser.parseCommandLine(":.s/foo/bar/")
    check cmd.action == claSubstitute

suite "CommandLine - parseSubstituteCommand edge cases":
  test "Current line to current line :.,.s/foo/bar/":
    let result = parseSubstituteCommand(":.,. s/foo/bar/")
    # Space before s/ makes it invalid
    check result.isValid == false

  test "Valid :.,.s/foo/bar/ without space":
    let result = parseSubstituteCommand(":.,. s/foo/bar/")
    check result.isValid == false

  test "Invalid range with letters :a,bs/foo/bar/":
    let result = parseSubstituteCommand(":a,bs/foo/bar/")
    check result.isValid == false

  test "Trailing backslash in replacement :s/foo/bar\\":
    let result = parseSubstituteCommand(":s/foo/bar\\")
    check result.isValid == true
    check result.pattern == "foo"
    check result.replacement == "bar\\"

  test "Trailing backslash in flags :s/foo/bar/g\\":
    let result = parseSubstituteCommand(":s/foo/bar/g\\")
    check result.isValid == true
    check result.flags == "g\\"

  test "Complex pattern with regex :s/\\d+/num/g":
    let result = parseSubstituteCommand(":s/\\d+/num/g")
    check result.isValid == true
    check result.pattern == "\\d+"
    check result.replacement == "num"
    check result.flags == "g"

suite "CommandLine - execute edge cases":
  setup:
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)

  test "Execute unknown command":
    let result = parser.parseAndExecute(":nonexistent")
    check result.kind == claUnknown
    check "Not an editor command" in result.errorMessage

  test "Execute goto with invalid line number":
    # Create a parsed command manually with invalid line number
    let cmd =
      ParsedCommand(action: claGoto, args: @["abc"], flags: @[], rawText: ":abc")
    let result = parser.execute(cmd)
    check result.kind == claUnknown
    check "Invalid line number" in result.errorMessage

  test "Execute goto without args":
    let cmd = ParsedCommand(action: claGoto, args: @[], flags: @[], rawText: ":")
    let result = parser.execute(cmd)
    check result.kind == claUnknown
    check "No line number" in result.errorMessage

  test "Execute substitute without args":
    let cmd = ParsedCommand(action: claSubstitute, args: @[], flags: @[], rawText: ":s")
    let result = parser.execute(cmd)
    check result.kind == claUnknown
