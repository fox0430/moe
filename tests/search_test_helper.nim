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

## Where a search from a position lands its match, for tests that only look at
## the match's start.

import std/options

import ../src/moepkg/[buffer, primitives]

proc findNext*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    match = smRegex,
): Option[BufferPosition] =
  ## Where the match a search forward from `startPos` reaches starts.
  b.findMatchFrom(searchText, startPos, ignorecase, match, Forward).map(start)

proc findPrev*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    match = smRegex,
): Option[BufferPosition] =
  ## Where the match a search back from `startPos` reaches starts.
  b.findMatchFrom(searchText, startPos, ignorecase, match, Backward).map(start)
