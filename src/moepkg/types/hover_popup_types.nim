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

## Lightweight type definitions for the LSP hover popup.
##
## Split out from `hover_popup` so modules that only need its manager type
## (notably `types` and its importers) do not transitively pull in the
## popup rendering procs.

type
  HoverPopupState* = enum
    hpsIdle ## No hover popup active
    hpsActive ## Hover popup is being displayed

  HoverPopupDisplay* = object ## Hover popup display state
    lines*: seq[string] ## Text lines to display (split by \n)
    scrollOffset*: int ## Current vertical scroll offset (first visible line)
    horizontalOffset*: int ## Current horizontal scroll offset (first visible column)
    maxVisibleLines*: int ## Maximum number of visible lines
    maxVisibleWidth*: int ## Maximum visible width (set during position calculation)
    cachedMaxLineWidth*: int ## Cached max line width (computed in show())

  HoverPopupManager* = ref object ## Manages hover popup state
    state*: HoverPopupState
    display*: HoverPopupDisplay
    triggerLine*: int ## Line where hover was triggered
    triggerCol*: int ## Column where hover was triggered
    isAutoHover*: bool ## true when triggered by auto-hover diagnostic
