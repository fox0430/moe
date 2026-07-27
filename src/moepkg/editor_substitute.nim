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

import std/strutils

import types/editor_types, command_line/substitute_parser
import buffer/[core, edit]

proc startSubstitutePreview*(e: Editor) =
  ## Start substitute preview by saving the current buffer content
  if e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  if buffer.readOnly:
    return
  e.state.ui.substitutePreview.originalLines = newSeqOfCap[string](buffer.len)
  for line in buffer.lines:
    e.state.ui.substitutePreview.originalLines.add(line)
  e.state.ui.substitutePreview.isActive = true
  e.state.ui.substitutePreview.lastPattern = ""
  e.state.ui.substitutePreview.lastReplacement = ""
  e.state.ui.substitutePreview.originalCursor = e.cursor
  e.state.ui.substitutePreview.originalTopLine = e.activeWindow.viewport.topLine
  e.state.ui.substitutePreview.originalLeftColumn = e.activeWindow.viewport.leftColumn

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
  # Clear last-applied pattern/replacement so the next updateSubstitutePreview
  # call does not skip work when identical values are reapplied.
  e.state.ui.substitutePreview.lastPattern = ""
  e.state.ui.substitutePreview.lastReplacement = ""

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.ui.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.cursor = e.state.ui.substitutePreview.originalCursor
  e.activeWindow.viewport.resetViewportTop(e.state.ui.substitutePreview.originalTopLine)
  e.activeWindow.viewport.leftColumn = e.state.ui.substitutePreview.originalLeftColumn
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (discard snapshot, keep current changes)
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]

proc updateSubstitutePreview*(
    e: Editor, pattern: string, replacement: string, isGlobalFlag: bool = true
) =
  ## Update substitute preview with new pattern and replacement
  ## isGlobalFlag: if true, replace all occurrences per line; if false, only first occurrence
  if not e.state.ui.substitutePreview.isActive:
    return

  # Skip if nothing changed
  if pattern == e.state.ui.substitutePreview.lastPattern and
      replacement == e.state.ui.substitutePreview.lastReplacement:
    return

  # Restore from snapshot first (this clears lastPattern/lastReplacement, so
  # cache the new values *after* restoring).
  e.restoreFromPreview()

  e.state.ui.substitutePreview.lastPattern = pattern
  e.state.ui.substitutePreview.lastReplacement = replacement

  if pattern.len == 0:
    return

  # Process escape sequences in replacement using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Apply substitute to buffer
  let buffer = e.activeBuffer()
  for lineIdx in 0 ..< buffer.len:
    var line = buffer.getLine(lineIdx)
    var newLine = ""
    var searchPos = 0
    var modified = false

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        newLine.add(line[searchPos ..^ 1])
        break

      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      newLine.add(processedReplacement)
      modified = true
      searchPos = idx + pattern.len

      # If not global flag, only replace first occurrence per line
      if not isGlobalFlag:
        newLine.add(line[searchPos ..^ 1])
        break

    if modified:
      buffer.replaceLineNoUndo(lineIdx, newLine)

  buffer.highlightNeedsUpdate = true
