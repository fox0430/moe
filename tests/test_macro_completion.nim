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

## The completion popup opens for a typed character only at the next frame,
## once every pending key is processed, like Vim's TextChangedI. A replay runs
## inside one key, so a replayed key never meets a popup the replay opened.
## Recording opens none, so the replay of a recorded key does what it did.

import std/[unittest, options, strutils, tables]

import pkg/results

import
  ../src/moepkg/[
    types, editor, handler, buffer, config, key_bindings, keybind_config, completion,
    registers, signature_help,
  ]
import ../src/moepkg/[editor_window, window_manager]
import ../src/moepkg/editor_frame {.all.}

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  result.state.registers = initRegisters()
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.syncActiveWindow()
  result.state.mode = EditorMode.Normal

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

proc nextFrame(e: Editor) =
  ## The frame's LSP phase, which opens the popup for the last typed character.
  e.tickLsp()

proc text(e: Editor): string =
  let b = e.activeBuffer
  var lines: seq[string]
  for i in 0 ..< b.len:
    lines.add b.getLine(i)
  lines.join("\n")

proc popupOpen(e: Editor): bool =
  e.handlerManager.insertHandler.completionManager.isActive()

suite "Completion popup opens at the frame":
  test "a typed character opens the popup at the next frame":
    # "x" matches the buffer word "xyzzy".
    let e = newTestEditor("xyzzy")
    e.press("o", "x")
    check not e.popupOpen

    e.nextFrame()
    check e.popupOpen

  test "the popup opens only in the window that was typed in":
    # The other window on the buffer has its cursor at the same place.
    let e = newTestEditor("xyzzy")
    check e.vsplit().isOk
    e.press("o", "x")
    let typedAt = e.cursor

    let other = 1 - e.windowManager.activeWindowIndex
    e.windowManager.activateWindow(other)
    e.syncActiveWindow()
    e.state.mode = EditorMode.Insert
    e.cursor = typedAt

    e.nextFrame()
    check not e.popupOpen

  test "Ctrl-C closes the popup and signature help as Escape does":
    let e = newTestEditor("xyzzy")
    e.press("o", "x")
    e.nextFrame()
    check e.popupOpen
    let sigHelp = e.handlerManager.insertHandler.signatureHelpManager
    sigHelp.state = shsActive

    check e.handleInterrupt()
    check e.state.mode == EditorMode.Normal
    check not e.popupOpen
    check not sigHelp.isActive

  test "a key after the character cancels it":
    let e = newTestEditor("xyzzy")
    e.press("o", "x", "Left")

    e.nextFrame()
    check not e.popupOpen

  test "a mapping's keys open the popup once, after the mapping":
    let e = newTestEditor("xyzzy")
    e.handlerManager.keyBindingRegistry.addKeySequenceMapping(
      EditorMode.Insert, "C-k", "x y Enter x"
    )

    e.press("o", "C-k")
    check e.text == "xyzzy\nxy\nx"
    check not e.popupOpen

    e.nextFrame()
    check e.popupOpen

  test "Enter in a popup nothing was picked in breaks the line":
    # As in Vim, so it does the same with the popup open or not.
    let e = newTestEditor("xyzzy")
    e.press("o", "x")
    e.nextFrame()
    check e.popupOpen

    e.press("Enter", "y")
    check not e.popupOpen
    check e.text == "xyzzy\nx\ny"

suite "Completion inside a macro":
  test "a running macro opens no popup, so Enter breaks the line":
    let e = newTestEditor("xyzzy")
    e.state.pendingInput.macroState.registers['q'] =
      @["o", "x", "y", "<Enter>", "w", "<Escape>"]

    e.press("@", "q")

    check e.text == "xyzzy\nxy\nw"

  test "Tab in a running macro indents instead of picking a candidate":
    let e = newTestEditor("xyzzy")
    e.state.expandTab = false
    e.state.pendingInput.macroState.registers['q'] =
      @["o", "x", "<Tab>", "a", "<Escape>"]

    e.press("@", "q")

    check e.text == "xyzzy\nx\ta"

  test "a macro that ends in Insert opens the popup once afterwards":
    let e = newTestEditor("xyzzy")
    e.state.pendingInput.macroState.registers['q'] = @["o", "x", "y"]

    e.press("@", "q")
    check e.state.mode == EditorMode.Insert
    check not e.popupOpen

    e.nextFrame()
    check e.popupOpen

  test "Ctrl-N completes inside a macro":
    let e = newTestEditor("foobar")
    e.state.pendingInput.macroState.registers['q'] =
      @["o", "f", "o", "<C-n>", "<C-n>", "<Escape>"]

    e.press("@", "q")

    check e.text == "foobar\nfoobar"

suite "Completion while recording":
  test "recording opens no popup, so the replay does what was typed":
    let e = newTestEditor("xyzzy")
    e.press("q", "q", "o", "x", "y")
    e.nextFrame()
    check not e.popupOpen

    e.press("Enter", "w", "Esc", "q")
    check e.text == "xyzzy\nxy\nw"

    e.press("@", "q")
    check e.text == "xyzzy\nxy\nw\nxy\nw"

  test "Ctrl-N while recording is replayed with the same result":
    let e = newTestEditor("foobar")
    e.press("q", "q", "o", "f", "o", "C-n", "C-n", "Esc", "q")
    check e.text == "foobar\nfoobar"

    e.press("@", "q")
    check e.text == "foobar\nfoobar\nfoobar"

  test "a mapping run while recording completes like the typed keys":
    let e = newTestEditor("xyzzy")
    check e.handlerManager.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "C-j", "C-n"
    ) == ""

    e.press("q", "q", "o", "x", "C-j", "C-j", "Esc", "q")
    check e.text == "xyzzy\nxyzzy"

    e.press("@", "q")
    check e.text == "xyzzy\nxyzzy\nxyzzy"

suite "Mappings outside a macro":
  test "a mapping still drives the popup":
    let e = newTestEditor("xyzzy")
    check e.handlerManager.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "C-j", "C-n"
    ) == ""

    e.press("o", "x")
    e.press("C-j")
    check e.popupOpen

    e.press("C-j")
    check e.activeBuffer.getLine(1) == "xyzzy"
