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

## Common navigation primitives for picker-style UIs.
## Operate on raw `var int` so they work with any State layout.

proc pickerMoveUp*(selectedIndex: var int) =
  if selectedIndex > 0:
    selectedIndex.dec

proc pickerMoveDown*(selectedIndex: var int, itemCount: int) =
  if selectedIndex < itemCount - 1:
    selectedIndex.inc

proc pickerMoveToFirst*(selectedIndex: var int) =
  selectedIndex = 0

proc pickerMoveToLast*(selectedIndex: var int, itemCount: int) =
  if itemCount > 0:
    selectedIndex = itemCount - 1
  else:
    selectedIndex = 0

proc pickerHalfPageUp*(selectedIndex: var int, viewportHeight: int) =
  selectedIndex = max(0, selectedIndex - viewportHeight div 2)

proc pickerHalfPageDown*(
    selectedIndex: var int, itemCount: int, viewportHeight: int
) =
  if itemCount > 0:
    selectedIndex = min(itemCount - 1, selectedIndex + viewportHeight div 2)

proc pickerEnsureVisible*(
    selectedIndex: int, topLine: var int, viewportHeight: int
) =
  if selectedIndex < topLine:
    topLine = selectedIndex
  elif viewportHeight > 0 and selectedIndex >= topLine + viewportHeight:
    topLine = selectedIndex - viewportHeight + 1
  if topLine < 0:
    topLine = 0
