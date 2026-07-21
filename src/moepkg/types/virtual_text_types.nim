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

## Lightweight type definitions for the virtual text layer.
##
## Split out from `virtual_text` so modules that only need the type surface
## (notably `types/editor_types` for the `RenderContext.virtualTextProviders`
## field) do not transitively pull in `pkg/celina` and `std/algorithm` via the
## full `virtual_text` module. The collection/rendering procs stay in
## `virtual_text`.

import std/tables

import ../color

type
  VirtualTextChunk* = object ## A run of virtual text drawn with a single color.
    text*: string
    color*: EditorColorPairIndex

  VirtualTextPlacement* = enum
    vtpEndOfLine ## After the last rune of the line
    vtpInline ## Before `column` (rune index); reserved, not yet rendered
    vtpAbove ## Separate virtual line above; reserved, not yet rendered
    vtpBelow ## Separate virtual line below; reserved, not yet rendered

  VirtualText* = object
    ## A single virtual text item supplied by a feature for one line.
    line*: int
    column*: int ## Rune index. Ignored for `vtpEndOfLine`.
    placement*: VirtualTextPlacement
    chunks*: seq[VirtualTextChunk]
    priority*: int ## Lower draws first (further left for end-of-line / inline)

  VirtualTextProvider* =
    proc(line: int): seq[VirtualText] {.closure, gcsafe, raises: [].}
    ## A feature's supplier of virtual text for a given buffer line.

  VirtualTextLine* = object
    ## Per-line virtual text already grouped by placement, ready to render.
    endOfLine*: seq[VirtualTextChunk] ## All end-of-line chunks, priority order
    inlineByColumn*: Table[int, seq[VirtualTextChunk]]
      ## column -> chunks (priority order)
