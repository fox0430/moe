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

## Live substitute (`:s`) preview: snapshot the buffer, apply candidate
## replacements as the user types, and restore/commit/cancel the preview.

import types/editor_types, command_line/substitute_parser
import buffer/[core, edit, search]

proc startSubstitutePreview*(e: Editor) =
  ## Start substitute preview by saving the current buffer content
  if e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  if buffer.readOnly:
    return
  # `:s` itself is refused on a raw buffer, so previewing it would only write
  # byte-sliced lines the user can never commit.
  if not buffer.allowsTextTransforms:
    return
  e.state.ui.substitutePreview.originalLines = newSeqOfCap[string](buffer.len)
  for line in buffer.lines:
    e.state.ui.substitutePreview.originalLines.add(line)
  e.state.ui.substitutePreview.isActive = true
  e.state.ui.substitutePreview.applied = SubstitutePreviewKey()
  e.state.ui.substitutePreview.originalCursor = e.cursor
  e.state.ui.substitutePreview.originalView = e.activeWindow.viewport.viewState

proc restoreFromPreview*(e: Editor) =
  ## Restore buffer content from preview snapshot without cancelling the preview.
  ## Callers that want to cancel preview entirely should use cancelSubstitutePreview.
  if not e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  # Restore all lines from snapshot
  for i in 0 ..< e.state.ui.substitutePreview.originalLines.len:
    if i < buffer.len:
      buffer.replaceLineNoUndo(i, e.state.ui.substitutePreview.originalLines[i])

  # Handle line count differences
  while buffer.len > e.state.ui.substitutePreview.originalLines.len:
    buffer.deleteLineNoUndo(buffer.len - 1)
  while buffer.len < e.state.ui.substitutePreview.originalLines.len:
    buffer.insertLineNoUndo(
      buffer.len, e.state.ui.substitutePreview.originalLines[buffer.len]
    )

  buffer.highlightNeedsUpdate = true
  # So that the next updateSubstitutePreview does not skip identical values.
  e.state.ui.substitutePreview.applied = SubstitutePreviewKey()

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.ui.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.cursor = e.state.ui.substitutePreview.originalCursor
  e.activeWindow.viewport.restoreViewState(e.state.ui.substitutePreview.originalView)
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (discard snapshot, keep current changes)
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]
  e.state.ui.substitutePreview.applied = SubstitutePreviewKey()

proc updateSubstitutePreview*(
    e: Editor,
    pattern: string,
    replacement: string,
    flags: SubstituteFlags,
    firstLine: int = 0,
    lastLine: int = high(int),
    match = smPlain,
) =
  ## Update substitute preview with new pattern and replacement
  ## Only lines `firstLine .. lastLine` are replaced, as `:s` runs on its range.
  if not e.state.ui.substitutePreview.isActive:
    return

  let key = SubstitutePreviewKey(
    pattern: pattern,
    replacement: replacement,
    global: flags.global,
    lines: firstLine .. lastLine,
    ignoreCase: flags.ignoreCase,
    match: match,
  )
  # Skip if nothing changed
  if key == e.state.ui.substitutePreview.applied:
    return

  # Restoring clears the key, so it is set after.
  e.restoreFromPreview()
  e.state.ui.substitutePreview.applied = key

  if pattern.len == 0:
    return

  let parsed = parseReplacement(replacement)

  # Apply substitute to buffer
  let buffer = e.activeBuffer()
  for lineIdx in max(firstLine, 0) .. min(lastLine, buffer.len - 1):
    let (newLine, count) = buffer.getLine(lineIdx).substituteMatches(
        pattern, parsed, flags.ignoreCase, flags.global, match
      )
    if count > 0:
      buffer.replaceLineNoUndo(lineIdx, newLine)

  buffer.highlightNeedsUpdate = true
