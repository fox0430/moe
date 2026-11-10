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

## Lightweight type definitions for the help viewer.
##
## Split out from `help_viewer` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in
## `help_generator` (and its large generated `HelpLines` const) via the
## full `help_viewer` module.

import std/strutils

import ../primitives
import list_viewer_types
export list_viewer_types

type
  HelpLineKind* = enum
    hlkText ## Prose, or a blank line
    hlkSection ## "# Heading", where `[` and `]` stop
    hlkSubsection ## "## Heading"
    hlkEntry ## "keys - description"

  HelpLine* = object
    kind*: HelpLineKind
    text*: string
    keyFirst*, keyEnd*: int ## Byte range of the keys in an entry's `text`

  HelpViewerState* = ref object of ListViewer[HelpLine]
    searchQuery*: string # Current search query
    searchDirection*: SearchDirection # The way the search for it went
    lastKeyWasEscape*: bool # Waiting for second Escape to clear highlight

func oneRow(text: string): string =
  ## `text`, which must not span rows: each help line is one buffer row.
  doAssert '\n' notin text, "a help line spans rows: " & text.escape
  text

func textLine*(text: string): HelpLine =
  HelpLine(kind: hlkText, text: text.oneRow)

func section*(title: string): HelpLine =
  HelpLine(kind: hlkSection, text: oneRow("# " & title))

func subsection*(title: string): HelpLine =
  HelpLine(kind: hlkSubsection, text: oneRow("## " & title))

func entryLine*(indent: int, keys: string, width: int, description: string): HelpLine =
  ## `keys` padded to `width`, then " - " and `description`.
  HelpLine(
    kind: hlkEntry,
    text: oneRow(' '.repeat(indent) & keys.alignLeft(width) & " - " & description),
    keyFirst: indent,
    keyEnd: indent + keys.len,
  )

func prose*(text: string): seq[HelpLine] =
  ## One text line per line of `text`, without the one after a final newline.
  for line in text.splitLines:
    result.add textLine(line)
  if text.endsWith('\n'):
    result.setLen(result.len - 1)
