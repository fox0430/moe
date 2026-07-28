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

## Generic list-viewer core shared by the LSP viewers, managers and other
## list-style modes. Selection/scroll navigation, the common vim-style key
## block (gg/G/j/k/Ctrl-d/Ctrl-u/Enter/q/:/Esc) and the read-only render
## buffer are implemented once here over `ListViewer[T]`.

import std/options

import buffer/core, key_bindings
import picker/nav
import types/list_viewer_types

export list_viewer_types

# Navigation
# Thin generic wrappers over the raw `picker/nav` primitives so every mode
# shares one implementation instead of re-wrapping them per state type.

proc itemCount*[T](v: ListViewer[T]): int =
  v.items.len

proc getItem*[T](v: ListViewer[T], index: int): Option[T] =
  if index >= 0 and index < v.items.len:
    some(v.items[index])
  else:
    none(T)

proc getSelectedItem*[T](v: ListViewer[T]): Option[T] =
  v.getItem(v.selectedIndex)

proc moveUp*[T](v: ListViewer[T]) =
  pickerMoveUp(v.selectedIndex)

proc moveDown*[T](v: ListViewer[T]) =
  pickerMoveDown(v.selectedIndex, v.items.len)

proc moveToFirst*[T](v: ListViewer[T]) =
  pickerMoveToFirst(v.selectedIndex)

proc moveToLast*[T](v: ListViewer[T]) =
  pickerMoveToLast(v.selectedIndex, v.items.len)

proc halfPageUp*[T](v: ListViewer[T], viewportHeight: int) =
  pickerHalfPageUp(v.selectedIndex, viewportHeight)

proc halfPageDown*[T](v: ListViewer[T], viewportHeight: int) =
  pickerHalfPageDown(v.selectedIndex, v.items.len, viewportHeight)

proc pageUp*[T](v: ListViewer[T], viewportHeight: int) =
  ## Full page up, keeping one line of overlap.
  v.selectedIndex = max(0, v.selectedIndex - max(1, viewportHeight - 1))

proc pageDown*[T](v: ListViewer[T], viewportHeight: int) =
  ## Full page down, keeping one line of overlap.
  if v.items.len > 0:
    v.selectedIndex = min(v.items.high, v.selectedIndex + max(1, viewportHeight - 1))

proc handleListNavKey*[T](
    v: ListViewer[T], viewportHeight: int, keyCombo: KeyCombo
): ListViewerAction =
  ## Handle the keys shared by every list-style viewer. Returns `lvaUnhandled`
  ## for any other key so the caller can apply its mode-specific bindings.
  ##
  ## Only the selection moves here; the window viewport follows `selectedIndex`
  ## through the cursor (see `editor_render_views.syncSelectionCursor`), so no
  ## scroll state is maintained on the viewer itself.

  # 'gg' — second 'g' jumps to the first item; any other key falls through.
  if v.waitingForG:
    v.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      v.moveToFirst()
      return lvaConsumed

  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      return lvaEscape
    of skUp:
      v.moveUp()
      return lvaConsumed
    of skDown:
      v.moveDown()
      return lvaConsumed
    of skEnter:
      return lvaSelect
    of skHome:
      v.moveToFirst()
      return lvaConsumed
    of skEnd:
      v.moveToLast()
      return lvaConsumed
    of skPageUp:
      v.pageUp(viewportHeight)
      return lvaConsumed
    of skPageDown:
      v.pageDown(viewportHeight)
      return lvaConsumed
    else:
      return lvaUnhandled

  # Ctrl-d / Ctrl-u — half page down/up.
  if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
    v.halfPageDown(viewportHeight)
    return lvaConsumed
  if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
    v.halfPageUp(viewportHeight)
    return lvaConsumed

  # Any other modifier combination falls through so caller-level bindings
  # (e.g. `C-q = quit-force`) still reach the router.
  if keyCombo.modifiers != {}:
    return lvaUnhandled

  case keyCombo.char
  of "q":
    return lvaQuitKey
  of ":":
    return lvaEnterCommand
  of "j":
    v.moveDown()
    return lvaConsumed
  of "k":
    v.moveUp()
    return lvaConsumed
  of "g":
    v.waitingForG = true
    return lvaConsumed
  of "G":
    v.moveToLast()
    return lvaConsumed
  else:
    return lvaUnhandled

proc toListTextBuffer*[T](
    v: ListViewer[T],
    header: string,
    formatItem: proc(item: T): string,
    emptyPlaceholder = "",
): TextBuffer =
  ## Build a read-only TextBuffer: a header line followed by one formatted line
  ## per item, rendered through the normal window path. When the list is empty
  ## and `emptyPlaceholder` is non-empty, it is shown as the only body line.
  var content = header
  if v.items.len == 0 and emptyPlaceholder.len > 0:
    content.add('\n')
    content.add(emptyPlaceholder)
  else:
    for i in 0 ..< v.items.len:
      content.add('\n')
      content.add(formatItem(v.items[i]))
  result = newTextBuffer(content)
  result.readOnly = true
