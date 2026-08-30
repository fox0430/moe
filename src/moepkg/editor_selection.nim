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

## Stable, read-only selection queries for embedding frontends.

import std/options

import types/editor_types
from command_handlers/visual_commands import getSelectionRange, getVisualSelectionText

type
  EditorSelectionKind* {.pure.} = enum
    Character
    Block
    Line

  EditorSelection* = object
    ## Snapshot of the active buffer's selection. Positions use zero-based
    ## rune columns and inclusive endpoints, matching Moe's editing model.
    ## Block selections describe a rectangle rather than one contiguous range.
    bufferId*: BufferId
    kind*: EditorSelectionKind
    anchor*: BufferPosition
    focus*: BufferPosition
    first*: BufferPosition
    last*: BufferPosition

func toEditorSelectionKind(kind: VisualSelectionKind): EditorSelectionKind =
  case kind
  of vskChar: EditorSelectionKind.Character
  of vskBlock: EditorSelectionKind.Block
  of vskLine: EditorSelectionKind.Line

proc currentSelection*(e: Editor): Option[EditorSelection] =
  ## Return a value snapshot of the active selection, or `none` when Moe has
  ## only a caret. Callers cannot mutate editor state through the snapshot.
  if e.isNil or e.windowManager.windows.len == 0 or not e.state.visualSelection.active:
    return none(EditorSelection)

  let
    selection = e.state.visualSelection
    (first, last) = selection.getSelectionRange()
  some(
    EditorSelection(
      bufferId: e.activeBuffer.id,
      kind: selection.kind.toEditorSelectionKind,
      anchor: selection.start,
      focus: selection.current,
      first: first,
      last: last,
    )
  )

proc selectedText*(e: Editor): string =
  ## Return the active selection's text using Moe's character, line, or block
  ## semantics. Returns an empty string when there is no active selection.
  if e.isNil or e.windowManager.windows.len == 0:
    return ""
  getVisualSelectionText(e.activeBuffer, e.state.visualSelection)
