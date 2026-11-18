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

## What a picker lists and what opening an item does. Free of chronos, as
## `types` is.

import ../buffer/core
import ../picker/[catalog, matcher]

export catalog, matcher

type
  PickerTargetKind* = enum
    ptkFile ## A path, opened where `:e` puts the cursor
    ptkBuffer ## A buffer of the editor
    ptkExCommand ## A command line, run as if typed after `:`

  PickerTarget* = object
    case kind*: PickerTargetKind
    of ptkFile:
      path*: string
    of ptkBuffer:
      buffer*: BufferId
    of ptkExCommand:
      command*: string

  PickerItem* = object
    key*: string ## What the query is matched against
    display*: string ## What the list shows
    keyAt*: int ## The character of `display` that `key` starts at
    target*: PickerTarget

  PickerAction* = enum
    paNext
    paPrevious
    paPageDown
    paPageUp
    paSplit ## Open the item in a split
    paVSplit ## Open the item in a vertical split

  PickerMatches* = object
    ## The items the query matches, best first, as the list shows them. Built
    ## a slice at a time: `pending` (the items an earlier query matched, when
    ## this one only narrows it) from `pendingAt`, then the items from `upTo`.
    valid*: bool ## Built for `query`
    query*: string
    pattern*: FuzzyPattern
    everyItem*: bool ## An empty query: all the items, in the source's order
    ranks*: seq[FuzzyRank]
    pending*: seq[int]
    pendingAt*: int
    upTo*: int
    scratch*: FuzzyMatcher
