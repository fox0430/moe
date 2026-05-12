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

## Small cursor helpers shared between `handler.nim` and the command-handler
## result processor. Kept here (depending only on `primitives.BufferPosition`)
## to avoid a circular import between `handler.nim` and
## `command_handlers/result_processor.nim`.

import primitives

proc adjustCursorAfterInsertExit*(cursor: var BufferPosition, lineCharLen: int) =
  ## Adjust cursor position when transitioning from Insert to Normal mode.
  ## Vim moves cursor one position to the left (unless at column 0 or empty line).
  if lineCharLen == 0:
    cursor.column = 0
  elif cursor.column > 0:
    cursor.column = min(cursor.column - 1, lineCharLen - 1)
