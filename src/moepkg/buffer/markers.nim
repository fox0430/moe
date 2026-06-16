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

## Sidebar markers, git-change navigation, and LSP diagnostic queries.

import std/options

import pkg/celina

import ../highlight
import ./core

proc setLineMarker*(b: TextBuffer, line: int, kind: LineMarkerKind) =
  ## Set a sidebar marker for a specific line
  ## Automatically resizes the marker array if needed
  b.ensureMarkersSize()
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = some(kind)

proc clearLineMarker*(b: TextBuffer, line: int) =
  ## Clear the sidebar marker for a specific line
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = none(LineMarkerKind)

proc getLineMarker*(b: TextBuffer, line: int): Option[LineMarkerKind] =
  ## Get the sidebar marker for a specific line
  ## Returns none if no marker is set or line is out of bounds
  if line >= 0 and line < b.lineMarkers.len:
    return b.lineMarkers[line]
  else:
    return none(LineMarkerKind)

proc isGitChangeMarker*(kind: LineMarkerKind): bool =
  kind in {GitAdded, GitChanged, GitDeleted, GitChangedAndDeleted}

proc findNextGitChange*(b: TextBuffer, startLine: int): Option[int] =
  ## Skip the current change block, then return the first line of the next
  ## change block.
  var i = startLine
  # Skip current marker block
  while i < b.lineMarkers.len:
    let m = b.getLineMarker(i)
    if m.isNone or not m.get.isGitChangeMarker:
      break
    inc i
  # Find the next marker
  while i < b.lineMarkers.len:
    let m = b.getLineMarker(i)
    if m.isSome and m.get.isGitChangeMarker:
      return some(i)
    inc i
  return none(int)

proc findPrevGitChange*(b: TextBuffer, startLine: int): Option[int] =
  ## Return the first line of the previous change block.
  var i = startLine - 1
  # Skip current marker block (backwards)
  while i >= 0:
    let m = b.getLineMarker(i)
    if m.isNone or not m.get.isGitChangeMarker:
      break
    dec i
  # Find the previous marker
  while i >= 0:
    let m = b.getLineMarker(i)
    if m.isSome and m.get.isGitChangeMarker:
      # Walk back to the start of this block
      while i > 0:
        let prev = b.getLineMarker(i - 1)
        if prev.isNone or not prev.get.isGitChangeMarker:
          break
        dec i
      return some(i)
    dec i
  return none(int)

proc clearAllMarkers*(b: TextBuffer) =
  ## Clear all sidebar markers and diagnostics. A fresh (all-none) CowSeq node
  ## avoids cloning a shared/frozen array only to overwrite every slot.
  b.lineMarkers = initCowSeq[Option[LineMarkerKind]](b.lineMarkers.len)
  b.diagnostics.setLen(0)

proc clearGitMarkers*(b: TextBuffer) =
  ## Clear only git-diff sidebar markers (added / changed / deleted).
  ## Leaves LSP diagnostics and other marker kinds (SyntaxError, Bookmark,
  ## SessionModified/Inserted, GitConflict) untouched. Used when
  ## re-applying git diff results so that diagnostics survive the refresh.
  for i in 0 ..< b.lineMarkers.len:
    let m = b.lineMarkers[i]
    if m.isSome and m.get.isGitChangeMarker:
      b.lineMarkers[i] = none(LineMarkerKind)

proc getDiagnosticsAt*(b: TextBuffer, line, col: int): seq[BufferDiagnostic] =
  ## Return diagnostics whose range covers the given (line, col) position
  for d in b.diagnostics:
    if line >= d.startLine and line <= d.endLine:
      if (line > d.startLine or col >= d.startCol) and
          (line < d.endLine or col < d.endCol):
        result.add(d)

proc applyDiagnosticHighlights*(
    highlight: var Highlight, diagnostics: seq[BufferDiagnostic]
) =
  ## Overwrite highlight segments in diagnostic ranges with undercurl styles.
  for d in diagnostics:
    let color =
      case d.severity
      of bdsError: EditorColorPairIndex.syntaxCheckErr
      of bdsWarning: EditorColorPairIndex.syntaxCheckWarn
      of bdsInformation: EditorColorPairIndex.syntaxCheckInfo
      of bdsHint: EditorColorPairIndex.syntaxCheckHint

    highlight.overwrite(
      ColorSegment(
        firstRow: d.startLine,
        firstColumn: d.startCol,
        lastRow: d.endLine,
        lastColumn: max(d.endCol - 1, d.startCol),
        color: color,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
