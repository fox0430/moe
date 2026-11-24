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

## Tests for `v`, `V` and `C-v` typed in a Visual mode.

import std/[unittest, options]

import
  ../src/moepkg/[
    buffer, types, modes, editor, config, key_bindings, keybind_config, handler,
    registers, visual_selection, frontend_input,
  ]
import ../src/moepkg/command_handlers/[handler_result, result_processor]

proc pos(line, column: int): BufferPosition =
  BufferPosition(line: line, column: column)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  config.clipboard.enable = false
  result = newEditor(config)
  discard result.activeBuffer.insertText(pos(0, 0), "abcdefgh\nab\nabcdefghij\nabcd")
  result.activeWindow.cursor = pos(0, 1)

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

const Kinds =
  {"v": EditorMode.Visual, "V": EditorMode.VisualLine, "C-v": EditorMode.VisualBlock}

suite "Switching between the Visual modes":
  for (fromKey, fromMode) in Kinds:
    for (toKey, toMode) in Kinds:
      if fromKey == toKey:
        test fromKey & " ends the mode it started":
          let e = createTestEditor()
          e.press(fromKey, "l", toKey)

          check e.state.mode == EditorMode.Normal
          check e.cursor == pos(0, 2)
          check e.activeBuffer.lastVisual.get.kind == fromMode.visualKind
      else:
        test fromKey & " to " & toKey & " keeps both ends":
          let e = createTestEditor()
          e.press(fromKey, "j", "j", toKey)

          check e.state.mode == toMode
          check e.activeWindow.visualSelection.start == pos(0, 1)
          check e.cursor == pos(2, 1)

          # The way out is still Normal.
          e.press("Esc")
          check e.state.mode == EditorMode.Normal

  test "an operator acts on the kind switched to":
    let e = createTestEditor()
    e.press("v", "j", "V", "d")

    check e.state.mode == EditorMode.Normal
    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "abcdefghij"

  test "the switch keeps the line end $ took the selection to":
    let e = createTestEditor()
    e.press("v", "$", "C-v", "j", "j")

    check e.currentSelection().get.extendsToLineEnd

  test "ending Visual with its key keeps the column vertical moves want":
    let e = createTestEditor()
    e.press("v", "$", "v", "j", "j")

    check e.cursor == pos(2, 9)

  test "Escape does not keep it":
    let e = createTestEditor()
    e.press("v", "$", "Esc", "j", "j")

    check e.cursor == pos(2, 7)

  test "the swapped end stays the cursor":
    let e = createTestEditor()
    e.press("v", "l", "j", "o", "V")

    check e.cursor == pos(0, 1)
    check e.activeWindow.visualSelection.start.line == 1

  test "a count does not carry over to the next command":
    let e = createTestEditor()
    e.press("v", "3", "V", "j")

    check e.state.mode == EditorMode.VisualLine
    check e.cursor.line == 1

  test "gv reselects the kind switched to":
    let e = createTestEditor()
    e.press("v", "j", "V", "V", "g", "v")

    check e.state.mode == EditorMode.VisualLine

  test "Insert resumes when the key ends a Visual entered after Ctrl-o":
    let e = createTestEditor()
    e.press("i", "C-o", "v", "V", "V")

    check e.state.mode == EditorMode.Insert

  test "ending a switched Visual returns to the viewer it was entered from":
    let e = createTestEditor()
    discard e.processResult(HandlerResult(kind: hrEnterLogViewer), e.activeBuffer)
    check e.state.mode == EditorMode.LogViewer

    e.press("v", "V")
    check e.state.mode == EditorMode.VisualLine
    e.press("V")
    check e.state.mode == EditorMode.LogViewer

  test "ending Visual with its key cancels an operator waiting since before it":
    let e = createTestEditor()
    e.press("d")
    # As a mouse selection does, with the operator still waiting.
    e.state.enterVisual(vskChar, pos(0, 1), pos(0, 2))
    check e.state.pendingInput.pendingOperator.isSome
    e.press("v", "l")

    check e.state.mode == EditorMode.Normal
    check e.state.pendingInput.pendingOperator.isNone
    check e.activeBuffer.getLine(0) == "abcdefgh"

  test "a mode_switch mapping to the current mode stays in it":
    for (key, target) in {"v": "visual", "V": "visualline", "C-v": "visualblock"}:
      let e = createTestEditor()
      e.press(key)
      let mode = e.state.mode
      check e.keyRouter.registry.addRuntimeMappingExpanded(
        mode, "Q", "mode_switch " & target
      ) == ""
      e.press("l", "Q")

      check e.state.mode == mode
      check e.activeWindow.visualSelection.start == pos(0, 1)
      check e.cursor == pos(0, 2)

  test "a user's Visual mapping on the keys holds in the other two modes":
    for (fromKey, mapped) in {"C-v": "V", "C-v": "v", "V": "C-v", "V": "v"}:
      let e = createTestEditor()
      check e.keyRouter.registry.addRuntimeMappingExpanded(
        EditorMode.Visual, mapped, "visual-yank"
      ) == ""
      e.press(fromKey, "l", mapped)

      check e.state.mode == EditorMode.Normal
      check e.state.registers.getRegisterContent('"').len > 0

  test "a count is dropped in the other two modes too":
    let e = createTestEditor()
    e.press("C-v", "3", "V", "j")

    check e.state.mode == EditorMode.VisualLine
    check e.cursor.line == 1

  test "a mouse selection cancels a waiting operator":
    # Each key would finish the operator if it were still waiting.
    for keys in [@["v", "l"], @["V", "l"], @["C-v", "l"], @["l"]]:
      for drag in [false, true]:
        let e = createTestEditor()
        e.config.standard.mouse = true
        e.activeWindow.viewport = ViewPort(x: 0, y: 0, width: 80, height: 24)
        e.state.showTabLine = false
        e.state.showLineNumbers = false
        e.state.showSidebar = false
        e.press("d")
        check e.state.pendingInput.pendingOperator.isSome
        if drag:
          check e.handlePointerInput(initPointerInput(0, 2))
          check e.handlePointerInput(initPointerInput(0, 4, action = paDrag))
          check e.handlePointerInput(initPointerInput(0, 4, action = paRelease))
        else:
          check e.handlePointerInput(initPointerInput(0, 2, clickCount = 2))
        check e.state.mode == EditorMode.Visual
        check e.state.pendingInput.pendingOperator.isNone
        e.press(keys)

        check e.activeBuffer.getLine(0) == "abcdefgh"

  test "ending each kind with its key cancels the operator and drops a count":
    for (key, mode) in Kinds:
      let e = createTestEditor()
      e.press("d")
      e.state.enterVisual(mode.visualKind, pos(0, 1), pos(0, 2))
      e.press("3", key)
      check e.state.mode == EditorMode.Normal
      check e.state.pendingInput.pendingOperator.isNone
      e.press("l")

      check e.activeBuffer.getLine(0) == "abcdefgh"
      check e.cursor == pos(0, 3)

  test "switching to another kind cancels an operator waiting since before Visual":
    for (fromKey, fromMode) in Kinds:
      for (toKey, toMode) in Kinds:
        if fromKey == toKey:
          continue
        let e = createTestEditor()
        e.press("d")
        e.state.enterVisual(fromMode.visualKind, pos(0, 1), pos(0, 2))
        e.press(toKey, "j")

        check e.state.mode == toMode
        check e.state.pendingInput.pendingOperator.isNone
        check e.activeBuffer.len == 4

  test "a shift-click in Visual cancels a waiting operator":
    let e = createTestEditor()
    e.config.standard.mouse = true
    e.activeWindow.viewport = ViewPort(x: 0, y: 0, width: 80, height: 24)
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.press("d")
    e.state.enterVisual(vskChar, pos(0, 1), pos(0, 2))
    check e.handlePointerInput(initPointerInput(0, 4, modifiers = {kmShift}))
    check e.state.pendingInput.pendingOperator.isNone
    e.press("l")

    check e.state.mode == EditorMode.Visual
    check e.activeBuffer.getLine(0) == "abcdefgh"

  test "an operator acts on the block or the lines switched to":
    for fromKey in ["v", "V"]:
      let e = createTestEditor()
      e.press(fromKey, "j", "j", "l", "C-v", "d")

      check e.state.mode == EditorMode.Normal
      check e.activeBuffer.getLine(0) == "adefgh"
      check e.activeBuffer.getLine(1) == "a"
      check e.activeBuffer.getLine(2) == "adefghij"
      check e.activeBuffer.getLine(3) == "abcd"

    let e = createTestEditor()
    e.press("C-v", "j", "V", "d")
    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "abcdefghij"

  test "a replayed macro switches":
    let e = createTestEditor()
    e.press("q", "a", "v", "V", "d", "q", "@", "a")

    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "abcdefghij"
