#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/unittest

import moepkg/ui

import moepkg/keybindings {.all.}

suite "keybindings: NormlaModeCommand.find":
  let k = defaultNormalModeKeyBindings()

  test "Basic":
    check @[moveNextWindow] == k.find(CtrlK.toKeys)
    check @[moveCursorLeft] == k.find("h".toKeys)
    check @[deleteLine] == k.find("dd".toKeys)
    check @[changeInner] == k.find("ci'".toKeys)

  test "Not found":
    check k.find("あ".toKeys).len == 0
    check k.find(CtrlZ.toKeys).len == 0
    check k.find("dz".toKeys).len == 0
