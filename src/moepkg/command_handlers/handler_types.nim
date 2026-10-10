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

import std/options

import
  ../[
    motion, key_bindings, command_registry, command_line, command_config, completion,
    signature_help, lsp_integration, primitives,
  ]
import ../buffer/core
from ../types import EditorWindow

proc textObjectCommandIdFor*(ch: string): string =
  ## Map a text-object key (the char after i/a) to its registered command id,
  ## or "" when the key is not a text object. Shared by the Normal and Visual
  ## handlers so the mapping lives in one place.
  case ch
  of "w": "textobject.word"
  of "W": "textobject.wideword"
  of "\"": "textobject.quote.double"
  of "'": "textobject.quote.single"
  of "`": "textobject.quote.backtick"
  of "(", ")", "b": "textobject.paren"
  of "[", "]": "textobject.bracket"
  of "{", "}", "B": "textobject.brace"
  of "<", ">": "textobject.angle"
  of "t": "textobject.tag"
  of "s": "textobject.sentence"
  of "p": "textobject.paragraph"
  else: ""

type
  NormalModeHandler* = ref object ## Handler for Normal mode specific commands
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry

  AutoTriggerMark* = object
    ## Where a typed character left the cursor. The popup opens there only if
    ## nothing has moved or changed by the next frame.
    window*: EditorWindow
      # Another window on the same buffer may have its cursor at the same place
    bufferId*: BufferId
    cursor*: BufferPosition
    contentVersion*: int

  InsertModeHandler* = ref object
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry
    completionManager*: CompletionManager
    signatureHelpManager*: SignatureHelpManager
    lsp*: LspIntegration
    autoTrigger*: Option[AutoTriggerMark]
      # Set by the last key when it typed a character, consumed by the frame

  CommandModeHandler* = ref object ## Handler for Command mode specific commands
    parser*: CommandLineParser
    config*: CommandConfig
    commandRegistry*: CommandRegistry

  VisualModeHandler* = ref object ## Handler for Visual mode operations
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry
    motionController*: MotionController

  ReplaceModeHandler* = ref object ## Handler for Replace mode specific commands
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    commandRegistry*: CommandRegistry
