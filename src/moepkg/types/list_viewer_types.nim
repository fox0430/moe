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

type
  ListViewer*[T] = ref object of RootObj
    ## Shared core for every list-style mode (LSP viewers, managers, ...).
    ## Owns the selection/list state. Concrete modes inherit from a
    ## `ListViewer[ItemT]` instantiation and add their own fields, so the
    ## generic navigation/key/render procs apply to them via subtyping while
    ## field names stay unchanged at every call site.
    ##
    ## Scrolling is not tracked here: every list mode renders through the normal
    ## window path with `cursor.line` mirrored from `selectedIndex`
    ## (see `editor_render_views.syncSelectionCursor`), so the window viewport is
    ## the single source of truth for the visible range.
    items*: seq[T]
    selectedIndex*: int ## Currently selected item index
    waitingForG*: bool ## Waiting for the second 'g' of 'gg'
    title*: string ## List title (empty when unused)

  ListViewerAction* = enum
    ## Result of the shared key handler. Mode-specific keys yield `lvaUnhandled`
    ## so the caller can apply its own bindings.
    lvaConsumed ## A shared navigation key was handled
    lvaQuitKey ## q (distinct from Escape so modes can treat them differently)
    lvaEscape ## Escape
    lvaEnterCommand ## :
    lvaSelect ## Enter (caller reads getSelectedItem)
    lvaUnhandled ## Not a shared key
