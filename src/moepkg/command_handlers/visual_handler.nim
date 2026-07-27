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

## Visual mode handler
##
## This module handles visual selection and provides the core selection
## functionality for Visual mode

import std/[options, strutils]

import pkg/results

import
  ../[
    buffer, modes, motion, types, key_bindings, command_registry, key_router,
    pending_input,
  ]
import ../types/editor_types
import handler_types
export handler_types

type
  VisualModeResultKind* = enum
    vmrHandled
    vmrUnhandled
    vmrWaitingForInput ## Waiting for additional input (e.g., replace char)
    vmrLspSelectionRange ## Execute LSP selection range
    vmrExecCommand
      ## Command mode command alias bridge — run `:<alias>` via the
      ## command-line parser
    vmrError

  VisualModeResult* = object ## Result of visual mode command execution
    case kind*: VisualModeResultKind
    of vmrHandled:
      modeTransition*: Option[EditorMode]
    of vmrUnhandled:
      discard
    of vmrWaitingForInput:
      discard
    of vmrLspSelectionRange:
      discard
    of vmrExecCommand:
      execCommandText*: string
        ## Visual mode has no count prefix, so the dispatcher always
        ## forwards count = 1 to the command-line parser.
    of vmrError:
      errorMessage*: string

proc newVisualModeHandler*(
    keyBindingRegistry: KeyBindingRegistry,
    commandRegistry: CommandRegistry,
    motionController: MotionController,
): VisualModeHandler =
  ## Create a new Visual mode handler. NotificationConfig is pulled live from
  ## `state.config` via CommandContext getter.
  VisualModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

proc initSelection*(
    state: EditorState, buffer: TextBuffer, kind: VisualSelectionKind = vskChar
) =
  ## Initialize visual selection at current cursor position
  let cursorPos = state.cursor
  state.visualSelection =
    VisualSelection(start: cursorPos, current: cursorPos, active: true, kind: kind)

proc clearSelection*(state: EditorState) =
  ## Clear the visual selection
  state.visualSelection.active = false

proc updateSelection*(state: EditorState, newPos: BufferPosition) =
  ## Update the current end of the selection
  if state.visualSelection.active:
    state.visualSelection.current = newPos

proc getSelectionRange*(
    selection: VisualSelection
): tuple[start, endPos: BufferPosition] {.inline.} =
  ## Get the normalized selection range (start is always before end)
  ## Returns (start, end) where start <= end

  if not selection.active:
    return (selection.start, selection.start)

  # Normalize so start is always before end
  if selection.start.line < selection.current.line:
    return (selection.start, selection.current)
  elif selection.start.line > selection.current.line:
    return (selection.current, selection.start)
  else:
    # Same line - compare columns
    if selection.start.column <= selection.current.column:
      return (selection.start, selection.current)
    else:
      return (selection.current, selection.start)

proc isPositionInSelection*(selection: VisualSelection, pos: BufferPosition): bool =
  ## Check if a position is within the current selection
  if not selection.active:
    return false

  let (selStart, selEnd) = selection.getSelectionRange()

  # Check if position is within range
  if pos.line < selStart.line or pos.line > selEnd.line:
    return false

  case selection.kind
  of vskBlock:
    # Block selection: column range applies to all lines in the selection
    let colStart = min(selection.start.column, selection.current.column)
    let colEnd = max(selection.start.column, selection.current.column)
    return pos.column >= colStart and pos.column <= colEnd
  of vskLine:
    # Line selection: entire lines are selected
    return true # Already checked line range above
  of vskChar:
    # Character-wise selection
    if pos.line == selStart.line and pos.line == selEnd.line:
      # Selection is on a single line
      return pos.column >= selStart.column and pos.column <= selEnd.column
    elif pos.line == selStart.line:
      # Position is on start line
      return pos.column >= selStart.column
    elif pos.line == selEnd.line:
      # Position is on end line
      return pos.column <= selEnd.column
    else:
      # Position is on a middle line
      return true

proc executeCommand*(
    handler: VisualModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    commandId: string,
    args: seq[string] = @[],
): VisualModeResult =
  ## Execute a command using the CommandRegistry
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
  )

  let originalMode = state.mode
  let r = handler.commandRegistry.execute(ctx, commandId, args)
  if r.isOk:
    # Check if mode changed from a visual mode to something else
    let modeTransition =
      if not isVisualAllMode(state.mode) or state.mode != originalMode:
        some(state.mode)
      else:
        none(EditorMode)
    return VisualModeResult(kind: vmrHandled, modeTransition: modeTransition)
  else:
    return VisualModeResult(kind: vmrError, errorMessage: r.error)

proc handleVisualModeKey*(
    handler: VisualModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): VisualModeResult =
  ## Main entry point for handling Visual mode key presses
  ## Works for Visual, VisualBlock, and VisualLine modes
  ## Macro recording is captured centrally in `handler.handleKeyCombo`.

  let originalMode = state.mode

  # Handle pending text object - waiting for text object kind (w, ", (, etc.)
  # This handles viw, va", vi( etc. in Visual mode
  if state.pendingInput.pendingTextObject.isSome:
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      # Map key to text object kind command (shared with the Normal handler)
      let textObjectCommandId = textObjectCommandIdFor(keyCombo.char)

      if textObjectCommandId.len > 0:
        let ctx = CommandContext(
          buffer: buffer,
          state: state,
          viewport: viewport,
          motionController: handler.motionController,
          keyBindingRegistry: handler.keyBindingRegistry,
        )

        let cmdResult = handler.commandRegistry.execute(ctx, textObjectCommandId, @[])

        if cmdResult.isOk:
          return VisualModeResult(kind: vmrHandled, modeTransition: none(EditorMode))
        else:
          return VisualModeResult(kind: vmrError, errorMessage: cmdResult.error)
      else:
        # Not a text object key - cancel pending state with feedback. Clear the
        # pending operator too (matching the Normal handler) so no stale operator
        # is left armed.
        state.pendingInput.pendingTextObject = none(PendingTextObject)
        state.pendingInput.pendingOperator = none(PendingOperator)
        state.statusMessage = "Not a text object: " & keyCombo.char
        return VisualModeResult(kind: vmrHandled, modeTransition: none(EditorMode))
    else:
      # Special key or key with modifiers - cancel pending state
      state.pendingInput.pendingTextObject = none(PendingTextObject)
      # Fall through to process the key normally

  # Resolve the key through the shared built-in decode entry (`resolveBuiltin`)
  # — the same path the Normal dispatcher uses. For VisualBlock/VisualLine, fall
  # back to the shared Visual bindings, but only when the sub-mode genuinely had
  # nothing to say (`rrUnhandled`). Falling back on `rrWaiting` would drive
  # `processKey` a second time and complete a one-key-short sequence early
  # (e.g. a single `g` in VisualBlock firing `gg`).
  var route = handler.keyBindingRegistry.resolveBuiltin(state.mode, keyCombo)
  if route.kind == rrUnhandled and state.mode != EditorMode.Visual:
    route = handler.keyBindingRegistry.resolveBuiltin(EditorMode.Visual, keyCombo)

  case route.kind
  of rrWaiting:
    # Accumulating a multi-key sequence (gg/ge/zf) or waiting for an operand
    # (e.g. after pressing `r`).
    return VisualModeResult(kind: vmrWaitingForInput)
  of rrCommand:
    discard # Fall through to dispatch below.
  of rrCancelled:
    # Escape cleared a pending sequence; stay in visual mode.
    return VisualModeResult(kind: vmrUnhandled)
  else:
    # rrUnhandled: no user mapping found.
    # ESC/C-c with no user mapping returns to previousMode.
    if (keyCombo.isSpecial and keyCombo.special == skEscape) or (
      not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == "c"
    ):
      if handler.keyBindingRegistry != nil:
        discard state.pendingInput.cancelAll(handler.keyBindingRegistry)
      state.clearSelection()
      let returnMode = state.previousMode
      state.mode = returnMode
      return VisualModeResult(kind: vmrHandled, modeTransition: some(returnMode))
    return VisualModeResult(kind: vmrUnhandled)

  let cmd = route.command

  # Special-case action dispatch — mirrors the `of ctAction` arm in
  # `normal_handler.handleNormalModeKey` so all three mode handlers funnel
  # the exec.cmdline.* bridge (and other action-only commandIds like
  # `lsp.selection.range`) through one place.
  if cmd.kind == ctAction:
    # Command mode command alias bridge: `exec.cmdline.<alias>` runs
    # `:<alias>` via the full command-line parser so safety checks
    # (modified-buffer guard etc.) fire. Visual mode has no in-progress
    # buffer transaction to commit, so just forward the alias to the
    # dispatcher.
    if cmd.commandId.startsWith(ExecCmdlinePrefix):
      let aliasText = cmd.commandId[ExecCmdlinePrefix.len ..^ 1]
      return VisualModeResult(kind: vmrExecCommand, execCommandText: aliasText)

  # LSP selection range can also be reached via ctTextObject / ctOperator /
  # ctCustom bindings, so the check is kept separate from the ctAction arm
  # above.
  if cmd.kind in {ctAction, ctTextObject, ctOperator, ctCustom}:
    if cmd.commandId == "lsp.selection.range":
      return VisualModeResult(kind: vmrLspSelectionRange)

  # Create command context
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
  )

  # Execute command through registry
  let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)

  # Update visual selection current position if still in visual mode
  if isVisualAllMode(state.mode) and state.visualSelection.active:
    state.visualSelection.current = state.cursor

  if cmdResult.isErr:
    return VisualModeResult(kind: vmrError, errorMessage: cmdResult.error)

  # Check for mode transition (exiting any visual mode)
  let modeTransition =
    if not isVisualAllMode(state.mode) or state.mode != originalMode:
      some(state.mode)
    else:
      none(EditorMode)

  return VisualModeResult(kind: vmrHandled, modeTransition: modeTransition)
