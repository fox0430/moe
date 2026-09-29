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

## `C-w <key>` window commands. Kept free of imports so `help_generator` can
## build its `Ctrl-w` entries from the same table as the bindings.

const WindowSecondKeyCommands*: seq[tuple[key, name, desc, commandId: string]] = @[
  ("w", "window-next", "Move to the next window", "window.next"),
  ("p", "window-prev", "Move to the last accessed window", "window.prev"),
  ("h", "window-move-left", "Move to the window on the left", "window.move.left"),
  ("j", "window-move-down", "Move to the window below", "window.move.down"),
  ("k", "window-move-up", "Move to the window above", "window.move.up"),
  ("l", "window-move-right", "Move to the window on the right", "window.move.right"),
  ("c", "close-window", "Close current window", "window.close"),
  ("_", "window-maximize-height", "Maximize window height", "window.maximize-height"),
  ("+", "window-increase-height", "Increase window height", "window.increase-height"),
  ("-", "window-decrease-height", "Decrease window height", "window.decrease-height"),
  (">", "window-increase-width", "Increase window width", "window.increase-width"),
  ("<", "window-decrease-width", "Decrease window width", "window.decrease-width"),
  ("=", "window-equalize", "Equalize all window sizes", "window.equalize"),
  ("x", "window-swap", "Swap window with next window", "window.swap"),
  (
    "n", "window-new", "Create a new empty buffer in a horizontally split window",
    "window.new",
  ),
]
  ## Second key of a `C-w <key>` window command, the command it fires and that
  ## command's ActionCommands entry. Single source for `normal_bindings`
  ## (`C-w <key>` entries), `command_passthrough.windowSecondKeyToHandlerResult`
  ## (special-mode `C-w`) and the `Ctrl-w` help entries.
