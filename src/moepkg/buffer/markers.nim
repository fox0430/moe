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

## Sidebar markers, git-change navigation, and diagnostic queries.

import std/[options, tables]

import ../celina_backend as celina

import ../highlight
import ./core

proc setLineMarker*(b: TextBuffer, line: int, kind: LineMarkerKind) =
  ## Set the git diff or conflict marker for a line
  assert kind in {GitAdded .. GitConflict}
  b.ensureMarkersSize()
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = some(kind)

proc clearLineMarker*(b: TextBuffer, line: int) =
  ## Clear the git diff or conflict marker for a line
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = none(LineMarkerKind)

proc getLineMarker*(b: TextBuffer, line: int): Option[LineMarkerKind] =
  ## Git diff or conflict marker for a line, if any
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
  b.clearDiagnostics()

proc clearGitMarkers*(b: TextBuffer) =
  ## Clear git-diff markers, keeping GitConflict. Used when re-applying git
  ## diff results.
  for i in 0 ..< b.lineMarkers.len:
    let m = b.lineMarkers[i]
    if m.isSome and m.get.isGitChangeMarker:
      b.lineMarkers[i] = none(LineMarkerKind)

func merge(
    marker: var Option[LineMarkerKind],
    source: DiagnosticSource,
    severity: BufferDiagnosticSeverity,
) =
  ## Error outranks Warning; LSP info/hints count as Warning, syntax checker
  ## marks none.
  if severity == bdsError:
    marker = some(SyntaxError)
  elif marker.isNone and (severity == bdsWarning or source == dsrcLsp):
    marker = some(SyntaxWarning)

proc diagnosticMarkers*(
    b: TextBuffer, firstLine, count: int
): seq[Option[LineMarkerKind]] =
  ## Diagnostic markers for `count` lines from `firstLine`, across all sources.
  result = newSeq[Option[LineMarkerKind]](max(count, 0))
  for source in DiagnosticSource:
    for d in b.diagnostics[source].startingOn(firstLine ..< firstLine + result.len):
      result[d.startLine - firstLine].merge(source, d.severity)

proc diagnosticMarker*(b: TextBuffer, line: int): Option[LineMarkerKind] =
  b.diagnosticMarkers(line, 1)[0]

proc getDiagnosticsAt*(b: TextBuffer, line, col: int): seq[BufferDiagnostic] =
  ## LSP diagnostics covering (line, col)
  for d in b.diagnostics[dsrcLsp].startingOn(0 .. line):
    if line <= d.endLine:
      if (line > d.startLine or col >= d.startCol) and
          (line < d.endLine or col < d.endCol):
        result.add(d)

proc applyDiagnosticHighlights*(highlight: var Highlight, report: DiagnosticReport) =
  ## Fill the per-row diagnostic overlay without touching `colorSegments`.
  for d in report.items:
    let color =
      case d.severity
      of bdsError: EditorColorPairIndex.syntaxCheckErr
      of bdsWarning: EditorColorPairIndex.syntaxCheckWarn
      of bdsInformation: EditorColorPairIndex.syntaxCheckInfo
      of bdsHint: EditorColorPairIndex.syntaxCheckHint
    let style = Style(modifiers: {StyleModifier.Undercurl})

    if d.startLine == d.endLine:
      let last = max(d.endCol - 1, d.startCol)
      highlight.diagnosticOverlay
        .mgetOrPut(d.startLine, DiagnosticOverlayLine()).cells
        .add(
          DiagnosticOverlayCell(
            firstColumn: d.startCol, lastColumn: last, color: color, style: style
          )
        )
    else:
      highlight.diagnosticOverlay
        .mgetOrPut(d.startLine, DiagnosticOverlayLine()).cells
        .add(
          DiagnosticOverlayCell(
            firstColumn: d.startCol, lastColumn: int.high, color: color, style: style
          )
        )

      for r in (d.startLine + 1) ..< d.endLine:
        highlight.diagnosticOverlay.mgetOrPut(r, DiagnosticOverlayLine()).cells.add(
          DiagnosticOverlayCell(
            firstColumn: 0, lastColumn: int.high, color: color, style: style
          )
        )

      if d.endCol > 0:
        highlight.diagnosticOverlay
          .mgetOrPut(d.endLine, DiagnosticOverlayLine()).cells
          .add(
            DiagnosticOverlayCell(
              firstColumn: 0, lastColumn: d.endCol - 1, color: color, style: style
            )
          )
