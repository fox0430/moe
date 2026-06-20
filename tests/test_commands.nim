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

## Tests for commands.nim

import std/[unittest, options]
import pkg/results
import
  ../src/moepkg/[
    commands, buffer, types, config, command_registry, key_bindings, modes, motion,
    render_utils,
  ]

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
    windowDisplay: WindowDisplayState(viewportReservedLines: steadyBottomAreaHeight()),
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

suite "CommandExecutor - Constructor":
  test "Create CommandExecutor with default registries":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    check exec.buffer == buf
    check exec.state == state
    check exec.viewport == viewport
    check exec.commandRegistry != nil
    check exec.keyBindingRegistry != nil

  test "Create CommandExecutor with custom ClipboardConfig":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let clipboardConfig = ClipboardConfig(enable: true, tool: cbtXclip)
    let exec = newCommandExecutor(buf, state, viewport, clipboardConfig)

    check exec.clipboardConfig.enable == true
    check exec.clipboardConfig.tool == cbtXclip

  test "Create CommandExecutor with custom NotificationConfig":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let notificationConfig = NotificationConfig()
    let exec =
      newCommandExecutor(buf, state, viewport, notificationConfig = notificationConfig)

    check exec.notificationConfig == notificationConfig

  test "Create CommandExecutor with provided CommandRegistry":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let customRegistry = newCommandRegistry()
    let exec =
      newCommandExecutor(buf, state, viewport, commandRegistry = some(customRegistry))

    check exec.commandRegistry == customRegistry

  test "Create CommandExecutor with provided KeyBindingRegistry":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let customKeyRegistry = newKeyBindingRegistry()
    let exec = newCommandExecutor(
      buf, state, viewport, keyBindingRegistry = some(customKeyRegistry)
    )

    check exec.keyBindingRegistry == customKeyRegistry

suite "CommandExecutor - Motion Execution":
  test "Execute motion left":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 5)
    exec.executeMotion(Motion.Left, 1)

    check exec.cursor.column == 4

  test "Execute motion right":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)
    exec.executeMotion(Motion.Right, 1)

    check exec.cursor.column == 1

  test "Execute motion left with count":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 5)
    exec.executeMotion(Motion.Left, 3)

    check exec.cursor.column == 2

  test "Execute motion down":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)
    exec.executeMotion(Motion.Down, 1)

    check exec.cursor.line == 1

  test "Execute motion up":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 2, column: 0)
    exec.executeMotion(Motion.Up, 1)

    check exec.cursor.line == 1

  test "Execute motion home":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 5)
    exec.executeMotion(Motion.Home, 1)

    check exec.cursor.column == 0

  test "Execute motion end":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)
    exec.executeMotion(Motion.End, 1)

    # End should move to last character position (10 for "Hello World")
    check exec.cursor.column == 10

  test "Execute motion first line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 2, column: 0)
    exec.executeMotion(Motion.FirstLine, 1)

    check exec.cursor.line == 0

  test "Execute motion last line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)
    exec.executeMotion(Motion.LastLine, 1)

    check exec.cursor.line == 2

suite "CommandExecutor - Compatibility Wrappers":
  test "clampCursor does not crash":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    # Should not crash (compatibility wrapper, does nothing)
    exec.clampCursor()

  test "updateViewport does not crash":
    let buf = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    # Should not crash (compatibility wrapper, does nothing)
    exec.updateViewport()

suite "CommandExecutor - Execute Command String":
  test "Execute unknown command returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    let result = exec.execute("nonexistent.command")

    check result.isErr

  test "Execute clears command buffer on success":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    state.commandText = "some command"
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    # Try executing a command that exists (motion.left should exist)
    let result = exec.execute("motion.left")

    if result.isOk:
      check state.commandText == ""

suite "CommandExecutor - Keybinding Execution":
  test "Execute keybinding with motion command":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 5)

    # Create a motion command
    let cmd = Command(
      name: "left",
      description: "Move left",
      count: 1,
      kind: ctMotion,
      motion: Motion.Left,
    )

    let result = exec.executeKeybinding(cmd)

    if result.isOk:
      check exec.cursor.column == 4

suite "CommandExecutor - Integration":
  test "Motion controller is initialized":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    check exec.motionController != nil

  test "Multiple motions in sequence":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)

    # Move right 3 times
    exec.executeMotion(Motion.Right, 1)
    exec.executeMotion(Motion.Right, 1)
    exec.executeMotion(Motion.Right, 1)

    check exec.cursor.column == 3

    # Move left 2 times
    exec.executeMotion(Motion.Left, 2)

    check exec.cursor.column == 1

  test "Motion boundary at start of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)

    # Try to move left from start of line - should stay at 0
    exec.executeMotion(Motion.Left, 1)

    check exec.cursor.column == 0

  test "Motion boundary at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 10) # Last character

    # Move right from end of line - should stay at last position
    exec.executeMotion(Motion.Right, 1)

    check exec.cursor.column == 10

  test "Multi-line motion navigation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let state = createTestState()
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)
    exec.cursor = BufferPosition(line: 0, column: 0)

    # Move down twice
    exec.executeMotion(Motion.Down, 2)
    check exec.cursor.line == 2

    # Move to end of line
    exec.executeMotion(Motion.End, 1)
    check exec.cursor.column == 5 # "Line 3" has 6 chars, last pos is 5

    # Move to first line
    exec.executeMotion(Motion.FirstLine, 1)
    check exec.cursor.line == 0

suite "ViewportManager - Goto Line Scrolling":
  proc createTestBuffer(lineCount: int): TextBuffer =
    ## Create a buffer with specified number of lines
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "viewport scrolls when jumping to line far below":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to line 100 (0-based index: 99)
    let targetLine = 99
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    # Line 100 should be visible
    let visibleHeight = viewportManager.viewport.height - steadyBottomAreaHeight()
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check targetLine >= viewportManager.viewport.topLine
    check targetLine <= maxVisibleLine
    check viewportManager.viewport.topLine > 70

  test "viewport scrolls when jumping to line far above":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 80, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to line 10 (0-based index: 9)
    let targetLine = 9
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check targetLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine <= 9

  test "viewport does not scroll if target line is already visible":
    let buffer = createTestBuffer(100)
    let initialTopLine = 40
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: initialTopLine, leftColumn: 0, height: 20, width: 80, x: 0, y: 0
      )
    )

    # Jump to line 50 (already visible)
    let targetLine = 50
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check viewportManager.viewport.topLine >= initialTopLine - 1
    check viewportManager.viewport.topLine <= initialTopLine + 1

  test "viewport scrolls to first line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 80, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let cursorPos = CursorPosition(x: 0, y: 0)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check viewportManager.viewport.topLine == 0

  test "viewport scrolls to last line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    let visibleHeight = viewportManager.viewport.height - steadyBottomAreaHeight()
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check lastLine >= viewportManager.viewport.topLine
    check lastLine <= maxVisibleLine

suite "ViewportManager - Line Wrap Scrolling":
  proc createTestBuffer(lineCount: int): TextBuffer =
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "lineWrap: viewport scrolls to last line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    # Cursor must be visible
    check lastLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine > 0

  test "lineWrap: viewport scrolls to line far below":
    let buffer = createTestBuffer(1000)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 30, width: 80, x: 0, y: 0)
    )

    let targetLine = 999
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    check targetLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine > 900

  test "lineWrap: viewport stays when cursor is visible":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 10, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let targetLine = 15
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    # topLine should not change since cursor is already visible
    check viewportManager.viewport.topLine == 10

  test "lineWrap: viewport scrolls up":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 50, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let cursorPos = CursorPosition(x: 0, y: 5)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == 5

  proc createLongLineBuffer(lineCount: int, lineWidth: int): TextBuffer =
    ## Create a buffer where each line has `lineWidth` characters (all 'a').
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      for j in 1 .. lineWidth:
        lines.add('a')
    result = newTextBuffer(lines)

  test "lineWrap: viewport scrolls to last line with wrapped lines":
    # Each line: 40 chars, viewport width 20 → 2 screen lines per logical line.
    # visibleHeight = 20 - 1 = 19. budget = 19 (cursorWrapOffset=0).
    # 9 lines × 2 = 18 < 19, 10 lines × 2 = 20 (not < 19) → topLine = lastLine - 9.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 20, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == lastLine - 9

  test "lineWrap: viewport scrolls with cursor at non-zero wrap offset":
    # Each line: 40 chars, viewport width 20 → 2 screen lines per logical line.
    # Cursor at column 25 → cursorWrapOffset = 1.
    # visibleHeight = 19, budget = 19 - 1 = 18.
    # 8 lines × 2 = 16 < 18, 9 lines × 2 = 18 (not < 18) → topLine = lastLine - 8.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 20, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 25, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      lineNumOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == lastLine - 8

suite "ViewportManager - Default reservedLines":
  proc createTestBuffer(lineCount: int): TextBuffer =
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "updateViewport default reservedLines matches steadyBottomAreaHeight()":
    ## When reservedLines is omitted (default = -1), the auto-calculated value
    ## for showStatusLine=true should equal steadyBottomAreaHeight().
    let buffer = createTestBuffer(100)

    # Explicit reservedLines = steadyBottomAreaHeight()
    let vmExplicit = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )
    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    vmExplicit.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    # Default reservedLines (omitted → auto-calculated)
    let vmDefault = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    vmDefault.updateViewport(cursorPos, buffer.len, showStatusLine = true)

    check vmExplicit.viewport.topLine == vmDefault.viewport.topLine
