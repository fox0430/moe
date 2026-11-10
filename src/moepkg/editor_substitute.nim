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

## Live substitute (`:s`) preview: write candidate replacements as the user
## types, recording each swap, and take them back to restore or cancel.

import std/options

import types/editor_types, command_line/substitute_parser, editor_notify
import buffer/[core, edit, search]

proc startSubstitutePreview*(e: Editor) =
  ## Start a substitute preview on the active buffer.
  if e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  if buffer.readOnly:
    return
  # `:s` itself is refused on a raw buffer, so previewing it would only write
  # byte-sliced lines the user can never commit.
  if not buffer.allowsTextTransforms:
    return
  e.state.ui.substitutePreview = SubstitutePreview(
    isActive: true,
    buffer: buffer,
    originalCursor: e.cursor,
    originalView: e.activeWindow.viewport.viewState,
  )

proc inPreview*(e: Editor, pos: BufferPosition): BufferPosition =
  ## Where the preview took a pre-preview cursor at `pos`: down with its line,
  ## as a mark, and on what is left of it.
  template preview(): untyped =
    e.state.ui.substitutePreview

  if not preview.isActive or preview.swap.isNone:
    return pos
  result = preview.buffer.markAcross(pos, preview.swap.get).get(pos)
  # A guessed line edit moves no column, so keep the cursor on the line.
  let lastColumn = max(0, preview.buffer.getLine(result.line).charLen - 1)
  result.column = min(result.column, lastColumn)

proc inPreview*(e: Editor, view: ViewState): ViewState =
  ## `view` of the pre-preview text, with its top line where the preview took
  ## it; a rewritten top line shows from its first screen row.
  template preview(): untyped =
    e.state.ui.substitutePreview

  result = view
  if preview.isActive and preview.swap.isSome:
    let
      swap = preview.swap.get
      top = BufferPosition(line: view.topLine, column: 0)
    result.topLine = preview.buffer.markAcross(top, swap).get(top).line
    if preview.buffer.lineBefore(swap, view.topLine) !=
        preview.buffer.getLine(result.topLine):
      result.topWrapOffset = 0

proc previewShows*(e: Editor, key: SubstitutePreviewKey): bool =
  ## Whether the preview shows what `key` makes and the buffer is unchanged.
  template preview(): untyped =
    e.state.ui.substitutePreview

  if not preview.isActive:
    return false
  var current = key
  current.version = preview.buffer.contentVersion
  preview.applied == current

proc notePreviewShows*(e: Editor, key: SubstitutePreviewKey) =
  ## Remember that the preview now shows what `key` makes.
  template preview(): untyped =
    e.state.ui.substitutePreview

  preview.applied = key
  preview.applied.version = preview.buffer.contentVersion

proc takeBackSwap(e: Editor) =
  ## Take back what the preview wrote.
  template preview(): untyped =
    e.state.ui.substitutePreview

  if preview.swap.isNone:
    return
  # Undoing the swap after another change would write into moved rows. If that
  # happened, keep the preview's lines and flag the buffer modified.
  if preview.buffer.revertNoUndo(preview.swap.get):
    preview.buffer.highlightNeedsUpdate = true
  else:
    preview.buffer.markUnrecordedChange()
    e.notify(
      "The buffer changed under the substitute preview, which stays in it", nlError
    )
  preview.swap = none(NoUndoSwap)

proc restoreFromPreview*(e: Editor) =
  ## Take back what the preview wrote and put the cursor back, keeping the
  ## preview open; use cancelSubstitutePreview to cancel it.
  if not e.state.ui.substitutePreview.isActive:
    return
  e.takeBackSwap()
  e.state.ui.substitutePreview.applied = SubstitutePreviewKey()
  e.cursor = e.state.ui.substitutePreview.originalCursor

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.ui.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.activeWindow.viewport.restoreViewState(e.state.ui.substitutePreview.originalView)
  e.state.ui.substitutePreview = SubstitutePreview()

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (forget the swap, keep current changes)
  e.state.ui.substitutePreview = SubstitutePreview()

proc updateSubstitutePreview*(
    e: Editor,
    pattern: string,
    replacement: string,
    flags: SubstituteFlags,
    match: SearchMatch,
    firstLine: int = 0,
    lastLine: int = high(int),
) =
  ## Take back what the preview wrote, then write what `:s` makes of lines
  ## `firstLine .. lastLine`, all at once. The caller puts the cursor.
  if not e.state.ui.substitutePreview.isActive:
    return

  e.takeBackSwap()

  # A pattern that does not compile, as one still being typed often does,
  # replaces nothing, so no line is scanned for it.
  if pattern.len == 0 or invalidRegex(pattern, flags.ignoreCase, match).len > 0:
    return

  let parsed = parseReplacement(replacement)
  let buffer = e.state.ui.substitutePreview.buffer
  var spans: seq[LineEdit]
  for s in buffer.substitutions(
    firstLine .. lastLine, pattern, parsed, flags.ignoreCase, flags.global, match
  ):
    spans.add LineEdit(start: s.line, delete: 1, insert: s.lines)
  e.state.ui.substitutePreview.swap = buffer.replaceLineSpansNoUndo(spans)
  if e.state.ui.substitutePreview.swap.isSome:
    buffer.highlightNeedsUpdate = true
