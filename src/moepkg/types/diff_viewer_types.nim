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

## Lightweight type definitions for the diff viewer.
##
## Split out from `diff_viewer` so modules that only need `DiffViewerState`
## (notably `types` and its importers) do not transitively pull in `highlight`
## / `syntax/tokenizer` via the full `diff_viewer` module.

import list_viewer_types
import ../primitives
import ../color
export list_viewer_types

type
  DiffLineKind* = enum
    dlkNormal # Normal (context) line
    dlkAdded # Added line (starts with +)
    dlkDeleted # Deleted line (starts with -)
    dlkHeader # Header line (@@, ---, +++)
    dlkMeta # Meta line (diff --git, index, etc.)

  DiffLine* = object ## Represents a single line in the diff output
    text*: string
    kind*: DiffLineKind

  DiffViewMode* = enum
    dvmUnified ## Classic unified diff (one column)
    dvmSideBySide ## GitHub/delta style two-column view

  SideBySideRowKind* = enum
    sbrContext ## Same content on both sides
    sbrChanged ## Paired old/new lines with word-level differences
    sbrAdded ## Only on the right (new) side
    sbrDeleted ## Only on the left (old) side
    sbrHeader ## Hunk header (@@ ...) spanning both columns
    sbrMeta ## File header (---/+++/diff/index) spanning both columns
    sbrEmpty ## "(No differences)" placeholder

  SideSyntaxSpan* = object ## Syntax color of a half-open char-column range
    startCol*: int # inclusive
    endCol*: int # exclusive
    color*: EditorColorPairIndex

  SideBySideRow* = object ## One aligned row for side-by-side rendering
    kind*: SideBySideRowKind
    leftText*: string ## Old side content (without -/+ prefix)
    rightText*: string ## New side content (without -/+ prefix)
    headerText*: string ## Full text for header/meta/empty rows
    oldLineNo*: int ## Old file line number, -1 when absent
    newLineNo*: int ## New file line number, -1 when absent
    sourceIndex*: int
      ## Index in the unified `items` this row came from. Non-decreasing, so
      ## the selection can be mapped between the two presentations.
    leftWordRanges*: seq[ColumnRange] ## Changed word ranges (char cols) on left
    rightWordRanges*: seq[ColumnRange] ## Changed word ranges (char cols) on right
    leftSyntax*: seq[SideSyntaxSpan] ## Syntax colors of leftText (char cols)
    rightSyntax*: seq[SideSyntaxSpan] ## Syntax colors of rightText (char cols)

  DiffViewerState* = ref object of ListViewer[DiffLine]
    ## State for the diff viewer UI.
    ## items (diff lines)/selectedIndex/waitingForG are inherited.
    sourceFilePath*: string # Path of the source file (current version)
    backupFilePath*: string # Path of the backup file (old version)
    errorMessage*: string # Error message if diff failed
    viewMode*: DiffViewMode # Requested presentation (unified or side-by-side)
    wordHighlight*: bool # Highlight changed words inside changed rows
    sideRows*: seq[SideBySideRow] # Aligned rows for side-by-side rendering
    sideRowsWordHighlight*: bool
      ## Whether `sideRows` carry word ranges. Building them is the expensive
      ## part, so it is skipped while the highlight is off.
    unifiedWordRanges*: seq[seq[ColumnRange]] # Per-item changed-word ranges
    renderedSideBySide*: bool # True when the current buffer actually shows two columns
    renderedWidth*: int # Text width the current buffer was built for
    renderedThemeGeneration*: int
      ## Theme generation the current buffer's colors were read from. The
      ## segments carry concrete backgrounds, so a theme change forces a
      ## rebuild.
    tabStop*: int # Tab width used to expand side-by-side row text
    syntaxComputed*: bool # True once side rows were syntax-highlighted
