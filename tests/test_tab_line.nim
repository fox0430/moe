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

## Tests for tab_line.nim - Tab line rendering for moe editor

import std/[unittest, options, tables, strutils]

import pkg/celina

import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/buffer {.all.}
import ../src/moepkg/tab_line {.all.}
import ../src/moepkg/color

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    display: DisplaySettings(
      showTabLine: false,
      showStatusLine: true,
      multiStatusLine: false,
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      showLineNumbers: true,
      showCursorLine: false,
      showSyntax: true,
      showIndentationLines: false,
      showSidebar: false,
      showGitDiff: false,
      showSyntaxChecker: false,
      showCodeLens: false,
      showDocumentHighlight: false,
      lineWrap: true,
      tabStop: 2,
      expandTab: true,
      autoIndent: true,
      autoCloseParen: false,
      autoDeleteParen: false,
    ),
    needsFullRedraw: false,
    viewportReservedLines: 2,
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
    ),
    registers: initRegisters(),
    overlay: none(OverlayState),
  )

proc createTestBuffer(): celina.Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

proc createTestTextBuffer(filePath: string = "", modified: bool = false): TextBuffer =
  ## Create a TextBuffer for testing with optional file path
  result = newTextBuffer()
  if filePath.len > 0:
    result.filePath = some(filePath)
  if modified:
    # Simulate modification by incrementing changeSeq
    result.changeSeq = 1

proc getBufferLine(buffer: celina.Buffer, y: int): string =
  ## Extract a line from celina Buffer as string
  result = ""
  for x in 0 ..< buffer.area.width:
    result.add(buffer[x, y].symbol)

suite "TabLine - toggleTabLine":
  test "Toggle from false to true":
    var state = createTestState()
    check state.display.showTabLine == false

    toggleTabLine(state)

    check state.display.showTabLine == true

  test "Toggle from true to false":
    var state = createTestState()
    state.display.showTabLine = true

    toggleTabLine(state)

    check state.display.showTabLine == false

  test "Toggle twice returns to original state":
    var state = createTestState()
    let original = state.display.showTabLine

    toggleTabLine(state)
    toggleTabLine(state)

    check state.display.showTabLine == original

suite "TabLine - setTabLineVisible":
  test "Set visible to true":
    var state = createTestState()
    check state.display.showTabLine == false

    setTabLineVisible(state, true)

    check state.display.showTabLine == true

  test "Set visible to false":
    var state = createTestState()
    state.display.showTabLine = true

    setTabLineVisible(state, false)

    check state.display.showTabLine == false

  test "Set to same value (idempotent)":
    var state = createTestState()
    state.display.showTabLine = true

    setTabLineVisible(state, true)

    check state.display.showTabLine == true

suite "TabLine - buildTabText":
  test "Build tab text for unnamed buffer":
    let buf = createTestTextBuffer()
    let text = buildTabText(buf, EditorMode.Normal, isActive = false)
    check text == " No Name "

  test "Build tab text for named buffer":
    let buf = createTestTextBuffer("/path/to/file.nim")
    let text = buildTabText(buf, EditorMode.Normal, isActive = false)
    check text == " file.nim "

  test "Build tab text for modified unnamed buffer":
    let buf = createTestTextBuffer("", modified = true)
    let text = buildTabText(buf, EditorMode.Normal, isActive = false)
    check text == " No Name[+] "

  test "Build tab text for modified named buffer":
    let buf = createTestTextBuffer("/path/to/file.nim", modified = true)
    let text = buildTabText(buf, EditorMode.Normal, isActive = false)
    check text == " file.nim[+] "

  test "Build tab text extracts filename only":
    let buf = createTestTextBuffer("/very/long/path/to/some/deep/directory/file.txt")
    let text = buildTabText(buf, EditorMode.Normal, isActive = false)
    check text == " file.txt "

suite "TabLine - renderTabLine":
  test "Does nothing when showTabLine is false":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, false)

    # Buffer should remain empty (all spaces)
    let line = getBufferLine(displayBuffer, 0)
    check line.strip() == ""

  test "Renders single tab":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, true)

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line

  test "Renders multiple tabs":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buf2 = createTestTextBuffer("/path/file2.nim")
    let buf3 = createTestTextBuffer("/path/file3.nim")
    let buffers = @[buf1, buf2, buf3]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, true)

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line
    check " file3.nim " in line

  test "Renders modified marker":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim", modified = true)
    let buffers = @[buf1]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, true)

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim[+] " in line

  test "Stops rendering when exceeding tab line width":
    var displayBuffer = createTestBuffer()
    # Create many buffers with long names
    var buffers: seq[TextBuffer] = @[]
    for i in 0 ..< 20:
      buffers.add(createTestTextBuffer("/path/verylongfilename" & $i & ".nim"))

    renderTabLine(buffers, buffers[0], EditorMode.Normal, displayBuffer, 0, 0, 40, true)

    # Only some tabs should be rendered due to width limit
    let line = getBufferLine(displayBuffer, 0)
    # First file should be visible
    check "verylongfilename0" in line
    # Later files might not fit
    # This test just verifies no crash occurs

  test "Renders at specified Y position":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 5, 0, 80, true)

    # Line 5 should have content
    let line5 = getBufferLine(displayBuffer, 5)
    check " file1.nim " in line5

    # Line 0 should be empty
    let line0 = getBufferLine(displayBuffer, 0)
    check line0.strip() == ""

  test "Renders at specified X position":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 10, 70, true)

    let line = getBufferLine(displayBuffer, 0)
    # First 10 characters should be spaces (unchanged)
    check line[0 ..< 10].strip() == ""
    # Tab content should start after X offset
    check " file1.nim " in line

suite "TabLine - renderWindowTabLine":
  test "Renders tab line for window":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buf2 = createTestTextBuffer("/path/file2.nim")
    let buffers = @[buf1, buf2]

    renderWindowTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, true)

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line

  test "Does nothing when showTabLine is false":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderWindowTabLine(
      buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, false
    )

    let line = getBufferLine(displayBuffer, 0)
    check line.strip() == ""

suite "TabLine - renderSingleViewTabLine":
  test "Renders tab line at y=0 across full width":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buf2 = createTestTextBuffer("/path/file2.nim")
    let buffers = @[buf1, buf2]

    renderSingleViewTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, true)

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line

  test "Does nothing when showTabLine is false":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderSingleViewTabLine(buffers, buf1, EditorMode.Normal, displayBuffer, false)

    let line = getBufferLine(displayBuffer, 0)
    check line.strip() == ""
