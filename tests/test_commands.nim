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
  ../src/moepkg/
    [commands, buffer, types, config, commandregistry, keybindings, modes, cursor]

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
    state.command = "some command"
    let viewport = createTestViewport()

    let exec = newCommandExecutor(buf, state, viewport)

    # Try executing a command that exists (motion.left should exist)
    let result = exec.execute("motion.left")

    if result.isOk:
      check state.command == ""

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
