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

## Celina types used by Moe's editor core.
##
## A regular Moe build re-exports Celina's complete terminal API. Embedded
## builds import only the value-type rendering and input modules needed by a
## host frontend, so compiling the editor core never pulls in POSIX terminal
## I/O (`termios`, stdin polling, or Celina's terminal application runtime).

when defined(moe.embedded):
  import std/unicode

  import
    pkg/celina/core/[geometry, colors, buffer, layout, borders, key_logic, mouse_logic]

  export unicode
  export geometry, colors, buffer, layout, borders, key_logic, mouse_logic

  type
    EventResult* = enum
      erContinue
      erConsume
      erQuit

    EventKind* = enum
      Key
      Mouse
      Resize
      Paste
      FocusIn
      FocusOut
      Quit
      Unknown

    MouseEvent* = object
      kind*: MouseEventKind
      button*: MouseButton
      x*: int
      y*: int
      modifiers*: set[KeyModifier]

    Event* = object
      case kind*: EventKind
      of Key:
        key*: KeyEvent
      of Mouse:
        mouse*: MouseEvent
      of Paste:
        pastedText*: string
      of Resize, FocusIn, FocusOut, Quit, Unknown:
        discard

else:
  import pkg/celina

  export celina
