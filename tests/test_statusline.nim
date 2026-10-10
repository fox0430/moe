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

import std/[unittest, options, tables, strutils, os, importutils]

import pkg/celina

import ../src/moepkg/[types, modes, registers, config, git_cache, unicode_utils]
import ../src/moepkg/buffer/core
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/status_line {.all.}

privateAccess(StatusItem)
privateAccess(Ruler)

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

proc activeSetupText(
    state: EditorState, textBuffer: TextBuffer, setupText: string
): string =
  ## `setupText` with the active window's values.
  parseSetupText(
    state.git,
    textBuffer,
    state.cursor,
    state.windowModeText(state.mode, true),
    setupText,
  )

proc activeRuler(
    state: EditorState,
    textBuffer: TextBuffer,
    mode: EditorMode,
    config: StatusLineConfig,
): Ruler =
  ## The active window's ruler.
  buildRuler(
    state.git, textBuffer, state.cursor, state.windowModeText(mode, true), mode, config
  )

proc joined(items: openArray[StatusItem]): string =
  ## The parts' text as one line shows them with room for all.
  for item in items:
    result.add item.text

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
  test "Mark a file a crash preserved work for, even with the changed mark off":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = false

    let result = buildFileDisplay(
      textBuffer, EditorMode.Normal, config, owesPreservedWork = true
    ).joined

    check result == " " & PreservedWorkMark & " file.nim"

  test "The preserved-work mark goes ahead of the path and the changed mark":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    textBuffer.changeSeq = textBuffer.savedSeq + 1
    var config = createTestStatusLineConfig()
    config.directory = false

    let result = buildFileDisplay(
      textBuffer, EditorMode.Normal, config, owesPreservedWork = true
    ).joined

    check result == " " & PreservedWorkMark & " file.nim [+]"

  test "Only the mark when neither name nor directory is shown":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(
      textBuffer, EditorMode.Normal, config, owesPreservedWork = true
    ).joined

    check result == " " & PreservedWorkMark

  test "A file name's trailing space is kept ahead of the changed mark":
    let textBuffer = createTestTextBuffer("/path/to/notes ")
    textBuffer.changeSeq = textBuffer.savedSeq + 1
    var config = createTestStatusLineConfig()
    config.directory = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " notes  [+]"

  test "No preserved-work mark in a mode that shows no file":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(
      textBuffer, EditorMode.Help, config, owesPreservedWork = true
    ).joined

    check PreservedWorkMark notin result

  test "Display [No Name] for unnamed buffer":
    let textBuffer = createTestTextBuffer()
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " [No Name]"

  test "Display full path when directory is enabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " /path/to/file.nim"

  test "Display filename only when directory is disabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " file.nim"

  test "Display changed mark for modified buffer":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " file.nim [+]"

  test "No changed mark when changedMark is disabled":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " file.nim"

  test "No changed mark for unmodified buffer":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " file.nim"

  test "Display absolute directory path with trailing slash in Filer mode":
    # Use an existing directory so dirExists returns true
    let absPath = getCurrentDir()
    let textBuffer = createTestTextBuffer(absPath)
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Filer, config).joined

    check result == " " & absPath & "/"

  test "Display empty string in Filer mode with no path":
    let textBuffer = createTestTextBuffer()
    let config = createTestStatusLineConfig()

    let result = buildFileDisplay(textBuffer, EditorMode.Filer, config).joined

    check result == ""

  test "Nothing when both directory and filename disabled, not modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == ""
    check "file.nim" notin result
    check "/path/to" notin result

  test "Nothing when both directory and filename disabled, bug fix regression":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    # Before fix, else branch incorrectly did extractFilename() so result was " file.nim"
    check result != " file.nim"
    check result == ""

  test "Display only changed mark when both directory and filename disabled but modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = true

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " [+]"
    check "file.nim" notin result

  test "No changed mark when both disabled and changedMark disabled even if modified":
    let textBuffer = createTestTextBuffer("/path/to/file.nim", modified = true)
    var config = createTestStatusLineConfig()
    config.directory = false
    config.filename = false
    config.changedMark = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == ""
    check "[+]" notin result

  test "Directory takes precedence over filename flag":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config = createTestStatusLineConfig()
    config.directory = true
    config.filename = false

    let result = buildFileDisplay(textBuffer, EditorMode.Normal, config).joined

    check result == " /path/to/file.nim"

  test "Directory enabled ignores filename false vs true":
    let textBuffer = createTestTextBuffer("/path/to/file.nim")
    var config1 = createTestStatusLineConfig()
    config1.directory = true
    config1.filename = true
    var config2 = createTestStatusLineConfig()
    config2.directory = true
    config2.filename = false

    check buildFileDisplay(textBuffer, EditorMode.Normal, config1).joined ==
      buildFileDisplay(textBuffer, EditorMode.Normal, config2).joined
    check buildFileDisplay(textBuffer, EditorMode.Normal, config1).joined ==
      " /path/to/file.nim"

  test "All combinations of directory/filename for Normal mode":
    let textBuffer = createTestTextBuffer("/a/b/c.nim")
    var config = createTestStatusLineConfig()
    config.changedMark = false
    # directory=true, filename=true -> full path
    config.directory = true
    config.filename = true
    check buildFileDisplay(textBuffer, EditorMode.Normal, config).joined == " /a/b/c.nim"
    # directory=true, filename=false -> still full path
    config.directory = true
    config.filename = false
    check buildFileDisplay(textBuffer, EditorMode.Normal, config).joined == " /a/b/c.nim"
    # directory=false, filename=true -> filename only
    config.directory = false
    config.filename = true
    check buildFileDisplay(textBuffer, EditorMode.Normal, config).joined == " c.nim"
    # directory=false, filename=false -> nothing
    config.directory = false
    config.filename = false
    check buildFileDisplay(textBuffer, EditorMode.Normal, config).joined == ""

suite "StatusLine - parseSetupText":
  test "Parse lineNumber placeholder":
    var state = createTestState()
    state.cursor.line = 9 # 0-indexed, so line 10

    let textBuffer = createMultiLineBuffer(20)

    let result = activeSetupText(state, textBuffer, "{lineNumber}")

    check result == "10"

  test "Parse totalLines placeholder":
    var state = createTestState()

    let textBuffer = createMultiLineBuffer(25)

    let result = activeSetupText(state, textBuffer, "{totalLines}")

    check result == "25"

  test "Parse columnNumber placeholder":
    var state = createTestState()
    state.cursor.column = 4 # 0-indexed, so column 5

    let textBuffer = createTestTextBuffer("", false, "Hello World")

    let result = activeSetupText(state, textBuffer, "{columnNumber}")

    check result == "5"

  test "Parse percentage placeholder":
    var state = createTestState()
    state.cursor.line = 49 # Middle of 100 lines (line 50 of 100 = 50%)

    let textBuffer = createMultiLineBuffer(100)

    let result = activeSetupText(state, textBuffer, "{percentage}")

    check result == "50%"

  test "Parse mode placeholder in normal mode":
    var state = createTestState()
    state.mode = EditorMode.Normal

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{mode}")

    check result == "NORMAL"

  test "Parse mode placeholder in insert mode":
    var state = createTestState()
    state.mode = EditorMode.Insert

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{mode}")

    check result == "INSERT"

  test "Parse mode placeholder with overlay":
    var state = createTestState()
    state.overlay = some(okCommand)

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{mode}")

    check result == "COMMAND"

  test "Parse filename placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = activeSetupText(state, textBuffer, "{filename}")

    check result == "myfile.nim"

  test "Parse directory placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = activeSetupText(state, textBuffer, "{directory}")

    check result == "/path/to"

  test "Parse filePath placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/to/myfile.nim", false, "test")

    let result = activeSetupText(state, textBuffer, "{filePath}")

    check result == "/path/to/myfile.nim"

  test "Parse multiple placeholders":
    var state = createTestState()
    state.cursor.line = 4
    state.cursor.column = 9

    let textBuffer = createMultiLineBuffer(10, "/path/to/file.nim")

    let result =
      activeSetupText(state, textBuffer, "{lineNumber}/{totalLines} {columnNumber}")

    check result == "5/10 10"

  test "Empty placeholders for unnamed buffer":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{filename} {directory}")

    check result == " "

suite "StatusLine - buildRuler":
  test "Shows the setupText format":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test line")

    var config = createTestStatusLineConfig()
    config.setupText = "{lineNumber}/{totalLines}"

    check activeRuler(state, textBuffer, state.mode, config).text == "1/1"

  test "An empty setupText takes the default format":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")
    textBuffer.language = SourceLanguage.langNim

    var config = createTestStatusLineConfig()
    config.setupText = ""

    check activeRuler(state, textBuffer, state.mode, config).text ==
      "1/1 1/4 UTF-8 LF Nim"

  test "No ruler in FileTree mode":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")
    let config = createTestStatusLineConfig()

    let ruler = activeRuler(state, textBuffer, EditorMode.FileTree, config)
    check ruler.text == ""
    check ruler.fieldWidth == 0

  test "The field fits the last line and columns up to WidestNumber":
    var state = createTestState()
    state.cursor.line = 8
    let textBuffer = createMultiLineBuffer(120)

    var config = createTestStatusLineConfig()
    config.setupText =
      "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {percentage}"

    let ruler = activeRuler(state, textBuffer, state.mode, config)
    check ruler.text == "9/120 1/5 7%"
    check ruler.fieldWidth == "120/120 999/999 100%".len

  test "A line longer than WidestNumber keeps the field":
    var state = createTestState()
    state.cursor.column = 1100
    let textBuffer = createTestTextBuffer("", false, "x".repeat(1200))

    var config = createTestStatusLineConfig()
    config.setupText = "{columnNumber}/{totalColumns}"

    let ruler = activeRuler(state, textBuffer, state.mode, config)
    check ruler.text == "1101/1200"
    check ruler.fieldWidth == "999/999".len

  test "The field fits the widest mode":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = "{mode}"

    for mode in [EditorMode.Normal, EditorMode.VisualBlock]:
      state.mode = mode
      check activeRuler(state, textBuffer, mode, config).fieldWidth ==
        "(insert) NORMAL".len

  test "The field fits git counts up to WidestNumber":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test")

    var config = createTestStatusLineConfig()
    config.setupText = "{gitChanges}"

    let ruler = activeRuler(state, textBuffer, state.mode, config)
    check ruler.text == "+0 ~0 -0"
    check ruler.fieldWidth == "+999 ~999 -999".len

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
  test "A narrow window keeps the preserved-work mark over the path":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer(
      "/a/rather/long/directory/path/leading/to/the/file.nim", false, "test content"
    )
    let config = createTestStatusLineConfig()

    renderWindowStatusLine(
      state,
      textBuffer,
      displayBuffer,
      10,
      0,
      40,
      true,
      state.mode,
      state.cursor,
      config,
      owesPreservedWork = true,
    )

    # The ruler's field takes the right half, the marks the rest
    check getBufferLine(displayBuffer, 10)[0 ..< 40] ==
      " NORMAL  [recover]    1/1 1/12 UTF-8 LF "

  test "Does nothing when showStatusLine is false":
    var state = createTestState()
    state.showStatusLine = false
    state.multiStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "test content")
    let config = createTestStatusLineConfig()

    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, state.cursor,
      config,
    )

    let line = getBufferLine(displayBuffer, 10)
    check "NORMAL" in line

  test "An inactive window's ruler shows its own cursor and mode":
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true
    state.cursor.line = 3999
    state.overlay = some(okCommand)
    state.insertNormalMode = true

    var displayBuffer = createTestBuffer()
    let textBuffer = createMultiLineBuffer(10, "/a/file.nim")
    var config = createTestStatusLineConfig()
    config.showModeInactive = true
    config.setupText = "{lineNumber}/{totalLines} {mode}"

    renderWindowStatusLine(
      state,
      textBuffer,
      displayBuffer,
      10,
      0,
      60,
      false,
      EditorMode.Normal,
      BufferPosition(line: 2, column: 0),
      config,
    )

    let line = getBufferLine(displayBuffer, 10)[0 ..< 60]
    check line.startsWith(" NORMAL  /a/file.nim ")
    check line.endsWith(" 3/10 NORMAL ")

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
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 15, 10, 60, true, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 10, 0, 30, true, state.mode, state.cursor,
      config,
    )

    let line = getBufferLine(displayBuffer, 10)
    # Should not crash and should render something
    check line.len > 0

suite "StatusLine - narrow lines":
  proc defaultConfig(): StatusLineConfig =
    result = newEditorConfig().statusLine
    result.gitChangedLines = false # Needs a git repository
    result.gitBranchName = false

  proc drawnWindow(width: int): string =
    var state = createTestState()
    state.showStatusLine = true
    state.multiStatusLine = true
    var displayBuffer = createTestBuffer()
    let textBuffer =
      createTestTextBuffer("/path/to/src/moepkg/status_line.nim", false, "test content")
    textBuffer.language = SourceLanguage.langNim
    renderWindowStatusLine(
      state,
      textBuffer,
      displayBuffer,
      10,
      0,
      width,
      true,
      state.mode,
      state.cursor,
      defaultConfig(),
    )
    getBufferLine(displayBuffer, 10)[0 ..< width]

  test "The default config keeps the mode label and cuts the path from the left":
    check drawnWindow(60) ==
      " NORMAL  <c/moepkg/status_line.nim    1/1 1/12 UTF-8 LF Nim "

  test "The default config's ruler stays right of the middle and loses its end":
    check drawnWindow(40) == " NORMAL  <s_line.nim  1/1 1/12 UTF-8 LF "

  test "renderStatusLine cuts a long path from the left":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    let textBuffer =
      createTestTextBuffer("/" & "dir/".repeat(20) & "file.nim", false, "test content")
    let config = createTestStatusLineConfig()

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    let line = getBufferLine(displayBuffer, 23)
    check line.startsWith(" NORMAL  <")
    check line.endsWith("dir/file.nim    1/1 1/12 UTF-8 LF ")

  test "setupText loses its end as Vim's ruler does":
    var state = createTestState()
    state.showStatusLine = true

    var displayBuffer = createTestBuffer()
    displayBuffer.area.width = 20
    let textBuffer = createTestTextBuffer("/file.nim", false, "test content")
    var config = createTestStatusLineConfig()
    config.mode = false
    config.setupText = "{lineNumber}/{totalLines} {filePath} {encoding}"

    renderStatusLine(state, textBuffer, displayBuffer, 23, config)

    check getBufferLine(displayBuffer, 23) == " /file.nim 1/1 /fil "

suite "StatusLine - layoutStatusLine":
  proc fitted(text: string): Ruler =
    ## A ruler whose field is as wide as its text.
    Ruler(text: text, fieldWidth: charDisplayWidth(text))

  let
    mode = part(" NORMAL ", srLabel)
    longName = part(" src/moepkg/status_line.nim", srName)
    ruler = fitted("123/456 7/80 UTF-8 LF Nim")

  proc drawn(left: openArray[StatusItem], ruler: Ruler, width: int): string =
    ## The status line `drawStatusLineRow` draws `width` columns wide.
    var buffer = createTestBuffer()
    buffer.drawStatusLineRow(0, 0, width, left, ruler, Style(), Style())
    for x in 0 ..< width:
      result.add buffer[x, 0].symbol

  test "Shows every part when they fit":
    check layoutStatusLine([mode, part(" file.nim", srName)], ruler, 80) ==
      (left: @[" NORMAL ", " file.nim"], ruler: ruler.text, rulerCol: 54)

  test "The ruler stays right of the middle and loses its end":
    check layoutStatusLine([mode, longName], ruler, 40) ==
      (left: @[" NORMAL ", " <s_line.nim"], ruler: "123/456 7/80 UTF-8", rulerCol: 21)

  test "Keeps the mode label while the name is cut":
    check layoutStatusLine([mode, longName], ruler, 21) ==
      (left: @[" NORMAL ", " <m"], ruler: "123/456", rulerCol: 13)

  test "Cuts the labels only when they alone are wider than the window":
    check layoutStatusLine([mode], ruler, 6) ==
      (left: @[" NORMA"], ruler: "", rulerCol: 0)

  test "Extras go, the last first, before the name is cut":
    let left = [
      mode,
      part(" +1 ~0 -0", srExtra),
      part(" ᚠ main", srExtra),
      part(" file.nim", srName),
      part("  Indexing ", srExtra),
    ]
    check layoutStatusLine(left, fitted("1/1"), 49).left ==
      @[" NORMAL ", " +1 ~0 -0", " ᚠ main", " file.nim", "  Indexing "]
    check layoutStatusLine(left, fitted("1/1"), 48).left ==
      @[" NORMAL ", " +1 ~0 -0", " ᚠ main", " file.nim", ""]
    check layoutStatusLine(left, fitted("1/1"), 36).left ==
      @[" NORMAL ", " +1 ~0 -0", "", " file.nim", ""]
    check layoutStatusLine(left, fitted("1/1"), 25).left ==
      @[" NORMAL ", "", "", " file.nim", ""]

  test "Extras stay while the name is cut to its last path component":
    let left = [
      mode,
      part(" +1 ~0 -0", srExtra),
      part(" ᚠ main", srExtra),
      part(" /home/user/src/file.nim", srName),
    ]
    check layoutStatusLine(left, fitted("1/1"), 52).left ==
      @[" NORMAL ", " +1 ~0 -0", " ᚠ main", " <ome/user/src/file.nim"]
    check layoutStatusLine(left, fitted("1/1"), 39).left ==
      @[" NORMAL ", " +1 ~0 -0", " ᚠ main", " <file.nim"]
    check layoutStatusLine(left, fitted("1/1"), 38).left ==
      @[" NORMAL ", " +1 ~0 -0", "", " <r/src/file.nim"]

  test "Keeps the marks while the name is cut":
    let left =
      [part(" [recover]", srMark), part(" file.nim", srName), part(" [+]", srMark)]
    check layoutStatusLine(left, Ruler(), 20).left == @[" [recover]", " <.nim", " [+]"]
    check layoutStatusLine(left, Ruler(), 16).left == @[" [recover]", "", " [+]"]

  test "The marks lose their start once the name is gone":
    let left =
      [part(" [recover]", srMark), part(" file.nim", srName), part(" [+]", srMark)]
    check layoutStatusLine(left, Ruler(), 12).left == @[" <cover]", "", " [+]"]
    check layoutStatusLine(left, Ruler(), 4).left == @["", "", " [+]"]
    check layoutStatusLine(left, Ruler(), 3).left == @["", "", " <]"]
    check layoutStatusLine(left, Ruler(), 2).left == @["", "", ""]

  test "The changed mark outlasts the recover mark beside the mode label":
    let left = [
      mode, part(" [recover]", srMark), part(" file.nim", srName), part(" [+]", srMark)
    ]
    check layoutStatusLine(left, ruler, 23) ==
      (left: @[" NORMAL ", "", "", " [+]"], ruler: "123/456 7", rulerCol: 13)

  test "A ruler as wide as its field ends a blank column before the right edge":
    check drawn([part(" file.nim", srName)], fitted("1/1"), 16) == " file.nim   1/1 "

  test "Draws the ruler flush right in its field":
    check drawn([part(" file.nim", srName)], Ruler(text: "1/1", fieldWidth: 5), 16) ==
      " file.nim   1/1 "

  test "The name keeps its cut while the ruler changes within its field":
    let
      before = Ruler(text: "9/120 1/0", fieldWidth: 15)
      after = Ruler(text: "10/120 1/45", fieldWidth: 15)
    check layoutStatusLine([mode, longName], before, 40) ==
      (left: @[" NORMAL ", " <atus_line.nim"], ruler: before.text, rulerCol: 30)
    check layoutStatusLine([mode, longName], after, 40) ==
      (left: @[" NORMAL ", " <atus_line.nim"], ruler: after.text, rulerCol: 28)

  test "A wide character at the cut leaves no gap before the next part":
    let left = [part(" 日本語ファイル.nim", srName), part(" [+]", srMark)]
    check drawn(left, Ruler(), 11) == " <.nim [+] "

suite "StatusLine - keptWidth":
  test "Keeps the last path component behind the cut":
    check keptWidth(" /home/user/file.nim") == " <file.nim".len
    check keptWidth(" /a/b/dir/") == " <dir/".len

  test "Keeps a name no wider than that whole":
    check keptWidth(" file.nim") == " file.nim".len
    check keptWidth(" /a.nim") == " /a.nim".len

suite "StatusLine - cutFromLeft":
  test "Keeps a text that fits":
    check cutFromLeft(" file.nim", 9) == " file.nim"

  test "Cuts the start with < and keeps the separator":
    check cutFromLeft(" /a/b/file.nim", 10) == " <file.nim"

  test "Does not split a wide character":
    check cutFromLeft(" a漢字", 5) == " <字"

  test "Drops zero-width marks with the character they combine with":
    check cutFromLeft(" cafe\u0301/file.nim", 11) == " </file.nim"

  test "Shows nothing narrower than MinCutWidth":
    check cutFromLeft(" file.nim", MinCutWidth) == " <m"
    check cutFromLeft(" file.nim", MinCutWidth - 1) == ""

suite "StatusLine - parseSetupText additional placeholders":
  test "Parse totalColumns placeholder":
    var state = createTestState()
    state.cursor.line = 0
    state.cursor.column = 0

    let textBuffer = createTestTextBuffer("", false, "Hello World")

    let result = activeSetupText(state, textBuffer, "{totalColumns}")

    check result == "11" # "Hello World" has 11 characters

  test "Parse encoding placeholder":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{encoding}")

    check result == "UTF-8"

  test "Parse lineEnding placeholder for LF":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = LF

    let result = activeSetupText(state, textBuffer, "{lineEnding}")

    check result == "LF"

  test "Parse lineEnding placeholder for a raw buffer":
    # A raw buffer never had its line endings classified, so report RAW rather
    # than the unused `lineEnding` field.
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CRLF
    textBuffer.keepRaw = true

    let result = activeSetupText(state, textBuffer, "{lineEnding}")

    check result == "RAW"

  test "Parse lineEnding placeholder for CRLF":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CRLF

    let result = activeSetupText(state, textBuffer, "{lineEnding}")

    check result == "CRLF"

  test "Parse lineEnding placeholder for CR":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")
    textBuffer.lineEnding = CR

    let result = activeSetupText(state, textBuffer, "{lineEnding}")

    check result == "CR"

  test "Parse fileType placeholder with language set":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("/path/file.nim", false, "echo \"hello\"")
    textBuffer.language = SourceLanguage.langNim

    let result = activeSetupText(state, textBuffer, "{fileType}")

    check result == "Nim"

  test "Parse fileType placeholder without language":
    var state = createTestState()
    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{fileType}")

    check result == ""

  test "Parse percentage placeholder for empty buffer":
    var state = createTestState()
    let textBuffer = newTextBuffer("")

    let result = activeSetupText(state, textBuffer, "{percentage}")

    # Empty buffer with cursor at line 0 shows 100% (line 1 of 1)
    # since newTextBuffer creates at least one line
    check result == "100%"

  test "Parse percentage placeholder at first line":
    var state = createTestState()
    state.cursor.line = 0

    let textBuffer = createMultiLineBuffer(10)

    let result = activeSetupText(state, textBuffer, "{percentage}")

    check result == "10%" # Line 1 of 10 = 10%

  test "Parse percentage placeholder at last line":
    var state = createTestState()
    state.cursor.line = 9 # Last line (0-indexed)

    let textBuffer = createMultiLineBuffer(10)

    let result = activeSetupText(state, textBuffer, "{percentage}")

    check result == "100%" # Line 10 of 10 = 100%

  test "Parse totalColumns for cursor beyond buffer":
    var state = createTestState()
    state.cursor.line = 100 # Beyond buffer length

    let textBuffer = createTestTextBuffer("", false, "test")

    let result = activeSetupText(state, textBuffer, "{totalColumns}")

    check result == "0" # Should return 0 for invalid cursor position

  test "Parse totalColumns for multibyte line":
    var state = createTestState()
    state.cursor.line = 0
    state.cursor.column = 0

    let textBuffer = createTestTextBuffer("", false, "あいうえお")

    let result = activeSetupText(state, textBuffer, "{totalColumns}")

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
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, state.cursor,
      config,
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
      state, textBuffer, displayBuffer, 10, 0, 80, true, state.mode, state.cursor,
      config,
    )

    let activeLine = getBufferLine(displayBuffer, 10)
    check "Loading..." in activeLine

    # Reset buffer for inactive window test
    displayBuffer = createTestBuffer()
    renderWindowStatusLine(
      state, textBuffer, displayBuffer, 10, 0, 80, false, state.mode, state.cursor,
      config,
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
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, true).joined

    check result == ""

  test "Returns empty for unnamed buffer even with git enabled":
    let textBuffer = createTestTextBuffer("", false, "test") # No file path
    var config = createTestStatusLineConfig()
    config.gitChangedLines = true
    config.gitBranchName = true

    let result =
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, true).joined

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
      buildGitInfo(GitCacheState(), textBuffer, EditorMode.Normal, config, false).joined
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
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg).joined
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
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg).joined
    check not hasControl(res)
    check "file name.nim" in res

  test "buildFileDisplay sanitizes with wide chars and controls":
    let tb = createTestTextBuffer("/tmp/漢\x00字🎉\x1B.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg).joined
    check not hasControl(res)
    check "漢 字" in res
    check "🎉 " in res
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))

  test "buildFileDisplay Filer mode sanitizes directory path":
    let tb = createTestTextBuffer("/tmp/\x00bad\x1Bdir")
    let cfg = createTestStatusLineConfig()
    let res = buildFileDisplay(tb, EditorMode.Filer, cfg).joined
    check not hasControl(res)
    check "bad dir" in res

  test "buildFileDisplay Filer sanitizes existing dir with control in name":
    # sanitized display differs but dirExists uses raw path - verify no crash and sanitized
    let tb = createTestTextBuffer(getCurrentDir() & "/\x00test")
    let cfg = createTestStatusLineConfig()
    let res = buildFileDisplay(tb, EditorMode.Filer, cfg).joined
    check not hasControl(res)

  test "parseSetupText sanitizes filePath placeholder":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/to/\x1Bfile\x00name.nim", false, "test")
    let res = activeSetupText(state, tb, "{filePath}")
    check not hasControl(res)
    check " file name.nim" in res or "file name.nim" in res
    check res == sanitizeForDisplay("/path/to/\x1Bfile\x00name.nim")

  test "parseSetupText sanitizes filename and directory derived from filePath":
    var state = createTestState()
    let tb = createTestTextBuffer("/tmp/\x1Bdir/file\x00name.nim", false, "test")
    let resFile = activeSetupText(state, tb, "{filename}")
    let resDir = activeSetupText(state, tb, "{directory}")
    check not hasControl(resFile)
    check not hasControl(resDir)
    check "file name.nim" in resFile
    check " dir" in resDir or "dir" in resDir

  test "parseSetupText sanitizes literal control characters in setupText template":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    let res = activeSetupText(state, tb, "pre\x1B[2J\x00mid {filePath} suf\x7F")
    check not hasControl(res)
    check "\x1B" notin res
    check "\x00" notin res
    check "\x7F" notin res
    check "pre [2J mid" in res
    check "suf " in res or res.endsWith(" ")

  test "parseSetupText sanitizes multiple placeholders with controls":
    var state = createTestState()
    let tb = createTestTextBuffer("/a/\x1Bb/c\x00d.nim", false, "test")
    let res = activeSetupText(state, tb, "{filename} {directory} {filePath}")
    check not hasControl(res)
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))

  test "parseSetupText with unnamed buffer still sanitizes template controls":
    var state = createTestState()
    let tb = createTestTextBuffer("", false, "test")
    let res = activeSetupText(state, tb, "pre\x1Bmid\x00suf")
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
    renderWindowStatusLine(
      state, tb, bufActive, 10, 0, 80, true, state.mode, state.cursor, cfg
    )
    check not hasControl(getBufferLine(bufActive, 10))
    check "Prog ress" in getBufferLine(bufActive, 10)
    var bufInactive = createTestBuffer()
    renderWindowStatusLine(
      state, tb, bufInactive, 10, 0, 80, false, state.mode, state.cursor, cfg
    )
    check "Prog" notin getBufferLine(bufInactive, 10)
    check not hasControl(getBufferLine(bufInactive, 10))

  test "buildFileDisplay and tab consistency: displayWidth equals rendered width":
    let tb = createTestTextBuffer("/tmp/\x1B漢\x00test\x7F.nim")
    var cfg = createTestStatusLineConfig()
    cfg.directory = true
    let res = buildFileDisplay(tb, EditorMode.Normal, cfg).joined
    # sanitizeForDisplay already applied, so rendering via setString will match
    var buf = createTestBuffer()
    var state = createTestState()
    state.showStatusLine = true
    renderStatusLine(state, tb, buf, 23, cfg)
    let line = getBufferLine(buf, 23)
    check not hasControl(line)
    check res in line

  test "buildGitInfo sanitizes branch name with controls":
    let tb = createTestTextBuffer("/path/to/file.nim", false, "test")
    var gc = GitCacheState()
    gc.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, repositoryPath: "/path", populated: true
    )
    gc.repositories["/path"] =
      GitRepositoryCacheEntry(name: "feat\x1B/branch\x00test\x7F", populated: true)
    var cfg = createTestStatusLineConfig()
    cfg.gitBranchName = true
    cfg.showGitInactive = true
    let res = buildGitInfo(gc, tb, EditorMode.Normal, cfg, true).joined
    check not hasControl(res)
    check "\x1B" notin res
    check "feat" in res
    check "branch test" in res

  test "parseSetupText sanitizes gitBranch with controls":
    var state = createTestState()
    let tb = createTestTextBuffer("/path/to/file.nim", false, "test")
    state.git.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, repositoryPath: "/path", populated: true
    )
    state.git.repositories["/path"] =
      GitRepositoryCacheEntry(name: "fix\x00/awful\x1Bbranch", populated: true)
    let res = activeSetupText(state, tb, "{gitBranch}")
    check not hasControl(res)
    check "fix /awful branch" in res or "fix" in res
    check "\x1B" notin res

  test "buildGitInfo and parseSetupText branch displayWidth consistent":
    let tb = createTestTextBuffer("/path/file.nim", false, "test")
    var gc = GitCacheState()
    gc.branchEntries[tb.id] = GitBranchCacheEntry(
      path: tb.filePath.get, repositoryPath: "/path", populated: true
    )
    gc.repositories["/path"] =
      GitRepositoryCacheEntry(name: "a\x1Bb\x00c漢\x7F", populated: true)
    var cfg = createTestStatusLineConfig()
    cfg.gitBranchName = true
    let res = buildGitInfo(gc, tb, EditorMode.Normal, cfg, true).joined
    check not hasControl(res)
    check displayWidth(res) == displayWidth(sanitizeForDisplay(res))
