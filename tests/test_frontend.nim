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

## Behavioral coverage for the frontend embedding facade.

import std/unittest

import ../src/moepkg/frontend

suite "frontend embedding facade":
  test "constructs and queries an editor through one import":
    let e = newEditor(newEditorConfig())

    e.setFrontendGitStatusEnabled(true)
    let status: FrontendStatus = e.frontendStatus

    check status.modeLabel == "NORMAL"
    check e.frontendGitStatusEnabled

  test "exposes frontend-neutral input values and handlers":
    let
      e = newEditor(newEditorConfig())
      pointer = PointerInput(
        row: 2,
        column: 3,
        button: pbPrimary,
        action: paPress,
        clickCount: 1,
      )

    check pointer.row == 2
    check pointer.column == 3
    check e.handleTextInput("")
