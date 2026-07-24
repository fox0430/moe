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

import ../src/moepkg/[types, config, modes, registers, buffer, unicode_utils]
import ../src/moepkg/tab_line {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
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
    config: newEditorConfig(),
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
    state.showTabLine = false

    toggleTabLine(state)

    check state.showTabLine == true

  test "Toggle from true to false":
    var state = createTestState()
    state.showTabLine = true

    toggleTabLine(state)

    check state.showTabLine == false

  test "Toggle twice returns to original state":
    var state = createTestState()
    let original = state.showTabLine

    toggleTabLine(state)
    toggleTabLine(state)

    check state.showTabLine == original

suite "TabLine - setTabLineVisible":
  test "Set visible to true":
    var state = createTestState()
    state.showTabLine = false

    setTabLineVisible(state, true)

    check state.showTabLine == true

  test "Set visible to false":
    var state = createTestState()
    state.showTabLine = true

    setTabLineVisible(state, false)

    check state.showTabLine == false

  test "Set to same value (idempotent)":
    var state = createTestState()
    state.showTabLine = true

    setTabLineVisible(state, true)

    check state.showTabLine == true

suite "TabLine - buildTabText":
  test "Build tab text for unnamed buffer":
    let buf = createTestTextBuffer()
    let text = buildTabText(buf)
    check text == " No Name "

  test "Build tab text for named buffer":
    let buf = createTestTextBuffer("/path/to/file.nim")
    let text = buildTabText(buf)
    check text == " file.nim "

  test "Build tab text for modified unnamed buffer":
    let buf = createTestTextBuffer("", modified = true)
    let text = buildTabText(buf)
    check text == " No Name[+] "

  test "Build tab text for modified named buffer":
    let buf = createTestTextBuffer("/path/to/file.nim", modified = true)
    let text = buildTabText(buf)
    check text == " file.nim[+] "

  test "Build tab text extracts filename only":
    let buf = createTestTextBuffer("/very/long/path/to/some/deep/directory/file.txt")
    let text = buildTabText(buf)
    check text == " file.txt "

  test "displayName overrides filename":
    let buf = createTestTextBuffer("/path/to/file.nim")
    buf.displayName = some("[Terminal: bash]")
    let text = buildTabText(buf)
    check text == " [Terminal: bash] "

  test "displayName suppresses modified marker":
    let buf = createTestTextBuffer("/path/to/file.nim", modified = true)
    buf.displayName = some("[Terminal: htop]")
    let text = buildTabText(buf)
    check text == " [Terminal: htop] "

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

    renderWindowTabLine(
      buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, true, true
    )

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line

  test "Does nothing when showTabLine is false":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]

    renderWindowTabLine(
      buffers, buf1, EditorMode.Normal, displayBuffer, 0, 0, 80, false, true
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

suite "TabLine - hitTestTabLine":
  test "Single tab - click inside":
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]
    # Tab text: " file1.nim " = 11 chars, range [0, 11)
    let idx = hitTestTabLine(buffers, EditorMode.Normal, 0, 80, 5)
    check idx == 0

  test "Single tab - click at start":
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]
    let idx = hitTestTabLine(buffers, EditorMode.Normal, 0, 80, 0)
    check idx == 0

  test "Single tab - click outside tab area":
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buffers = @[buf1]
    # " file1.nim " = 11 chars, so clicking at 11 should miss
    let tabText = buildTabText(buf1)
    let tabWidth = displayWidth(tabText)
    let idx = hitTestTabLine(buffers, EditorMode.Normal, 0, 80, tabWidth)
    check idx == -1

  test "Multiple tabs - click each tab":
    let buf1 = createTestTextBuffer("/path/a.nim")
    let buf2 = createTestTextBuffer("/path/b.nim")
    let buf3 = createTestTextBuffer("/path/c.nim")
    let buffers = @[buf1, buf2, buf3]
    # " a.nim " = 7 chars, " b.nim " = 7 chars, " c.nim " = 7 chars
    let w1 = displayWidth(buildTabText(buf1))
    let w2 = displayWidth(buildTabText(buf2))

    # Click in first tab
    check hitTestTabLine(buffers, EditorMode.Normal, 0, 80, 0) == 0
    # Click in second tab
    check hitTestTabLine(buffers, EditorMode.Normal, 0, 80, w1) == 1
    # Click in third tab
    check hitTestTabLine(buffers, EditorMode.Normal, 0, 80, w1 + w2) == 2

  test "Click beyond all tabs returns -1":
    let buf1 = createTestTextBuffer("/path/a.nim")
    let buffers = @[buf1]
    let w = displayWidth(buildTabText(buf1))
    let idx = hitTestTabLine(buffers, EditorMode.Normal, 0, 80, w + 10)
    check idx == -1

  test "Tab hidden by width limit returns -1":
    let buf1 = createTestTextBuffer("/path/verylongfilename1.nim")
    let buf2 = createTestTextBuffer("/path/verylongfilename2.nim")
    let buffers = @[buf1, buf2]
    let w1 = displayWidth(buildTabText(buf1))
    # Use narrow width that only fits the first tab
    let idx = hitTestTabLine(buffers, EditorMode.Normal, 0, w1, w1 + 2)
    check idx == -1

  test "With tabLineX offset":
    let buf1 = createTestTextBuffer("/path/file.nim")
    let buffers = @[buf1]
    let w = displayWidth(buildTabText(buf1))
    # Tab starts at X=10, so clicking at X=10 should hit tab 0
    check hitTestTabLine(buffers, EditorMode.Normal, 10, 80, 10) == 0
    # Clicking at X=9 (before offset) should miss
    check hitTestTabLine(buffers, EditorMode.Normal, 10, 80, 9) == -1
    # Clicking at X=10+w should miss (past end of tab)
    check hitTestTabLine(buffers, EditorMode.Normal, 10, 80, 10 + w) == -1

suite "TabLine - Special mode tab display":
  test "BookmarkManager mode: tabs show filenames, not mode label":
    ## Special modes should not override tab display.
    ## Tabs always show buffer filenames; mode is shown in the status line.
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buf2 = createTestTextBuffer("/path/file2.nim")
    let buffers = @[buf1, buf2]

    renderWindowTabLine(
      buffers, buf1, EditorMode.BookmarkManager, displayBuffer, 0, 0, 80, true, true
    )

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line
    check " BOOKMARKS " notin line

  test "BufferManager mode: tabs show filenames, not mode label":
    var displayBuffer = createTestBuffer()
    let buf1 = createTestTextBuffer("/path/file1.nim")
    let buf2 = createTestTextBuffer("/path/file2.nim")
    let buffers = @[buf1, buf2]

    renderWindowTabLine(
      buffers, buf1, EditorMode.BufferManager, displayBuffer, 0, 0, 80, true, true
    )

    let line = getBufferLine(displayBuffer, 0)
    check " file1.nim " in line
    check " file2.nim " in line
    check " BUFFERS " notin line
