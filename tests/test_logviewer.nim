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

## Tests for logviewer.nim
## This module tests the Log Viewer state management functionality.

import std/unittest

import ../src/moepkg/logviewer

suite "logviewer: LogContentKind":
  test "lckEditor enum value":
    check lckEditor == LogContentKind.lckEditor

  test "lckLsp enum value":
    check lckLsp == LogContentKind.lckLsp

  test "Enum values are distinct":
    check lckEditor != lckLsp

suite "logviewer: newLogViewerState":
  test "Create with default kind (lckEditor)":
    let state = newLogViewerState()

    check state != nil
    check state.contentKind == lckEditor

  test "Create with lckEditor kind":
    let state = newLogViewerState(lckEditor)

    check state != nil
    check state.contentKind == lckEditor

  test "Create with lckLsp kind":
    let state = newLogViewerState(lckLsp)

    check state != nil
    check state.contentKind == lckLsp

suite "logviewer: LogViewerState fields":
  test "contentKind is readable":
    let state = newLogViewerState(lckLsp)

    check state.contentKind == lckLsp

  test "contentKind is writable":
    let state = newLogViewerState(lckEditor)

    state.contentKind = lckLsp

    check state.contentKind == lckLsp

  test "Multiple states are independent":
    let
      state1 = newLogViewerState(lckEditor)
      state2 = newLogViewerState(lckLsp)

    check state1.contentKind == lckEditor
    check state2.contentKind == lckLsp

    state1.contentKind = lckLsp

    check state1.contentKind == lckLsp
    check state2.contentKind == lckLsp
