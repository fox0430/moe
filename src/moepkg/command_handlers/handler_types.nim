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

## Handler-related type definitions.
##
## This module is the single source of truth for the *Handler ref object types
## and the HandlerManager that aggregates them. Centralizing these types here
## lets the subhandler and handler_manager modules import editor_types (for the
## Editor parameter) without forming a cycle through editor_types' need to know
## the HandlerManager field type.

import
  ../[
    motion, key_bindings, command_registry, command_line, command_config, config,
    completion, signature_help, lsp_integration, modes,
  ]

type
  NormalModeHandler* = ref object ## Handler for Normal mode specific commands
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry
    clipboardConfig*: ClipboardConfig
    smoothScrollConfig*: SmoothScrollConfig
    notificationConfig*: NotificationConfig

  InsertModeHandler* = ref object ## Handler for Insert mode specific commands
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry
    completionManager*: CompletionManager
    signatureHelpManager*: SignatureHelpManager
    lsp*: LspIntegration ## LSP integration for completions
    autocompleteEnabled*: bool ## Whether autocomplete is enabled
    notificationConfig*: NotificationConfig

  CommandModeHandler* = ref object ## Handler for Command mode specific commands
    parser*: CommandLineParser
    config*: CommandConfig
    commandRegistry*: CommandRegistry

  VisualModeHandler* = ref object ## Handler for Visual mode operations
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry
    motionController*: MotionController
    notificationConfig*: NotificationConfig

  ReplaceModeHandler* = ref object ## Handler for Replace mode specific commands
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry

  SubStateHandler* = ref object
    ## Unified handler state for all sub-state modes (Filer, FileTree, the
    ## various viewers/managers, Terminal, Debug). These modes share a tiny,
    ## flat set of transient key-sequence flags, so a single superset type
    ## replaces what used to be 15 near-identical ref object types. Stored in
    ## `HandlerManager.subStates` indexed by `EditorMode` and reached through the
    ## per-mode accessor procs below.
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    lastKeyWasEscape*: bool # Help: waiting for second Escape to clear highlight
    waitingForCtrlW*: bool # FileTree: waiting for second key after Ctrl-w
    isSearching*: bool # FileTree: in search input mode
    searchBuffer*: string # FileTree: text being typed during search

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    subStates*: array[EditorMode, SubStateHandler]
      ## Per-mode handler state for all sub-state modes, replacing the former
      ## 14 individual handler fields. Indexed directly by the (dense, pure)
      ## EditorMode enum: sub-state modes hold a handler, the rest stay nil.
      ## Access via the `filerHandler`, `fileTreeHandler`, ... accessor procs
      ## below, which preserve the old `manager.<mode>Handler` call sites.
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    commandRegistry*: CommandRegistry

# Sub-state handler accessors. Each returns the shared SubStateHandler ref for a
# mode, so existing `manager.<mode>Handler.<field>` reads and writes keep working
# (the ref means writes hit the stored object). initSubStates populates every
# slot these accessors read, so the lookup never returns nil.
proc newSubStateHandler*(): SubStateHandler =
  ## Create a sub-state handler with all flags at their zero values. Shared by
  ## every sub-state mode (Filer, FileTree, the viewers/managers, Terminal,
  ## Debug).
  SubStateHandler()

proc initSubStates*(): array[EditorMode, SubStateHandler] =
  ## Build the sub-state handler array, allocating a handler for every sub-state
  ## mode (each with all flags at their zero values). Modes without a sub-state
  ## handler (Normal, Insert, ...) stay nil; their accessors are never called.
  ## Used by newHandlerManager (and tests) so the per-mode accessor procs below
  ## never return nil.
  for m in [
    EditorMode.Filer, EditorMode.FileTree, EditorMode.LogViewer, EditorMode.Help,
    EditorMode.BufferManager, EditorMode.BookmarkManager, EditorMode.BackupManager,
    EditorMode.DiffViewer, EditorMode.RecentFile, EditorMode.Config,
    EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
    EditorMode.Terminal,
  ]:
    result[m] = newSubStateHandler()

proc filerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.Filer]

proc fileTreeHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.FileTree]

proc logViewerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.LogViewer]

proc helpViewerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.Help]

proc bufferManagerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.BufferManager]

proc bookmarkManagerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.BookmarkManager]

proc backupManagerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.BackupManager]

proc diffViewerHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.DiffViewer]

proc recentFileModeHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.RecentFile]

proc configModeHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.Config]

proc referencesHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.References]

proc documentSymbolHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.DocumentSymbol]

proc callHierarchyHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.CallHierarchy]

proc terminalHandler*(m: HandlerManager): SubStateHandler =
  m.subStates[EditorMode.Terminal]
