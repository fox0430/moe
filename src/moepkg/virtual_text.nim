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

## Feature-agnostic virtual text layer.
##
## "Virtual text" is text the editor draws into the view that does not exist in
## the buffer: LSP inlay hints, inline diagnostics (Error Lens style), git blame
## annotations, inline debug values, and so on. Each feature exposes a
## `VirtualTextProvider` closure that, given a buffer line, returns the virtual
## text for that line. The renderer collects from all registered providers and
## draws the result; it never needs to know which features exist.
##
## Placement kinds:
## - `vtpEndOfLine`: appended after the last rune of the line (implemented).
## - `vtpInline`: inserted before a given rune column, shifting real text right.
## - `vtpAbove` / `vtpBelow`: a separate virtual line above/below.
##
## Only `vtpEndOfLine` is rendered today. The other placements are part of the
## API so providers and the data model are stable; rendering support for them is
## added incrementally (inline insertion affects cursor display column, mouse
## hit-testing, line wrapping and horizontal scrolling, so it lands separately).

import std/[algorithm, tables, unicode]

import celina_backend as celina

import types/virtual_text_types
export virtual_text_types

proc totalWidth*(chunks: seq[VirtualTextChunk]): int =
  ## Total display width (sum of rune widths) of the chunks.
  for chunk in chunks:
    for rune in chunk.text.runes:
      result += runeWidth(rune)

proc isEmpty*(vtLine: VirtualTextLine): bool {.inline.} =
  vtLine.endOfLine.len == 0 and vtLine.inlineByColumn.len == 0

proc collectVirtualText*(
    providers: openArray[VirtualTextProvider], line: int
): VirtualTextLine =
  ## Gather virtual text for `line` from all providers, sort by priority
  ## (stable, so same-priority items keep provider registration order), and
  ## split by placement. `vtpAbove` / `vtpBelow` are dropped for now (no
  ## rendering support yet).
  var items: seq[VirtualText]
  for provider in providers:
    if provider.isNil:
      continue
    items.add provider(line)

  if items.len == 0:
    return

  # algorithm.sort is a stable merge sort, so equal priorities preserve order.
  items.sort(
    proc(a, b: VirtualText): int =
      cmp(a.priority, b.priority)
  )

  for item in items:
    case item.placement
    of vtpEndOfLine:
      result.endOfLine.add item.chunks
    of vtpInline:
      result.inlineByColumn.mgetOrPut(item.column, @[]).add item.chunks
    of vtpAbove, vtpBelow:
      discard

proc inlineWidthBefore*(vtLine: VirtualTextLine, runeCol: int): int =
  ## Total display width of inline virtual text inserted before `runeCol`.
  ## Used to correct the cursor display column once inline rendering exists.
  for col, chunks in vtLine.inlineByColumn:
    if col < runeCol:
      result += totalWidth(chunks)
