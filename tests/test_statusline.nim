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

## Tests for status_line.nim - Status line rendering for moe editor

import std/[unittest, options, tables, strutils, os, osproc]

import pkg/celina

import ../src/moepkg/[types, modes, registers, config, git_cache, unicode_utils]
import ../src/moepkg/buffer/[core, edit]
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/status_line {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let cfg = newEditorConfig()
  cfg.statusLine.multipleStatusLine = false
  EditorState(
    activeWindow: EditorWindow(
      cursor: BufferPosition(line: 0, column: 0),
      preferredColumn: -1,
      screenCursor: CursorPosition(x: 0, y: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
    ),
    display:
      DisplaySettings(showLineCount: true, showLinePercentage: true, showEncoding: true),
    config: cfg,
    windowDisplay: WindowDisplayState(viewportReservedLines: 2),
    pendingInput: PendingInputState(
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
    overlay: none(OverlayKind),
  )

proc createTestBuffer(): celina.Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

proc createTestTextBuffer(
    filePath: string = "", modified: bool = false, content: string = ""
): TextBuffer =
  ## Create a TextBuffer for testing with optional file path and content
  result = newTextBuffer(content)
  if filePath.len > 0:
    result.filePath = some(filePath)
  if modified:
    # Simulate modification by incrementing changeSeq
    result.changeSeq = 1

proc createMultiLineBuffer(lineCount: int, filePath: string = ""): TextBuffer =
  ## Create a TextBuffer with multiple lines for testing
  var lines: seq[string] = @[]
  for i in 0 ..< lineCount:
    lines.add("line" & $i)
  createTestTextBuffer(filePath, false, lines.join("\n"))

proc createTestStatusLineConfig(): StatusLineConfig =
  ## Create a default StatusLineConfig for testing
  StatusLineConfig(
    multipleStatusLine: true,
    merge: false,
    mode: true,
    filename: true,
    changedMark: true,
    directory: true,
    gitChangedLines: false, # Disable for testing (requires git repo)
    gitBranchName: false, # Disable for testing (requires git repo)
    showGitInactive: false,
    showModeInactive: false,
    setupText: "",
  )

proc getBufferLine(buffer: celina.Buffer, y: int): string =
  ## Extract a line from celina Buffer as string
  result = ""
  for x in 0 ..< buffer.area.width:
    result.add(buffer[x, y].symbol)

suite "StatusLine - toggleStatusLine":
  test "Toggle from true to false":
    var state = createTestState()
    check state.showStatusLine == true

    toggleStatusLine(state)

    check state.showStatusLine == false

  test "Toggle from false to true":
    var state = createTestState()
    state.showStatusLine = false

    toggleStatusLine(state)

    check state.showStatusLine == true

  test "Toggle twice returns to original state":
    var state = createTestState()
    let original = state.showStatusLine

    toggleStatusLine(state)
    toggleStatusLine(state)

    check state.showStatusLine == original

suite "StatusLine - setStatusLineVisible":
  test "Set visible to true":
    var state = createTestState()
    state.showStatusLine = false

    setStatusLineVisible(state, true)

    check state.showStatusLine == true

  test "Set visible to false":
    var state = createTestState()
    state.showStatusLine = true

    setStatusLineVisible(state, false)

    check state.showStatusLine == false

  test "Set to same value (idempotent)":
    var state = createTestState()
    state.showStatusLine = true

    setStatusLineVisible(state, true)

    check state.showStatusLine == true

suite "StatusLine - toggleLineCount":
  test "Toggle from true to false":
    var state = createTestState()
    check state.display.showLineCount == true

    toggleLineCount(state)

    check state.display.showLineCount == false

  test "Toggle from false to true":
    var state = createTestState()
    state.display.showLineCount = false

    toggleLineCount(state)

    check state.display.showLineCount == true

suite "StatusLine - setLineCountVisible":
  test "Set visible to true":
    var state = createTestState()
    state.display.showLineCount = false

    setLineCountVisible(state, true)

    check state.display.showLineCount == true

  test "Set visible to false":
    var state = createTestState()
    state.display.showLineCount = true

    setLineCountVisible(state, false)

    check state.display.showLineCount == false

suite "StatusLine - toggleLinePercentage":
  test "Toggle from true to false":
    var state = createTestState()
    check state.display.showLinePercentage == true

    toggleLinePercentage(state)

    check state.display.showLinePercentage == false

  test "Toggle from false to true":
    var state = createTestState()
    state.display.showLinePercentage = false

    toggleLinePercentage(state)

    check state.display.showLinePercentage == true

suite "StatusLine - setLinePercentageVisible":
  test "Set visible to true":
    var state = createTestState()
    state.display.showLinePercentage = false

    setLinePercentageVisible(state, true)

    check state.display.showLinePercentage == true

  test "Set visible to false":
    var state = createTestState()
    state.display.showLinePercentage = true

    setLinePercentageVisible(state, false)

    check state.display.showLinePercentage == false

suite "StatusLine - toggleEncoding":
  test "Toggle from true to false":
    var state = createTestState()
    check state.display.showEncoding == true

    toggleEncoding(state)

    check state.display.showEncoding == false

  test "Toggle from false to true":
    var state = createTestState()
    state.display.showEncoding = false

    toggleEncoding(state)

    check state.display.showEncoding == true

suite "StatusLine - setEncodingVisible":
  test "Set visible to true":
    var state = createTestState()
    state.display.showEncoding = false

    setEncodingVisible(state, true)

    check state.display.showEncoding == true

  test "Set visible to false":
    var state = createTestState()
    state.display.showEncoding = true

    setEncodingVisible(state, false)

    check state.display.showEncoding == false

suite "StatusLine - setLineEndingVisible":
  test "Set visible to true":
    var state = createTestState()
    state.display.showLineEnding = false

    setLineEndingVisible(state, true)

    check state.display.showLineEnding == true

  test "Set visible to false":
    var state = createTestState()
    state.display.showLineEnding = true

    setLineEndingVisible(state, false)

    check state.display.showLineEnding == false

suite "StatusLine - toggleMultiStatusLine":
  test "Toggle from false to true":
    var state = createTestState()
    check state.multiStatusLine == false

    toggleMultiStatusLine(state)

    check state.multiStatusLine == true

  test "Toggle from true to false":
    var state = createTestState()
    state.multiStatusLine = true

    toggleMultiStatusLine(state)

    check state.multiStatusLine == false

suite "StatusLine - setMultiStatusLine":
  test "Set enabled to true":
    var state = createTestState()
    state.multiStatusLine = false

    setMultiStatusLine(state, true)

    check state.multiStatusLine == true

  test "Set enabled to false":
    var state = createTestState()
    state.multiStatusLine = true

    setMultiStatusLine(state, false)

    check state.multiStatusLine == false

suite "StatusLine - buildFileDisplay":
  test "Display [No Name] for unnamed buffer":
    let textBuffer = createTestTextBuffer()
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " [No Name]"

  test "Display full path when directory is enabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " /path/to/file.nim"

  test "Display filename only when directory is disabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " file.nim"

  test "Display changed mark for modified buffer":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " file.nim [+]"

  test "No changed mark when changedMark is disabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " file.nim"

  test "No changed mark for unmodified buffer":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " file.nim"

  test "Display absolute directory path with trailing slash in Filer mode":
    # Use an existing directory so dirExists returns true
    let absPath = getCurrentDir()
    let textBuffer = createTestTextBuffer(absPath)
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Filer, config)

    check result == " " & absPath & "/"

  test "Display empty string in Filer mode with no path":
    let textBuffer = createTestTextBuffer()
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Filer, config)

    check result == ""

  test "Display empty when both directory and filename disabled, not modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " "
    check "file.nim" notin result
    check "/path/to" notin result

  test "Display only space when both directory and filename disabled, bug fix regression":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    # Before fix, else branch incorrectly did extractFilename() so result was " file.nim"
    check result != " file.nim"
    check result == " "

  test "Display only changed mark when both directory and filename disabled but modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " [+]"
    check "file.nim" notin result

  test "No changed mark when both disabled and changedMark disabled even if modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " "
    check "[+]" notin result

  test "Directory takes precedence over filename flag":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = true
    config.filename = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config)

    check result == " /path/to/file.nim"

  test "Directory enabled ignores filename false vs true":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config1 = createTestStatusLineConfig()
    config1.directory = true
    config1.filename = true
    var config2 = createTestStatusLineConfig()
    config2.directory = true
    config2.filename = false

    check buildFileDisplay(textBuffer, EditorMode.Normal, config1) ==
      buildFileDisplay(textBuffer, EditorMode.Normal, config2)
    check buildFileDisplay(textBuffer, EditorMode.Normal, config1) ==
      " /path/to/file.nim"

  test "All combinations of directory/filename for Normal mode":
    let textBuffer = createTestTextBuffer("/a/b/c.nim")
    var config = createTestStatusLineConfig()
    config.changedMark = false
    # directory=true, filename=true -> full path
    config.directory = true
    config.filename = true
    check buildFileDisplay(textBuffer, EditorMode.Normal, config) == " /a/b/c.nim"
    # directory=true, filename=false -> still full path
    config.directory = true
    config.filename = false
    check buildFileDisplay(textBuffer, EditorMode.Normal, config) == " /a/b/c.nim"
    # directory=false, filename=true -> filename only
    config.directory = false
    config.filename = true
    check buildFileDisplay(textBuffer, EditorMode.Normal, config) == " c.nim"
    # directory=false, filename=false -> space only
    config.directory = false
    config.filename = false
    check buildFileDisplay(textBuffer, EditorMode.Normal, config) == " "

suite "StatusLine - parseSetupText":
  test "Parse lineNumber placeholder":
    var state = createTestState()
    state.cursor.line = 9 # 0-indexed, so line 10

    let textBuffer = createMultiLineBuffer(20)

    let result = parseSetupText(state, textBuffer, "{lineNumber}")

    check result == "10"

  test "Parse totalLines placeholder":
    var state = createTestState()

    let textBuffer = createMultiLineBuffer(25)

    let result = parseSetupText(state, textBuffer, "{totalLines}")

    check result == "25"

  test "Parse columnNumber placeholder":
    var state = createTestState()
    state.cursor.column = 4 # 0-indexed, so column 5

    let textBuffer = createTestTextBuffer("", false, "Hello World")

    let result = parseSetupText(state, textBuffer, "{columnNumber}")

    check result == "5"

  test "Parse percentage placeholder":
    var state = createTestState()
    state.cursor.line = 49 # Middle of 100 lines (line 50 of 100 = 50%)

    let textBuffer = createMultiLineBuffer(100)

    let result = parseSetupText(state, textBuffer, "{percentage}")

    check result == "50%"

  test "Parse mode placeholder in normal mode":
    var state = createTestState()
    state.mode = EditorMode.Normal

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{mode}")

    check result == "NORMAL"

  test "Parse mode placeholder in insert mode":
    var state = createTestState()
    state.mode = EditorMode.Insert

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{mode}")

    check result == "INSERT"

  test "Parse mode placeholder with overlay":
    var state = createTestState()
    state.overlay = some(okCommand)

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{mode}")

    check result == "COMMAND"

  test "Parse filename placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = parseSetupText(state, textBuffer, "{filename}")

    check result == "myfile.nim"

  test "Parse directory placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = parseSetupText(state, textBuffer, "{directory}")

    check result == "/path/to"

  test "Parse filePath placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = parseSetupText(state, textBuffer, "{filePath}")

    check result == "/path/to/myfile.nim"

  test "Parse multiple placeholders":
    var state = createTestState()
    state.cursor.line = 4
    state.cursor.column = 9

    let textBuffer = createMultiLineBuffer(10, "/path/to/file.nim")

    let result =
      parseSetupText(state, textBuffer, "{lineNumber}/{totalLines} {columnNumber}")

    check result == "5/10 10"

  test "Empty placeholders for unnamed buffer":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{filename} {directory}")

    check result == " "

suite "StatusLine - buildRightSideInfo":
  test "Returns custom format when setupText is set":
    var state = createTestState()
    state.cursor.line = 0

    let textBuffer = createTestTextBuffer("", false, "test line")

    var config = createTestStatusLineConfig()
    config.setupText = "{lineNumber}/{totalLines}"

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check result == " 1/1"

  test "Returns empty string for empty setupText result":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = ""

    # With empty setupText, default format is used
    # Default format depends on display settings
    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    # Result should contain percentage and line count based on display settings
    check "1/1" in result or "100%" in result

suite "StatusLine - renderStatusLine":
  test "Does nothing when showStatusLine is false":
    var state = createTestState()
    state.showStatusLine = false

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    let config = createTestStatusLineConfig()

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check line.strip() == ""

  test "Renders status line when showStatusLine is true":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true
    config.filename = true
    config.directory = false

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    # Should contain mode label and filename
    check "NORMAL" in line
    check "file.nim" in line

  test "Renders with insert mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.Insert

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "INSERT" in line

  test "Renders with visual mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.Visual

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "VISUAL" in line

  test "Renders with command overlay":
    var state = createTestState()
    state.showStatusLine = true
    state.overlay = some(okCommand)

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "COMMAND" in line

  test "Renders [No Name] for unnamed buffer":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("", false, "test content")
    let config = createTestStatusLineConfig()

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "[No Name]" in line

  test "Renders modified marker":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", true, "test content")
    var config = createTestStatusLineConfig()
    config.changedMark = true
    config.directory = false

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "[+]" in line

  test "Does not render mode label when mode is disabled":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = false

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "NORMAL" notin line

suite "StatusLine - renderWindowStatusLine":
  test "Does nothing when showStatusLine is false":
    var state = createTestState()
    state.showStatusLine = false
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    let config = createTestStatusLineConfig()

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check line.strip() == ""

  test "Does nothing when multiStatusLine is false":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = false

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    let config = createTestStatusLineConfig()

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check line.strip() == ""

  test "Renders status line for active window":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true
    config.filename = true
    config.directory = false

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check "NORMAL" in line
    check "file.nim" in line

  test "Renders status line for inactive window with showModeInactive":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true
    config.showModeInactive = true
    config.filename = true
    config.directory = false

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check "NORMAL" in line

  test "Does not render mode for inactive window without showModeInactive":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true
    config.showModeInactive = false
    config.filename = true
    config.directory = false

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check "NORMAL" notin line

  test "Renders at specified position":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.directory = false

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 15, 10, 60, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 15)
    check "file.nim" in line

    # Line 0 should be empty
    let line0 = getBufferLine(displayBuffer, 0)
    check line0.strip() == ""

  test "Truncates long file path to fit width":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer(
      "/very/long/path/to/some/deeply/nested/directory/structure/file.nim", false,
      "test content",
    )
    var config = createTestStatusLineConfig()
    config.directory = true
    config.mode = false

    # Use a narrow width to force truncation
    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 30, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    # Should not crash and should render something
    check line.len > 0

suite "StatusLine - parseSetupText additional placeholders":
  test "Parse totalColumns placeholder":
    var state = createTestState()
    state.cursor.line = 0
    state.cursor.column = 0

    let textBuffer = createTestTextBuffer("", false, "Hello World")

    let result = parseSetupText(state, textBuffer, "{totalColumns}")

    check result == "11" # "Hello World" has 11 characters

  test "Parse encoding placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{encoding}")

    check result == "UTF-8"

  test "Parse lineEnding placeholder for LF":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = LF

    let result = parseSetupText(state, textBuffer, "{lineEnding}")

    check result == "LF"

  test "Parse lineEnding placeholder for a raw buffer":
    # A raw buffer never had its line endings classified, so report RAW rather
    # than the unused `lineEnding` field.
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CRLF
    textBuffer.keepRaw = true

    let result = parseSetupText(state, textBuffer, "{lineEnding}")

    check result == "RAW"

  test "Parse lineEnding placeholder for CRLF":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CRLF

    let result = parseSetupText(state, textBuffer, "{lineEnding}")

    check result == "CRLF"

  test "Parse lineEnding placeholder for CR":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CR

    let result = parseSetupText(state, textBuffer, "{lineEnding}")

    check result == "CR"

  test "Parse fileType placeholder with language set":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "echo \"hello\"")
    textBuffer.language = SourceLanguage.langNim

    let result = parseSetupText(state, textBuffer, "{fileType}")

    check result == "Nim"

  test "Parse fileType placeholder without language":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{fileType}")

    check result == ""

  test "Parse percentage placeholder for empty buffer":
    var state = createTestState()
    let textBuffer = newTextBuffer("")

    let result = parseSetupText(state, textBuffer, "{percentage}")

    # Empty buffer with cursor at line 0 shows 100% (line 1 of 1)
    # since newTextBuffer creates at least one line
    check result == "100%"

  test "Parse percentage placeholder at first line":
    var state = createTestState()
    state.cursor.line = 0

    let textBuffer = createMultiLineBuffer(10)

    let result = parseSetupText(state, textBuffer, "{percentage}")

    check result == "10%" # Line 1 of 10 = 10%

  test "Parse percentage placeholder at last line":
    var state = createTestState()
    state.cursor.line = 9 # Last line (0-indexed)

    let textBuffer = createMultiLineBuffer(10)

    let result = parseSetupText(state, textBuffer, "{percentage}")

    check result == "100%" # Line 10 of 10 = 100%

  test "Parse totalColumns for cursor beyond buffer":
    var state = createTestState()
    state.cursor.line = 100 # Beyond buffer length

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = parseSetupText(state, textBuffer, "{totalColumns}")

    check result == "0" # Should return 0 for invalid cursor position

  test "Parse totalColumns for multibyte line":
    var state = createTestState()
    state.cursor.line = 0
    state.cursor.column = 0

    let textBuffer = createTestTextBuffer("", false, "あいうえお")

    let result = parseSetupText(state, textBuffer, "{totalColumns}")

    check result == "5" # 5 characters, not 15 bytes

suite "StatusLine - renderStatusLine additional modes":
  test "Renders with replace mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.Replace

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "REPLACE" in line

  test "Renders with filer mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.Filer

    var displayBuffer = createTestBuffer()
    let absPath = getCurrentDir() / "src"
    let textBuffer = createTestTextBuffer(absPath, false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "FILER" in line

  test "Renders with visual line mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.VisualLine

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "VISUAL LINE" in line

  test "Renders with visual block mode":
    var state = createTestState()
    state.showStatusLine = true
    state.mode = EditorMode.VisualBlock

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "VISUAL BLOCK" in line

  test "Renders with search overlay":
    var state = createTestState()
    state.showStatusLine = true
    state.overlay = some(okSearch)

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "SEARCH" in line

  test "Renders with rename overlay":
    var state = createTestState()
    state.showStatusLine = true
    state.overlay = some(okRename)

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "RENAME" in line

  test "Renders with LSP progress text":
    var state = createTestState()
    state.showStatusLine = true
    state.ui.lspProgressText = "Loading..."

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.directory = false

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check "Loading..." in line

suite "StatusLine - buildRightSideInfo default format":
  test "Returns file type in default format":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = false

    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")
    textBuffer.language = SourceLanguage.langNim

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check "Nim" in result

  test "Returns encoding in default format":
    var state = createTestState()
    state.display.showEncoding = true
    state.display.showLineCount = false
    state.display.showLinePercentage = false

    let textBuffer = createTestTextBuffer("", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check "UTF-8" in result

  test "Returns line percentage in default format":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = true
    state.cursor.line = 0

    let textBuffer = createTestTextBuffer("", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check "100%" in result

  test "Returns line count in default format":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = true
    state.display.showLinePercentage = false
    state.cursor.line = 0

    let textBuffer = createTestTextBuffer("", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check "1/1" in result

  test "Returns line ending LF in default format":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = false
    state.display.showLineEnding = true

    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = LF
    textBuffer.language = SourceLanguage.langNone

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check result == " LF"

  test "Returns line ending CRLF in default format":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = false
    state.display.showLineEnding = true

    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CRLF
    textBuffer.language = SourceLanguage.langNone

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check result == " CRLF"

  test "Does not return line ending when showLineEnding is false":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = false
    state.display.showLineEnding = false

    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.language = SourceLanguage.langNone

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check result == ""

  test "Returns empty when all display options are disabled":
    var state = createTestState()
    state.display.showEncoding = false
    state.display.showLineCount = false
    state.display.showLinePercentage = false

    let textBuffer = createTestTextBuffer("", false, "test")
    # Ensure no file type
    textBuffer.language = SourceLanguage.langNone

    var config = createTestStatusLineConfig()
    config.setupText = ""

    let result = buildRightSideInfo(state, textBuffer, state.mode, config, true)

    check result == ""

suite "StatusLine - renderWindowStatusLine additional":
  test "Renders with overlay in window":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true
    state.overlay = some(okSearch)

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = true

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, config
    )

    let line = getBufferLine(displayBuffer, 10)
    check "SEARCH" in line

  test "Renders LSP progress only for active window":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true
    state.ui.lspProgressText = "Loading..."

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.directory = false

    # Active window should show progress
    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, config
    )

    let activeLine = getBufferLine(displayBuffer, 10)
    check "Loading..." in activeLine

    # Reset buffer for inactive window test
    displayBuffer = createTestBuffer()
    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, config
    )

    let inactiveLine = getBufferLine(displayBuffer, 10)
    check "Loading..." notin inactiveLine

suite "StatusLine - buildGitInfo":
  test "Returns empty when git features disabled":
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")
    var config = createTestStatusLineConfig()
    config.gitChangedLines = false
    config.gitBranchName = false

    let result =
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, true)

    check result == ""

  test "Returns empty for unnamed buffer even with git enabled":
    let textBuffer = createTestTextBuffer("", false, "test") # No file path
    var config = createTestStatusLineConfig()
    config.gitChangedLines = true
    config.gitBranchName = true

    let result =
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, true)

    check result == ""

  test "Git info not shown for inactive window without showGitInactive":
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")
    var config = createTestStatusLineConfig()
    config.gitChangedLines = true
    config.gitBranchName = true
    config.showGitInactive = false

    # Even with a file path, inactive window should not show git info
    # (unless showGitInactive is true)
    # This test verifies the condition check
    let result =
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, false)
      # isActiveWindow = false

    # Result should be empty because showGitInactive is false
    check result == ""

suite "StatusLine - sanitize control characters":
  proc hasControl(s: string): bool =
    for r in s.runes:
      if isC0Control(r):
        return true
    false

  test "buildFileDisplay sanitizes C0 and DEL in filePath":
    let tb = createTestTextBuffer("/tmp/a\x1B[2J/b\x00c.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg)
    check not hasControl(res)
    check "\x1B" notin res
    check "\x00" notin res
    # ESC and NUL become spaces, brackets remain
    check "a [2J" in res
    check "b c.nim" in res
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))

  test "buildFileDisplay sanitizes DEL in filePath":
    let tb = createTestTextBuffer("/tmp/file\x7Fname.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = false
    cfg.filename = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg)
    check not hasControl(res)
    check "file name.nim" in res

  test "buildFileDisplay sanitizes with wide chars and controls":
    let tb = createTestTextBuffer("/tmp/漢\x00字🎉\x1B.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg)
    check not hasControl(res)
    check "漢 字" in res
    check "🎉 " in res
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))

  test "buildFileDisplay Filer mode sanitizes directory path":
    let tb = createTestTextBuffer("/tmp/\x00bad\x1Bdir")
    let cfg = createTestStatusLineConfig()
    let res = buildFileDisplay(tb, EditorMode.Filer, cfg)
    check not hasControl(res)
    check "bad dir" in res

  test "buildFileDisplay Filer sanitizes existing dir with control in name":
    # sanitized display differs but dirExists uses raw path - verify no crash and sanitized
    let tb = createTestTextBuffer(getCurrentDir() & "/\x00test")
    let cfg = createTestStatusLineConfig()
    let res = buildFileDisplay(tb, EditorMode.Filer, cfg)
    check not hasControl(res)

  test "parseSetupText sanitizes filePath placeholder":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/to/\x1Bfile\x00name.nim", false, "test")
    let res = parseSetupText(state, tb, "{filePath}")
    check not hasControl(res)
    check " file name.nim" in res or "file name.nim" in res
    check res == sanitizeForDisplay("/path/to/\x1Bfile\x00name.nim")

  test "parseSetupText sanitizes filename and directory derived from filePath":
    var state = createTestState()
    let tb = createTestTextBuffer("/tmp/\x1Bdir/file\x00name.nim", false, "test")
    let resFile = parseSetupText(state, tb, "{filename}")
    let resDir = parseSetupText(state, tb, "{directory}")
    check not hasControl(resFile)
    check not hasControl(resDir)
    check "file name.nim" in resFile
    check " dir" in resDir or "dir" in resDir

  test "parseSetupText sanitizes literal control characters in setupText template":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    let res = parseSetupText(state, tb, "pre\x1B[2J\x00mid {filePath} suf\x7F")
    check not hasControl(res)
    check "\x1B" notin res
    check "\x00" notin res
    check "\x7F" notin res
    check "pre [2J mid" in res
    check "suf " in res or res.endsWith(" ")

  test "parseSetupText sanitizes multiple placeholders with controls":
    var state = createTestState()
    let tb = createTestTextBuffer("/a/\x1Bb/c\x00d.nim", false, "test")
    let res = parseSetupText(state, tb, "{filename} {directory} {filePath}")
    check not hasControl(res)
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))

  test "parseSetupText with unnamed buffer still sanitizes template controls":
    var state = createTestState()
    let tb = createTestTextBuffer("", false, "test")
    let res = parseSetupText(state, tb, "pre\x1Bmid\x00suf")
    check not hasControl(res)
    check res == "pre mid suf"

  test "renderStatusLine sanitizes lspProgressText":
    var state = createTestState()
    state.showStatusLine = true
    state.ui.lspProgressText = "Load\x1Bing\x00.."
    var buf = createTestBuffer()
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    var cfg = createTestStatusLineConfig()
    cfg.mode = false
    cfg.directory = false
    renderStatusLine(state, tb, buf, 23, cfg)
    let line = getBufferLine(buf, 23)
    check not hasControl(line)
    check "Load ing" in line
    check "\x1B" notin line

  test "renderStatusLine displayWidth consistent with sanitized lspProgress":
    var state = createTestState()
    state.showStatusLine = true
    state.ui.lspProgressText = "\x1B漢\x00🎉"
    var buf = createTestBuffer()
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    var cfg = createTestStatusLineConfig()
    cfg.mode = false
    renderStatusLine(state, tb, buf, 23, cfg)
    let line = getBufferLine(buf, 23)
    check not hasControl(line)
    # Wide chars preserved, controls become spaces
    check "漢" in line
    check "🎉" in line

  test "renderWindowStatusLine sanitizes lspProgressText only for active":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true
    state.ui.lspProgressText = "Prog\x1Bress\x00"
    var cfg = createTestStatusLineConfig()
    cfg.mode = false
    cfg.directory = false
    var bufActive = createTestBuffer()
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    renderWindowStatusLine(state, tb, bufActive, 10, 0, 80, true, state.mode, cfg)
    check not hasControl(getBufferLine(bufActive, 10))
    check "Prog ress" in getBufferLine(bufActive, 10)
    var bufInactive = createTestBuffer()
    renderWindowStatusLine(state, tb, bufInactive, 10, 0, 80, false, state.mode, cfg)
    check "Prog" notin getBufferLine(bufInactive, 10)
    check not hasControl(getBufferLine(bufInactive, 10))

  test "buildFileDisplay and tab consistency: displayWidth equals rendered width":
    let tb = createTestTextBuffer("/tmp/\x1B漢\x00test\x7F.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg)
    # sanitizeForDisplay already applied, so rendering via setString will match
    var buf = createTestBuffer()
    var state = createTestState()
    state.showStatusLine = true
    renderStatusLine(state, tb, buf, 23, cfg)
    let line = getBufferLine(buf, 23)
    check not hasControl(line)

  test "buildGitInfo sanitizes branch name with controls":
    let tb = createTestTextBuffer("/path/to/file.nim", false, "test")
    var gc = GitCacheState()
    gc.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, name: "feat\x1B/branch\x00test\x7F", populated: true
    )
    var cfg = createTestStatusLineConfig()
    cfg.gitBranchName = true
    cfg.showGitInactive = true
    let res = buildGitInfo(gc, tb, EditorMode.Normal, cfg, true)
    check not hasControl(res)
    check "\x1B" notin res
    check "feat" in res
    check "branch test" in res

  test "parseSetupText sanitizes gitBranch with controls":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/to/file.nim", false, "test")
    state.git.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, name: "fix\x00/awful\x1Bbranch", populated: true
    )
    let res = parseSetupText(state, tb, "{gitBranch}")
    check not hasControl(res)
    check "fix /awful branch" in res or "fix" in res
    check "\x1B" notin res

  test "buildGitInfo and parseSetupText branch displayWidth consistent":
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    var gc = GitCacheState()
    gc.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, name: "a\x1Bb\x00c漢\x7F", populated: true
    )
    var cfg = createTestStatusLineConfig()
    cfg.gitBranchName = true
    let res = buildGitInfo(gc, tb, EditorMode.Normal, cfg, true)
    check not hasControl(res)
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))
