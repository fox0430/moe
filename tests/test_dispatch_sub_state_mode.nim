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

## Tests for dispatchSubStateMode in mode_dispatchers.nim.
##
## Covers:
##   * isNone × 11 template-driven modes (template expansion symmetry)
##   * isNone × Terminal (explicit branch, distinct handler signature)
##   * isSome smoke for Filer (template happy path)
##   * Early-return branches (migrated modes + Command/RecentFile/Debug/QuickRun)

import std/[unittest, options, os]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_line {.all.}
import ../src/moepkg/command_config {.all.}
import ../src/moepkg/filer {.all.}
import ../src/moepkg/editor_types except Command
import ../src/moepkg/command_handlers/handler_manager {.all.}
import ../src/moepkg/command_handlers/mode_dispatchers {.all.}
import ../src/moepkg/command_handlers/command_handler {.all.}
import ../src/moepkg/command_handlers/visual_handler {.all.}
import ../src/moepkg/command_handlers/insert_handler {.all.}
import ../src/moepkg/command_handlers/filetree_handler {.all.}
import editor_test_helper

proc createTestState(): EditorState =
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
  )
  result = EditorState(activeWindow: window)
  result.registers = initRegisters()

proc createTestViewport(): ViewPort =
  ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80)

proc createTestManager(): HandlerManager =
  let keyBindingRegistry = newKeyBindingRegistry()
  keyBindingRegistry.setupDefaultBindings()

  let commandRegistry = newCommandRegistry()
  commandRegistry.registerBuiltinCommands()

  let motionController = MotionController()

  let normalHandler = NormalModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let insertHandler = newInsertModeHandler(
    keyBindingRegistry, motionController, commandRegistry, autocompleteEnabled = false
  )

  let visualHandler = VisualModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let replaceHandler = ReplaceModeHandler(keyBindingRegistry: keyBindingRegistry)

  let commandLineParser = newCommandLineParser()
  let commandConfig = newCommandConfig()
  commandConfig.loadDefaultConfig()
  commandConfig.applyToParser(commandLineParser)
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)

  HandlerManager(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
    filerHandler: newFilerHandler(),
    fileTreeHandler: newFileTreeHandler(),
  )

proc setupDispatchTest(mode: EditorMode): (HandlerManager, Editor, KeyCombo) =
  let manager = createTestManager()
  let buffer = newTextBuffer()
  let state = createTestState()
  state.activeWindow.mode = mode
  let viewport = createTestViewport()
  let editor = createTestEditor(buffer, state, viewport, manager.keyBindingRegistry)
  let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
  (manager, editor, keyCombo)

suite "dispatchSubStateMode - missing sub-state returns hrError":
  test "Filer: filerState=none yields 'Filer state not initialized'":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Filer)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Filer state not initialized"

  test "FileTree: fileTreeState=none yields 'FileTree state not initialized'":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.FileTree)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "FileTree state not initialized"

  test "Help: helpViewerState=none yields 'Help viewer state not initialized'":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Help)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Help viewer state not initialized"

  test "BufferManager: bufferManagerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.BufferManager)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Buffer manager state not initialized"

  test "BookmarkManager: bookmarkManagerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.BookmarkManager)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Bookmark manager state not initialized"

  test "BackupManager: backupManagerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.BackupManager)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Backup manager state not initialized"

  test "DiffViewer: diffViewerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.DiffViewer)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Diff viewer state not initialized"

  test "Config: configModeState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Config)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Config mode state not initialized"

  test "References: referencesViewerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.References)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "References viewer state not initialized"

  test "DocumentSymbol: documentSymbolViewerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.DocumentSymbol)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Document symbol viewer state not initialized"

  test "CallHierarchy: callHierarchyViewerState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.CallHierarchy)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Call hierarchy viewer state not initialized"

  test "Terminal (explicit branch): terminalState=none yields proper message":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Terminal)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Terminal state not initialized"

suite "dispatchSubStateMode - wrong-kind variant returns hrError":
  # If `mode` and `modeState.kind` disagree (a transient inconsistency we
  # never expect in production, but worth pinning), the dispatcher must
  # treat it as "state not initialized" rather than dereferencing the
  # wrong variant payload.
  test "Filer mode with Help variant payload yields Filer hrError":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Filer)
    editor.activeWindow.modeState = ModeState(kind: mskHelp, help: newHelpViewerState())
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Filer state not initialized"

  test "Terminal mode with Filer variant payload yields Terminal hrError":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Terminal)
    editor.activeWindow.modeState =
      ModeState(kind: mskFiler, filer: newFilerState(getTempDir()))
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    check r.kind == hrError
    check r.errorMessage == "Terminal state not initialized"

suite "dispatchSubStateMode - happy path smoke (Filer)":
  test "Filer: filerState=some forwards to handleFilerMode":
    let (manager, editor, keyCombo) = setupDispatchTest(EditorMode.Filer)
    # newFilerState requires an existing directory; use the OS temp dir.
    let fs = newFilerState(getTempDir())
    editor.activeWindow.modeState = ModeState(kind: mskFiler, filer: fs)
    let r = manager.dispatchSubStateMode(editor, keyCombo)
    # 'a' is not a registered filer key — handler returns hrUnhandled, but
    # importantly we did NOT hit the hrError branch.
    check r.kind != hrError

suite "dispatchSubStateMode - early-return branches":
  test "Migrated modes return hrUnhandled (Normal/Insert/Visual/Replace)":
    for m in [
      EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
      EditorMode.VisualLine, EditorMode.Replace,
    ]:
      let (manager, editor, keyCombo) = setupDispatchTest(m)
      let r = manager.dispatchSubStateMode(editor, keyCombo)
      check r.kind == hrUnhandled

  test "Command/RecentFile/Debug/QuickRun return hrUnhandled":
    for m in [
      EditorMode.Command, EditorMode.RecentFile, EditorMode.Debug, EditorMode.QuickRun
    ]:
      let (manager, editor, keyCombo) = setupDispatchTest(m)
      let r = manager.dispatchSubStateMode(editor, keyCombo)
      check r.kind == hrUnhandled

# LogViewer is intentionally not covered here: it uses buffer-based dispatch
# instead of logViewerState (see TODO in mode_dispatchers.nim), and the
# underlying handler dereferences fields that are nil in a minimal test
# harness. LogViewer behavior is owned by LogViewerHandler-specific tests.
