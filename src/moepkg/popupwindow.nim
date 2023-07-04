#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/options
import ui, color, unicodeext

# TODO: Add PopUpWindow type

proc writePopUpWindow*(
  popUpWindow: var Window,
  h, w, y, x: int,
  currentLine: Option[int],
  buffer: seq[Runes]) =

    # TODO: Probably, the parameter `y` means the bottom of the window,
    #       but it should change to the top of the window for consistency.

    popUpWindow.erase

    # Pop up window position
    let
      absY = y.clamp(0, getTerminalHeight() - 1 - h)
      absX = x.clamp(0, getTerminalWidth() - w)

    popUpWindow.resize(h, w, absY, absX)

    let startLine =
      if currentLine.isSome and currentLine.get - h >= 0:
        currentLine.get - h + 1
      else:
        0

    for i in 0 ..< h:
      if currentLine.isSome and i + startLine == currentLine.get:
        let color = EditorColorPairIndex.popUpWinCurrentLine
        popUpWindow.write(i, 1, buffer[i + startLine], color.int16, false)
      else:
        let color = EditorColorPairIndex.popUpWindow
        popUpWindow.write(i, 1, buffer[i + startLine], color.int16, false)

    popUpWindow.refresh

# Delete the popup window.
# Need `status.update` after delete it.
proc delete*(popUpWindow: var Window) =
  # TODO: Use Option type
  if popUpWindow != nil:
    popUpWindow.deleteWindow
