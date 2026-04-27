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
    completion, signature_help, lsp_integration,
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

  FilerHandler* = ref object ## Handler for Filer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  FileTreeHandler* = ref object
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    waitingForCtrlW*: bool # Waiting for second key after Ctrl-w
    isSearching*: bool # In search input mode
    searchBuffer*: string # Text being typed during search

  LogViewerHandler* = ref object ## Handler for Log Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  HelpViewerHandler* = ref object ## Handler for Help Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    lastKeyWasEscape*: bool # Waiting for second Escape for highlight clear

  BufferManagerHandler* = ref object
    ## Handler for Buffer Manager mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  BookmarkManagerHandler* = ref object
    ## Handler for Bookmark Manager mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  BackupManagerHandler* = ref object
    ## Handler for Backup Manager mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  DiffViewerHandler* = ref object ## Handler for Diff Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  RecentFileModeHandler* = ref object
    waitingForG*: bool # Waiting for second 'g' in 'gg' command

  DebugViewerHandler* = ref object ## Handler for Debug Viewer mode specific commands
    discard

  ConfigModeHandler* = ref object ## Handler for Configuration mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  ReferencesHandler* = ref object
    ## Handler for References Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  DocumentSymbolHandler* = ref object
    ## Handler for Document Symbol Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

  CallHierarchyHandler* = ref object
    ## Handler for Call Hierarchy Viewer mode specific commands
    waitingForG*: bool ## Waiting for second 'g' for 'gg' command

  TerminalHandler* = ref object ## Handler for Terminal mode specific commands
    discard

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    filerHandler*: FilerHandler
    logViewerHandler*: LogViewerHandler
    helpViewerHandler*: HelpViewerHandler
    bufferManagerHandler*: BufferManagerHandler
    bookmarkManagerHandler*: BookmarkManagerHandler
    backupManagerHandler*: BackupManagerHandler
    diffViewerHandler*: DiffViewerHandler
    recentFileModeHandler*: RecentFileModeHandler
    configModeHandler*: ConfigModeHandler
    referencesHandler*: ReferencesHandler
    documentSymbolHandler*: DocumentSymbolHandler
    callHierarchyHandler*: CallHierarchyHandler
    terminalHandler*: TerminalHandler
    fileTreeHandler*: FileTreeHandler
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    commandRegistry*: CommandRegistry
